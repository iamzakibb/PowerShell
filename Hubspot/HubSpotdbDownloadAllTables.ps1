<#
  HubDB CSV exporter using HubSpot /cms/v3/hubdb export endpoints.
  - Set $accessToken (preferred private app token) or $useHapiKey/$hapikey.
  - Saves CSV files to $outputDir and keeps a manifest to skip unchanged tables.
#>

# ---------- CONFIG ----------
$useHapiKey   = $false
$hapikey      = "<YOUR_HAPIKEY_IF_USING_IT>"
$accessToken  = ""
$outputDir    = "C:\HubDB_CSVs"
$manifestPath = Join-Path $outputDir "hubdb_manifest.json"
$limitTables  = 100    # when listing tables
$maxRetries   = 3
# -----------------------------

if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

# headers (token preferred)
$headers = @{ }
if (-not $useHapiKey) {
    if (-not $accessToken -or $accessToken -match "<YOUR") { Write-Error "Set $accessToken or enable hapikey."; return }
    $headers = @{ "Authorization" = "Bearer $accessToken"; "Accept" = "application/json" }
} else {
    if (-not $hapikey -or $hapikey -match "<YOUR") { Write-Error "Set $hapikey or disable hapikey."; return }
    $headers = @{ "Accept" = "application/json" }
}

# load manifest
$manifest = @{ }
if (Test-Path $manifestPath) {
    try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $manifest = @{ } }
}
if (-not $manifest) { $manifest = @{ } }
function Save-Manifest($m) { $m | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8 }

function Build-Url($base, $qs) {
    $pairs = @()
    if ($qs) {
        foreach ($k in $qs.Keys) { $pairs += "$k=$([uri]::EscapeDataString($qs[$k]))" }
    }
    $query = if ($pairs.Count -gt 0) { $pairs -join "&" } else { "" }
    if ($useHapiKey) {
        if ($query) { return "$base`?$query&hapikey=$hapikey" } else { return "$base?hapikey=$hapikey" }
    } else {
        if ($query) { return "$base`?$query" } else { return $base }
    }
}

function Sanitize([string]$n) {
    if (-not $n) { return [guid]::NewGuid().ToString() }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) { $n = $n.Replace($c, "_") }
    $n = $n.Trim()
    if ($n.Length -eq 0) { $n = [guid]::NewGuid().ToString() }
    return $n
}

function Invoke-WithRetries {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$Retries = $maxRetries
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $ScriptBlock
        } catch {
            if ($attempt -ge $Retries) { throw $_ }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}


# Probe listing endpoint (prefer cms v3)
$probeList = @(
    @{ name="cms v3 tables"; url="https://api.hubapi.com/cms/v3/hubdb/tables"; qs = @{ limit = $limitTables } },
    @{ name="legacy v2 tables"; url="https://api.hubapi.com/hubdb/api/v2/tables"; qs = @{ limit = 1 } }
)
$working = $null
foreach ($p in $probeList) {
    $url = Build-Url -base $p.url -qs $p.qs
    try {
        $resp = Invoke-WithRetries { Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop }
        $working = $p; break
    } catch {
        Write-Warning "Probe failed for $($p.name): $($_.Exception.Message)"
    }
}
if (-not $working) { Write-Error "No table-list endpoint worked. Check token scopes."; return }

Write-Host "Using listing endpoint: $($working.name)"

# List all tables (offset pagination for v3) — safer loop
$tables = @()
$offset = 0
$maxIterations = 1000   # safety guard — adjust if you really have many pages
$iteration = 0

do {
    $iteration++
    if ($iteration -gt $maxIterations) {
        Write-Warning "Reached max iterations ($maxIterations). Stopping to avoid infinite loop."
        break
    }

    $qs = @{ limit = $limitTables; offset = $offset }
    $url = Build-Url -base $working.url -qs $qs

    try {
        $resp = Invoke-WithRetries { Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop }
    } catch {
        Write-Error "Failed to list tables at offset {$offset}: $($_.Exception.Message)"
        break
    }

    # extract page items safely (do NOT append $null)
    if ($null -ne $resp -and $null -ne $resp.results) {
        $page = $resp.results
    } elseif ($null -ne $resp -and $null -ne $resp.objects) {
        $page = $resp.objects
    } elseif ($resp -is [System.Array]) {
        $page = $resp
    } else {
        $page = @()
    }

    # Determine total count from response if present (helps early stop)
    $totalAvailable = $null
    try {
        if ($null -ne $resp.total) { $totalAvailable = [int]$resp.total }
        elseif ($resp.paging -and $resp.paging.total) { $totalAvailable = [int]$resp.paging.total }
        elseif ($resp.paging -and $resp.paging.next -and $resp.paging.next.total) { $totalAvailable = [int]$resp.paging.next.total }
    } catch { $totalAvailable = $null }

    # If API returned zero items for this page, stop (no more data)
    if ($page.Count -eq 0) {
        Write-Host "No items returned at offset $offset — stopping pagination."
        break
    }

    # Append real items only
    $tables += $page

    Write-Host ("Fetched tables offset {0} -> {1} (total so far: {2})" -f $offset, $page.Count, $tables.Count)

    # If totalAvailable is known, stop when we've collected enough
    if ($totalAvailable -and ($tables.Count -ge $totalAvailable)) {
        Write-Host ("Collected all tables (reported total: {0}). Stopping." -f $totalAvailable)
        break
    }

    # Advance offset for next page
    $offset += $limitTables

} while ($true)


if ($tables.Count -eq 0) { Write-Warning "No HubDB tables found."; return }

# For each table: check manifest, call export endpoint if needed
$downloaded = 0; $skipped = 0
foreach ($t in $tables) {
    # identify tableId or name
    $tableId = $null
    if ($t.id) { $tableId = $t.id } elseif ($t.tableId) { $tableId = $t.tableId } elseif ($t.name) { $tableId = $t.name }
    if (-not $tableId) { Write-Warning "Skipping unnamed table"; continue }

    $friendly = $t.name
    if (-not $friendly) { $friendly = ("table_" + $tableId) }
    $friendly = Sanitize $friendly
    $csvName = "{0}_{1}.csv" -f $friendly, $tableId
    $csvPath = Join-Path $outputDir $csvName

    # determine remote version
    $remoteVersion = $null
    if ($t.updatedAt) { $remoteVersion = $t.updatedAt }
    elseif ($t.updated) { $remoteVersion = $t.updated }
    elseif ($t.publishedAt) { $remoteVersion = $t.publishedAt }

    # skip if manifest matches and file exists
    $existing = $null
    try { $existing = $manifest.$tableId } catch { $existing = $null }
    if ($existing -and $remoteVersion -and ($existing.remoteVersion -eq $remoteVersion) -and (Test-Path $csvPath)) {
        $skipped++; Write-Host "Skipping (up-to-date): $csvName" -ForegroundColor DarkGray
        continue
    }

    # Try export published first: GET /cms/v3/hubdb/tables/{tableId}/export?format=CSV
    $exportBase = "https://api.hubapi.com/cms/v3/hubdb/tables/$tableId/export"
    $exportUrl = Build-Url -base $exportBase -qs @{ format = "CSV" }
    $succeeded = $false

    try {
        Write-Host "Exporting (published) table $tableId -> $csvName"

        # CSV-friendly headers (only for export calls) — do not force application/json
        $csvHeaders = @{}
        if (-not $useHapiKey) { $csvHeaders["Authorization"] = "Bearer $accessToken" }
        $csvHeaders["Accept"] = "text/csv, application/octet-stream, */*"
        # optional User-Agent (some servers are picky)
        $csvHeaders["User-Agent"] = "hubdb-export-script/1.0"

        Invoke-WithRetries { Invoke-WebRequest -Uri $exportUrl -Headers $csvHeaders -Method Get -OutFile $csvPath -UseBasicParsing -ErrorAction Stop }
        $succeeded = $true
    } catch {
        Write-Warning "Published export failed for {$tableId}: $($_.Exception.Message)"
    }

    # If published export failed, try draft export endpoint
    if (-not $succeeded) {
        $draftExport = "https://api.hubapi.com/cms/v3/hubdb/tables/$tableId/draft/export"
        $draftUrl = Build-Url -base $draftExport -qs @{ format = "CSV" }
        try {
            Write-Host "Trying draft export for $tableId -> $csvName"

            $csvHeaders = @{}
            if (-not $useHapiKey) { $csvHeaders["Authorization"] = "Bearer $accessToken" }
            $csvHeaders["Accept"] = "text/csv, application/octet-stream, */*"
            $csvHeaders["User-Agent"] = "hubdb-export-script/1.0"

            Invoke-WithRetries { Invoke-WebRequest -Uri $draftUrl -Headers $csvHeaders -Method Get -OutFile $csvPath -UseBasicParsing -ErrorAction Stop }
            $succeeded = $true
        } catch {
            Write-Warning "Draft export failed for {$tableId}: $($_.Exception.Message)"
        }
    }

    if ($succeeded -and (Test-Path $csvPath)) {
        Write-Host "Saved CSV: $csvPath" -ForegroundColor Green
        $manifest.$tableId = [ordered]@{
            fileName = $csvName
            remoteVersion = ($remoteVersion -as [string])
            lastDownloaded = (Get-Date).ToString("o")
        }
        Save-Manifest -m $manifest
        $downloaded++
    } else {
        Write-Warning "Failed to export table $tableId - no CSV saved."
    }
}

Write-Host "`nDone. CSVs saved to: $outputDir"
Write-Host "Downloaded: $downloaded ; Skipped: $skipped"
Write-Host "Manifest saved to: $manifestPath"

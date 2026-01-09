
# ---------- CONFIG ----------
$useHapiKey   = $false
$hapikey      = "<YOUR_HAPIKEY_IF_USING_IT>"
$accessToken  = ""
$outputDir    = "C:\HubSpotSitePages"
$manifestPath = Join-Path $outputDir "manifest.json"
$limit        = 50   # page size for pagination (adjust if needed)
$maxProbeRetries = 2
# -----------------------------

# sanity
if (-not $useHapiKey -and (-not $accessToken -or $accessToken -match "<YOUR")) {
    Write-Error "Set a valid $accessToken or enable hapikey mode (`$useHapiKey = $true`)."; return
}
if ($useHapiKey -and (-not $hapikey -or $hapikey -match "<YOUR")) {
    Write-Error "Set a valid $hapikey or disable hapikey mode."; return
}
if (-not (Test-Path $outputDir)) { New-Item -Path $outputDir -ItemType Directory | Out-Null }

# headers
$headers = @{}
if (-not $useHapiKey) { $headers = @{ "Authorization" = "Bearer $accessToken"; "Accept" = "application/json" } }
else { $headers = @{ "Accept" = "application/json" } }

# load manifest
$manifest = @{}
if (Test-Path $manifestPath) {
    try { $manifest = (Get-Content $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop) } catch { $manifest = @{} }
}
if (-not $manifest) { $manifest = @{} }

function Save-Manifest($m) { $m | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8 }

function Build-Url($base, $qs) {
    $query = ""
    if ($qs -and $qs.Count -gt 0) {
        $pairs = @()
        foreach ($k in $qs.Keys) { $pairs += "$k=$([uri]::EscapeDataString($qs[$k]))" }
        $query = $pairs -join "&"
    }
    if ($useHapiKey) {
        if ($query) { return "$base`?$query&hapikey=$hapikey" } else { return "$base?hapikey=$hapikey" }
    } else {
        if ($query) { return "$base`?$query" } else { return $base }
    }
}

function SanitizeName([string]$n) {
    if (-not $n) { return [guid]::NewGuid().ToString() }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) { $n = $n.Replace($c, "_") }
    $n = $n.Trim()
    if ($n.Length -eq 0) { $n = [guid]::NewGuid().ToString() }
    return $n
}

# ---- Probe candidate endpoints to find one that lists pages for this account ----
$probes = @(
    @{ name = "GET cms v3 site-pages"; method = "GET";  url = "https://api.hubapi.com/cms/v3/pages/site-pages"; qs = @{ limit = $limit; offset = 0 } },
    @{ name = "GET cms v3 landing-pages"; method = "GET";  url = "https://api.hubapi.com/cms/v3/pages/landing-pages"; qs = @{ limit = $limit; offset = 0 } },
    @{ name = "GET legacy v2 pages list"; method = "GET"; url = "https://api.hubapi.com/content/api/v2/pages"; qs = @{ limit = $limit; offset = 0 } }
)

Write-Host "Probing page-list endpoints..."
$workingProbe = $null
foreach ($p in $probes) {
    $url = Build-Url -base $p.url -qs $p.qs
    Write-Host "  Trying [$($p.name)] $url"
    $ok = $false
    for ($i=1; $i -le $maxProbeRetries; $i++) {
        try {
            $resp = Invoke-RestMethod -Uri $url -Method $p.method -Headers $headers -ErrorAction Stop
            $ok = $true; break
        } catch {
            Start-Sleep -Seconds (2 * $i)
        }
    }
    if ($ok) {
        Write-Host "    Probe succeeded: $($p.name)" -ForegroundColor Green
        $workingProbe = $p; break
    } else {
        Write-Warning "    Probe failed: $($p.name)"
    }
}

if (-not $workingProbe) { Write-Error "No listing endpoint worked for your account/token. Check token scopes (CMS Pages)."; return }

# ---- Listing + pagination (offset-based) ----
function Get-AllPages($baseUrl) {
    $all = @()
    $offset = 0
    while ($true) {
        $qs = @{ limit = $limit; offset = $offset }
        $url = Build-Url -base $baseUrl -qs $qs
        try {
            $resp = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
        } catch {
            Write-Error "Failed to list pages at offset $offset : $($_.Exception.Message)"
            break
        }
        # common shapes: results / objects / list
        if ($resp -and $resp.results) { $items = $resp.results }
        elseif ($resp -and $resp.objects) { $items = $resp.objects }
        elseif ($resp -and $resp.length -and $resp -is [System.Array]) { $items = $resp }
        else { $items = @() }

        if ($items.Count -eq 0) { break }
        $all += $items
        Write-Host "  Fetched page offset $offset -> items: $($items.Count) total so far: $($all.Count)"
        $offset += $limit
    }
    return $all
}

# choose listing base URL from working probe
$listingBase = $workingProbe.url

Write-Host "Listing pages from chosen endpoint: $($workingProbe.name)"
$pages = Get-AllPages -baseUrl $listingBase
if (-not $pages -or $pages.Count -eq 0) { Write-Warning "No pages found. Exiting."; return }
Write-Host "Total pages discovered: $($pages.Count)" -ForegroundColor Green

# ---- Helpers to fetch a single page object (full content) ----
function Get-PageDetails($pageId) {
    $url = Build-Url -base ("https://api.hubapi.com/cms/v3/pages/site-pages/$pageId") -qs @{}
    try {
        $r = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
        return $r
    } catch {
        return $null
    }
}

function Get-RemoteFingerprintViaHead($pageUrl) {
    try {
        $h = Invoke-WebRequest -Uri $pageUrl -Method Head -UseBasicParsing -ErrorAction Stop
        $len = $h.Headers.'Content-Length'; $lm = $h.Headers.'Last-Modified'
        if ($len -or $lm) { return ("{0}|{1}" -f ($len -as [string]), ($lm -as [string])) }
    } catch { return $null }
    return $null
}

# ---- Download loop with manifest-based dedupe ----
$downloaded = 0; $skipped = 0
foreach ($p in $pages) {
    # page id fields vary; pick the obvious ones
    $pageId = $null
    if ($p.id) { $pageId = $p.id } elseif ($p.objectId) { $pageId = $p.objectId } elseif ($p.pageId) { $pageId = $p.pageId }
    if (-not $pageId) { Write-Warning "Skipping page without id"; continue }

    # friendly filename: try slug -> name -> id
    $name = $null
    if ($p.slug) { $name = $p.slug } elseif ($p.name) { $name = $p.name } elseif ($p.htmlTitle) { $name = $p.htmlTitle } else { $name = $pageId }
    $name = SanitizeName $name
    $outName = "{0}_{1}.json" -f $name, $pageId
    $outPath = Join-Path $outputDir $outName

    # remote version checks (common fields: updatedAt, createdAt, publishDate)
    $remoteVersion = $null
    if ($p.updatedAt) { $remoteVersion = $p.updatedAt }
    elseif ($p.updated) { $remoteVersion = $p.updated }
    elseif ($p.createdAt) { $remoteVersion = $p.createdAt }
    elseif ($p.publishDate) { $remoteVersion = $p.publishDate }

    # check manifest
    $existing = $null
    try { $existing = $manifest.$pageId } catch { $existing = $null }

    $needDownload = $true
    if ($existing) {
        if ($remoteVersion -and $existing.remoteVersion -and ($existing.remoteVersion -eq $remoteVersion) -and (Test-Path (Join-Path $outputDir $existing.fileName))) {
            $needDownload = $false
        } 
    }

    if (-not $needDownload) {
        $skipped++; Write-Host "Skipped (up-to-date): $outName" -ForegroundColor DarkGray
        continue
    }

    # fetch full page details (gives layoutSections/content)
    $full = Get-PageDetails -pageId $pageId
    if (-not $full) { Write-Warning "Failed to fetch details for page $pageId - skipping"; continue }

    # save the JSON dump
    try {
        $full | ConvertTo-Json -Depth 12 | Set-Content -Path $outPath -Encoding UTF8
        Write-Host "Saved page: $outName" -ForegroundColor Green
        $downloaded++
        # update manifest entry
        $manifest.$pageId = [ordered]@{
            fileName = $outName
            remoteVersion = ($remoteVersion -as [string])
            lastDownloaded = (Get-Date).ToString("o")
        }
        Save-Manifest -m $manifest
    } catch {
        Write-Warning "Failed to save page $pageId : $($_.Exception.Message)"
    }
}

Write-Host "`nDone. Downloaded: $downloaded ; Skipped: $skipped"
Write-Host "Manifest saved to: $manifestPath"

# Simple HubSpot files downloader with dedupe by manifest + push new files to Azure Repos
# Set these before running:
$useHapiKey  = $false
$hapikey     = "<YOUR_HAPIKEY_IF_USING_IT>"
$accessToken = "<YOUR_HUBSPOT_PRIVATE_APP_TOKEN>"   # recommended: private app token (pat-...)
$outputDir   = "C:\HubSpotFiles"
$manifestPath = Join-Path $outputDir "manifest.json"
$limit = 100   # page size (HubSpot commonly supports up to 100)

# --- AZURE REPO CONFIG: set these to enable pushing ---
$azureRepoUrl = "https://dev.azure.com/<Org>/<Project>/_git/<RepoName>"  # do NOT include credentials here
$azurePat     = "<YOUR_AZURE_DEVOPS_PAT>"
$azureUser    = "azureuser"   # arbitrary username for URL-auth (kept generic)
$branch       = "main"
# =======================================================

# --- sanity / setup ---
if (-not $useHapiKey -and (-not $accessToken -or $accessToken -match "<YOUR")) {
    Write-Error "Set a valid access token in `$accessToken or switch to hapikey mode."
    return
}
if ($useHapiKey -and (-not $hapikey -or $hapikey -match "<YOUR")) {
    Write-Error "Set a valid hapikey or switch to token mode."
    return
}
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

# headers
$headers = @{}
if (-not $useHapiKey) {
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Accept"        = "application/json"
    }
} else {
    $headers = @{ "Accept" = "application/json" }
}

# load manifest (maps fileId -> metadata)
$manifest = @{}
if (Test-Path $manifestPath) {
    try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $manifest = @{} }
}
if (-not $manifest) { $manifest = @{} }

function Save-Manifest { param($m) $m | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8 }

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

function SanitizeFileName([string]$n) {
    if (-not $n) { return [guid]::NewGuid().ToString() }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalid) { $n = $n.Replace($c, "_") }
    $n = $n.Trim()
    if ($n.Length -eq 0) { $n = [guid]::NewGuid().ToString() }
    return $n
}

# Try to list all files via GET files.v3/files/search (works for your account)
function Get-AllFiles {
    $all = @()
    $after = $null
    do {
        $qs = @{ limit = $limit }
        if ($after) { $qs.after = $after }
        $url = Build-Url -base "https://api.hubapi.com/files/v3/files/search" -qs $qs

        try {
            $resp = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
        } catch {
            Write-Error "Failed to list files: $($_.Exception.Message)"
            return $all
        }

        # response shapes vary: results / files / objects
        if ($null -ne $resp.results) { $items = $resp.results }
        elseif ($null -ne $resp.files) { $items = $resp.files }
        elseif ($null -ne $resp.objects) { $items = $resp.objects }
        else { $items = @() }

        $all += $items

        if ($resp.paging -and $resp.paging.next -and $resp.paging.next.after) { $after = $resp.paging.next.after } else { $after = $null }

        Write-Host "Fetched page; items this page: $($items.Count) total so far: $($all.Count)"
    } while ($after)
    return $all
}

function Get-SignedUrl($fileId) {
    $url = Build-Url -base ("https://api.hubapi.com/files/v3/files/$fileId/signed-url") -qs @{ }
    try {
        $r = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
    } catch {
        return $null
    }
    if ($r.url) { return $r.url }
    if ($r.signedUrl) { return $r.signedUrl }
    if ($r.signed_url) { return $r.signed_url }
    return $null
}

function Get-RemoteFingerprint($downloadUrl) {
    # try HEAD to get Content-Length and Last-Modified. If not allowed, return $null.
    try {
        $head = Invoke-WebRequest -Uri $downloadUrl -Method Head -UseBasicParsing -ErrorAction Stop
        $len = $null; $lm = $null
        if ($head.Headers.'Content-Length') { $len = $head.Headers.'Content-Length' }
        if ($head.Headers.'Last-Modified') { $lm = $head.Headers.'Last-Modified' }
        if ($len -or $lm) { return ("{0}|{1}" -f ($len -as [string]), ($lm -as [string])) }
    } catch {
        return $null
    }
    return $null
}

# Main: download loop (collect newly downloaded file names for pushing)
Write-Host "Listing files from HubSpot..."
$files = Get-AllFiles
if (-not $files -or $files.Count -eq 0) {
    Write-Warning "No files found or listing failed. Exiting."
    return
}
Write-Host "Total files discovered: $($files.Count)" -ForegroundColor Green

$downloaded = 0; $skipped = 0
$newDownloads = @()   # will store full path of files downloaded in this run

foreach ($f in $files) {
    # obtain id
    $fileId = $null
    if ($f.id) { $fileId = $f.id } elseif ($f.objectId) { $fileId = $f.objectId } elseif ($f.fileId) { $fileId = $f.fileId } elseif ($f.uuid) { $fileId = $f.uuid }
    if (-not $fileId) { Write-Warning "Skipping item with no id"; continue }

    # determine display name
    $name = $f.name
    if (-not $name -and $f.url) {
        try { $name = [System.IO.Path]::GetFileName([uri]$f.url).Split('?')[0] } catch { $name = $fileId }
    }
    $name = SanitizeFileName $name

    # determine remote version timestamp (check several common fields)
    $remoteVersion = $null
    if ($f.updated) { $remoteVersion = $f.updated }
    elseif ($f.updatedAt) { $remoteVersion = $f.updatedAt }
    elseif ($f.created) { $remoteVersion = $f.created }
    elseif ($f.createdAt) { $remoteVersion = $f.createdAt }
    elseif ($f.timestamp) { $remoteVersion = $f.timestamp }

    # get signed url (preferred)
    $downloadUrl = $null
    if ($fileId) { $downloadUrl = Get-SignedUrl -fileId $fileId }

    # fallback to file.url if signed url not available
    if (-not $downloadUrl -and $f.url) { $downloadUrl = $f.url }

    if (-not $downloadUrl) {
        Write-Warning "No downloadable URL for $fileId - skipping."
        continue
    }

    # fingerprint fallback via HEAD (if remoteVersion is empty)
    $remoteFinger = $null
    if (-not $remoteVersion) { $remoteFinger = Get-RemoteFingerprint -downloadUrl $downloadUrl }

    # check manifest for existing entry
    $existing = $null
    try { $existing = $manifest.$fileId } catch { $existing = $null }

    $needDownload = $true
    if ($existing) {
        if ($remoteVersion) {
            if ($existing.remoteVersion -and ($existing.remoteVersion -eq $remoteVersion)) { $needDownload = $false }
        } elseif ($remoteFinger) {
            if ($existing.remoteFinger -and ($existing.remoteFinger -eq $remoteFinger) -and (Test-Path (Join-Path $outputDir $existing.fileName))) {
                $needDownload = $false
            }
        } else {
            # no reliable remote fingerprint; if file exists locally and same name, skip
            $localPath = Join-Path $outputDir $existing.fileName
            if (Test-Path $localPath) { $needDownload = $false }
        }
    }

    if (-not $needDownload) {
        $skipped++; Write-Host "Skipped (up-to-date): $name" -ForegroundColor DarkGray
        continue
    }

    # if name already exists locally for a different file, append id to avoid clobber
    $destName = $name
    $destPath = Join-Path $outputDir $destName
    if (Test-Path $destPath) {
        if (-not $existing -or $existing.fileName -ne $destName) {
            $ext = [System.IO.Path]::GetExtension($destName)
            $base = [System.IO.Path]::GetFileNameWithoutExtension($destName)
            $destName = "{0}_{1}{2}" -f $base, $fileId, $ext
            $destPath = Join-Path $outputDir $destName
        }
    }

    # download
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $destPath -UseBasicParsing -ErrorAction Stop
        Write-Host "Downloaded: $destName" -ForegroundColor Green
        $downloaded++
        $newDownloads += $destPath

        # update manifest
        $manifest.$fileId = [ordered]@{
            fileName = $destName
            remoteVersion = ($remoteVersion -as [string])
            remoteFinger = ($remoteFinger -as [string])
            lastDownloaded = (Get-Date).ToString("o")
        }
        Save-Manifest -m $manifest
    } catch {
        Write-Warning "Failed to download $destName : $($_.Exception.Message)"
        continue
    }
}

Write-Host "`nDone. Downloaded: $downloaded ; Skipped: $skipped"
Write-Host "Manifest saved to: $manifestPath"

# === AZURE REPOS PUSH LOGIC ===
if (-not $azureRepoUrl -or $azureRepoUrl -match "<Org>" -or -not $azurePat -or $azurePat -match "<YOUR") {
    Write-Host "Azure Repo not configured (azureRepoUrl or azurePat missing). Skipping push to Azure Repos."
    return
}

if ($newDownloads.Count -eq 0) {
    Write-Host "No new files downloaded this run — skipping push to Azure Repos." -ForegroundColor Yellow
    return
}

# ensure git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is not installed or not in PATH. Please install git and retry."
    return
}

# Prepare temporary clone folder
$rand = [guid]::NewGuid().ToString().Substring(0,8)
$tempClone = Join-Path $env:TEMP ("hubspot_azure_clone_$rand")
if (Test-Path $tempClone) { Remove-Item -Recurse -Force $tempClone }
New-Item -ItemType Directory -Path $tempClone | Out-Null

# build auth clone URL (username:azurePat must be URL-encoded)
$encPat = [uri]::EscapeDataString($azurePat)
$encUser = [uri]::EscapeDataString($azureUser)
if ($azureRepoUrl.StartsWith("https://")) {
    $authCloneUrl = "https://$encUser`:$encPat@{0}" -f $azureRepoUrl.Substring(8)
} else {
    $authCloneUrl = $azureRepoUrl
}

# Clone the remote branch into temp folder
Write-Host "Cloning Azure repo (branch: $branch) into temp folder..."
$cloneArgs = @("clone","--branch",$branch,"--single-branch",$authCloneUrl,$tempClone)
$cloneProc = & git @cloneArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git clone failed: $cloneProc"
    Remove-Item -Recurse -Force $tempClone -ErrorAction SilentlyContinue
    return
}

# Copy only newly downloaded files into the clone
Write-Host "Copying $($newDownloads.Count) new file(s) into repo..."
$relativePaths = @()
foreach ($fullPath in $newDownloads) {
    $fileName = Split-Path $fullPath -Leaf
    $destPath = Join-Path $tempClone $fileName
    Copy-Item -Path $fullPath -Destination $destPath -Force
    $relativePaths += $fileName
}

# Check git status to see if anything changed
Push-Location $tempClone
try {
    & git add -- $relativePaths | Out-Null
    $status = & git status --porcelain
    if (-not $status) {
        Write-Host "No changes to commit in the repo — skipping push." -ForegroundColor Yellow
        Pop-Location
        Remove-Item -Recurse -Force $tempClone -ErrorAction SilentlyContinue
        return
    }

    # Commit and push
    & git commit -m "Update HubSpot files: $(Get-Date -Format o)" --author "hubspot-sync <noreply@local>" | Out-Null
    # push using auth URL so we don't need to persist credentials
    Write-Host "Pushing changes to Azure Repo..."
    $pushProc = & git push $authCloneUrl HEAD:$branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git push failed: $pushProc"
    } else {
        Write-Host "Push complete."
    }
} finally {
    Pop-Location
    # cleanup
    Remove-Item -Recurse -Force $tempClone -ErrorAction SilentlyContinue
}

# End
Write-Host "Finished: downloaded $downloaded new files and attempted push for those files."

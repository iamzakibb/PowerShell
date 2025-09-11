$systemAccessToken = ''

# Base theme folder name in HubSpot
$baseThemeName = ''

# Subfolders in the HubSpot theme (environments)
$subThemes = @()
# Repo details
$localRepoPath = Join-Path (Get-Location) 'repo'
$repoUrl       = "https://$systemAccessToken@grahamsio.visualstudio.com/CN%20Website/_git/Hubspot"

# 1) Clone repo fresh
if (Test-Path $localRepoPath) {
    Write-Host "Removing existing folder $localRepoPath..."
    Remove-Item -Recurse -Force $localRepoPath
}
Write-Host "Cloning repo from $repoUrl..."
git clone $repoUrl $localRepoPath 2>&1 | Write-Host
Set-Location $localRepoPath

# Ensure themes root exists in working copy (will be created/cleaned per branch)
$themesRoot = Join-Path $localRepoPath 'themes'
if (-not (Test-Path $themesRoot)) { New-Item -ItemType Directory -Path $themesRoot -Force | Out-Null }

foreach ($subTheme in $subThemes) {
    # HubSpot accepts theme path like "BaseTheme/Subfolder"
    $themeName = "$baseThemeName/$subTheme"

    # Create safe branch name (theme-cnmw-dev, etc)
    $safeName = $subTheme.ToLower() `
        -replace '[^a-z0-9]', '-' `
        -replace '-+', '-'
    $safeName = $safeName.Trim('-')
    $branchName = "theme-$safeName"

    # Destination folder inside repo for this subtheme (use sanitized folder name)
    $folderSafe = $safeName -replace '-', '_'   # optional: convert to underscores for filesystem clarity
    $dest = Join-Path $themesRoot $folderSafe

    Write-Host "`n=== Processing: $themeName -> Branch: $branchName -> Dest: $dest ==="

    # 2) Create or checkout branch (local)
    & git checkout -B $branchName 2>&1 | Write-Host

    # 2.a) If remote branch exists, pull it first (safe)
    & git remote set-url origin $repoUrl 2>&1 | Out-Null
    & git ls-remote --heads origin $branchName > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Remote branch $branchName exists — pulling latest..."
        & git pull --rebase origin $branchName 2>&1 | Write-Host
    } else {
        Write-Host "Remote branch $branchName does not exist — continuing with local branch."
    }

    # Ensure dest is clean (remove previous contents so fetch writes a single authoritative snapshot)
    if (Test-Path $dest) {
        Write-Host "Cleaning existing destination folder: $dest"
        try { Remove-Item -Recurse -Force -LiteralPath $dest -ErrorAction Stop } catch { Write-Warning "Could not clean ${dest}: $($_.Exception.Message)" }
    }
    # Recreate destination parent to be safe
    $parentDir = Split-Path -Path $dest -Parent
    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

    # 3) Fetch the theme from HubSpot into the dedicated destination
    Write-Host "Fetching HubSpot theme '$themeName' into '$dest'..."
    try {
        $hsOutput = hs fetch "$themeName" "$dest" --overwrite 2>&1
        Write-Host $hsOutput
    } catch {
        Write-Warning ("hs fetch threw for '{0}': {1}" -f $themeName, $_.Exception.Message)
    }

    # Ensure the dest exists and contains files — if not, log and skip commit
    $fetchedFiles = Get-ChildItem -Path $dest -Recurse -File -ErrorAction SilentlyContinue
    if (-not $fetchedFiles -or $fetchedFiles.Count -eq 0) {
        Write-Warning "No files were fetched into $dest; skipping commit for $branchName."
        continue
    }

    # === IMPORTANT: remove other subtheme folders so branch contains only this subtheme ===
    Write-Host "Pruning other folders under themes/ so branch contains only '$folderSafe'..."
    try {
        $otherDirs = Get-ChildItem -Path $themesRoot -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -ne $folderSafe }
        foreach ($od in $otherDirs) {
            Write-Host "Removing $($od.FullName) (will be recorded as deletion in git)"
            try { Remove-Item -Recurse -Force -LiteralPath $od.FullName -ErrorAction Stop } catch { Write-Warning ("Failed to remove {0}: {1}" -f $od.FullName, $_.Exception.Message) }
        }
    } catch {
        Write-Warning ("Could not prune other folders: {0}" -f $_.Exception.Message)
    }

    # Stage only the folder for this subtheme (and record deletions)
    $relPath = "themes/$folderSafe"
    Write-Host "Staging $relPath (adds + deletions)..."
    & git add --all $relPath 2>&1 | Write-Host

    # Also stage deletions from themes root (in case pruning removed other subthemes)
    & git add --all 'themes' 2>&1 | Out-Null

    # Commit & push if there are staged changes
    if (-not (git diff --cached --quiet)) {
        Write-Host "Changes detected. Committing & pushing..."
        & git config user.name  'AutomatedBuild' 2>&1 | Out-Null
        & git config user.email 'build@yourdomain.com' 2>&1 | Out-Null
        & git commit -m ("Automated sync of HubSpot subtheme '{0}' → {1}" -f $subTheme, $branchName) 2>&1 | Write-Host

        Write-Host "Pushing to origin/$branchName ..."
        $pushOut = & git push origin ("HEAD:" + $branchName) 2>&1
        Write-Host $pushOut
    } else {
        Write-Host "No changes detected for $themeName - nothing to commit."
    }
}

Write-Host "`n✅ All sub-themes processed."

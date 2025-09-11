# === Configuration ===
$apiKey = "<YOUR_HUBSPOT_API_KEY_OR_ACCESS_TOKEN>"
$headers = @{ Authorization = "Bearer $apiKey" }
$searchEndpoint = "https://api.hubapi.com/files/v3/files/search"
$fileDetailsEndpoint = "https://api.hubapi.com/files/v3/files"
$localFolder = "C:\HubSpotFiles"

# Ensure target folder exists
if (!(Test-Path $localFolder)) {
    New-Item -ItemType Directory -Path $localFolder | Out-Null
}

# Pagination variables
$after = $null
$allFiles = @()

do {
    $body = @{ limit = 100 }
    if ($after) { $body.after = $after }

    $response = Invoke-RestMethod -Method Post -Uri $searchEndpoint -Headers $headers -Body ($body | ConvertTo-Json)
    $allFiles += $response.results

    $after = $response.paging?.next?.after
} while ($after)

Write-Host "Found $($allFiles.Count) files."

# Download each file
foreach ($file in $allFiles) {
    $fileId = $file.id
    $details = Invoke-RestMethod -Method Get -Uri "$fileDetailsEndpoint/$fileId" -Headers $headers
    $downloadUrl = $details.url

    if ($downloadUrl) {
        $fileName = Split-Path $downloadUrl -Leaf
        $destination = Join-Path $localFolder $fileName
        Invoke-WebRequest -Uri $downloadUrl -OutFile $destination
        Write-Host "Downloaded: $fileName"
    } else {
        Write-Warning "No URL found for file ID $fileId"
    }
}

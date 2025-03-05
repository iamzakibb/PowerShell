$artifactDir = Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY "TicketData"
$sysidFile   = Join-Path $artifactDir "sysid.txt"
#$ticketFile  = Join-Path $artifactDir "ticketNumber.txt"

if (-not (Test-Path $sysidFile)) {
    Write-Host "Error: sysid.txt not found in artifact."
    exit 1
}
# if (-not (Test-Path $ticketFile)) {
#     Write-Host "Warning: ticketNumber.txt not found. Proceeding without ticket number."
# }

$sysID        = Get-Content -Path $sysidFile
# $ticketNumber = Get-Content -Path $ticketFile

Write-Host "Retrieved sysID: $sysID"
# Write-Host "Retrieved ticketNumber: $ticketNumber"

$username   = "your-username"
$password   = "your-password"
$apiUrl     = "https://frsdev.servicenowservices.com/api/now/table/change_request/$sysID"

# Auth headers
$encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
  "Authorization" = "Basic $encodedCreds"
  "Content-Type"  = "application/json"
  "Accept"        = "application/json"
}

# Update body
$body = @{ "state" = "-1" } | ConvertTo-Json

try {
  Write-Host "Updating ticket '$ticketNumber' (sys_id: $sysID) to 'implement'..."
  $response = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $headers -Body $body
  Write-Host "Update successful."

  # Simply display the JSON response as an object
  $response | ConvertTo-Json -Depth 5 | ConvertFrom-Json
}
catch {
    Write-Host "Failed to update ticket '$ticketNumber'."
    Write-Host "Error details: $($_.Exception.Message)"
    exit 1
}

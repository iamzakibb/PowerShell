# Minimal PowerShell script to update a ServiceNow ticket state to "implement" using pipeline variables

# Retrieve pipeline variables
$sysID        = "$(sys_id)"
$ticketNumber = "$(ticketNumber)"

if (-not $sysID) { 
    Write-Host "sys_id missing."
    exit 1
}

Write-Host "Using sys_id: $sysID"

# ServiceNow details
$instance   = "your-instance"
$username   = "your-username"
$password   = "your-password"
$apiUrl     = "https://$instance.service-now.com/api/now/table/change_request/$sysID"

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
  $response | ConvertTo-Json
}
catch {
    Write-Host "Failed to update ticket '$ticketNumber'."
    Write-Host "Error details: $($_.Exception.Message)"
    exit 1
}

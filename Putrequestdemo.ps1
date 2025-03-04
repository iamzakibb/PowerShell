# Retrieve pipeline variables
$sysID        = "$(sys_id)"
$ticketNumber = "$(ticketNumber)"

if (-not $sysID) { 
    Write-Host "sys_id missing."
    exit 1
}

Write-Host "Using sys_id: $sysID"
#
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

  # Format JSON output into a table
  if ($response.result -is [System.Collections.IDictionary]) {
      $response.result.GetEnumerator() | Select-Object Key, Value | Format-Table -AutoSize
  } else {
      Write-Host "Unexpected response format:"
      $response | ConvertTo-Json -Depth 3
  }
}
catch {
    Write-Host "Failed to update ticket '$ticketNumber'."
    Write-Host "Error details: $($_.Exception.Message)"
    exit 1
}

$orgname = ""
$projectName = ""
$pat = ""

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

$authHeader = @{Authorization = "Basic $base64AuthInfo"}

$variableGroupUrl = "https://tfs.clev.frb.org/$orgname/$projectName/_apis/distributedtask/variablegroups/183?api-version=7.1"

# Fetch latest variable group values
$response = Invoke-RestMethod -Uri $variableGroupUrl -Method Get -Headers $authHeader
$latestSysID = $response.variables.sys_id.value

Write-Host "Latest Sys ID: $latestSysID"

# Retrieve pipeline variables
$sys_id = $latestSysID

if (-not $sys_id) { 
    Write-Host "sys_id missing."
    exit 1
}

Write-Host "Using sys_id: $sys_id"

$username   = "your-username"
$password   = "your-password"
$apiUrl     = "https://frsdev.servicenowservices.com/api/now/table/change_request/$sys_id"

# Auth headers
$encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
  "Authorization" = "Basic $encodedCreds"
  "Content-Type"  = "application/json"
  "Accept"        = "application/json"
}

$startDate = Get-Date -Format "MM/dd/yyyy HH:mm:ss"

$endDate = (Get-Date).AddDays(15).ToString("MM/dd/yyyy HH:mm:ss")
$body = @{ 
  "state"       = "3"
  "close_code"  = "Successfull"
  "close_notes" = "Sample closed notes"
  "start_date"  = $startDate
  "end_date"    = $endDate

} | ConvertTo-Json -Depth 2


try {
  Write-Host "Updating ticket (sys_id: $sys_id) to 'Close'..."
  $response = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $headers -Body $body
  Write-Host "Update successful."

  # Simply display the JSON response as an object
  $response | ConvertTo-Json -Depth 5 | ConvertFrom-Json
}
catch {
    Write-Host "Failed to update ticket ."
    Write-Host "Error details: $($_.Exception.Message)"
    exit 1
}

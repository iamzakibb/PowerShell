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

# Update body
$body = @{ 
    "requested_by" = "Malinda Ibe"
 } | ConvertTo-Json


 
try {
  Write-Host "Updating ticket (sys_id: $sys_id) to 'implement'..."
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
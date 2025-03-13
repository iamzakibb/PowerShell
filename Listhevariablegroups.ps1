# Define variables
$organization = "yasirmushtaq7"
$project = "yasir_mushtaq7"
$pat = ""

# Encode PAT for authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{
    Authorization = "Basic $base64AuthInfo"
    "Content-Type" = "application/json"
}

# REST API URL to list all Variable Groups
$uri = "https://dev.azure.com/$organization/$project/_apis/distributedtask/variablegroups?api-version=7.1"

# Get variable groups
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    if ($response.value) {
        Write-Host "✅ Found the following Variable Groups:"
        $response.value | ForEach-Object { Write-Host "ID: $($_.id) - Name: $($_.name)" }
    } else {
        Write-Host "⚠️ No Variable Groups found in project '$project'."
    }
}
 catch {
    Write-Host "❌ Error: Unable to fetch Variable Groups. Check your PAT and permissions."
    Write-Host "🔍 Error Message: $($_.Exception.Message)"
}

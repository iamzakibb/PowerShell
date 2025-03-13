
$pat = "PAT_TOKEN_HERE"
$orgname = "YOURORGNAMEHERE"
$apiUrl   = "https://api.example.com/resource"
$username = "your-username"
$password = "your-password"
$projectID = "PROJECTIDHERE"
$projectName = "PROJECTNAMEHERE"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$authHeader = @{Authorization = "Basic $base64AuthInfo"}
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
    "Authorization" = "Basic $encodedCreds"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}


try {
    Write-Host "Making API call to: $apiUrl"
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -ErrorVariable apiError -ErrorAction SilentlyContinue

    if ($apiError) {
        Write-Host "API Request Failed!"
        Write-Host "Status Code: $($apiError.ErrorDetails.Message)"
        Write-Host "Raw Response: $apiError"
        exit 1
    }

    # Extract Sys ID from API Response
    if ($response -and $response.result) {
        $sysID = $response.result.sys_id.value
        Write-Host "✅ Ticket created successfully. Sys ID: $sysID"
    }
    else {
        Write-Host "⚠️ Unexpected API response format."
        Write-Host "Raw Response: $response"
        exit 1
    }
}
catch {
    Write-Host "❌ API Call Failed: $($_.Exception.Message)"
    exit 1
}

# Construct JSON Body to Update Variable
$body = @{
    description = "Variable Group"
    name = "Sys_id"
    type = "Vsts"
    variables = @{
        sys_id = @{
            isSecret = "false"
            isReadOnly = "false"
            value = "$sysID" 
        }
    }
    variableGroupProjectReferences = @(
        @{
            name = "Sys_id"
            description = "Variable Group"
            projectReference = @{
                id = $projectID
                name = $projectName
            }
        }
    )
} | ConvertTo-Json -Depth 10

# Update Variable in Azure DevOps
try {
    Write-Host "Updating Azure DevOps Variable Group with Sys ID..."
    Invoke-RestMethod -Uri "https://tfs.clev.frb.org/$orgname/$projectName/_apis/distributedtask/variablegroups/183?api-version=7.1" `
    -Method Put `
    -Body $body `
    -Headers $authHeader `
    -ContentType "application/json"

 

    Write-Host "✅ Successfully updated variable group with Sys ID: $sysID"
}
catch {
    Write-Host "❌ Failed to update Azure DevOps Variable Group: $($_.Exception.Message)"
    exit 1
}

Write-Host "✅ Script execution completed successfully."

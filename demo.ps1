# Set Azure DevOps Variables
$orgName    = "ORGnamehere"
$pat        = "PAT_TOKEN_HERE"  # PAT stored as a pipeline variable
$project    = "$(System.TeamProject)"
$releaseId  = "$(Release.ReleaseId)"

# Encode PAT for Authentication
$patToken   = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$authHeader = @{ "Authorization" = "Basic $patToken"; "Content-Type" = "application/json" }

# API Credentials for External Service
$apiUrl   = "https://api.example.com/resource"
$username = "your-username"
$password = "your-password"

# Encode API Credentials
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
    "Authorization" = "Basic $encodedCreds"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

# Call External API
try {
    Write-Host "Making API call to: $apiUrl"
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -ErrorVariable apiError -ErrorAction SilentlyContinue

    if ($apiError) {
        Write-Host "API Request Failed!"
        Write-Host "Status Code: $($apiError.ErrorDetails.Message)"
        Write-Host "Raw Response: $apiError"
        exit 1
    }

    # Check if response contains expected fields
    if ($response -and $response.result) {
        $ticketNumber = $response.result.number.value
        $sysID        = $response.result.sys_id.value

        Write-Host "✅ Ticket created successfully."
        Write-Host "Ticket Number: $ticketNumber"
        Write-Host "Sys ID: $sysID"
    }
    else {
        Write-Host "⚠️ Unexpected API response format. Please verify the API response structure."
        Write-Host "Raw Response: $response"
        exit 1
    }
}
catch {
    Write-Host "❌ API Call Failed: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        Write-Host "HTTP Status Code: $statusCode"

        # Read the response body for detailed error message
        $responseStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $errorResponse = $reader.ReadToEnd()
        Write-Host "Error Response: $errorResponse"
    }
    exit 1
}

# Construct JSON Payload for Azure DevOps REST API
$updateBody = @{
    variables = @{
        "SysID" = @{ value = $sysID }
        "TicketNumber" = @{ value = $ticketNumber }
    }
} | ConvertTo-Json -Depth 3

# Azure DevOps REST API Endpoint for Updating Release Variables
$updateUrl = "https://tfs.clev.frb.org/$orgName/$project/_apis/release/releases?/$releaseId?api-version=7.1"

# Call Azure DevOps API to Update Release Variables
try {
    Write-Host "Updating Azure DevOps Release Variables..."
    Invoke-RestMethod -Uri $updateUrl -Method Put -Headers $authHeader -Body $updateBody

    Write-Host "✅ Successfully updated release variables in Azure DevOps."
}
catch {
    Write-Host "❌ Failed to update Azure DevOps Release Variables: $($_.Exception.Message)"
    exit 1
}

Write-Host "✅ Script execution completed successfully."

Install-Module VSTeam -Scope CurrentUser -Force

# Set VSTeam Account
try {
    Set-VSTeamAccount -Account "ORGnamehere" -PersonalAccessToken "YOUR-PAT-HERE"
}
catch {
    Write-Host "Error setting VSTeam account: $($_.Exception.Message)"
    exit 1
}

# API Credentials
$apiUrl   = "https://api.example.com/resource"
$username = "your-username"
$password = "your-password"

# Encode Credentials
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
    "Authorization" = "Basic $encodedCreds"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

# Call API with Error Handling
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

# Get VSTeam Release Info
try {
    Write-Host "Fetching VSTeam Release details..."
    $r = Get-VSTeamRelease -ProjectName "$(System.TeamProject)" -Id $(Release.ReleaseId) -Raw
}
catch {
    Write-Host "Error fetching VSTeam Release: $($_.Exception.Message)"
    exit 1
}

# Add Variables to Release
$r.variables | Add-Member -MemberType NoteProperty -Name "SysID" -Value ([PSCustomObject]@{ value = $sysID })
$r.variables | Add-Member -MemberType NoteProperty -Name "TicketNumber" -Value ([PSCustomObject]@{ value = $ticketNumber })

# Update VSTeam Release
try {
    Write-Host "Updating VSTeam Release with new variables..."
    Update-VSTeamRelease -ProjectName "$(System.TeamProject)" -Id $(Release.ReleaseId) -Release $r -Force
}
catch {
    Write-Host "Error updating VSTeam Release: $($_.Exception.Message)"
    exit 1
}

Write-Host "✅ Script execution completed successfully."

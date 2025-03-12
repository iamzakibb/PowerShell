# Define parameters
$patToken = "PATTOKENHERE"  # Replace with your actual PAT
$orgName = "ORGNAMEHERE"                # Replace with your Azure DevOps organization name
$projectName = "PROJECTNAMEHERE"            # Replace with your project name
$releaseId = "2025"                          # Replace with a valid release ID
$apiVersion = "7.1"               # Correct API version for release pipelines

# Encode PAT Token for authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($patToken)"))

# List of API endpoints to test
$apiUrls = @(
    "https://vsrm.dev.azure.com/$orgName/$projectName/_apis/release/releases?/$releaseId?api-version=$apiVersion",  # Correct URL for release pipelines
    "https://dev.azure.com/$orgName/$projectName/_apis/release/releases?/$releaseId?api-version=$apiVersion"      # Alternative DevOps URL (won't work for releases)
    "https://tfs.clev.frb.org/tfs/$orgName/$projectName/_apis/release/releases/$releaseId?api-version=$apiVersion", # Azure DevOps Server (TFS) format
    "https://tfs.clev.frb.org/DefaultCollection/$projectName/_apis/release/releases/$releaseId?api-version=$apiVersion"
)

# Loop through each API endpoint and test it
foreach ($apiUrl in $apiUrls) {
    try {
        Write-Host "🔄 Testing API: $apiUrl" -ForegroundColor Cyan
        
        # Invoke API request
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{
            Authorization = "Basic $base64AuthInfo"
        }

        Write-Host "✅ SUCCESS: API responded correctly!" -ForegroundColor Green
        Write-Host "Response: $($response | Out-String  )"
        break  # Exit loop if successful
    } catch {
        Write-Host "❌ ERROR: API failed - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "⚠️ StatusCode: $($_.Exception.Response.StatusCode.Value__)" -ForegroundColor Yellow
    }
}

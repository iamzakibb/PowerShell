# Define variables
$organization = "yasirmushtaq7" # Replace with your Azure DevOps organization name
$projectName = "yasir_mushtaq7" # Replace with your project name
$pat = "PATTOKENHERE" 

# Encode PAT for authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))

# Define API URL
$uri = "https://dev.azure.com/$organization/_apis/projects?api-version=7.1-preview.4"

# Invoke REST API
$response = Invoke-RestMethod -Uri $uri -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get

# Extract project ID
$project = $response.value | Where-Object { $_.name -eq $projectName }
if ($project) {
    Write-Output "Project ID for '$projectName': $($project.id)"
} else {
    Write-Output "Project '$projectName' not found."
}


# ====== INPUTS ======
$tenantId          = "$(TenantId)"
$servicePrincipalId= "$(ServicePrincipalId)"
$servicePrincipalKey= "$(ServicePrincipalKey)"
$subscriptionId    = "$(SubscriptionId)"
$resourceGroupName = "$(ResourceGroupName)"
$logicAppName      = "$(LogicAppName)"

# ====== 1. Get Azure AD Access Token ======
$authBody = @{
    grant_type    = "client_credentials"
    ServicePrincipalId     = $servicePrincipalId
    ServicePrincipalKey = $servicePrincipalKey
    resource      = "https://management.azure.com/"
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" `
    -Body $authBody

$accessToken = $tokenResponse.access_token

if (-not $accessToken) {
    Write-Host "##[error]Failed to get access token"
    exit 1
}

# ====== 2. Call Azure REST API to Get Logic App Details ======
$apiVersion = "2019-05-01"
$uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Logic/workflows/$logicAppName?api-version=$apiVersion"

$response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
    Authorization = "Bearer $accessToken"
}

# ====== 3. Output Logic App Details ======
Write-Host "Logic App Name: $($response.name)"
Write-Host "Location: $($response.location)"
Write-Host "State: $($response.properties.state)"
Write-Host "Definition Version: $($response.properties.provisioningState)"
Write-Host "Kind: $($response.kind)"

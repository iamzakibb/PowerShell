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
    client_id     = $servicePrincipalId
    client_secret = $servicePrincipalKey
    resource      = "https://management.azure.com/"
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" `
    -Body $authBody

$accessToken = $tokenResponse.access_token
# ===== Get latest run =====
$runUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Logic/workflows/$logicAppName/runs?api-version=2019-05-01&$top=1&$orderby=properties/startTime desc"

$latestRun = Invoke-RestMethod -Method Get -Uri $runUri -Headers @{ Authorization = "Bearer $accesstoken" }

if (-not $latestRun.value -or $latestRun.value.Count -eq 0) {
    Write-Host "No runs found for Logic App: $logicAppName"
    exit 1
}

$lastRunStatus = $latestRun.value[0].properties.status
$lastRunId = $latestRun.value[0].name
$lastRunTime = $latestRun.value[0].properties.startTime

Write-Host "Latest Run ID: $lastRunId"
Write-Host "Start Time: $lastRunTime"
Write-Host "Status: $lastRunStatus"

# ===== Decide pipeline outcome =====
if ($lastRunStatus -eq "Succeeded") {
    Write-Host "Logic App last run succeeded ✅"
    exit 0
} else {
    Write-Host "Logic App last run FAILED ❌"
    exit 1
}
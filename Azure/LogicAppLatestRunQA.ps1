# ====== INPUTS ======
$tenantIdQA          = "$(TenantIdQA)"
$servicePrincipalIdQA = "$(ServicePrincipalIdQA)"
$servicePrincipalKeyQA = "$(ServicePrincipalKeyQA)"
$subscriptionIdQA    = "$(SubscriptionIdQA)"
$resourceGroupNameQA = "$(ResourceGroupNameQA)"
$logicAppNameQA      = "$(LogicAppNameQA)"


# ====== 1. Get Azure AD Access Token ======
$authBody = @{
    grant_type    = "client_credentials"
    client_id     = $servicePrincipalIdQA
    client_secret = $servicePrincipalKeyQA
    resource      = "https://management.azure.com/"
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantIdQA/oauth2/token" `
    -Body $authBody

$accessToken = $tokenResponse.access_token
# ===== Get latest run =====
$runUri = "https://management.azure.com/subscriptions/$subscriptionIdQA/resourceGroups/$resourceGroupNameQA/providers/Microsoft.Logic/workflows/$logicAppNameQA/runs?api-version=2019-05-01&$top=1&$orderby=properties/startTime desc"

$latestRun = Invoke-RestMethod -Method Get -Uri $runUri -Headers @{ Authorization = "Bearer $accesstoken" }

if (-not $latestRun.value -or $latestRun.value.Count -eq 0) {
    Write-Host "No runs found for Logic App: $logicAppNameQA"
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
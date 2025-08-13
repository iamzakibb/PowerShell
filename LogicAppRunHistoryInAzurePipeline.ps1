
$resourceGroupName = "$(ResourceGroupName)"
$logicAppName = "$(LogicAppName)"
$subscriptionName = "$(AzureSubscription)"
$servicePrincipalId = "$(ServicePrincipalId)"
$servicePrincipalKey = "$(ServicePrincipalKey)"
$tenantId = "$(TenantId)"

 # Check and remove AzureRM modules if installed
$azureRmModules = Get-Module -ListAvailable | Where-Object { $_.Name -like "AzureRM*" }
if ($azureRmModules) {
    Write-Host "AzureRM modules found — uninstalling..."
    $azureRmModules | ForEach-Object {
        try {
            Remove-Module $_.Name -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    try {
        Uninstall-AzureRm -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "AzureRM uninstall skipped (not available)."
    }
} else {
    Write-Host "No AzureRM modules found — skipping removal."
}

# Install Az module (latest version)
Write-Host "Installing Az module..."
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force -AllowClobber

# Import Az.Accounts
Import-Module Az.Accounts -ErrorAction Stop


try {
    # Connect to Azure using Service Principal
    $securePassword = ConvertTo-SecureString $servicePrincipalKey -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($servicePrincipalId, $securePassword)
    
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId -ErrorAction Stop | Out-Null
    Write-Host "##[section]Successfully connected to Azure"

    # Set subscription context if specified
    if ($subscriptionName) { 
        Set-AzContext -Subscription $subscriptionName -ErrorAction Stop | Out-Null
        Write-Host "##[section]Using subscription: $((Get-AzContext).Subscription.Name)"
    }

    # Check if resource group exists
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        Write-Host "##[error]Resource group '$resourceGroupName' not found"
        exit 1
    }
    Write-Host "##[section]Resource group '$resourceGroupName' exists"

    # Check if logic app exists
    $logicApp = Get-AzLogicApp -ResourceGroupName $resourceGroupName -Name $logicAppName -ErrorAction SilentlyContinue
    if (-not $logicApp) {
        Write-Host "##[error]Logic App '$logicAppName' not found"
        exit 1
    }
    Write-Host "##[section]Logic App '$logicAppName' exists"

    # Get run history
    $runs = Get-AzLogicAppRunHistory -ResourceGroupName $resourceGroupName -Name $logicAppName -ErrorAction Stop
    
    if (-not $runs) {
        Write-Host "##[warning]No run history found for Logic App '$logicAppName'"
        exit 0
    }

    $latestRun = $runs | Sort-Object StartTime -Descending | Select-Object -First 1
    Write-Host "##[section]Last run status: $($latestRun.Status)"
    Write-Host "##[section]Start time: $($latestRun.StartTime)"
    Write-Host "##[section]End time: $($latestRun.EndTime)"

    # Check if latest run failed
    if ($latestRun.Status -eq "Failed") {
        Write-Host "##[error]Latest Logic App run failed - blocking pipeline progression"
        exit 1
    }
    elseif ($latestRun.Status -ne "Succeeded") {
        Write-Host "##[warning]Latest Logic App run status: $($latestRun.Status) - pipeline will continue"
    }
}
catch {
    Write-Host "##[error]Error: $_"
    Write-Host "##[debug]Current subscription: $((Get-AzContext).Subscription.Name)"
    exit 1
}
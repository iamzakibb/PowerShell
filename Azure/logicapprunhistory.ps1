

$resourceGroupName = ""
$logicAppName = ""
$subscriptionName = ""
try {
    # Set subscription context if specified
    if ($subscriptionName) {
        Set-AzContext -Subscription $subscriptionName -ErrorAction Stop | Out-Null
        Write-Host "Using subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Cyan
    }

    # Check if resource group exists
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        throw "Resource group '$resourceGroupName' not found in subscription '$(Get-AzContext).Subscription.Name'"
    }
    Write-Host "Resource group '$resourceGroupName' exists" -ForegroundColor Green

    # Check if logic app exists
    $logicApp = Get-AzLogicApp -ResourceGroupName $resourceGroupName -Name $logicAppName -ErrorAction SilentlyContinue
    if (-not $logicApp) {
        throw "Logic App '$logicAppName' not found in resource group '$resourceGroupName'"
    }
    Write-Host "Logic App '$logicAppName' exists" -ForegroundColor Green

    # Get run history
    try {
        $runs = Get-AzLogicAppRunHistory -ResourceGroupName $resourceGroupName -Name $logicAppName -ErrorAction Stop
        
        if (-not $runs) {
            Write-Host "No run history found for Logic App '$logicAppName'" -ForegroundColor Yellow
            exit
        }

        $latestRun = $runs | Sort-Object StartTime -Descending | Select-Object -First 1
        Write-Host "Last run status: $($latestRun.Status)" -ForegroundColor Cyan
        Write-Host "Start time: $($latestRun.StartTime)"
        Write-Host "End time: $($latestRun.EndTime)"
    }
    catch {
        Write-Host "Error retrieving run history: $_" -ForegroundColor Red
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Current subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Yellow
    Write-Host "Available resource groups: $( (Get-AzResourceGroup).ResourceGroupName -join ', ' )" -ForegroundColor Yellow
}
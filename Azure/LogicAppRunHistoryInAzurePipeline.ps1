# --- inputs (from pipeline variables) ---
$resourceGroupName = "$(ResourceGroupName)"
$logicAppName      = "$(LogicAppName)"
$subscriptionName  = "$(AzureSubscription)"
$servicePrincipalId= "$(ServicePrincipalId)"
$servicePrincipalKey= "$(ServicePrincipalKey)"
$tenantId          = "$(TenantId)"

# ---- Bootstrap: unload conflicting modules, uninstall AzureRM if present (no Az import) ----
$ProgressPreference = 'SilentlyContinue'

function Get-Environment {
    Write-Host "Preparing session: removing loaded Az/AzureRM modules and attempting AzureRM uninstall (no Az import)."

    # Remove any currently loaded Az/AzureRM modules from the session (best-effort)
    $loaded = Get-Module -Name AzureRM* -ErrorAction SilentlyContinue
    if ($loaded) {
        Write-Host "Removing loaded Az/AzureRM modules from session..."
        foreach ($m in $loaded) {
            try {
                Remove-Module -Name $m.Name -Force -ErrorAction SilentlyContinue
                Write-Host "Removed module $($m.Name)"
            } catch {
                Write-Host "Warning: could not remove module $($m.Name) from session: $_"
            }
        }
    } else {
        Write-Host "No Az/AzureRM modules loaded in session."
    }

    # Attempt to uninstall AzureRM only if Uninstall-AzureRm helper exists
    if (Get-Command -Name Uninstall-AzureRm -ErrorAction SilentlyContinue) {
        Write-Host "Uninstall-AzureRm helper found. Attempting to uninstall AzureRM (best-effort)..."
        try {
            Uninstall-AzureRm -Force -ErrorAction SilentlyContinue
            Write-Host "Uninstall-AzureRm executed (if AzureRM existed it was removed)."
        } catch {
            Write-Host "AzureRM uninstall skipped or failed (likely not present) - continuing."
        }
    } else {
        Write-Host "Uninstall-AzureRm not found - skipping AzureRM uninstall."
    }

    # IMPORTANT: do not import Az modules here (per request).
    # Instead, check that the required Az cmdlets are already available in the environment.
    if (-not (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)) {
        Write-Host "##[error]Az cmdlets (e.g. Connect-AzAccount) are not available in this session."
        Write-Host "This script intentionally does not import or install Az. Please ensure Az is preinstalled on the agent or use the AzurePowerShell@* task."
        throw "Az cmdlets not present"
    } else {
        Write-Host "Az cmdlets detected in session (no import performed)."
    }
}

# Run prepare
try {
    Get-Environment
} catch {
    Write-Host "##[error]Could not prepare environment: $_"
    exit 1
}

# --- Main logic (unchanged) ---
try {
    # Connect to Azure using Service Principal
    $securePassword = ConvertTo-SecureString $servicePrincipalKey -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($servicePrincipalId, $securePassword)
    
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId -ErrorAction Stop | Out-Null
    Write-Host "##[section]Successfully connected to Azure"

    # Set subscription context if specified
    if ($subscriptionName) { 
        Set-AzContext -Subscription $subscriptionName -ErrorAction Stop | Out-Null
        $ctx = Get-AzContext -ErrorAction SilentlyContinue
        $subName = if ($ctx -and $ctx.Subscription) { $ctx.Subscription.Name } else { $subscriptionName }
        Write-Host "##[section]Using subscription: $subName"
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

    # Only attempt to get context info if the cmdlet exists
    if (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue) {
        try {
            $ctx = Get-AzContext -ErrorAction SilentlyContinue
            if ($ctx -and $ctx.Subscription) {
                Write-Host "##[debug]Current subscription: $($ctx.Subscription.Name)"
            } else {
                Write-Host "##[debug]No Az context available."
            }
        } catch {
            Write-Host "##[debug]Could not retrieve Az context: $_"
        }
    } else {
        Write-Host "##[debug]Get-AzContext cmdlet not available in this session."
    }

    exit 1
}

# --- inputs (from pipeline variables) ---
$resourceGroupName = "$(ResourceGroupName)"
$logicAppName      = "$(LogicAppName)"
$subscriptionName  = "$(AzureSubscription)"
$servicePrincipalId= "$(ServicePrincipalId)"
$servicePrincipalKey= "$(ServicePrincipalKey)"
$tenantId          = "$(TenantId)"

# ---- Bootstrap Az modules: unload conflicting modules, uninstall AzureRM if present, then import Az ----
$ProgressPreference = 'SilentlyContinue'

function Prepare-Az {
    Write-Host "Preparing PowerShell session for Az modules..."

    # Remove any currently loaded Az/AzureRM modules from the session (best-effort)
    $loaded = Get-Module -Name Az*,AzureRM* -ErrorAction SilentlyContinue
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

    # Attempt to uninstall AzureRM only if the Uninstall-AzureRm helper is available
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

    # Now ensure Az is available on the agent (we will NOT install it here)
    $azAvailable = Get-Module -ListAvailable -Name Az* -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $azAvailable) {
        Write-Host "##[error]Az module not found on this agent. This script expects Az to be preinstalled."
        Write-Host "Either switch to the AzurePowerShell@* task (recommended) or install Az on the agent image."
        throw "Az module not present"
    } else {
        Write-Host "Az module present on system: $($azAvailable.Name) $($azAvailable.Version)"
    }

    # Import the Az module (force) to ensure cmdlets like Connect-AzAccount are available
    try {
        Import-Module Az -Force -ErrorAction Stop
        Write-Host "Imported Az modules into session."
    } catch {
        # If importing the full Az fails, try importing core accounts module as fallback
        Write-Host "Warning: Import-Module Az failed: $_"
        Write-Host "Attempting to import Az.Accounts specifically..."
        try {
            Import-Module Az.Accounts -Force -ErrorAction Stop
            Write-Host "Imported Az.Accounts into session."
        } catch {
            Write-Host "##[error]Failed to import Az modules. Aborting. Error: $_"
            throw
        }
    }
}

# Call prepare
try {
    Prepare-Az
} catch {
    Write-Host "##[error]Could not prepare Az modules. Aborting."
    Write-Host "Error details: $_"
    exit 1
}

# --- Main logic (unchanged except safer debug handling in catch) ---
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

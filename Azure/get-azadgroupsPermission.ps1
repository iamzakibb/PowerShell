# PowerShell script to show AD groups and their RBAC access in Azure subscription

# 1. Install required modules if not present
#    Install-Module Az -Scope CurrentUser

# Connect-AzAccount
$PATH = (Get-Location).Path
$groupNamePattern = "edai-pci*"  # Change this to your pattern

$subscriptionId = "YOUR-SUBSCRIPTION-ID-HERE"  # Replace with your subscription ID
# 2. Connect to Azure
try {
    Write-Host "Attempting to connect to Azure..." -ForegroundColor Cyan
    Connect-AzAccount -ErrorAction Stop | Out-Null
    Write-Host "Successfully connected to Azure" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to connect to Azure" -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    exit 1
}

# 3. Set your subscription ID


if ($subscriptionId -eq "YOUR-SUBSCRIPTION-ID-HERE") {
    Write-Host "ERROR: Please replace 'YOUR-SUBSCRIPTION-ID-HERE' with your actual subscription ID" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "Setting Azure context to subscription: $subscriptionId" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
    Write-Host "Successfully set subscription context" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to set subscription context" -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    exit 1
}

# 4. Set your AD group search pattern

Write-Host "Searching for groups with pattern: $groupNamePattern" -ForegroundColor Cyan
Write-Host "Checking access in subscription: $subscriptionId`n" -ForegroundColor Cyan

# 5. Find matching groups
try {
    $matchingGroups = @(Get-AzAdGroup -Filter "DisplayName -startswith 'edai-pci'" -ErrorAction Stop | 
                      Where-Object {$_.DisplayName -like $groupNamePattern} |
                      Select-Object DisplayName, Id)
    
    Write-Host "Found $($matchingGroups.Count) groups matching pattern`n" -ForegroundColor Green
    
    if ($matchingGroups.Count -eq 0) {
        Write-Host "No groups found matching pattern '$groupNamePattern'. Exiting." -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "ERROR: Failed to retrieve AD groups" -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    exit 1
}

# 6. Check RBAC assignments for each group
$results = @()

foreach ($group in $matchingGroups) {
    try {
        Write-Host "Checking RBAC for: $($group.DisplayName)" -ForegroundColor Yellow
        
        # Get role assignments for this group
        $roleAssignments = @(Get-AzRoleAssignment -ObjectId $group.Id -ErrorAction SilentlyContinue)
        
        if ($roleAssignments.Count -gt 0) {
            foreach ($assignment in $roleAssignments) {
                $scope = $assignment.Scope
                $scopeType = if ($scope -match "/resourceGroups/") { "Resource Group" }
                            elseif ($scope -match "/subscriptions/") { "Subscription" }
                            elseif ($scope -match "/managementGroups/") { "Management Group" }
                            else { "Resource" }
                
                $results += [PSCustomObject]@{
                    GroupName = $group.DisplayName
                    Role = $assignment.RoleDefinitionName
                    ScopeType = $scopeType
                    Scope = $scope
                    PrincipalType = $assignment.ObjectType
                }
                
                Write-Host "  - $($assignment.RoleDefinitionName) at $scopeType level" -ForegroundColor White
            }
        } else {
            Write-Host "  No RBAC assignments found" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  WARNING: Failed to check RBAC for group '$($group.DisplayName)': $_" -ForegroundColor Yellow
        continue
    }
}

# 7. Display summary table
Write-Host "`n`n=== RBAC ACCESS SUMMARY ===" -ForegroundColor Cyan
if ($results.Count -gt 0) {
    $results | Format-Table -Property GroupName, Role, ScopeType, @{
        Name="ScopeShort"
        Expression={ 
            if ($_.Scope -match "/resourceGroups/([^/]+)") {
                $matches[1]
            } elseif ($_.Scope -match "/subscriptions/([^/]+)") {
                "Entire Subscription"
            } else {
                $_.Scope
            }
        }
    } -AutoSize
    
    # 8. Export to CSV
    try {
        $exportPath = "$PATH\$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        $results | Export-Csv -Path $exportPath -NoTypeInformation -ErrorAction Stop
        Write-Host "`nExported full results to: $exportPath" -ForegroundColor Green
    } catch {
        Write-Host "`nWARNING: Failed to export results to CSV: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "No RBAC assignments found for any matching groups." -ForegroundColor Yellow
}

# 9. Additional: List all unique roles being used
if ($results.Count -gt 0) {
    Write-Host "`n=== ROLES IN USE ===" -ForegroundColor Cyan
    $results | Group-Object Role | ForEach-Object {
        Write-Host "$($_.Name): $($_.Count) assignments" -ForegroundColor White
    }
}

Write-Host "`n=== Script completed successfully ===" -ForegroundColor Green
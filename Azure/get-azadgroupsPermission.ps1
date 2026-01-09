# PowerShell script to show AD groups and their RBAC access in Azure subscription

# 1. Install required modules if not present
#    Install-Module AzureAD -Scope CurrentUser
#    Install-Module Az -Scope CurrentUser

# 2. Connect to Azure AD and Azure
# Connect-AzureAD
Connect-AzAccount

# 3. Set your subscription ID
$subscriptionId = "YOUR-SUBSCRIPTION-ID-HERE"  # Replace with your subscription ID
Set-AzContext -SubscriptionId $subscriptionId

# 4. Set your AD group search pattern
$groupNamePattern = "edai-pci*"  # Change this to your pattern

Write-Host "Searching for groups with pattern: $groupNamePattern" -ForegroundColor Cyan
Write-Host "Checking access in subscription: $subscriptionId`n" -ForegroundColor Cyan

# 5. Find matching groups
$matchingGroups = Get-AzureADGroup -Filter "startswith(DisplayName, 'edai-pci')" | 
                  Where-Object {$_.DisplayName -like $groupNamePattern} |
                  Select-Object DisplayName, ObjectId

Write-Host "Found $($matchingGroups.Count) groups matching pattern`n" -ForegroundColor Green

# 6. Check RBAC assignments for each group
$results = @()

foreach ($group in $matchingGroups) {
    Write-Host "Checking RBAC for: $($group.DisplayName)" -ForegroundColor Yellow
    
    # Get role assignments for this group
    $roleAssignments = Get-AzRoleAssignment -ObjectId $group.ObjectId -ErrorAction SilentlyContinue
    
    if ($roleAssignments) {
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
}

# 7. Display summary table
Write-Host "`n`n=== RBAC ACCESS SUMMARY ===" -ForegroundColor Cyan
if ($results) {
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
    $exportPath = "$env:USERPROFILE\Desktop\GroupRBAC_Audit_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    Write-Host "`nExported full results to: $exportPath" -ForegroundColor Green
} else {
    Write-Host "No RBAC assignments found for any matching groups." -ForegroundColor Yellow
}

# 9. Additional: List all unique roles being used
if ($results) {
    Write-Host "`n=== ROLES IN USE ===" -ForegroundColor Cyan
    $results | Group-Object Role | ForEach-Object {
        Write-Host "$($_.Name): $($_.Count) assignments" -ForegroundColor White
    }
}
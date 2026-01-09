# -----------------------------
# Configuration - update these values
# -----------------------------
$serverName      = ""  # Azure SQL Server FQDN
$databaseName    = ""                                 # Database where user should be created
$adminUser       = ""                                  # Admin login for the database server
$adminPassword   = ""                             # Admin login password

$newUserName     = ""                              # The new contained user to create
$newUserPassword = ""                    

# Allowed IP addresses for this user (firewall rules are server-wide)
$allowedIPs = @("", "")

# -----------------------------
# Step 1: Create the user in the codeninjas database with read and write access
# -----------------------------
$userQuery = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$newUserName')
BEGIN
    CREATE USER [$newUserName] WITH PASSWORD = '$newUserPassword';
END
ALTER ROLE db_datareader ADD MEMBER [$newUserName];
ALTER ROLE db_datawriter ADD MEMBER [$newUserName];
"@

Write-Host "Creating user '$newUserName' in database '$databaseName'..."
try {
    Invoke-Sqlcmd -ServerInstance $serverName `
                  -Database $databaseName `
                  -Username $adminUser `
                  -Password $adminPassword `
                  -Query $userQuery `
                  -ErrorAction Stop -Verbose
    Write-Host "User '$newUserName' created with read-write access in database '$databaseName'."
}
catch {
    Write-Error "Error creating user: $($_.Exception.Message)"
}

# -----------------------------
# Step 2: Create firewall rules for the allowed IP addresses.
# Firewall rules are created in the master database.
# -----------------------------
foreach ($ip in $allowedIPs) {
    # Use a rule name that includes the IP address
    $ruleName = "Allow_$ip"
    $firewallQuery = @"
EXEC sp_set_firewall_rule 
    @name = N'$ruleName', 
    @start_ip_address = '$ip', 
    @end_ip_address = '$ip';
"@
    Write-Host "Setting firewall rule '$ruleName' to allow IP $ip..."
    try {
        Invoke-Sqlcmd -ServerInstance $serverName `
                      -Database "master" `
                      -Username $adminUser `
                      -Password $adminPassword `
                      -Query $firewallQuery `
                      -ErrorAction Stop -Verbose
        Write-Host "Firewall rule '$ruleName' set for IP $ip."
    }
    catch {
        Write-Error "Error setting firewall rule for IP $ip : $($_.Exception.Message)"
    }
}

Write-Host "Script completed."

# Variables: update these with your actual values
$serverName     = "yourserver.database.windows.net"  # Azure SQL Server FQDN
$databaseName   = "codeninjas"                       # Database where user should be created
$adminUser      = "yourAdminUser"                    # Admin login for the database server
$adminPassword  = "yourAdminPassword"                # Admin login password
$newUserName    = "ReadUser"                         # The new contained user to create
$newUserPassword= "YourReadUserStrongPassword!"     # Password for the new user

# Build the T-SQL script to create the user if it does not already exist
$query = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$newUserName')
BEGIN
    CREATE USER [$newUserName] WITH PASSWORD = '$newUserPassword';
END
-- Grant only read access by adding the user to db_datareader role
ALTER ROLE db_datareader ADD MEMBER [$newUserName];
"@

# Run the T-SQL script on the specified database
Invoke-Sqlcmd -ServerInstance $serverName `
              -Database $databaseName `
              -Username $adminUser `
              -Password $adminPassword `
              -Query $query

Write-Host "User '$newUserName' has been created in database '$databaseName' with read-only access."

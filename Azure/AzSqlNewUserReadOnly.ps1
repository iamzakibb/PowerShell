# Variables: update these with your actual values
$serverName     = "" # Azure SQL Server FQDN
$databaseName   = ""                       # Database where user should be created
$adminUser      = ""                    # Admin login for the database server
$adminPassword  = ""                # Admin login password
$newUserName    = ""                         # The new contained user to create
$newUserPassword= ""     # Password for the new user

# Build the T-SQL script to create the user if it does not already exist
$query = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$newUserName')
BEGIN
    CREATE USER [$newUserName] WITH PASSWORD = '$newUserPassword';
END
-- Grant only read access by adding the user to db_datareader role
ALTER ROLE db_datareader ADD MEMBER [$newUserName];
"@

Write-Host "Executing query on server '$serverName', database '$databaseName':"
Write-Host $query
Write-Host "--------------------------------------------"

try {
    $result = Invoke-Sqlcmd -ServerInstance $serverName `
                            -Database $databaseName `
                            -Username $adminUser `
                            -Password $adminPassword `
                            -Query $query `
                            -ErrorAction Stop `
                            -Verbose

    Write-Host "User '$newUserName' should now exist in database '$databaseName' with read-only access."
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    if ($_.Exception.InnerException) {
         Write-Error "Inner exception: $($_.Exception.InnerException.Message)"
    }
}

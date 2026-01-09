# Connect to Azure
Connect-AzAccount

# Define threshold for underutilization
$cpuThreshold = 10
$underutilizedDatabases = @()

# Get all subscriptions you have access to
$subscriptions = Get-AzSubscription

foreach ($sub in $subscriptions) {
    Write-Host "`n== Checking Subscription: $($sub.Name) ==" -ForegroundColor Magenta
    Set-AzContext -SubscriptionId $sub.Id

    # Get all SQL Databases in the current subscription
    $databases = Get-AzSqlDatabase | Where-Object { $_.DatabaseName -ne "master" }

    foreach ($db in $databases) {
        Write-Host "Checking: $($db.ServerName) / $($db.DatabaseName)" -ForegroundColor Cyan

        # Get average CPU usage over last 7 days
        $cpuMetrics = Get-AzMetric -ResourceId $db.Id `
            -TimeGrain 00:01:00 `
            -StartTime (Get-Date).AddDays(-7) `
            -EndTime (Get-Date) `
            -MetricName "cpu_percent"

        $avgCpu = ($cpuMetrics.Data | Measure-Object -Property Average -Average).Average

        if ($avgCpu -lt $cpuThreshold) {
            $underutilizedDatabases += [PSCustomObject]@{
                Subscription  = $sub.Name
                ServerName    = $db.ServerName
                DatabaseName  = $db.DatabaseName
                ResourceGroup = $db.ResourceGroupName
                Location      = $db.Location
                AvgCpuPercent = [Math]::Round($avgCpu, 2)
            }
        }
    }
}

# Output result
if ($underutilizedDatabases.Count -eq 0) {
    Write-Host "No underutilized databases found in any subscription." -ForegroundColor Green
} else {
    Write-Host "`nUnderutilized Azure SQL Databases (CPU < $cpuThreshold%):" -ForegroundColor Yellow
    $underutilizedDatabases | Format-Table -AutoSize
    # Optionally export to CSV
    # $underutilizedDatabases | Export-Csv "UnderutilizedSQLDatabases_AllSubscriptions.csv" -NoTypeInformation
}

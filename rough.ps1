# Get current date and time
$startDate = Get-Date -Format "MM/dd/yyyy HH:mm:ss"

$endDate = (Get-Date).AddDays(15).ToString("MM/dd/yyyy HH:mm:ss")

# JSON object with updated dates
$jsonData = @{
    start_date = $startDate
    end_date = $endDate
} | ConvertTo-Json -Depth 10

# Output JSON
$jsonData | Out-File -FilePath "UpdatedServiceNowData.json"

Write-Output "Updated JSON file created: UpdatedServiceNowData.json"

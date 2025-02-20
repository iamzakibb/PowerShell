
$website = "https://google.com"

if (Test-Connection -ComputerName (New-Object System.Uri($website)).Host -Count 4 -Quiet) {
    Write-Host "$website is reachable." -ForegroundColor Green

   
    try {
        $response = Invoke-WebRequest -Uri $website -UseBasicParsing
        Write-Host "HTTP Status Code: $($response.StatusCode)" -ForegroundColor Cyan
    } catch {
        Write-Host "Failed to retrieve HTTP status. Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "$website is not reachable." -ForegroundColor Red
}

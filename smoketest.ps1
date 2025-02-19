
$website = ""

if (Test-Connection -ComputerName $website -Count 4 -Quiet) {
    Write-Host "$website is reachable." -ForegroundColor Green
} else {
    Write-Host "$website is not reachable." -ForegroundColor Red
}

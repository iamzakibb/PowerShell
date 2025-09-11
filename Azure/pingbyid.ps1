$ipAddress = "142.250.206.174"  # Replace with the IP address you want to ping

if (Test-Connection -ComputerName $ipAddress -Count 2 -Quiet) {
    Write-Output "$ipAddress is reachable"
} else {
    Write-Output "$ipAddress is not reachable"
}

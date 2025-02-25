try {
    $uri = "https://google.com"
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 30
    Write-Host "Status Code: $($response.StatusCode)"
    
    if ($response.StatusCode -eq 200) {
        Write-Host "App is reachable"
    }
    else {
        Write-Host "App is not reachable"
    }
}
catch {
    Write-Host "App is not reachable"
}

try {
    $uri = "https://googlesdsds.com"
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 30
    Write-Host "Status Code: $($response.StatusCode)"
    
    if ($response.StatusCode -eq 200) {
        Write-Host "App is reachable"
    }
    else {
        Write-Host "App is not reachable. Status code: $($response.StatusCode)"
    }
}
catch {
    Write-Host "App is not reachable"
    Write-Host "Error details: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)"
        Write-Host "Status Description: $($_.Exception.Response.StatusDescription)"
    }
}

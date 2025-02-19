$apiUrl = "https://api.example.com/resource"  
$authToken = "token"         

# Set headers
$headers = @{
    "Authorization" = "Bearer $authToken"
    "Content-Type"  = "application/json"
}

# Perform the GET request
$response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers

# Output the response
$response | ConvertTo-Json -Depth 3 

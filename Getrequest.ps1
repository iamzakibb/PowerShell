# Define variables
$apiUrl   = "https://api.example.com/resource" 
$username = "your-username"                    
$password = "your-password"                    

# Create Basic Auth header
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
    "Authorization" = "Basic $encodedCreds"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

try {
    # Perform the API request (GET/POST as required)
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers

    # Validate response structure and capture ticket details
    if ($response -and $response.result) {
        $ticketNumber = $response.result.number
        $sysID        = $response.result.sys_id

        # Display the ticket number and sys_id
        Write-Host "Ticket created successfully."
        Write-Host "Ticket Number: $ticketNumber"
        Write-Host "Sys ID: $sysID"

        # Set pipeline variables for later stages
        Write-Host "##vso[task.setvariable variable=TicketNumber;]$ticketNumber"
        Write-Host "##vso[task.setvariable variable=SysID;]$sysID"
    }
    else {
        Write-Host "Unexpected response format. Please verify the API response."
        # Optionally set the pipeline variables to default values
        Write-Host "##vso[task.setvariable variable=TicketNumber;]none"
        Write-Host "##vso[task.setvariable variable=SysID;]none"
        exit 1
    }
}
catch {
    Write-Host "An error occurred while making the API call: $($_.Exception.Message)"
    # Optionally set the pipeline variables to default values on error
    Write-Host "##vso[task.setvariable variable=TicketNumber;]none"
    Write-Host "##vso[task.setvariable variable=SysID;]none"
    exit 1
}

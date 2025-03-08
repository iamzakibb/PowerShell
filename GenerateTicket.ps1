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
    # Perform the API request
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers

    # Validate response structure and fields
    if ($response -and $response.result -and $response.result.number.value -and $response.result.sys_id.value) {
        $ticketNumber = $response.result.number.value
        $sysID        = $response.result.sys_id.value

        # Display the ticket details
        Write-Host "Ticket created successfully."
        Write-Host "Ticket Number: $ticketNumber"
        Write-Host "Sys ID: $sysID"

        # Set pipeline variables for later stages
        # Write-Host "##vso[task.setvariable variable=SysID;isOutput=true]$sysID"
        # Write-Host "##vso[task.setvariable variable=TicketNumber;isOutput=true]$ticketNumber"

        # Ensure artifact staging directory exists
        $buildDir = $env:SYSTEM_DEFAULTWORKINGDIRECTORY
        if (!(Test-Path $buildDir)) {
            New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
        }
        
        # Define file path
        $artifactFile = Join-Path $buildDir "sysid.txt"
        
        # Write sys_id to file
        Set-Content -Path $artifactFile -Value $sysID
        Write-Host "Sys ID written to file: $artifactFile"
        
        # Verify file existence
        if (Test-Path $artifactFile) {
            Write-Host "✅ sysid.txt successfully created at: $artifactFile"
            Write-Host "File Content: $(Get-Content $artifactFile)"
        } else {
            Write-Host "❌ ERROR: sysid.txt was NOT created!"
            exit 1
        }
    }
    else {
        Write-Host "❌ Unexpected API response format. Missing required fields."
        exit 1
    }
}
catch {
    Write-Host "❌ API call failed: $($_.Exception.Message)"
    if ($_.ErrorDetails) {
        Write-Host "Error details: $($_.ErrorDetails)"
    }
    exit 1
}

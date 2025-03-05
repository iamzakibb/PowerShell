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
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers

    # Validate response structure and capture ticket details
    if ($response -and $response.result) {
        $ticketNumber = $response.result.number.value
        $sysID        = $response.result.sys_id.value

        # Display the ticket number and sys_id
        Write-Host "Ticket created successfully."
        Write-Host "Ticket Number: $ticketNumber"
        Write-Host "Sys ID: $sysID"

        # Set pipeline variables for later stages
       #Write-Host "##vso[task.setvariable variable=SysID;isOutput=true]$sysID"
       #Write-Host "##vso[task.setvariable variable=TicketNumber;isOutput=true]$ticketNumber"
       # Ensure artifact staging directory exists
        $buildDir = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY"
        if (!(Test-Path $buildDir)) {
            New-Item -ItemType Directory -Path $buildDir -Force
        }
        
        # Define file path
        $artifactFile = "$buildDir\sysid.txt"
        
        # Write sys_id to file
        Set-Content -Path $artifactFile -Value $sysID
        Write-Host "Sys ID written to file: $artifactFile"
        
        # Verify file existence
        if (Test-Path $artifactFile) {
            Write-Host "✅ sysid.txt successfully created at: $artifactFile"
            # Output file content for debugging
            Write-Host "File Content:"
            Get-Content $artifactFile
        } else {
            Write-Host "❌ ERROR: sysid.txt was NOT created!"
            exit 1
        }

    }
        else {
        Write-Host "Unexpected response format. Please verify the API response."
        # Optionally set the pipeline variables to default values
        #Write-Host "##vso[task.setvariable variable=TicketNumber;]none"
        #Write-Host "##vso[task.setvariable variable=SysID;]none"
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


Install-Module VSTeam -Scope CurrentUser -Force

Set-VSTeamAccount -Account "ORGnamehere" -PersonalAccessToken "YOUR-PAT-HERE"


$apiUrl   = "https://api.example.com/resource"
$username = "your-username"
$password = "your-password"


$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
    "Authorization" = "Basic $encodedCreds"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

try {
    
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers

   
    if ($response -and $response.result) {
        $ticketNumber = $response.result.number.value
        $sysID        = $response.result.sys_id.value

        Write-Host "Ticket created successfully."
        Write-Host "Ticket Number: $ticketNumber"
        Write-Host "Sys ID: $sysID"

        
        $r = Get-VSTeamRelease -ProjectName "$(System.TeamProject)" -Id $(Release.ReleaseId) -Raw

        
        $r.variables | Add-Member -MemberType NoteProperty -Name "SysID" -Value ([PSCustomObject]@{ value = $sysID })
        $r.variables | Add-Member -MemberType NoteProperty -Name "TicketNumber" -Value ([PSCustomObject]@{ value = $ticketNumber })

        
        Update-VSTeamRelease -ProjectName "$(System.TeamProject)" -Id $(Release.ReleaseId) -Release $r -Force
    }
    else {
        Write-Host "Unexpected response format. Please verify the API response."
        exit 1
    }
}
catch {
    Write-Host "An error occurred while making the API call: $($_.Exception.Message)"
    exit 1
}

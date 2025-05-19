# Define your MongoDB API credentials
$mongoPublicKey = ""
$mongoPrivateKey = ""

# Define the MongoDB group IDs
$mongoGroupIds = @(
    "642c0f86ebf883533358175c"
    
)

$ipAddressesToWhitelist = @(
   
)


# Build the JSON body with all IPs
$ipObjects = @()
foreach ($ip in $ipAddressesToWhitelist) {
    $ipObjects += @{
        ipAddress = $ip
        comment = "Whitelisted by Azure Pipeline"
    }
}
$body = $ipObjects | ConvertTo-Json -Depth 3

# Loop through all groups and whitelist the IPs
foreach ($groupId in $mongoGroupIds) {
    $apiUrl = "https://cloud.mongodb.com/api/atlas/v1.0/groups/$groupId/accessList"
    Write-Output "Sending request to group ID: $groupId"

    $response = Invoke-RestMethod -Uri $apiUrl `
        -Method Post `
        -Body $body `
        -Headers @{
            "Content-Type" = "application/json"
            "Accept" = "application/json"
        } `
        -Credential (New-Object System.Management.Automation.PSCredential($mongoPublicKey, (ConvertTo-SecureString $mongoPrivateKey -AsPlainText -Force))) `
        -ErrorAction Stop

    Write-Output "Whitelist response for Group $groupId"
    $response | ConvertTo-Json -Depth 5
}

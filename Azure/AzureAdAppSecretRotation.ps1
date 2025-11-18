# ===================================================================
# CONFIGURATION
# ===================================================================
$TenantId           = "<TENANT-ID>"
$ClientId           = "<SERVICE-PRINCIPAL-CLIENT-ID>"
$ClientSecret       = "<SERVICE-PRINCIPAL-CLIENT-SECRET>"

$KeyVaultName       = "<KEYVAULT-NAME>"

$DaysToExpire       = 30
$SecretDisplayName  = "Auto-Renewed"
$SecretLifeYears    = 1

# ===================================================================
# FUNCTION: Get OAuth Token for Microsoft Graph
# ===================================================================
function Get-GraphToken {
    try {
        $Body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
        }

        $TokenResponse = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body $Body -ErrorAction Stop

        return $TokenResponse.access_token
    }
    catch {
        Write-Error "Failed to get Graph API token. Check SP permissions and credentials."
        throw
    }
}

# ===================================================================
# FUNCTION: Get OAuth Token for Key Vault
# ===================================================================
function Get-KeyVaultToken {
    try {
        $Body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            resource      = "https://vault.azure.net"
        }

        $TokenResponse = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" `
            -Body $Body -ErrorAction Stop

        return $TokenResponse.access_token
    }
    catch {
        Write-Error "Failed to get Key Vault access token."
        throw
    }
}

# ===================================================================
# FUNCTION: Store Secret in Key Vault REST
# ===================================================================
function Store-SecretInKeyVault {
    param(
        [string]$SecretName,
        [string]$SecretValue
    )

    try {
        $kvToken = Get-KeyVaultToken

        $kvUri = "https://$KeyVaultName.vault.azure.net/secrets/$SecretName?api-version=7.3"

        $payload = @{ value = $SecretValue } | ConvertTo-Json

        Invoke-RestMethod -Method Put `
            -Uri $kvUri `
            -Headers @{ Authorization = "Bearer $kvToken" } `
            -Body $payload `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Host "Stored new secret in Key Vault: $SecretName"
    }
    catch {
        Write-Error "Failed to store secret $SecretName in Key Vault."
        throw
    }
}

# ===================================================================
# FUNCTION: Get All App Registrations
# ===================================================================
function Get-AllAppRegistrations {
    param([string]$AccessToken)

    try {
        $apps = Invoke-RestMethod `
            -Method Get `
            -Uri "https://graph.microsoft.com/v1.0/applications?`$top=999" `
            -Headers @{ Authorization = "Bearer $AccessToken" } `
            -ErrorAction Stop

        if (-not $apps.value) {
            Write-Error "No App Registrations returned by Microsoft Graph."
            return $null
        }

        return $apps.value
    }
    catch {
        Write-Error "Failed to list App Registrations. Check Application.ReadWrite.All permissions."
        throw
    }
}

# ===================================================================
# FUNCTION: Find Expiring Secrets (< N days)
# ===================================================================
function Get-ExpiringSecrets {
    param(
        [array]$Apps,
        [int]$DaysToExpire
    )

    $expiringList = @()

    foreach ($app in $Apps) {
        if (-not $app.passwordCredentials) { continue }

        foreach ($secret in $app.passwordCredentials) {
            $expiry = [datetime]$secret.endDateTime
            $daysLeft = ($expiry - (Get-Date)).Days

            if ($daysLeft -lt $DaysToExpire) {
                $expiringList += [PSCustomObject]@{
                    AppName      = $app.displayName
                    AppObjectId  = $app.id
                    SecretId     = $secret.keyId
                    ExpiryDate   = $expiry
                    DaysLeft     = $daysLeft
                }
            }
        }
    }

    return $expiringList
}

# ===================================================================
# FUNCTION: Delete old secret
# ===================================================================
function Remove-AppSecret {
    param(
        [string]$AccessToken,
        [string]$AppObjectId,
        [string]$SecretId
    )

    try {
        $payload = @{ keyId = $SecretId } | ConvertTo-Json

        Invoke-RestMethod `
            -Method Post `
            -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId/removePassword" `
            -Headers @{ Authorization = "Bearer $AccessToken" } `
            -Body $payload `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Host "Deleted secret $SecretId for App $AppObjectId"
    }
    catch {
        Write-Error "Failed to delete secret $SecretId for App $AppObjectId"
    }
}

# ===================================================================
# FUNCTION: Create new secret
# ===================================================================
function New-AppSecret {
    param(
        [string]$AccessToken,
        [string]$AppObjectId
    )

    try {
        $start = (Get-Date).ToString("o")
        $end   = (Get-Date).AddYears($SecretLifeYears).ToString("o")

        $payload = @{
            passwordCredential = @{
                displayName   = $SecretDisplayName
                startDateTime = $start
                endDateTime   = $end
            }
        } | ConvertTo-Json

        $result = Invoke-RestMethod `
            -Method Post `
            -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjectId/addPassword" `
            -Headers @{ Authorization = "Bearer $AccessToken" } `
            -Body $payload `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Host "Created new secret for App $AppObjectId"
        return $result.secretText
    }
    catch {
        Write-Error "Failed to create new secret for App $AppObjectId"
        throw
    }
}

# ===================================================================
# FUNCTION: Full Renewal Process for One App
# ===================================================================
function Renew-AppSecrets {
    param(
        [string]$AccessToken,
        [pscustomobject]$SecretEntry
    )

    $app = $SecretEntry

    Write-Host "Renewing secret for App: $($app.AppName)"

    Remove-AppSecret -AccessToken $AccessToken `
                     -AppObjectId $app.AppObjectId `
                     -SecretId $app.SecretId

    $newSecret = New-AppSecret -AccessToken $AccessToken -AppObjectId $app.AppObjectId

    $secretName = "appsecret-$($app.AppObjectId)-current"

    Store-SecretInKeyVault -SecretName $secretName -SecretValue $newSecret

    Write-Host "Renewal completed for App $($app.AppName)"
}

# ===================================================================
# MAIN EXECUTION
# ===================================================================
Write-Host "Starting App Registration Secret Rotation"

$token = Get-GraphToken
$apps  = Get-AllAppRegistrations -AccessToken $token

if (-not $apps) {
    Write-Error "Cannot continue because App Registrations could not be retrieved."
    exit 1
}

Write-Host "Retrieved $($apps.Count) App Registrations."

$expiring = Get-ExpiringSecrets -Apps $apps -DaysToExpire $DaysToExpire

if ($expiring.Count -eq 0) {
    Write-Host "No secrets expiring within $DaysToExpire days."
    exit
}

Write-Host "Expiring secrets found:"
$expiring | Format-Table AppName, AppObjectId, DaysLeft, ExpiryDate

foreach ($item in $expiring) {
    Renew-AppSecrets -AccessToken $token -SecretEntry $item
}

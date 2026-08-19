Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-VidAzdEnvironment {
    $values = & azd env get-values 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read the azd environment: $($values -join [Environment]::NewLine)"
    }

    foreach ($line in @($values)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2).Replace('\"', '"')
        }
        Set-Item -Path "Env:$name" -Value $value
    }
}

function Get-VidEnvironmentValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Default = '',
        [switch]$Required
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Required) { throw "Required azd environment value '$Name' is missing." }
        return $Default
    }
    return $value
}

function Set-VidEnvironmentValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [switch]$Force
    )

    $current = [Environment]::GetEnvironmentVariable($Name)
    if (-not $Force -and $current -ceq $Value) { return }

    $output = & azd env set $Name -- $Value 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to set azd environment value '$Name': $($output -join [Environment]::NewLine)"
    }
    Set-Item -Path "Env:$Name" -Value $Value
}

function Initialize-VidEnvironmentDefaults {
    $domainWasSpecified = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('VERIFIED_ID_DOMAIN'))
    $accountJson = & az account show --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI is not signed in. Run 'az login' for the target tenant. $($accountJson -join ' ')"
    }
    $account = $accountJson | ConvertFrom-Json

    $organizationJson = & az rest --method get --url 'https://graph.microsoft.com/v1.0/organization?$select=displayName,verifiedDomains' --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to discover the tenant organization and verified domains from Microsoft Graph. $($organizationJson -join ' ')"
    }
    $organization = @((($organizationJson | ConvertFrom-Json).value))[0]
    if ($null -eq $organization) { throw 'Microsoft Graph did not return the tenant organization.' }
    $verifiedDomains = @($organization.verifiedDomains)
    $primaryDomain = @($verifiedDomains | Where-Object { $_.isDefault -and -not $_.isInitial })[0]
    if ($null -eq $primaryDomain) { $primaryDomain = @($verifiedDomains | Where-Object { -not $_.isInitial })[0] }
    if ($null -eq $primaryDomain) { $primaryDomain = @($verifiedDomains | Where-Object { $_.isDefault })[0] }
    if ($null -eq $primaryDomain -or [string]::IsNullOrWhiteSpace($primaryDomain.name)) {
        throw 'The tenant does not expose a verified primary domain for the did:web default.'
    }
    $defaultDisplayName = if ([string]::IsNullOrWhiteSpace($organization.displayName)) { $primaryDomain.name } else { $organization.displayName }
    $defaultDidHostname = "did.$($primaryDomain.name.ToLowerInvariant())"
    if (-not $domainWasSpecified -and $primaryDomain.isInitial) {
        throw "The tenant only exposes the initial domain '$($primaryDomain.name)'. Set VERIFIED_ID_DOMAIN to a hostname in a public DNS zone you control."
    }

    $environmentName = Get-VidEnvironmentValue -Name 'AZURE_ENV_NAME' -Default 'dev'
    $safeEnvironmentName = ($environmentName.ToLowerInvariant() -replace '[^a-z0-9-]', '').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeEnvironmentName)) { $safeEnvironmentName = 'dev' }
    if ($safeEnvironmentName.Length -gt 24) { $safeEnvironmentName = $safeEnvironmentName.Substring(0, 24).TrimEnd('-') }

    $token = (Get-VidSha256Hex -Value "$($account.id):$safeEnvironmentName").Substring(0, 8)
    $defaults = [ordered]@{
        AZURE_SUBSCRIPTION_ID = [string]$account.id
        AZURE_TENANT_ID = [string]$account.tenantId
        AZURE_LOCATION = 'westus2'
        AZURE_RESOURCE_GROUP_NAME = "rg-verified-id-$safeEnvironmentName"
        VERIFIED_ID_DISPLAY_NAME = $defaultDisplayName
        VERIFIED_ID_DOMAIN = $defaultDidHostname
        VERIFIED_ID_EMPLOYEE_LOGO_URI = 'https://uhf.microsoft.com/images/microsoft/RE1Mu3b.png'
        VERIFIED_ID_EMPLOYEE_LOCALE = 'en-US'
        VERIFIED_ID_EMPLOYEE_CARD_TITLE = 'Verified Employee'
        VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR = '#000000'
        VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR = '#FFFFFF'
        VERIFIED_ID_EMPLOYEE_CARD_DESCRIPTION = 'This verifiable credential is issued to all members of the {displayName} org.'
        VERIFIED_ID_EMPLOYEE_LOGO_DESCRIPTION = 'Default verified employee logo'
        VERIFIED_ID_EMPLOYEE_CONSENT_TITLE = 'Do you want to accept the verified employee credential from {displayName}.'
        VERIFIED_ID_EMPLOYEE_CONSENT_INSTRUCTIONS = 'Verify your identity and workplace the easy way. Add this ID for online and in-person use.'
        VERIFIED_ID_KEY_VAULT_NAME = "kvvid$token"
        VERIFIED_ID_KEY_VAULT_SKU = 'standard'
        VERIFIED_ID_STATIC_WEB_APP_NAME = "swa-vid-$safeEnvironmentName-$token"
        VERIFIED_ID_STATIC_WEB_APP_LOCATION = 'eastus2'
        VERIFIED_ID_STATIC_WEB_APP_EXISTS = 'false'
        VERIFIED_ID_ENABLE_PURGE_PROTECTION = 'false'
        VERIFIED_ID_KEY_VAULT_EXISTS = 'false'
        VERIFIED_ID_ADMIN_SP_ID = ''
        VERIFIED_ID_SERVICE_SP_ID = ''
        VERIFIED_ID_REQUEST_SP_ID = ''
        VERIFIED_ID_ALLOW_PREMIUM = 'false'
        VERIFIED_ID_SKIP_TENANT_BOOTSTRAP = 'false'
        VERIFIED_ID_RESET_TENANT_ON_DOWN = 'false'
        AZD_VERIFIED_ID_USE_DEVICE_CODE = 'false'
    }

    foreach ($entry in $defaults.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($entry.Key))) {
            Set-VidEnvironmentValue -Name $entry.Key -Value $entry.Value
        }
    }

    Set-VidEnvironmentValue -Name 'VERIFIED_ID_TENANT_PRIMARY_DOMAIN' -Value $primaryDomain.name

    $userObjectId = & az ad signed-in-user show --query id --output tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$userObjectId)) {
        throw "Unable to determine the signed-in user object ID. $($userObjectId -join ' ')"
    }
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_DEPLOYER_OBJECT_ID' -Value ([string]$userObjectId).Trim()

    $vaultName = Get-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_NAME' -Required
    $resourceGroupName = Get-VidEnvironmentValue -Name 'AZURE_RESOURCE_GROUP_NAME' -Required
    $vaultJson = & az keyvault show --subscription $account.id --resource-group $resourceGroupName --name $vaultName --output json 2>$null
    if ($LASTEXITCODE -eq 0) {
        $vault = $vaultJson | ConvertFrom-Json
        if ($vault.tags.'azd-env-name' -ne $environmentName -or $vault.tags.solution -ne 'azd-verified-id') {
            throw "Existing Key Vault '$vaultName' is not owned by azd environment '$environmentName'."
        }
        if ($vault.properties.tenantId -ne $account.tenantId) {
            throw "Existing Key Vault '$vaultName' belongs to a different tenant."
        }
        if ($vault.properties.enableRbacAuthorization -eq $true) {
            throw "Existing Key Vault '$vaultName' uses Azure RBAC, which is incompatible with Verified ID advanced setup."
        }
        $requestedSku = (Get-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_SKU' -Required).ToLowerInvariant()
        if ($vault.properties.sku.name -ne $requestedSku) {
            throw "Existing Key Vault '$vaultName' uses SKU '$($vault.properties.sku.name)', not requested SKU '$requestedSku'."
        }
        if ((ConvertTo-VidBoolean -Value (Get-VidEnvironmentValue -Name 'VERIFIED_ID_ENABLE_PURGE_PROTECTION')) -and
            $vault.properties.enablePurgeProtection -ne $true) {
            throw 'Purge protection must be selected before the first provision. Existing vaults are not modified by Bicep.'
        }
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_EXISTS' -Value 'true'
    } else {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_EXISTS' -Value 'false'
    }

    $staticWebAppName = Get-VidEnvironmentValue -Name 'VERIFIED_ID_STATIC_WEB_APP_NAME' -Required
    $staticWebAppId = "/subscriptions/$($account.id)/resourceGroups/$resourceGroupName/providers/Microsoft.Web/staticSites/$staticWebAppName"
    $staticWebAppJson = & az resource show --ids $staticWebAppId --api-version 2024-11-01 --output json 2>$null
    if ($LASTEXITCODE -eq 0) {
        $staticWebApp = $staticWebAppJson | ConvertFrom-Json
        if ($staticWebApp.tags.'azd-env-name' -ne $environmentName -or $staticWebApp.tags.solution -ne 'azd-verified-id') {
            throw "Existing Static Web App '$staticWebAppName' is not owned by azd environment '$environmentName'."
        }
        $actualLocation = ([string]$staticWebApp.location -replace '\s', '').ToLowerInvariant()
        $requestedLocation = ((Get-VidEnvironmentValue -Name 'VERIFIED_ID_STATIC_WEB_APP_LOCATION' -Required) -replace '\s', '').ToLowerInvariant()
        if ($actualLocation -ne $requestedLocation) {
            throw "Existing Static Web App '$staticWebAppName' is in '$($staticWebApp.location)', not the requested location."
        }
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_STATIC_WEB_APP_EXISTS' -Value 'true'
    } else {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_STATIC_WEB_APP_EXISTS' -Value 'false'
    }
}

Export-ModuleMember -Function *-Vid*

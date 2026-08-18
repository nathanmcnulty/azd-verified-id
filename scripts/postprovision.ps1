[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VerifiedId.psm1') -Force -DisableNameChecking

Import-VidAzdEnvironment
Initialize-VidEnvironmentDefaults
Write-VidStep 'Verified ID tenant bootstrap'

if (ConvertTo-VidBoolean -Value (Get-VidEnvironmentValue -Name 'VERIFIED_ID_SKIP_TENANT_BOOTSTRAP' -Default 'false')) {
    Write-Warning 'Tenant bootstrap was skipped by VERIFIED_ID_SKIP_TENANT_BOOTSTRAP. Azure infrastructure is ready for validation.'
    foreach ($name in @('VERIFIED_ID_TENANT_STATUS', 'VERIFIED_ID_DOMAIN_VALIDATION_STATUS', 'VERIFIED_ID_EMPLOYEE_STATUS', 'VERIFIED_ID_MY_ACCOUNT_STATUS')) {
        Set-VidEnvironmentValue -Name $name -Value 'NotReconciled'
    }
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'InfrastructureOnly'
    return
}

Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'Reconciling'
foreach ($name in @('VERIFIED_ID_TENANT_STATUS', 'VERIFIED_ID_DOMAIN_VALIDATION_STATUS', 'VERIFIED_ID_EMPLOYEE_STATUS', 'VERIFIED_ID_MY_ACCOUNT_STATUS')) {
    Set-VidEnvironmentValue -Name $name -Value 'Reconciling'
}

$hostname = Normalize-VidHostname -Value (Get-VidEnvironmentValue -Name 'VERIFIED_ID_DOMAIN' -Required)
$expectedDid = "did:web:$hostname"
$authorityId = Get-VidEnvironmentValue -Name 'VERIFIED_ID_AUTHORITY_ID'
if ([string]::IsNullOrWhiteSpace($authorityId)) {
    Write-Host 'This operation will onboard Microsoft Entra Verified ID, grant its service principals access to the dedicated Key Vault, and create a did:web authority.'
    Confirm-VidAction -Prompt 'Approve the Verified ID tenant bootstrap?' -ExpectedValue $expectedDid `
        -NonInteractiveConfirmationVariable 'VERIFIED_ID_CONFIRM_BOOTSTRAP_DID'
}

$temporaryApplication = $null
try {
    $temporaryApplication = New-VidTemporaryAdminApplication -TenantId (Get-VidEnvironmentValue -Name 'AZURE_TENANT_ID' -Required)
    Write-VidSuccess 'Temporary administration application authorized'

    $tenantResult = Initialize-VidTenant `
        -AccessToken $temporaryApplication.AccessToken `
        -TenantId (Get-VidEnvironmentValue -Name 'AZURE_TENANT_ID' -Required) `
        -SubscriptionId (Get-VidEnvironmentValue -Name 'AZURE_SUBSCRIPTION_ID' -Required) `
        -ResourceGroupName (Get-VidEnvironmentValue -Name 'AZURE_RESOURCE_GROUP' -Required) `
        -VaultName (Get-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_NAME' -Required) `
        -Hostname $hostname `
        -DisplayName (Get-VidEnvironmentValue -Name 'VERIFIED_ID_DISPLAY_NAME' -Required) `
        -PersistedAuthorityId $authorityId `
        -PersistedContractId (Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CONTRACT_ID')
    Write-VidSuccess "Verified ID authority ready: $($tenantResult.Authority.didModel.did)"

    $domainResult = Deploy-VidDocumentsAndDomain `
        -Documents $tenantResult.Documents `
        -AuthorityId $tenantResult.Authority.id `
        -ExpectedDid $tenantResult.Authority.didModel.did `
        -SubscriptionId (Get-VidEnvironmentValue -Name 'AZURE_SUBSCRIPTION_ID' -Required) `
        -ResourceGroupName (Get-VidEnvironmentValue -Name 'AZURE_RESOURCE_GROUP' -Required) `
        -StaticWebAppName (Get-VidEnvironmentValue -Name 'VERIFIED_ID_STATIC_WEB_APP_NAME' -Required) `
        -StaticWebAppHostname (Get-VidEnvironmentValue -Name 'VERIFIED_ID_STATIC_WEB_APP_HOSTNAME' -Required) `
        -Hostname $hostname

    if ($domainResult.Ready) {
        Invoke-VidWellKnownValidation -AuthorityId $tenantResult.Authority.id -AccessToken $temporaryApplication.AccessToken
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_DOMAIN_VALIDATION_STATUS' -Value 'Validated'
        Write-VidSuccess 'Verified ID accepted the public DID and linked-domain configuration'
    } else {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_DOMAIN_VALIDATION_STATUS' -Value $domainResult.Status
    }

    if ($null -eq $tenantResult.VerifiedEmployeeContract) {
        $credentialRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'credential'
        $rules = Get-Content -LiteralPath (Join-Path $credentialRoot 'verified-employee-rules.json') -Raw | ConvertFrom-Json -Depth 30
        $display = Get-Content -LiteralPath (Join-Path $credentialRoot 'verified-employee-display.json') -Raw | ConvertFrom-Json -Depth 30
        $displayName = Get-VidEnvironmentValue -Name 'VERIFIED_ID_DISPLAY_NAME' -Required
        $display.locale = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_LOCALE' -Required
        $display.card.title = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CARD_TITLE' -Required
        $display.card.backgroundColor = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR' -Required
        $display.card.textColor = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR' -Required
        $display.card.description = (Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CARD_DESCRIPTION' -Required).Replace('{displayName}', $displayName)
        $display.card.issuedBy = $displayName
        $display.card.logo.uri = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_LOGO_URI' -Required
        $display.card.logo.description = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_LOGO_DESCRIPTION' -Required
        $display.consent.title = (Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CONSENT_TITLE' -Required).Replace('{displayName}', $displayName)
        $display.consent.instructions = Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CONSENT_INSTRUCTIONS' -Required

        $logoUri = [Uri]$display.card.logo.uri
        if ($logoUri.Scheme -ne 'https') { throw 'VerifiedEmployee logo URI must use HTTPS.' }
        $logoResponse = Invoke-WebRequest -Uri $logoUri -Method GET -MaximumRedirection 5 -ErrorAction Stop
        if ([int]$logoResponse.StatusCode -ne 200 -or $logoResponse.Headers.'Content-Type' -notmatch '^image/') {
            throw "VerifiedEmployee logo URI did not return an image: $logoUri"
        }

        $tenantResult.VerifiedEmployeeContract = New-VidVerifiedEmployeeContract `
            -AuthorityId $tenantResult.Authority.id -Rules $rules -Display $display `
            -AccessToken $temporaryApplication.AccessToken
        Write-VidSuccess 'Managed VerifiedEmployee credential created'
    } else {
        Write-VidSuccess 'Managed VerifiedEmployee credential discovered; no update was performed'
    }
    Assert-VidVerifiedEmployeeManifest -Contract $tenantResult.VerifiedEmployeeContract `
        -ExpectedDid $tenantResult.Authority.didModel.did `
        -ExpectedLogoUri (Get-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_LOGO_URI' -Required) | Out-Null
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CONTRACT_ID' -Value $tenantResult.VerifiedEmployeeContract.id
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_MANIFEST_URL' -Value $tenantResult.VerifiedEmployeeContract.manifestUrl
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_STATUS' -Value 'Ready'

    $myAccount = Enable-VidMyAccountContract -ContractId $tenantResult.VerifiedEmployeeContract.id `
        -AccessToken $temporaryApplication.AccessToken
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_MY_ACCOUNT_STATUS' -Value 'Enabled'
    if ($myAccount.Changed) {
        Write-VidSuccess 'VerifiedEmployee credential enabled in My Account'
    } else {
        Write-VidSuccess 'VerifiedEmployee credential already enabled in My Account'
    }

    if ($domainResult.Ready -and $null -ne $tenantResult.VerifiedEmployeeContract) {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'Complete'
        Write-VidSuccess 'Verified ID deployment is complete'
    } elseif ($domainResult.Status -eq 'AwaitingHttps') {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'AwaitingHttps'
    } else {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'DnsActionRequired'
    }
} catch {
    $failure = $_
    try { Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'Failed' } catch { Write-Warning 'Unable to persist failed provisioning status.' }
    throw $failure
} finally {
    if ($null -ne $temporaryApplication) {
        Remove-VidTemporaryAdminApplication -TemporaryApplication $temporaryApplication -SuppressErrors
        Write-VidSuccess 'Temporary administration application removed'
    }
}

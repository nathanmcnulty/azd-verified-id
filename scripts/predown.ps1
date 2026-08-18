[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VerifiedId.psm1') -Force -DisableNameChecking

Import-VidAzdEnvironment
Initialize-VidEnvironmentDefaults
$did = Get-VidEnvironmentValue -Name 'VERIFIED_ID_DID' -Default '(unknown DID)'
Write-Warning "Deleting this environment removes the public DID documents and signing Key Vault for $did."

if ([string]::IsNullOrWhiteSpace((Get-VidEnvironmentValue -Name 'VERIFIED_ID_AUTHORITY_ID'))) {
    Write-VidInfo 'No Verified ID authority is recorded for this environment; tenant cleanup is not required.'
    return
}

$hostname = Get-VidEnvironmentValue -Name 'VERIFIED_ID_DOMAIN' -Required
$resetTenant = ConvertTo-VidBoolean -Value (Get-VidEnvironmentValue -Name 'VERIFIED_ID_RESET_TENANT_ON_DOWN' -Default 'false')
if (-not $resetTenant) {
    Confirm-VidAction `
        -Prompt 'The Verified ID tenant authority will remain configured but lose its DID site and signing vault. Continue without tenant reset?' `
        -ExpectedValue $hostname `
        -NonInteractiveConfirmationVariable 'VERIFIED_ID_CONFIRM_RESOURCE_DELETE_DOMAIN'
    return
}

Write-Warning 'Verified ID opt-out is tenant-wide. It removes every authority and contract and invalidates every issued credential in this tenant.'
Confirm-VidAction `
    -Prompt 'Permanently reset Microsoft Entra Verified ID for this tenant?' `
    -ExpectedValue $hostname `
    -NonInteractiveConfirmationVariable 'VERIFIED_ID_CONFIRM_TENANT_RESET_DOMAIN'

$temporaryApplication = $null
try {
    $temporaryApplication = New-VidTemporaryAdminApplication -TenantId (Get-VidEnvironmentValue -Name 'AZURE_TENANT_ID' -Required)
    $authorities = Get-VidAuthorities -AccessToken $temporaryApplication.AccessToken
    $expectedAuthority = Find-VidAuthority -Authorities $authorities -Hostname $hostname `
        -AuthorityId (Get-VidEnvironmentValue -Name 'VERIFIED_ID_AUTHORITY_ID')
    if ($null -eq $expectedAuthority) {
        throw "The expected authority '$did' was not found. Refusing tenant-wide opt-out."
    }
    Assert-VidAuthorityVault -Authority $expectedAuthority `
        -SubscriptionId (Get-VidEnvironmentValue -Name 'AZURE_SUBSCRIPTION_ID' -Required) `
        -ResourceGroupName (Get-VidEnvironmentValue -Name 'AZURE_RESOURCE_GROUP' -Required) `
        -VaultName (Get-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_NAME' -Required)

    Write-Host 'Current tenant authority inventory:'
    foreach ($authority in $authorities) {
        Write-Host "  - $($authority.didModel.did) [$($authority.id)]"
    }
    Invoke-VidTenantOptOut -AccessToken $temporaryApplication.AccessToken
    foreach ($name in @(
        'VERIFIED_ID_AUTHORITY_ID',
        'VERIFIED_ID_DID',
        'VERIFIED_ID_EMPLOYEE_CONTRACT_ID',
        'VERIFIED_ID_EMPLOYEE_MANIFEST_URL',
        'VERIFIED_ID_MY_ACCOUNT_STATUS'
    )) {
        Set-VidEnvironmentValue -Name $name -Value '' -Force
    }
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_TENANT_STATUS' -Value 'NotOnboarded' -Force
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_STATUS' -Value 'NotCreated' -Force
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_PROVISIONING_STATUS' -Value 'TenantReset' -Force
    Write-VidSuccess 'Microsoft Entra Verified ID tenant reset completed'
} finally {
    if ($null -ne $temporaryApplication) {
        Remove-VidTemporaryAdminApplication -TemporaryApplication $temporaryApplication -SuppressErrors
    }
}

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VerifiedId.psm1') -Force -DisableNameChecking

Import-VidAzdEnvironment
Initialize-VidEnvironmentDefaults
Remove-VidOrphanedAdminApplication

$requiredCommands = @('az', 'azd', 'pwsh')
foreach ($command in $requiredCommands) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' is not installed or is not on PATH."
    }
}

$hostname = Normalize-VidHostname -Value (Get-VidEnvironmentValue -Name 'VERIFIED_ID_DOMAIN' -Required)
Set-VidEnvironmentValue -Name 'VERIFIED_ID_DOMAIN' -Value $hostname
Set-VidEnvironmentValue -Name 'VERIFIED_ID_ORIGIN' -Value "https://$hostname/"
Set-VidEnvironmentValue -Name 'VERIFIED_ID_DID' -Value "did:web:$hostname"

$sku = (Get-VidEnvironmentValue -Name 'VERIFIED_ID_KEY_VAULT_SKU' -Required).ToLowerInvariant()
if ($sku -notin @('standard', 'premium')) { throw "Unsupported Key Vault SKU '$sku'." }
if ($sku -eq 'premium' -and -not (ConvertTo-VidBoolean -Value $env:VERIFIED_ID_ALLOW_PREMIUM)) {
    throw "Premium Key Vault requires an explicit deployment opt-in: azd env set VERIFIED_ID_ALLOW_PREMIUM true"
}

$account = (& az account show --output json | ConvertFrom-Json)
if ($account.id -ne $env:AZURE_SUBSCRIPTION_ID -or $account.tenantId -ne $env:AZURE_TENANT_ID) {
    throw 'Azure CLI context does not match the selected azd subscription and tenant.'
}
if ($account.environmentName -ne 'AzureCloud') {
    throw "This template currently supports Azure public cloud only. Current cloud: '$($account.environmentName)'."
}

foreach ($name in @('VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR', 'VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR')) {
    $color = Get-VidEnvironmentValue -Name $name -Required
    if ($color -notmatch '^#[0-9A-Fa-f]{6}$') { throw "$name must be a six-digit hexadecimal color such as #000000." }
}
foreach ($name in @('VERIFIED_ID_ALLOW_PREMIUM', 'VERIFIED_ID_SKIP_TENANT_BOOTSTRAP', 'AZD_VERIFIED_ID_USE_DEVICE_CODE', 'VERIFIED_ID_ENABLE_PURGE_PROTECTION')) {
    ConvertTo-VidBoolean -Value (Get-VidEnvironmentValue -Name $name -Required) | Out-Null
}
Assert-VidGraphBootstrapPermission

Write-VidStep 'Verified ID deployment preflight'
Write-VidInfo "Tenant: $($account.tenantId)"
Write-VidInfo "Subscription: $($account.name) ($($account.id))"
Write-VidInfo "Authority: $env:VERIFIED_ID_DISPLAY_NAME"
Write-VidInfo "DID: $env:VERIFIED_ID_DID"
Write-VidInfo "Key Vault SKU: $sku"
Write-VidSuccess 'Preprovision validation completed'

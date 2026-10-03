[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][guid]$ExpectedTenantId)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VerifiedId.psm1') -Force -DisableNameChecking
Import-VidAzdEnvironment

$tenantId = [guid](Get-VidEnvironmentValue -Name 'AZURE_TENANT_ID' -Required)
$subscriptionId = [guid](Get-VidEnvironmentValue -Name 'AZURE_SUBSCRIPTION_ID' -Required)
if ($tenantId -ne $ExpectedTenantId) { throw 'The expected tenant does not match the selected azd environment.' }

$accountJson = & az account show --subscription $subscriptionId.Guid --output json --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountJson) { throw 'The selected Azure CLI subscription could not be verified.' }
$account = ($accountJson -join "`n") | ConvertFrom-Json
if ($account.id -ne $subscriptionId.Guid -or $account.tenantId -ne $tenantId.Guid) {
    throw 'Azure CLI subscription and tenant do not match the selected azd environment.'
}

if ($PSCmdlet.ShouldProcess($tenantId.Guid, 'Remove recorded temporary Verified ID administration objects')) {
    Remove-VidOrphanedAdminApplication -TenantId $tenantId
}

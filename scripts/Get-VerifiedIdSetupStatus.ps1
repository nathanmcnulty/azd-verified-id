#requires -Version 7.6
[CmdletBinding()]
param(
    [string]$TenantId = $env:AZURE_TENANT_ID,
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    [string]$OperatorObjectId = $env:VERIFIED_ID_DEPLOYER_OBJECT_ID,
    [string]$Hostname = $env:VERIFIED_ID_DOMAIN,
    [string]$StaticWebAppHostname = $env:VERIFIED_ID_STATIC_WEB_APP_HOSTNAME,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$KeyVaultName = $env:VERIFIED_ID_KEY_VAULT_NAME,
    [string]$AuthorityId = $env:VERIFIED_ID_AUTHORITY_ID,
    [string]$ContractId = $env:VERIFIED_ID_EMPLOYEE_CONTRACT_ID,
    [Security.SecureString]$AdminAccessToken
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/VerifiedIdStatus.psm1') -Force
# Explicitly forward resolved defaults; PSBoundParameters omits process-environment defaults.
Get-VerifiedIdSetupStatus -TenantId $TenantId -SubscriptionId $SubscriptionId -OperatorObjectId $OperatorObjectId -Hostname $Hostname -StaticWebAppHostname $StaticWebAppHostname -ResourceGroup $ResourceGroup -KeyVaultName $KeyVaultName -AuthorityId $AuthorityId -ContractId $ContractId -AdminAccessToken $AdminAccessToken | ConvertTo-Json -Depth 8

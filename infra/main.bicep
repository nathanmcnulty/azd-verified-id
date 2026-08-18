targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('The azd environment name.')
param environmentName string

@metadata({
  azd: {
    type: 'location'
  }
})
@description('Primary Azure region for the Key Vault.')
param location string

@description('Resource group name. The preprovision hook supplies a stable default.')
param resourceGroupName string

@description('Globally unique Key Vault name. The preprovision hook supplies a stable default.')
param keyVaultName string

@description('Globally unique Static Web App name. The preprovision hook supplies a stable default.')
param staticWebAppName string

@allowed([
  'standard'
  'premium'
])
@description('Key Vault SKU. Standard is the default and is mandatory for automated tests.')
param keyVaultSku string = 'standard'

@description('Azure Static Web Apps region. Static Web Apps availability is independent of the Key Vault region.')
param staticWebAppLocation string = 'eastus2'

@description('Verified ID authority and credential issuer display name. Defaults to the tenant organization name.')
param verifiedIdDisplayName string

@description('Public did:web hostname. Defaults to did.<tenant-primary-domain>.')
param verifiedIdDomain string

@description('Anonymous HTTPS logo used when creating the VerifiedEmployee credential.')
param employeeLogoUri string = 'https://uhf.microsoft.com/images/microsoft/RE1Mu3b.png'

@description('BCP 47 locale for the VerifiedEmployee display definition.')
param employeeLocale string = 'en-US'

@description('VerifiedEmployee card title.')
param employeeCardTitle string = 'Verified Employee'

@description('VerifiedEmployee card background color as #RRGGBB.')
param employeeCardBackgroundColor string = '#000000'

@description('VerifiedEmployee card text color as #RRGGBB.')
param employeeCardTextColor string = '#FFFFFF'

@description('VerifiedEmployee card description. {displayName} is replaced with the issuer display name.')
param employeeCardDescription string = 'This verifiable credential is issued to all members of the {displayName} org.'

@description('Accessible description for the VerifiedEmployee logo.')
param employeeLogoDescription string = 'Default verified employee logo'

@description('VerifiedEmployee consent title. {displayName} is replaced with the issuer display name.')
param employeeConsentTitle string = 'Do you want to accept the verified employee credential from {displayName}.'

@description('Instructions shown when accepting the VerifiedEmployee credential.')
param employeeConsentInstructions string = 'Verify your identity and workplace the easy way. Add this ID for online and in-person use.'

@allowed([
  'true'
  'false'
])
@description('Explicitly allow Premium when keyVaultSku is premium.')
param allowPremium string = 'false'

@allowed([
  'true'
  'false'
])
@description('Provision Azure infrastructure without changing the Verified ID tenant.')
param skipTenantBootstrap string = 'false'

@allowed([
  'true'
  'false'
])
@description('Use device-code authentication instead of the default system-browser PKCE flow.')
param useDeviceCode string = 'false'

@allowed([
  'true'
  'false'
])
@description('Enable Key Vault purge protection. Recommended for long-lived production authorities.')
param enablePurgeProtection string = 'false'

@description('Object ID of the administrator running the deployment.')
param deployerObjectId string

@allowed([
  'true'
  'false'
])
@description('Whether the dedicated Key Vault already exists. Existing vaults are referenced without replacing their access policies.')
param keyVaultExists string = 'false'

@allowed([
  'true'
  'false'
])
@description('Whether the Static Web App already exists. Existing sites are referenced without replacing provider-managed properties.')
param staticWebAppExists string = 'false'

var resourceToken = toLower(uniqueString(subscription().id, environmentName, resourceGroupName))
var purgeProtectionEnabled = enablePurgeProtection == 'true'
var createKeyVault = keyVaultExists != 'true'
var tags = {
  'azd-env-name': environmentName
  'managed-by': 'azd'
  solution: 'azd-verified-id'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault-${resourceToken}'
  scope: resourceGroup
  params: {
    name: keyVaultName
    location: location
    tenantId: tenant().tenantId
    skuName: keyVaultSku
    enablePurgeProtection: purgeProtectionEnabled
    deployerObjectId: deployerObjectId
    createVault: createKeyVault
    tags: tags
  }
}

module staticWebApp './modules/static-web-app.bicep' = {
  name: 'static-web-app-${resourceToken}'
  scope: resourceGroup
  params: {
    name: staticWebAppName
    location: staticWebAppLocation
    createSite: staticWebAppExists != 'true'
    tags: tags
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_RESOURCE_GROUP_NAME string = resourceGroup.name
output VERIFIED_ID_KEY_VAULT_NAME string = keyVault.outputs.name
output VERIFIED_ID_KEY_VAULT_ID string = keyVault.outputs.resourceId
output VERIFIED_ID_KEY_VAULT_URI string = keyVault.outputs.vaultUri
output VERIFIED_ID_KEY_VAULT_SKU string = keyVaultSku
output VERIFIED_ID_STATIC_WEB_APP_NAME string = staticWebApp.outputs.name
output VERIFIED_ID_STATIC_WEB_APP_ID string = staticWebApp.outputs.resourceId
output VERIFIED_ID_STATIC_WEB_APP_HOSTNAME string = staticWebApp.outputs.defaultHostname
output VERIFIED_ID_STATIC_WEB_APP_LOCATION string = staticWebAppLocation
output VERIFIED_ID_DISPLAY_NAME string = verifiedIdDisplayName
output VERIFIED_ID_DOMAIN string = verifiedIdDomain
output VERIFIED_ID_EMPLOYEE_LOGO_URI string = employeeLogoUri
output VERIFIED_ID_EMPLOYEE_LOCALE string = employeeLocale
output VERIFIED_ID_EMPLOYEE_CARD_TITLE string = employeeCardTitle
output VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR string = employeeCardBackgroundColor
output VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR string = employeeCardTextColor
output VERIFIED_ID_EMPLOYEE_CARD_DESCRIPTION string = employeeCardDescription
output VERIFIED_ID_EMPLOYEE_LOGO_DESCRIPTION string = employeeLogoDescription
output VERIFIED_ID_EMPLOYEE_CONSENT_TITLE string = employeeConsentTitle
output VERIFIED_ID_EMPLOYEE_CONSENT_INSTRUCTIONS string = employeeConsentInstructions
output VERIFIED_ID_ALLOW_PREMIUM string = allowPremium
output VERIFIED_ID_SKIP_TENANT_BOOTSTRAP string = skipTenantBootstrap
output AZD_VERIFIED_ID_USE_DEVICE_CODE string = useDeviceCode

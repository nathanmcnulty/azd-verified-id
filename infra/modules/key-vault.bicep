@minLength(3)
@maxLength(24)
param name string
param location string
param tenantId string

@allowed([
  'standard'
  'premium'
])
param skuName string

param enablePurgeProtection bool
param deployerObjectId string
param createVault bool = true
param tags object = {}

var administratorKeyPermissions = [
  'get'
  'create'
  'delete'
  'list'
  'sign'
  'recover'
  'backup'
  'restore'
]
var keyVaultDnsSuffix = startsWith(environment().suffixes.keyvaultDns, '.')
  ? substring(environment().suffixes.keyvaultDns, 1)
  : environment().suffixes.keyvaultDns
var deployerPolicy = empty(deployerObjectId) ? [] : [
  {
    tenantId: tenantId
    objectId: deployerObjectId
    permissions: {
      keys: administratorKeyPermissions
      secrets: []
      certificates: []
      storage: []
    }
  }
]

var vaultProperties = union({
  tenantId: tenantId
  sku: {
    family: 'A'
    name: skuName
  }
  accessPolicies: deployerPolicy
  enableRbacAuthorization: false
  enabledForDeployment: false
  enabledForDiskEncryption: false
  enabledForTemplateDeployment: false
  softDeleteRetentionInDays: 90
  publicNetworkAccess: 'Enabled'
  networkAcls: {
    bypass: 'AzureServices'
    defaultAction: 'Allow'
  }
}, enablePurgeProtection ? {
  enablePurgeProtection: true
} : {})

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = if (createVault) {
  name: name
  location: location
  tags: tags
  properties: vaultProperties
}

output name string = name
output resourceId string = resourceId('Microsoft.KeyVault/vaults', name)
output vaultUri string = 'https://${name}.${keyVaultDnsSuffix}/'

param name string
param location string
param createSite bool = true
param tags object = {}

resource staticWebApp 'Microsoft.Web/staticSites@2024-11-01' = if (createSite) {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Disabled'
  }
}

resource existingStaticWebApp 'Microsoft.Web/staticSites@2024-11-01' existing = {
  name: name
}

output name string = name
output resourceId string = resourceId('Microsoft.Web/staticSites', name)
output defaultHostname string = createSite ? staticWebApp!.properties.defaultHostname : existingStaticWebApp.properties.defaultHostname

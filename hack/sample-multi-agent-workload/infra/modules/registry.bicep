param name string
param location string
param tags object

resource registry 'Microsoft.ContainerRegistry/registries@2026-11-01' = {
  name: name
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

output name string = registry.name
output resourceId string = registry.id
output loginServer string = registry.properties.loginServer

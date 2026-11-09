param name string
param location string
param tags object

resource keyVault 'Microsoft.KeyVault/vaults@2026-05-15' = {
  name: name
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 7
  }
  tags: tags
}

output name string = keyVault.name
output resourceId string = keyVault.id
output vaultUri string = keyVault.properties.vaultUri

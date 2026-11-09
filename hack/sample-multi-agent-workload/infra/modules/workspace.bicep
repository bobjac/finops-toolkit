param name string
param location string
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: name
  location: location
  sku: {
    name: 'PerGB2018'
  }
  properties: {
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: tags
}

output resourceId string = workspace.id
output customerId string = workspace.properties.customerId

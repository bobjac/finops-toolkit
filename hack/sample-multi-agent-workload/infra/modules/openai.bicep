param name string
param location string
param tags object

resource openAi 'Microsoft.CognitiveServices/accounts@2026-11-01' = {
  name: name
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
  tags: tags
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2026-11-01' = {
  parent: openAi
  name: 'gpt-5-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
  }
}

output resourceId string = openAi.id
output endpoint string = openAi.properties.endpoint
output deploymentName string = deployment.name

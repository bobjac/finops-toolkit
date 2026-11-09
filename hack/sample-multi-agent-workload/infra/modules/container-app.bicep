param name string
param location string
param environmentId string
param image string
param isPlaceholder bool
param registryLoginServer string
param identityResourceId string
param identityClientId string
param keyVaultUri string
param openAiEndpoint string
param openAiDeployment string
param appInsightsConnectionString string
param tags object

var appEnv = isPlaceholder ? [
  {
    name: 'SAMPLE_MODEL_MODE'
    value: 'bootstrap'
  }
  {
    name: 'SAMPLE_DATABASE'
    value: '/app/data/retail.db'
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: identityClientId
  }
  {
    name: 'SAMPLE_REVISION'
    value: tags.revision
  }
] : [
  {
    name: 'SAMPLE_MODEL_MODE'
    value: 'azure-openai'
  }
  {
    name: 'SAMPLE_DATABASE'
    value: '/app/data/retail.db'
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: identityClientId
  }
  {
    name: 'SAMPLE_REVISION'
    value: tags.revision
  }
  {
    name: 'AZURE_OPENAI_ENDPOINT'
    value: openAiEndpoint
  }
  {
    name: 'AZURE_OPENAI_DEPLOYMENT'
    value: openAiDeployment
  }
  {
    name: 'AZURE_OPENAI_API_VERSION'
    value: '2024-10-21'
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  {
    name: 'SAMPLE_API_TOKEN'
    secretRef: 'sample-api-token'
  }
]

resource app 'Microsoft.App/containerApps@2026-07-01' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: isPlaceholder ? [] : [
        {
          server: registryLoginServer
          identity: identityResourceId
        }
      ]
      secrets: isPlaceholder ? [] : [
        {
          name: 'sample-api-token'
          keyVaultUrl: '${keyVaultUri}secrets/sample-api-token'
          identity: identityResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'sample-workload'
          image: image
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: appEnv
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
    }
  }
  tags: tags
}

output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn

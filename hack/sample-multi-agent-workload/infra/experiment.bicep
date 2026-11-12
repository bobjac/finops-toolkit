targetScope = 'resourceGroup'

@description('Run-owned temporary app name, never the retained sample app.')
@minLength(10)
@maxLength(32)
param appName string
@description('Immutable experiment image digest in the existing registry.')
param image string
param identityClientId string
param modelEndpoint string
param modelDeployment string
@secure()
param appInsightsConnectionString string
param tags object

var groupScope = resourceGroup().id

module app 'modules/container-app.bicep' = {
  name: '${appName}-app'
  params: {
    name: appName
    location: 'eastus2'
    environmentId: '${groupScope}/providers/Microsoft.App/managedEnvironments/cae-ftk-dto-hack-s-ae46'
    image: image
    isPlaceholder: false
    minReplicas: 1
    registryLoginServer: 'crftkdtohacksae46.azurecr.io'
    identityResourceId: '${groupScope}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ftk-dto-hack-s-ae46'
    identityClientId: identityClientId
    keyVaultUri: 'https://kv-ftk-dto-hack-s-ae46${environment().suffixes.keyvaultDns}/'
    openAiEndpoint: modelEndpoint
    openAiDeployment: modelDeployment
    appInsightsConnectionString: appInsightsConnectionString
    tags: tags
  }
}

output appName string = app.outputs.name
output fqdn string = app.outputs.fqdn

// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

targetScope = 'resourceGroup'

@description('Deterministic name for this sandbox hub.')
param hubName string

@description('Deterministic name for the development Data Explorer cluster.')
param clusterName string

@description('Sandbox region.')
param location string

@allowed([
  'Dev(No SLA)_Standard_E2a_v4'
])
@description('Approved sandbox Data Explorer SKU.')
param clusterSku string

@description('Ownership, source revision, and expiration tags.')
param tags object

@description('Application ID of the signed-in workflow identity.')
param workflowClientId string

module hub '../release/finops-hub/main.bicep' = {
  name: 'hack-foundation-hub'
  params: {
    hubName: hubName
    location: location
    dataExplorerName: clusterName
    dataExplorerSku: clusterSku
    dataExplorerCapacity: 1
    enableManagedExports: false
    enableRecommendations: false
    scopesToMonitor: []
    tags: tags
  }
}

// The storage name is a hub output, so scoped RBAC needs a child deployment.
module access 'foundation-access.bicep' = {
  name: 'hack-foundation-access'
  params: {
    storageAccountName: hub.outputs.storageAccountName
    clusterName: clusterName
    workflowClientId: workflowClientId
    workflowObjectId: deployer().objectId
  }
}

output storageAccountId string = hub.outputs.storageAccountId
output storageAccountName string = hub.outputs.storageAccountName
output clusterId string = hub.outputs.clusterId
output clusterUri string = hub.outputs.clusterUri
output hubDbName string = hub.outputs.hubDbName
output ingestionDbName string = hub.outputs.ingestionDbName
output dataFactoryName string = hub.outputs.dataFactoryName

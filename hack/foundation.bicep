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

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: hub.outputs.storageAccountName
}

resource storageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, deployer().objectId, 'hack-blob-contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: deployer().objectId
    principalType: 'ServicePrincipal'
  }
}

resource cluster 'Microsoft.Kusto/clusters@2025-02-14' existing = {
  name: clusterName
}

resource databaseAccess 'Microsoft.Kusto/clusters/databases/principalAssignments@2025-02-14' = [for database in ['Hub', 'Ingestion']: {
  name: '${clusterName}/${database}/${guid(cluster.id, database, workflowClientId)}'
  dependsOn: [
    hub
  ]
  properties: {
    principalId: workflowClientId
    principalType: 'App'
    role: 'Admin'
    tenantId: tenant().tenantId
  }
}]

output storageAccountId string = hub.outputs.storageAccountId
output storageAccountName string = hub.outputs.storageAccountName
output clusterId string = hub.outputs.clusterId
output clusterUri string = hub.outputs.clusterUri
output hubDbName string = hub.outputs.hubDbName
output ingestionDbName string = hub.outputs.ingestionDbName
output dataFactoryName string = hub.outputs.dataFactoryName

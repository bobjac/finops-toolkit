// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

targetScope = 'resourceGroup'

@description('Deployed hub storage account name.')
param storageAccountName string

@description('Deployed Data Explorer cluster name.')
param clusterName string

@description('Application ID of the signed-in workflow identity.')
param workflowClientId string

@description('Object ID of the signed-in workflow identity.')
param workflowObjectId string

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, workflowObjectId, 'hack-blob-contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: workflowObjectId
    principalType: 'ServicePrincipal'
  }
}

resource cluster 'Microsoft.Kusto/clusters@2025-02-14' existing = {
  name: clusterName
}

resource databaseAccess 'Microsoft.Kusto/clusters/databases/principalAssignments@2025-02-14' = [for database in ['Hub', 'Ingestion']: {
  name: '${clusterName}/${database}/${guid(cluster.id, database, workflowClientId)}'
  properties: {
    principalId: workflowClientId
    principalType: 'App'
    role: 'Admin'
    tenantId: tenant().tenantId
  }
}]

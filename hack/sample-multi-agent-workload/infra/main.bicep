targetScope = 'subscription'

@description('Deployment environment name.')
param environmentName string
@description('Azure region.')
param location string
@description('Onboarding session identifier.')
param sessionId string
@description('Deployment actor description.')
param deployedBy string
@description('Deployment timestamp.')
param createdAt string
@description('Object ID of the deployment service principal.')
@minLength(36)
@maxLength(36)
param deployerObjectId string
@description('Container image used by the app. Keep the placeholder for bootstrap.')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
@description('When true, omit runtime credentials and model settings.')
param isPlaceholder bool = true
@description('Revision tag for resource ownership and runtime telemetry.')
param revision string = 'ae46'
@description('Optimization experiment identifier.')
param optimizationExperimentId string = 'h05'
@description('Optimization variant.')
param optimizationVariant string = 'baseline'
@description('Expiration date for sandbox resources.')
param expiresOn string = '2026-12-31'

var runtimeIdentityName = 'id-ftk-dto-hack-s-ae46'

var tags = {
  'ftk-tool': 'design-time-optimizer-sample'
  'ftk-workload': 'contoso-outdoor-agent'
  repository: 'bobjac/finops-toolkit'
  revision: revision
  'optimization-experiment-id': optimizationExperimentId
  'optimization-variant': optimizationVariant
  'expires-on': expiresOn
  'app-onboard-skill': 'true'
  environment: environmentName
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'ftk-dto-hack-s-ae46'
  location: location
  tags: union(tags, {
    'created-by': deployedBy
    'created-at': createdAt
    'session-id': sessionId
  })
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: resourceGroup
  params: {
    name: runtimeIdentityName
    location: location
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: resourceGroup
  params: {
    name: 'crftkdtohacksae46'
    location: location
    tags: tags
  }
}

module workspace 'modules/workspace.bicep' = {
  name: 'workspace'
  scope: resourceGroup
  params: {
    name: 'log-ftk-dto-hack-s-ae46'
    location: location
    tags: tags
  }
}

module appInsights 'modules/app-insights.bicep' = {
  name: 'appInsights'
  scope: resourceGroup
  params: {
    name: 'appi-ftk-dto-hack-s-ae46'
    location: location
    workspaceResourceId: workspace.outputs.resourceId
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVault'
  scope: resourceGroup
  params: {
    name: 'kv-ftk-dto-hack-s-ae46'
    location: location
    tags: tags
  }
}

module openAi 'modules/openai.bicep' = {
  name: 'openAi'
  scope: resourceGroup
  params: {
    name: 'oai-ftk-dto-hack-s-ae46'
    location: location
    tags: tags
  }
}

module environment 'modules/container-environment.bicep' = {
  name: 'environment'
  scope: resourceGroup
  params: {
    name: 'cae-ftk-dto-hack-s-ae46'
    location: location
    workspaceName: 'log-ftk-dto-hack-s-ae46'
    workspaceCustomerId: workspace.outputs.customerId
    tags: tags
  }
}

module app 'modules/container-app.bicep' = {
  name: 'app'
  scope: resourceGroup
  params: {
    name: 'ca-ftk-dto-hack-s-ae46'
    location: location
    environmentId: environment.outputs.resourceId
    image: containerImage
    isPlaceholder: isPlaceholder
    registryLoginServer: registry.outputs.loginServer
    identityResourceId: identity.outputs.resourceId
    identityClientId: identity.outputs.clientId
    keyVaultUri: keyVault.outputs.vaultUri
    openAiEndpoint: openAi.outputs.endpoint
    openAiDeployment: openAi.outputs.deploymentName
    appInsightsConnectionString: appInsights.outputs.connectionString
    tags: tags
  }
}

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  scope: resourceGroup
  dependsOn: [
    appInsights
    openAi
  ]
  params: {
    deployerObjectId: deployerObjectId
    runtimePrincipalId: identity.outputs.principalId
    runtimeIdentityResourceId: resourceId(subscription().subscriptionId, resourceGroup.name, 'Microsoft.ManagedIdentity/userAssignedIdentities', runtimeIdentityName)
    registryName: registry.outputs.name
    openAiName: 'oai-ftk-dto-hack-s-ae46'
    keyVaultName: keyVault.outputs.name
    appInsightsName: 'appi-ftk-dto-hack-s-ae46'
  }
}

output resourceGroupName string = resourceGroup.name
output registryName string = registry.outputs.name
output registryLoginServer string = registry.outputs.loginServer
output containerAppName string = app.outputs.name
output keyVaultName string = keyVault.outputs.name
output applicationInsightsResourceId string = appInsights.outputs.resourceId
output workspaceCustomerId string = workspace.outputs.customerId
output modelEndpoint string = openAi.outputs.endpoint
output modelDeployment string = openAi.outputs.deploymentName
output fqdn string = app.outputs.fqdn

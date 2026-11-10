// Viewers need query access to both Application Insights and the hub database.

@description('Azure region for the workbook resource.')
param location string = resourceGroup().location

@description('Resource ID the workbook is scoped to (the App Insights component with gen_ai traces).')
param appInsightsId string

@description('Cluster query endpoint from the verified foundation deployment outputs.')
param hubClusterUri string

@description('Ingestion database from the verified foundation deployment outputs.')
param hubDatabase string

@description('Verified seed meter identities and provenance. Prices are still read live from the hub.')
param priceContext object

@description('Ownership and source tags for the workbook.')
param tags object = {}

@description('Display name shown in the Workbooks gallery.')
param displayName string = 'AI Agent Tokenomics (live hub prices)'

// Parse at runtime so JSON dropdown strings are not evaluated as ARM expressions.
var source = json(loadTextContent('AiAgentTokenomicsLivePrices.workbook'))
var query = loadTextContent('token-cost.kql')
var items = [for item in source.items: union(item, {
  content: contains(item.content, 'query')
    ? union(item.content, { query: replace(item.content.query, '__TOKEN_COST_QUERY__', query) })
    : item.content
})]
var configured = union(source, { items: items })
var withApplication = replace(string(configured), '__APP_INSIGHTS_ID__', appInsightsId)
var withCluster = replace(withApplication, '__HUB_CLUSTER__', hubClusterUri)
var withDatabase = replace(withCluster, '__HUB_DATABASE__', hubDatabase)
var serialized = replace(withDatabase, '__PRICE_CONTEXT__', base64(string(priceContext)))

resource workbook 'microsoft.insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'AiAgentTokenomics-liveprices')
  location: location
  kind: 'shared'
  tags: tags
  properties: {
    displayName: displayName
    category: 'workbook'
    sourceId: appInsightsId
    version: 'Notebook/1.0'
    serializedData: serialized
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name
output workbookUrl string = 'https://portal.azure.com/#@/resource${workbook.id}/workbook'

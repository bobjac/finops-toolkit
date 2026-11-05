// Deploys the "AI Agent Tokenomics" workbook (static gpt-5 rate card) as a
// standalone Azure Monitor workbook resource.
//
// Deploy:
//   az deployment group create -g <resourceGroup> \
//     -f deploy.bicep -p appInsightsId="<app-insights-resource-id>"
//
// Then open: Portal > Monitor > Workbooks (or the App Insights > Workbooks
// gallery) > "AI Agent Tokenomics (static rates)".

@description('Azure region for the workbook resource.')
param location string = resourceGroup().location

@description('Resource ID the workbook is scoped to (the App Insights component with gen_ai traces).')
param appInsightsId string = '/subscriptions/987426a7-38b5-4ab6-b12b-95f5556b5ddf/resourceGroups/rg-vs-analytics-tju4/providers/microsoft.insights/components/tju4-appinsights-4c1ca4e15b31'

@description('Display name shown in the Workbooks gallery.')
param displayName string = 'AI Agent Tokenomics (static rates)'

resource workbook 'microsoft.insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'AiAgentTokenomics-static')
  location: location
  kind: 'shared'
  properties: {
    displayName: displayName
    category: 'workbook'
    sourceId: appInsightsId
    version: 'Notebook/1.0'
    serializedData: loadTextContent('AiAgentTokenomics.workbook')
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name

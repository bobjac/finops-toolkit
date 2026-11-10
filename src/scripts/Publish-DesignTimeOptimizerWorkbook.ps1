# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Deploys and queries the live-price workbook using verified predecessor artifacts.

    .DESCRIPTION
    Runs only through the fork dev workflow and sandbox environment. Never creates
    foundation or sample resources, updates prices, or generates model traffic.
    A failed query or incomplete pricing cannot produce a ready report.

    .PARAMETER SeedDirectory
    Downloaded sandbox-seed artifact, including the second pass and its foundation report.

    .PARAMETER SampleDirectory
    Downloaded successful sample-validation artifact.

    .PARAMETER Operation
    Deploy the workbook or Validate its queries without changing Azure resources.

    .PARAMETER ConfirmResourceGroup
    Exact sample group required for Deploy.

    .PARAMETER OutputDirectory
    Directory for nonsecret query results, deployment parameters, and readiness evidence.

    .EXAMPLE
    ./src/scripts/Publish-DesignTimeOptimizerWorkbook.ps1 -SeedDirectory .tmp/seed -SampleDirectory .tmp/sample -Operation Validate
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$SeedDirectory,
    [Parameter(Mandatory)][string]$SampleDirectory,
    [ValidateSet('Deploy', 'Validate')][string]$Operation = 'Validate',
    [string]$ConfirmResourceGroup,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../.tmp/workbook')
)

$ErrorActionPreference = 'Stop'
$workbookDirectory = Join-Path $PSScriptRoot '../workbooks/optimization/AiAgentTokenomicsLivePrices'
. "$PSScriptRoot/../../hack/sample-multi-agent-workload/eng/Sample-Common.ps1"

function Get-TokenomicsContext
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory)][System.Collections.IDictionary]$SeedReport,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Foundation,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Sample,
        [Parameter(Mandatory)][string]$Subscription
    )
    $coverage = $Metadata.modelCoverage
    if ($Metadata.version -ne 1 -or $SeedReport.Status -ne 'VerifiedAndRetained' -or
        $SeedReport.ReadyForSeededHistory -ne $true -or $SeedReport.BaselineMatch -ne $true -or
        $SeedReport.SourceRevision -cne $Metadata.sourceRevision -or
        $Metadata.sourceRevision -cnotmatch '^[a-f0-9]{40}$' -or
        $Foundation.Status -ne 'VerifiedAndRetained' -or $Foundation.ReadyForDataIngestion -ne $true -or
        $Sample.status -ne 'Completed' -or $Sample.stage -ne 'Validation' -or $Sample.liveVerified -ne $true -or
        $Sample.revision -cnotmatch '^[a-f0-9]{40}$' -or $Sample.subscriptionId -ne $Subscription)
    {
        throw 'Workbook requires successful seed replacement, foundation verification, and live sample artifacts.'
    }
    $scope = "/subscriptions/$Subscription/resourceGroups/"
    $appId = $Sample.outputs.applicationInsightsResourceId.value
    $cluster = $Foundation.Outputs.clusterUri
    if ($Sample.resourceGroup -cnotmatch '^[a-zA-Z0-9_-]+$' -or
        $appId -notmatch "^$([regex]::Escape("$scope$($Sample.resourceGroup)"))/providers/Microsoft.Insights/components/[a-zA-Z0-9_-]+$" -or
        $Foundation.ResourceGroupId -ine "$scope$($Foundation.ResourceGroup)" -or
        $Foundation.Outputs.clusterId -notlike "$($Foundation.ResourceGroupId)/providers/Microsoft.Kusto/clusters/*" -or
        $cluster -cnotmatch '^https://[a-z0-9]+[.][a-z0-9]+[.]kusto[.]windows[.]net/?$' -or
        $Foundation.Outputs.ingestionDbName -cnotmatch '^[a-zA-Z][a-zA-Z0-9_]*$')
    {
        throw 'Workbook outputs must identify the verified sandbox resources and a supported hub endpoint.'
    }
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]$coverage.retrievedAt
    if ($age.TotalSeconds -lt 0 -or $age.TotalDays -gt 7 -or
        $coverage.model -cne $Sample.prices.model -or $coverage.region -cne $Sample.prices.region -or
        $coverage.deploymentSku -cne 'GlobalStandard' -or $Sample.prices.deploymentSku -cne 'GlobalStandard' -or
        $coverage.currency -cne 'USD' -or $coverage.sourceUrl -cnotmatch '^https://prices[.]azure[.]com/api/retail/prices[?]' -or
        (($coverage.requiredMeters.Keys | Sort-Object) -join ',') -cne 'cachedInput,input,output')
    {
        throw 'Price provenance must match the sample model, region, offer, currency, and seven-day freshness policy.'
    }
    $packages = @($Metadata.packages | Where-Object { $_.label -ceq 'model-prices' })
    if ($packages.Count -ne 1 -or $packages[0].profile -cne 'dto-retail-public-v1' -or $packages[0].prices.Count -ne 3)
    {
        throw 'Exactly three verified public-retail model meters are required.'
    }
    $meters = foreach ($direction in 'input', 'cachedInput', 'output')
    {
        $meter = $coverage.requiredMeters[$direction]
        $rows = @($packages[0].prices | Where-Object { $_.meterId -ceq $meter.meterId })
        if ($meter.meterId -cnotmatch '^[a-f0-9-]{36}$' -or $rows.Count -ne 1 -or
            $rows[0].offer -cne 'PUBLIC-RETAIL' -or $rows[0].unit -cne '1M' -or
            $rows[0].blockSize -ne 1000000 -or -not $rows[0].region -or
            $null -eq $rows[0].listPrice -or -not [double]::IsFinite([double]$rows[0].listPrice) -or
            $rows[0].listPrice -le 0 -or $rows[0].listPrice -ne $meter.usdPerMillionTokens -or
            [DateTimeOffset]$rows[0].effectiveStart -ne [DateTimeOffset]$meter.effectiveStart)
        {
            throw "Required model meter '$direction' has invalid identity, units, price, or effective dates."
        }
        @{
            direction = $direction; meterId = $meter.meterId; region = $rows[0].region
            price = $rows[0].listPrice; effectiveStart = $rows[0].effectiveStart
        }
    }
    if (@($meters.meterId | Sort-Object -Unique).Count -ne 3) { throw 'Required meter identities must be distinct.' }
    @{
        appInsightsId = $appId; hubClusterUri = $cluster.TrimEnd('/')
        hubDatabase = $Foundation.Outputs.ingestionDbName
        priceContext = @{
            model = $coverage.model; region = $coverage.region; currency = $coverage.currency
            deploymentSku = $coverage.deploymentSku; retrievedAt = $coverage.retrievedAt
            sourceUrl = $coverage.sourceUrl; seedRevision = $Metadata.sourceRevision; meters = @($meters)
        }
    }
}

function Get-TokenomicsWorkbook
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkbookId)
    $uri = "https://management.azure.com${WorkbookId}?api-version=2022-04-01&canFetchContent=true"
    $workbook = Invoke-SampleAz @('rest', '--method', 'get', '--url', $uri)
    if ([string]::IsNullOrWhiteSpace($workbook.properties.serializedData))
    {
        throw 'Workbook content readback returned no serialized data.'
    }
    return $workbook
}

function Get-TokenomicsQuery
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Parameters,
        [DateTimeOffset]$Start = [DateTimeOffset]::UtcNow.AddDays(-1),
        [DateTimeOffset]$End = [DateTimeOffset]::UtcNow
    )
    $context = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Parameters.priceContext | ConvertTo-Json -Depth 15 -Compress)))
    $Query.Replace('{HubCluster}', $Parameters.hubClusterUri).Replace('{HubDatabase}', $Parameters.hubDatabase).
        Replace('{PriceContext}', $context).Replace('{TimeRange:start}', $Start.UtcDateTime.ToString('o')).
        Replace('{TimeRange:end}', $End.UtcDateTime.ToString('o')).Replace('{Experiment:escapejson}', 'all').
        Replace('{Baseline}', 'baseline').Replace('{Candidate}', 'candidate')
}

function Invoke-TokenomicsQuery
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Query, [Parameter(Mandatory)][string]$ApplicationInsights)
    $result = Invoke-SampleAz @('monitor', 'app-insights', 'query', '--app', $ApplicationInsights, '--analytics-query', $Query)
    if ($result.error -or $result.partialError -or $result.tables.Count -ne 1 -or $result.tables[0].name -ne 'PrimaryResult')
    {
        throw 'Workbook query failed or returned partial results.'
    }
    foreach ($row in $result.tables[0].rows)
    {
        $record = @{}
        for ($column = 0; $column -lt $result.tables[0].columns.Count; $column++)
        {
            $record[$result.tables[0].columns[$column].name] = $row[$column]
        }
        $record
    }
}

function Assert-TokenomicsPreview
{
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Preview, [Parameter(Mandatory)][string]$Scope)
    if ($Preview.status -ne 'Succeeded' -or $null -eq $Preview.changes) { throw 'Workbook preview did not succeed.' }
    foreach ($change in $Preview.changes)
    {
        if ($change.changeType -eq 'Ignore' -and
            ([string]$change.resourceId).StartsWith("$Scope/providers/", [StringComparison]::OrdinalIgnoreCase))
        {
            continue
        }
        if ($change.changeType -notin @('Create', 'Modify', 'NoChange') -or
            $change.resourceId -notmatch "^$([regex]::Escape($Scope))/providers/Microsoft.Insights/workbooks/[a-f0-9-]{36}$")
        {
            throw "Workbook preview rejected '$($change.changeType)' for '$($change.resourceId)': unsupported or out-of-scope change."
        }
        if ($change.changeType -eq 'Modify')
        {
            $existing = Invoke-SampleAz @('resource', 'show', '--ids', $change.resourceId, '--api-version', '2022-04-01')
            if ($existing.tags.'ftk-owner' -cne 'bobjac/finops-toolkit' -or $existing.tags.'ftk-component' -cne 'dto-workbook')
            {
                throw 'Refusing to overwrite an unowned workbook.'
            }
        }
    }
}

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'bobjac/finops-toolkit' -or $env:GITHUB_REF -ne 'refs/heads/dev')
{
    throw 'Use the approved fork dev workbook workflow and sandbox environment.'
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$report = @{ Status = 'Started'; ReadyForWorkbook = $false; SourceRevision = $env:GITHUB_SHA; RunId = $env:GITHUB_RUN_ID }
try
{
    $metadata = Get-Content "$SeedDirectory/seed-second/seed.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $seed = Get-Content "$SeedDirectory/seed-evidence-second/seed-report.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $foundation = Get-Content "$SeedDirectory/seed-evidence-second/foundation/foundation.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $sample = Get-Content "$SampleDirectory/deployment-validation.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $parameters = Get-TokenomicsContext -Metadata $metadata -SeedReport $seed -Foundation $foundation -Sample $sample -Subscription $env:AZURE_SUBSCRIPTION_ID
    Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
    $group = Invoke-SampleAz @('group', 'show', '--name', $sample.resourceGroup)
    Assert-SampleOwnership $group
    if ($foundation.ResourceGroup -cne 'ftk-dto-hack-foundation' -or
        $sample.resourceGroup -cne 'ftk-dto-hack-s-ae46' -or
        [DateTimeOffset]$sample.expiresOn -le [DateTimeOffset]::UtcNow)
    {
        throw 'Workbook deployment must use the existing, unexpired owned sandbox.'
    }
    $actualCluster = Invoke-SampleAz @('resource', 'show', '--ids', $foundation.Outputs.clusterId, '--api-version', '2025-02-14')
    if ($actualCluster.properties.uri.TrimEnd('/') -ine $parameters.hubClusterUri) { throw 'Foundation cluster output no longer matches Azure.' }
    $parameters.tags = @{
        'ftk-owner' = 'bobjac/finops-toolkit'; 'ftk-component' = 'dto-workbook'
        'ftk-source' = $env:GITHUB_SHA; 'ftk-expires-on' = $sample.expiresOn
    }
    $report.Parameters = $parameters
    $report.SampleRevision = $sample.revision
    $report.SeedRevision = $metadata.sourceRevision
    $report.SeedRunId = $seed.RunId
    $report.SampleRunId = $sample.runId
    $report.ResourceGroup = $sample.resourceGroup
    $parameterFile = Join-Path $OutputDirectory 'workbook.parameters.json'
    $armParameters = @{}
    foreach ($key in $parameters.Keys) { $armParameters[$key] = @{ value = $parameters[$key] } }
    @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $armParameters } |
        ConvertTo-Json -Depth 20 | Set-Content $parameterFile
    if ($Operation -eq 'Deploy')
    {
        if ($ConfirmResourceGroup -cne $sample.resourceGroup) { throw 'Confirm the exact sample resource group before workbook deployment.' }
        $arguments = @('--resource-group', $sample.resourceGroup, '--name', 'hack-tokenomics-workbook', '--mode', 'Incremental',
            '--template-file', "$workbookDirectory/deploy.bicep", '--parameters', "@$parameterFile")
        $null = Invoke-SampleAz (@('deployment', 'group', 'validate') + $arguments)
        $preview = Invoke-SampleAz (@('deployment', 'group', 'what-if') + $arguments + @('--no-pretty-print', '--result-format', 'FullResourcePayloads'))
        $report.Preview = @($preview.changes | Select-Object resourceId, changeType)
        Assert-TokenomicsPreview -Preview $preview -Scope $group.id
        if (-not $PSCmdlet.ShouldProcess($group.id, 'Deploy only the owned tokenomics workbook')) { throw 'Workbook deployment was not approved.' }
        $deployment = Invoke-SampleAz (@('deployment', 'group', 'create') + $arguments)
        if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Workbook deployment did not succeed.' }
        $report.DeploymentOutputs = $deployment.properties.outputs
    }
    else
    {
        $deployment = Invoke-SampleAz @('deployment', 'group', 'show', '--resource-group', $sample.resourceGroup, '--name', 'hack-tokenomics-workbook')
        if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'A successful workbook deployment is required before Validate.' }
        $report.DeploymentOutputs = $deployment.properties.outputs
    }
    $template = Get-Content "$workbookDirectory/AiAgentTokenomicsLivePrices.workbook" -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    $base = Get-Content "$workbookDirectory/token-cost.kql" -Raw
    $workbookId = $report.DeploymentOutputs.workbookId.value
    if ($workbookId -notmatch "^$([regex]::Escape($group.id))/providers/Microsoft.Insights/workbooks/[a-f0-9-]{36}$")
    {
        throw 'Workbook deployment output is missing or outside the owned sample group.'
    }
    $actual = Get-TokenomicsWorkbook -WorkbookId $workbookId
    $report.WorkbookRevision = $actual.tags.'ftk-source'
    if ($actual.properties.sourceId -ine $parameters.appInsightsId -or
        $actual.tags.'ftk-owner' -cne 'bobjac/finops-toolkit' -or $actual.tags.'ftk-component' -cne 'dto-workbook')
    {
        throw 'Deployed workbook source or ownership does not match the approved outputs.'
    }
    $deployed = $actual.properties.serializedData | ConvertFrom-Json -AsHashtable -Depth 40
    if (@($deployed.items | Where-Object { $_.type -eq 9 }).Count -ne 1 -or
        @($deployed.items | Where-Object { $_.type -eq 3 }).Count -ne @($template.items | Where-Object { $_.type -eq 3 }).Count -or
        $deployed.fallbackResourceIds.Count -ne 1 -or $deployed.fallbackResourceIds[0] -cne $parameters.appInsightsId)
    {
        throw 'Deployed workbook panels or fallback scope do not match the selected source.'
    }
    $defaults = @{}
    foreach ($parameter in @($deployed.items | Where-Object { $_.type -eq 9 })[0].content.parameters)
    {
        $defaults[$parameter.name] = $parameter.value
    }
    if ($defaults.ApplicationInsights -cne $parameters.appInsightsId -or
        $defaults.HubCluster -cne $parameters.hubClusterUri -or $defaults.HubDatabase -cne $parameters.hubDatabase -or
        $defaults.Count -ne 8 -or $defaults.Experiment -cne 'all' -or
        $defaults.Baseline -cne 'baseline' -or $defaults.Candidate -cne 'candidate' -or $defaults.TimeRange.durationMs -ne 86400000)
    {
        throw 'Deployed workbook resource defaults do not match deployment outputs.'
    }
    $deployedContext = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($defaults.PriceContext)) | ConvertFrom-Json -AsHashtable
    foreach ($key in 'model', 'region', 'currency', 'deploymentSku', 'retrievedAt', 'sourceUrl', 'seedRevision')
    {
        if ($deployedContext[$key] -cne $parameters.priceContext[$key]) { throw "Deployed workbook price context differs: $key." }
    }
    if ($deployedContext.meters.Count -ne 3) { throw 'Deployed workbook price meter coverage differs.' }
    foreach ($meter in $parameters.priceContext.meters)
    {
        $matching = @($deployedContext.meters | Where-Object { $_.direction -ceq $meter.direction })
        if ($matching.Count -ne 1) { throw 'Deployed workbook price meter identity differs.' }
        foreach ($key in $meter.Keys)
        {
            if ($matching[0][$key] -cne $meter[$key]) { throw "Deployed workbook meter differs: $key." }
        }
    }
    $report.QueryResults = @{}
    $selector = @($deployed.items | Where-Object { $_.type -eq 9 })[0].content.parameters |
        Where-Object { $_.name -ceq 'Experiment' }
    $expectedSelector = @($template.items | Where-Object { $_.type -eq 9 })[0].content.parameters |
        Where-Object { $_.name -ceq 'Experiment' }
    if ($selector.query -cne $expectedSelector.query -or $selector.queryType -ne 0 -or
        $selector.crossComponentResources.Count -ne 1 -or $selector.crossComponentResources[0] -cne '{ApplicationInsights}')
    {
        throw 'Deployed workbook experiment selector differs from the selected source.'
    }
    $selectorQuery = Get-TokenomicsQuery -Query $selector.query -Parameters $parameters
    $report.QueryResults.experiments = @(Invoke-TokenomicsQuery -Query $selectorQuery -ApplicationInsights $parameters.appInsightsId)
    foreach ($item in $template.items | Where-Object { $_.type -eq 3 })
    {
        $actualItems = @($deployed.items | Where-Object { $_.name -ceq $item.name -and $_.type -eq 3 })
        if ($actualItems.Count -ne 1 -or $actualItems[0].content.query -cne $item.content.query.Replace('__TOKEN_COST_QUERY__', $base) -or
            $actualItems[0].content.queryType -ne 0 -or $actualItems[0].content.crossComponentResources.Count -ne 1 -or
            $actualItems[0].content.crossComponentResources[0] -cne '{ApplicationInsights}')
        {
            throw "Deployed workbook query does not match the selected source: $($item.name)."
        }
        $query = Get-TokenomicsQuery -Query $actualItems[0].content.query -Parameters $parameters
        $report.QueryResults[$item.name] = @(Invoke-TokenomicsQuery -Query $query -ApplicationInsights $parameters.appInsightsId)
    }
    $summary = $report.QueryResults.summary
    if ($summary.Count -ne 1 -or $summary[0].Calls -le 0 -or $summary[0].UnpricedCalls -ne 0 -or
        $null -eq $summary[0].EstimatedTotalUSD -or $report.QueryResults.breakdown.Count -lt 1)
    {
        throw 'Workbook queries require measured model calls with complete current price coverage.'
    }
    & "$PSScriptRoot/Test-DesignTimeOptimizerWorkbook.ps1" -Parameters $parameters -OutputDirectory $OutputDirectory
    $report.Status = 'VerifiedAndRetained'
    $report.ReadyForWorkbook = $true
}
catch
{
    $report.Status = 'Failed'
    throw
}
finally
{
    $report.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 40 | Set-Content (Join-Path $OutputDirectory 'workbook-report.json')
}

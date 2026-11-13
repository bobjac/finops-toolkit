# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
Checks interactive presentation access without changing Azure resources.
.DESCRIPTION
CheckAccess reads the owned app, exact experiment telemetry, and Ingestion prices.
Capture is a separate, explicitly confirmed paid operation: one inventory question,
with no retries. It reads the existing API secret but never creates or prints it.
Neither operation deploys, grants access, refreshes prices, or deletes resources.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputDirectory,
    [Parameter(Mandatory)][string]$PreparationFile,
    [Parameter(Mandatory)][string]$OutputFile,
    [ValidateSet('CheckAccess', 'Capture')][string]$Operation = 'CheckAccess',
    [string]$Confirmation,
    [switch]$WorkbookRendered
)

. "$PSScriptRoot/Experiment-Common.ps1"
if (Test-Path -LiteralPath $OutputFile) { throw 'Use a new receipt path; preserve the previous evidence.' }
if ($Operation -eq 'Capture' -and $Confirmation -cne 'capture-one-inventory-question') {
    throw 'Capture requires separate paid-request approval and capture-one-inventory-question confirmation.'
}
$report = Get-Content -LiteralPath $PreparationFile -Raw | ConvertFrom-Json
$sample = Get-Content -LiteralPath "$InputDirectory/sample/deployment-validation.json" -Raw | ConvertFrom-Json
$scope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
$baseUri = [string]$report.links.application -replace '/docs$', ''
if ($report.historicalEvidenceVerified -ne $true -or
    $report.experimentId -cnotmatch '^h09-[0-9]+$' -or
    $report.experimentHash -cnotmatch '^[a-f0-9]{64}$' -or
    $report.deploymentRevision -cnotmatch '^[a-f0-9]{40}$' -or
    $sample.revision -cne $report.deploymentRevision -or
    $sample.outputs.applicationInsightsResourceId.value -ine "$scope/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46" -or
    $baseUri -cnotmatch '^https://ca-ftk-dto-hack-s-ae46[.][a-z0-9-]+[.]eastus2[.]azurecontainerapps[.]io$' -or
    $baseUri -cne "https://$($sample.outputs.fqdn.value)") {
    throw 'Run local preparation first. Only the verified retained sandbox is allowed.'
}
$account = Invoke-SampleAz @('account', 'show')
Assert-SampleAccount $account
if ($account.user.type -cne 'user') { throw 'A service principal is not evidence of interactive viewer access.' }
$group = Invoke-SampleAz @('group', 'show', '--name', 'ftk-dto-hack-s-ae46')
Assert-SampleOwnership $group
$app = Invoke-SampleAz @('containerapp', 'show', '--name', 'ca-ftk-dto-hack-s-ae46', '--resource-group', 'ftk-dto-hack-s-ae46')
$expectedImage = "crftkdtohacksae46.azurecr.io/sample:$($report.deploymentRevision)"
if ($app.id -ine "$scope/providers/Microsoft.App/containerApps/ca-ftk-dto-hack-s-ae46" -or
    $app.properties.template.containers.Count -ne 1 -or
    $app.properties.template.containers[0].image -cne $expectedImage -or
    $app.properties.configuration.activeRevisionsMode -cne 'Single' -or
    -not $app.properties.latestReadyRevisionName -or
    $app.properties.latestReadyRevisionName -cne $app.properties.latestRevisionName) {
    throw 'The ready, single-revision retained app does not match the recorded deployment.'
}
$null = Invoke-WebRequest -Uri "$baseUri/docs" -TimeoutSec 60
if ($Operation -eq 'Capture') {
    $case = Get-Content -LiteralPath "$PSScriptRoot/../tests/evaluation/questions.json" -Raw |
        ConvertFrom-Json | Where-Object { $_.id -ceq 'inventory-below-reorder' }
    $token = Invoke-SampleAz @('keyvault', 'secret', 'show', '--vault-name', 'kv-ftk-dto-hack-s-ae46',
        '--name', 'sample-api-token', '--query', 'value')
    if ($token -isnot [string] -or $token.Length -lt 32) {
        throw 'The existing API secret is missing or invalid. No secret will be created or replaced.'
    }
    try {
        $body = @{
            question = $case.question
            sessionId = "h14-$([Guid]::NewGuid())"
            experimentId = 'h14-presentation-capture'
            variant = 'candidate'
        } | ConvertTo-Json -Compress
        $answer = Invoke-RestMethod -Uri "$baseUri/api/questions" -Method Post `
            -Headers @{ 'x-sample-token' = $token } -ContentType 'application/json' `
            -Body $body -TimeoutSec 230
    }
    catch {
        throw 'The single paid question failed. No retry was made; preserve the failure and request approval before another attempt.'
    }
    finally { $token = $null }
    Assert-SampleAnswer -Case $case -Answer $answer
    if ($answer.evidence.modelMode -cne 'azure-openai' -or
        @($answer.evidence.modelUsage).Count -ne 4 -or
        $answer.evidence.traceId -cnotmatch '^[a-f0-9]{32}$') {
        throw 'The captured answer is missing real model usage or trace evidence.'
    }
    @{
        capturedUtc = [DateTimeOffset]::UtcNow.ToString('o')
        question = $case.question; revision = $report.deploymentRevision; response = $answer
    } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputFile -Encoding utf8
    return
}
$runs = @(Get-Content -LiteralPath "$InputDirectory/experiment/runs.json" -Raw | ConvertFrom-Json)
if ($runs.Count -ne 3 -or @($runs | Where-Object { $_.experimentId -cne $report.experimentId }).Count) {
    throw 'Viewer checks require all three measured passes of the selected experiment.'
}
foreach ($run in $runs) {
    $null = Get-ExperimentTelemetry -Run $run -WorkspaceId $sample.outputs.workspaceCustomerId.value `
        -AppInsightsId $sample.outputs.applicationInsightsResourceId.value
}
$foundation = Get-Content -LiteralPath "$InputDirectory/seed/seed-evidence-second/foundation/foundation.json" -Raw | ConvertFrom-Json
$cluster = [string]$foundation.Outputs.clusterUri
$foundationScope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-foundation'
if ($foundation.Status -cne 'VerifiedAndRetained' -or
    $foundation.ResourceGroupId -ine $foundationScope -or
    $cluster -cnotmatch '^https://[a-z0-9]+[.]eastus2[.]kusto[.]windows[.]net/?$' -or
    $foundation.Outputs.clusterId -ine "$foundationScope/providers/Microsoft.Kusto/clusters/$(([Uri]$cluster).Host.Split('.')[0])") {
    throw 'Viewer access requires the owned verified foundation endpoint.'
}
$bodyPath = [IO.Path]::GetTempFileName()
try {
    @{
        db = 'Ingestion'
        csl = "Prices_final_v1_2 | where x_BillingProfileId =~ 'dto-retail-public-v1' | take 1 | count"
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $bodyPath -Encoding utf8
    $frames = @(Invoke-SampleAz @('rest', '--method', 'post', '--url', "$($cluster.TrimEnd('/'))/v2/rest/query",
        '--resource', 'https://api.kusto.windows.net', '--body', "@$bodyPath"))
    $tables = @($frames | Where-Object { $_.FrameType -ceq 'DataTable' -and $_.TableKind -ceq 'PrimaryResult' })
    $completion = @($frames | Where-Object { $_.FrameType -ceq 'DataSetCompletion' -and $_.HasErrors -eq $false })
    if ($tables.Count -ne 1 -or $completion.Count -ne 1 -or
        @($frames | Where-Object { $_.HasErrors -or $_.Cancelled -or $_.error }).Count -or
        $tables[0].Rows.Count -ne 1 -or $tables[0].Rows[0][0] -ne 1) {
        throw 'The interactive identity could not query retained model prices in Ingestion.'
    }
}
finally { Remove-Item -LiteralPath $bodyPath -Force }
@{
    checkedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    subscriptionId = $account.id; tenantId = $account.tenantId; identityType = 'user'
    deploymentRevision = $report.deploymentRevision; experimentHash = $report.experimentHash
    applicationReachable = $true; insightsQuery = $true; ingestionQuery = $true
    workbookRendered = $WorkbookRendered.IsPresent
} | ConvertTo-Json | Set-Content -LiteralPath $OutputFile -Encoding utf8

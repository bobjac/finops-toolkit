# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][Uri]$BaseUri,
    [Parameter(Mandatory)][string]$ApiToken,
    [Parameter(Mandatory)][string]$ApplicationInsightsResourceId,
    [Parameter(Mandatory)][Guid]$WorkspaceCustomerId,
    [Parameter(Mandatory)][string]$OutputDirectory
)

. "$PSScriptRoot/Sample-Common.ps1"
if ($BaseUri.Scheme -ne 'https' -or $BaseUri.Host -notlike '*.azurecontainerapps.io') {
    throw 'Live validation requires the deployed Container Apps HTTPS endpoint.'
}
$ready = $null
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        $ready = Invoke-RestMethod -Uri "$($BaseUri.AbsoluteUri.TrimEnd('/'))/ready" -TimeoutSec 10
        if ($ready.status -eq 'ready' -and $ready.modelMode -eq 'azure-openai') { break }
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Write-Warning 'The deployed revision is not ready yet.'
    }
    Start-Sleep -Seconds 3
}
if ($ready.status -ne 'ready' -or $ready.modelMode -ne 'azure-openai') {
    throw 'The live runtime is not ready; an offline container is not live acceptance.'
}
$golden = Get-Content "$PSScriptRoot/../tests/evaluation/questions.json" -Raw | ConvertFrom-Json
$results = @()
foreach ($case in $golden) {
    $body = @{
        question = $case.question; sessionId = "h05-$([Guid]::NewGuid())"
        experimentId = 'h05-live'; variant = 'baseline'
    } | ConvertTo-Json
    $answer = Invoke-RestMethod -Uri "$($BaseUri.AbsoluteUri.TrimEnd('/'))/api/questions" `
        -Method Post -ContentType 'application/json' -Body $body `
        -Headers @{ 'x-sample-token' = $ApiToken } -TimeoutSec 230
    Assert-SampleAnswer -Case $case -Answer $answer
    if (-not $answer.evidence.modelUsage -or $answer.evidence.modelMode -ne 'azure-openai' -or
        $answer.evidence.traceId -notmatch '^[a-f0-9]{32}$') {
        throw "Measured live usage and trace correlation are missing: $($case.id)."
    }
    $traceId = $answer.evidence.traceId
    $query = @"
union AppRequests, AppDependencies
| where OperationId == '$traceId'
| where _ResourceId =~ '$ApplicationInsightsResourceId'
| project Name, OperationId, ParentId, Id, Properties
"@
    $telemetry = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $telemetry = Invoke-SampleAz @('monitor', 'log-analytics', 'query',
            '--workspace', "$WorkspaceCustomerId",
            '--analytics-query', $query, '--timespan', 'PT30M')
        $names = @($telemetry | ForEach-Object { $_.Name })
        if (@($telemetry | Where-Object { $_.Name -eq 'gen_ai.chat' }).Count -eq
            @($answer.evidence.modelUsage).Count -and 'coordinator.run' -in $names) { break }
        Start-Sleep -Seconds 10
    }
    if ('coordinator.run' -notin $names -or 'gen_ai.chat' -notin $names) {
        throw "Exported Application Insights correlation was not observed: $($case.id)."
    }
    Assert-SampleTelemetry -Answer $answer -Rows @($telemetry)
    $results += @{
        caseId = $case.id; answerStatus = $answer.answerStatus
        traceId = $traceId; modelUsage = $answer.evidence.modelUsage; telemetry = $telemetry
    }
    $results | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $OutputDirectory 'live-evaluation.json')
    Start-Sleep -Seconds 60
}

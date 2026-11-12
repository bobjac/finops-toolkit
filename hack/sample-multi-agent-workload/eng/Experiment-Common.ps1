# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. "$PSScriptRoot/Sample-Common.ps1"

function Get-ExperimentAppName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9]{1,12}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateSet('baseline', 'candidate')][string]$Variant
    )
    "ca-dto-x-$RunId-$($Variant.Substring(0, 1))"
}

function Assert-ExperimentApp {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App, [Parameter(Mandatory)][string]$RunId, [Parameter(Mandatory)][string]$Name)
    $scope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
    $names = @('baseline', 'candidate' | ForEach-Object { Get-ExperimentAppName -RunId $RunId -Variant $_ })
    $expires = [DateTimeOffset]::MinValue
    if ($Name -cnotin $names -or $App.id -ine "$scope/providers/Microsoft.App/containerApps/$Name" -or
        $App.tags.repository -cne 'bobjac/finops-toolkit' -or
        $App.tags.'ftk-tool' -cne 'design-time-optimizer-experiment' -or
        $App.tags.'experiment-run-id' -cne $RunId -or
        $App.tags.'experiment-id' -cne "h09-$RunId" -or
        $App.tags.revision -cnotmatch '^[a-f0-9]{40}$' -or
        $Name -cne (Get-ExperimentAppName -RunId $RunId -Variant $App.tags.variant) -or
        -not [DateTimeOffset]::TryParse([string]$App.tags.'expires-on', [ref]$expires)) {
        throw 'Refusing to modify an app outside this exact owned experiment.'
    }
}

function Assert-ExperimentPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Preview, [Parameter(Mandatory)][string]$AppName)
    $scope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
    if ($Preview.status -cne 'Succeeded' -or $null -eq $Preview.changes) {
        throw 'Temporary app preview did not complete successfully.'
    }
    foreach ($change in $Preview.changes) {
        if ($change.changeType -ceq 'Ignore' -and ([string]$change.resourceId).StartsWith("$scope/providers/", [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($change.resourceId -ine "$scope/providers/Microsoft.App/containerApps/$AppName" -or
            $change.changeType -cnotin @('Create', 'NoChange')) {
            throw 'Temporary app preview rejected a modification, deletion, or out-of-scope resource.'
        }
    }
}

function Get-ExperimentTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][Guid]$WorkspaceId,
        [Parameter(Mandatory)][string]$AppInsightsId
    )
    $expectedInsights = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46'
    if ($AppInsightsId -ine $expectedInsights -or
        $Run.revision -cnotmatch '^[a-f0-9]{40}$' -or $Run.variant -cnotin @('baseline', 'candidate') -or
        -not $Run.requests.Count -or @($Run.requests | Where-Object { $_.sessionHash -cnotmatch '^[a-f0-9]{64}$' }).Count) {
        throw 'Telemetry requires a valid bounded measurement record.'
    }
    $experimentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Run.experimentId))).ToLowerInvariant()
    $sessions = @($Run.requests.sessionHash) | ConvertTo-Json -Compress -AsArray
    $startTime = [DateTimeOffset]$Run.startUtc
    $endTime = [DateTimeOffset]$Run.endUtc
    if ($endTime -le $startTime -or ($endTime - $startTime).TotalMinutes -gt 11 -or
        $Run.requests.Count -gt 7 -or $endTime -gt [DateTimeOffset]::UtcNow) {
        throw 'Telemetry requires a completed, bounded measured window.'
    }
    $start = $startTime.UtcDateTime.ToString('o')
    $end = $endTime.UtcDateTime.ToString('o')
    $query = @"
union AppRequests, AppDependencies
| where TimeGenerated between (datetime($start) .. datetime($end))
| where _ResourceId =~ '$AppInsightsId'
| where AppVersion == '$($Run.revision)'
| where tostring(Properties['experiment.id']) == '$experimentHash'
| where tostring(Properties['optimization.variant']) == '$($Run.variant)'
| where SessionId in (dynamic($sessions))
| project Name, TimeGenerated, AppVersion, OperationId, SessionId, Id, ParentId, Properties
| take 201
"@
    $bodyPath = [IO.Path]::GetTempFileName()
    try {
        @{ query = $query; timespan = "$start/$end" } | ConvertTo-Json -Compress | Set-Content -LiteralPath $bodyPath
        $url = "https://api.loganalytics.azure.com/v1/workspaces/$WorkspaceId/query"
        $previousCount = -1
        $stable = 0
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            $response = Invoke-SampleAz @('rest', '--method', 'post', '--url', $url, '--resource', 'https://api.loganalytics.io', '--body', "@$bodyPath")
            if ($response.error -or @($response.tables).Count -ne 1 -or $null -eq $response.tables[0].rows) {
                throw 'Experiment telemetry query failed or returned partial results.'
            }
            $table = $response.tables[0]
            if ($table.rows.Count -gt 200) { throw 'Experiment telemetry exceeded the row bound.' }
            $rows = foreach ($row in $table.rows) {
                if ($row.Count -ne $table.columns.Count) { throw 'Experiment telemetry row shape is invalid.' }
                $record = @{}
                for ($column = 0; $column -lt $table.columns.Count; $column++) { $record[$table.columns[$column].name] = $row[$column] }
                $record
            }
            $rootCount = @($rows | Where-Object { $_.Name -ceq 'coordinator.run' }).Count
            $modelCount = @($rows | Where-Object { $_.Name -ceq 'gen_ai.chat' }).Count
            $missingParents = @($rows | Where-Object { $_.Name -ceq 'gen_ai.chat' -and (-not $_.ParentId -or $_.ParentId -cnotin $rows.Id) }).Count
            $expectedModels = @($Run.requests | ForEach-Object { $_.modelUsage }).Count
            if ($rootCount -eq $Run.requests.Count -and $modelCount -ge $expectedModels -and $modelCount -gt 0 -and $missingParents -eq 0) {
                $stable = if ($table.rows.Count -eq $previousCount) { $stable + 1 } else { 0 }
                if ($stable -ge 2) { return @($rows) }
            }
            $previousCount = $table.rows.Count
            Start-Sleep -Seconds 10
        }
        throw 'Timed out waiting for complete, stable experiment telemetry.'
    }
    finally { Remove-Item -LiteralPath $bodyPath -Force }
}

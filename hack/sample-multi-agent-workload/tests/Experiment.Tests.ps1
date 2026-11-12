# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . "$PSScriptRoot/../eng/Experiment-Common.ps1"
    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        throw 'Azure must be mocked in experiment tests.'
    }
    $script:scope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
    function New-TestExperimentApp {
        param([string]$Variant = 'baseline')
        $name = Get-ExperimentAppName -RunId 123 -Variant $Variant
        @{
            name = $name; id = "$script:scope/providers/Microsoft.App/containerApps/$name"
            tags = @{
                repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-experiment'
                'experiment-run-id' = '123'; 'experiment-id' = 'h09-123'; revision = 'a' * 40
                variant = $Variant; 'expires-on' = [DateTimeOffset]::UtcNow.AddMinutes(90).ToString('o')
            }
        }
    }
}

Describe 'Bounded experiment deployment and cleanup' {
    It 'Never accepts the retained app or another run for cleanup' {
        $app = New-TestExperimentApp
        { Assert-ExperimentApp -App $app -RunId 123 -Name $app.name } | Should -Not -Throw
        { Assert-ExperimentApp -App $app -RunId 124 -Name $app.name } | Should -Throw
        $app.id = "$script:scope/providers/Microsoft.App/containerApps/ca-ftk-dto-hack-s-ae46"
        { Assert-ExperimentApp -App $app -RunId 123 -Name $app.name } | Should -Throw
    }

    It 'Rejects missing or inconsistent ownership tags' -ForEach @(
        @{ Key = 'repository'; Value = 'another/repository' }
        @{ Key = 'ftk-tool'; Value = 'design-time-optimizer-sample' }
        @{ Key = 'experiment-run-id'; Value = '999' }
        @{ Key = 'experiment-id'; Value = 'h09-999' }
        @{ Key = 'revision'; Value = 'dev' }
        @{ Key = 'variant'; Value = 'candidate' }
        @{ Key = 'expires-on'; Value = '' }
    ) {
        $app = New-TestExperimentApp
        $app.tags[$Key] = $Value
        { Assert-ExperimentApp -App $app -RunId 123 -Name $app.name } | Should -Throw
    }

    It 'Allows only a temporary app creation in the deployment preview' {
        $app = New-TestExperimentApp
        $preview = @{ status = 'Succeeded'; changes = @(@{ resourceId = $app.id; changeType = 'Create' }) }
        { Assert-ExperimentPreview -Preview $preview -AppName $app.name } | Should -Not -Throw
        foreach ($type in 'Modify', 'Delete', 'Deploy') {
            $preview.changes[0].changeType = $type
            { Assert-ExperimentPreview -Preview $preview -AppName $app.name } | Should -Throw
        }
        $preview.changes[0] = @{ resourceId = "$script:scope/providers/Microsoft.CognitiveServices/accounts/oai-ftk-dto-hack-s-ae46"; changeType = 'Create' }
        { Assert-ExperimentPreview -Preview $preview -AppName $app.name } | Should -Throw
    }
}

Describe 'Exact experiment app deletion' {
    BeforeEach {
        $script:savedEnvironment = @{}
        foreach ($entry in @{ GITHUB_ACTIONS = 'true'; GITHUB_REPOSITORY = 'bobjac/finops-toolkit'; GITHUB_REF = 'refs/heads/dev' }.GetEnumerator()) {
            $script:savedEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
        # Native mocks and nested scripts share this isolated, explicitly cleared test state.
        $global:experimentTestApps = [Collections.Generic.List[object]]::new()
        $global:experimentTestApps.Add((New-TestExperimentApp))
        $global:experimentTestApps.Add((New-TestExperimentApp -Variant candidate))
        $global:experimentTestDeleted = [Collections.Generic.List[string]]::new()
        $global:experimentTestFailBaseline = $false
        Mock az {
            param($Arguments)
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'account') { return (@{ id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'; tenantId = '3670e846-58dd-4658-86fb-00e4029045d6' } | ConvertTo-Json) }
            if ($Arguments[0] -eq 'group') { return (@{ name = 'ftk-dto-hack-s-ae46'; tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' } } | ConvertTo-Json) }
            if ($Arguments[1] -eq 'list') { return (ConvertTo-Json -InputObject @($global:experimentTestApps.ToArray()) -Depth 20) }
            if ($Arguments[1] -eq 'delete') {
                $name = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                $global:experimentTestDeleted.Add($name)
                if ($global:experimentTestFailBaseline -and $name.EndsWith('-b')) { throw 'Synthetic delete failure.' }
                $app = @($global:experimentTestApps | Where-Object { $_.name -eq $name })[0]
                $global:experimentTestApps.Remove($app) | Out-Null
                return
            }
            throw 'Unexpected Azure mutation.'
        }
        $script:cleanupDirectory = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
    }
    AfterEach {
        foreach ($entry in $script:savedEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value) }
        Remove-Variable -Name experimentTestApps, experimentTestDeleted, experimentTestFailBaseline -Scope Global
    }
    It 'Deletes only the two exact temporary apps and preserves a retryable receipt' {
        & "$PSScriptRoot/../eng/Remove-Experiment.ps1" -RunId 123 -OutputDirectory $script:cleanupDirectory -Confirm:$false
        $global:experimentTestDeleted.Count | Should -Be 2
        $receipt = Get-Content "$script:cleanupDirectory/cleanup.json" -Raw | ConvertFrom-Json
        $receipt.verified | Should -BeTrue
        $receipt.removed.Count | Should -Be 2
        & "$PSScriptRoot/../eng/Remove-Experiment.ps1" -RunId 123 -OutputDirectory $script:cleanupDirectory -Confirm:$false
        $receipt = Get-Content "$script:cleanupDirectory/cleanup.json" -Raw | ConvertFrom-Json
        $receipt.removed.Count | Should -Be 2
        $global:experimentTestDeleted.Count | Should -Be 2
    }
    It 'Still attempts candidate cleanup when baseline deletion fails' {
        $global:experimentTestFailBaseline = $true
        { & "$PSScriptRoot/../eng/Remove-Experiment.ps1" -RunId 123 -OutputDirectory $script:cleanupDirectory -Confirm:$false } | Should -Throw '*cleanup is incomplete*'
        $global:experimentTestDeleted.Count | Should -Be 2
        $receipt = Get-Content "$script:cleanupDirectory/cleanup.json" -Raw | ConvertFrom-Json
        $receipt.verified | Should -BeFalse
        $receipt.failures | Should -Contain 'ca-dto-x-123-b'
    }
    It 'Refuses an unowned same-name app while cleaning the other owned app' {
        $global:experimentTestApps[0].tags.repository = 'another/repository'
        { & "$PSScriptRoot/../eng/Remove-Experiment.ps1" -RunId 123 -OutputDirectory $script:cleanupDirectory -Confirm:$false } | Should -Throw
        $global:experimentTestDeleted | Should -Not -Contain 'ca-dto-x-123-b'
        $global:experimentTestDeleted | Should -Contain 'ca-dto-x-123-c'
    }
}

Describe 'Bounded experiment telemetry collection' {
    BeforeEach {
        $script:queries = [Collections.Generic.List[object]]::new()
        $script:run = @{
            experimentId = 'h09-123'; revision = 'a' * 40; variant = 'candidate'
            startUtc = [DateTimeOffset]::UtcNow.AddMinutes(-8).ToString('o')
            endUtc = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
            requests = @(@{ sessionHash = 'f' * 64; modelUsage = @(@{ model = 'gpt-5-mini' }) })
        }
        Mock Start-Sleep {}
        Mock Invoke-SampleAz {
            param($Arguments)
            $bodyPath = $Arguments[[Array]::IndexOf($Arguments, '--body') + 1].Substring(1)
            $script:queries.Add((Get-Content $bodyPath -Raw | ConvertFrom-Json))
            @{
                tables = @(@{
                    columns = @(@{ name = 'Name' }, @{ name = 'Id' }, @{ name = 'ParentId' })
                    rows = @(@('coordinator.run', 'root', $null), @('gen_ai.chat', 'model', 'root'))
                })
            }
        }
    }
    It 'Uses explicit matching UTC bounds, revision, exact sessions, variant, and resource ID' {
        $id = "$script:scope/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46"
        $rows = @(Get-ExperimentTelemetry -Run $script:run -WorkspaceId '00000000-0000-0000-0000-000000000001' -AppInsightsId $id)
        $rows.Count | Should -Be 2
        $script:queries.Count | Should -Be 3
        $query = $script:queries[0].query
        $query | Should -Match ([regex]::Escape("AppVersion == '$('a' * 40)'"))
        $query | Should -Match "optimization.variant.*candidate"
        $query | Should -Match 'SessionId in \(dynamic\('
        $query | Should -Match ([regex]::Escape('f' * 64))
        $query | Should -Match 'take 201'
        $script:queries[0].timespan | Should -Match 'Z/.*Z$'
    }
    It 'Rejects a different application scope without querying Azure' {
        { Get-ExperimentTelemetry -Run $script:run -WorkspaceId '00000000-0000-0000-0000-000000000001' -AppInsightsId "$script:scope/providers/Microsoft.Insights/components/another-app" } | Should -Throw
        $script:queries.Count | Should -Be 0
    }
}

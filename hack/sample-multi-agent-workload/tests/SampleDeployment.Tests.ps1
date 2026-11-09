# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . "$PSScriptRoot/../eng/Sample-Common.ps1"
}

Describe 'Sample ownership and price preflight' {
    It 'previews without creating and rejects deletion, unsupported changes, and foreign scopes' {
        $scope = '/subscriptions/approved/resourceGroups/ftk-dto-hack-s-ae46'
        $script:samplePreview = @{
            status = 'Succeeded'
            changes = @(@{ resourceId = "$scope/providers/Microsoft.App/containerApps/sample"; changeType = 'Create' })
        }
        Mock Invoke-SampleAz { $script:samplePreview }
        $arguments = @('deployment', 'sub', 'create', '--location', 'eastus2')
        { Get-SamplePreview -Arguments $arguments -Scope $scope } | Should -Not -Throw
        $arguments[2] | Should -Be 'create'
        Should -Invoke Invoke-SampleAz -Times 1 -Exactly -ParameterFilter {
            $Arguments[2] -eq 'what-if' -and '--no-pretty-print' -in $Arguments
        }
        foreach ($type in @('Delete', 'Unsupported')) {
            $script:samplePreview.changes[0].changeType = $type
            { Get-SamplePreview -Arguments $arguments -Scope $scope } | Should -Throw
        }
        $script:samplePreview.changes[0].changeType = 'Create'
        $script:samplePreview.changes[0].resourceId = '/subscriptions/approved/resourceGroups/ftk-dto-hack-foundation'
        { Get-SamplePreview -Arguments $arguments -Scope $scope } | Should -Throw
        $script:samplePreview.changes = @()
        { Get-SamplePreview -Arguments $arguments -Scope $scope } | Should -Not -Throw
        $script:samplePreview.status = 'Failed'
        { Get-SamplePreview -Arguments $arguments -Scope $scope } | Should -Throw
    }
    It 'rejects Azure accounts outside the approved subscription and tenant' {
        $account = @{
            id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
            tenantId = '3670e846-58dd-4658-86fb-00e4029045d6'
        }
        { Assert-SampleAccount $account } | Should -Not -Throw
        $account.id = '00000000-0000-0000-0000-000000000000'
        { Assert-SampleAccount $account } | Should -Throw
        $account.id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
        $account.tenantId = '00000000-0000-0000-0000-000000000000'
        { Assert-SampleAccount $account } | Should -Throw
    }
    It 'rejects the retained foundation and foreign groups' {
        { Assert-SampleOwnership @{
            name = 'ftk-dto-hack-foundation'
            tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' }
        } } | Should -Throw
        { Assert-SampleOwnership @{
            name = 'ftk-dto-hack-s-ae46'
            tags = @{ repository = 'other/fork'; 'ftk-tool' = 'design-time-optimizer-sample' }
        } } | Should -Throw
    }
    It 'accepts only the separately owned sample' {
        { Assert-SampleOwnership @{
            name = 'ftk-dto-hack-s-ae46'
            tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' }
        } } | Should -Not -Throw
    }
    It 'rejects missing, stale, and zero-filled price evidence' {
        $price = @{
            currency = 'USD'; region = 'eastus2'; model = 'gpt-5-mini'
            modelVersion = '2025-08-07'; deploymentSku = 'GlobalStandard'
            verifiedAt = [DateTimeOffset]::UtcNow.ToString('o')
            inputPerMillion = 1; cachedInputPerMillion = 1; outputPerMillion = 1; analyticsPerGB = 1
            sourceUrls = @('https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/',
                'https://azure.microsoft.com/pricing/details/monitor/')
        }
        { Assert-SamplePrice ($price | ConvertTo-Json) } | Should -Not -Throw
        $price.inputPerMillion = 0
        { Assert-SamplePrice ($price | ConvertTo-Json) } | Should -Throw
        $price.inputPerMillion = 1
        $price.verifiedAt = [DateTimeOffset]::UtcNow.AddDays(-8).ToString('o')
        { Assert-SamplePrice ($price | ConvertTo-Json) } | Should -Throw
    }
    It 'compares live golden numbers semantically without accepting numeric strings' {
        $cases = Get-Content "$PSScriptRoot/evaluation/questions.json" -Raw | ConvertFrom-Json
        $case = $cases[0]
        $answer = @{
            answerStatus = $case.expectedStatus; answer = $case.expectedAnswer
            data = ($case.expectedData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
            evidence = @{ agentCalls = $case.expectedCalls }
        }
        { Assert-SampleAnswer -Case $case -Answer $answer } | Should -Not -Throw
        $answer.data.rows[0][1] = 400.0
        { Assert-SampleAnswer -Case $case -Answer $answer } | Should -Not -Throw
        $answer.data.rows[0][1] = '400'
        { Assert-SampleAnswer -Case $case -Answer $answer } | Should -Throw
        $answer.data.rows[0][1] = 399
        { Assert-SampleAnswer -Case $case -Answer $answer } | Should -Throw
    }
    It 'rejects exported usage and attribution that differ from provider evidence' {
        $properties = [PSCustomObject]@{
            'session.id' = 'session-hash'; 'experiment.id' = 'experiment-hash'
            'optimization.variant' = 'baseline'
            'gen_ai.response.model' = 'gpt-5-mini'
            'agent.name' = 'coordinator'
            'gen_ai.usage.input_tokens' = 5; 'gen_ai.usage.output_tokens' = 2
        }
        $rows = @(
            [PSCustomObject]@{ Name = 'coordinator.run'; Id = 'root'; ParentId = ''; Properties = $properties }
            [PSCustomObject]@{ Name = 'gen_ai.chat'; Id = 'child'; ParentId = 'root'; Properties = $properties }
        )
        $answer = @{
            evidence = @{
                sessionHash = 'session-hash'; experimentHash = 'experiment-hash'
                agentCalls = @('coordinator')
                modelUsage = @([PSCustomObject]@{
                    model = 'gpt-5-mini'; inputTokens = 5; outputTokens = 2
                    cachedInputTokens = $null
                })
            }
        }
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Not -Throw
        $properties.'gen_ai.usage.input_tokens' = 4
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
        $properties.'gen_ai.usage.input_tokens' = 5
        $properties.'gen_ai.response.model' = 'other-model'
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
        $properties.'gen_ai.response.model' = 'gpt-5-mini'
        $properties | Add-Member 'gen_ai.usage.cache_read.input_tokens' 0
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
        $answer.evidence.modelUsage[0].cachedInputTokens = 0
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Not -Throw
        $properties.'gen_ai.usage.cache_read.input_tokens' = 1
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
        $properties.'gen_ai.usage.cache_read.input_tokens' = 0
        $properties.'session.id' = 'foreign-session'
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
    }
}

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . "$PSScriptRoot/../eng/Sample-Common.ps1"
}

Describe 'Checkpointed deployment stages' {
    BeforeAll {
        function az {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            throw 'Azure must be mocked in deployment stage tests.'
        }
        function git {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            throw 'Git must be mocked in deployment stage tests.'
        }
        $script:deploymentRevision = 'a' * 40
        $script:deploymentScope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
        $script:deploymentOutputs = @{
            registryName = @{ value = 'crftkdtohacksae46' }
            registryLoginServer = @{ value = 'crftkdtohacksae46.azurecr.io' }
            keyVaultName = @{ value = 'kv-ftk-dto-hack-s-ae46' }
            containerAppName = @{ value = 'ca-ftk-dto-hack-s-ae46' }
            applicationInsightsResourceId = @{ value = "$script:deploymentScope/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46" }
            workspaceCustomerId = @{ value = '00000000-0000-0000-0000-000000000001' }
            fqdn = @{ value = 'ca-ftk-dto-hack-s-ae46.synthetic.eastus2.azurecontainerapps.io' }
        }
        $script:stageScript = "$PSScriptRoot/../eng/Deploy-Sample.ps1"
    }
    BeforeEach {
        $script:savedEnvironment = @{}
        $environment = @{
            GITHUB_ACTIONS = 'true'; GITHUB_REPOSITORY = 'bobjac/finops-toolkit'
            GITHUB_REF = 'refs/heads/dev'; GITHUB_RUN_ID = '1234'; GITHUB_RUN_ATTEMPT = '2'
            SAMPLE_PRICE_EVIDENCE = (@{
                currency = 'USD'; region = 'eastus2'; model = 'gpt-5-mini'
                modelVersion = '2025-08-07'; deploymentSku = 'GlobalStandard'
                verifiedAt = [DateTimeOffset]::UtcNow.ToString('o')
                inputPerMillion = 1; cachedInputPerMillion = 1; outputPerMillion = 1; analyticsPerGB = 1
                sourceUrls = @('https://prices.azure.com/model', 'https://prices.azure.com/analytics')
            } | ConvertTo-Json)
        }
        foreach ($name in $environment.Keys) {
            $script:savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $environment[$name])
        }
        $script:azureCalls = [Collections.Generic.List[string]]::new()
        $script:storedToken = 'synthetic-token-not-for-artifacts-' * 2
        $script:secretExists = $true
        $script:readyRevision = 'approved-revision'
        $script:liveImage = "crftkdtohacksae46.azurecr.io/sample:$script:deploymentRevision"
        $script:checkpoint = @{
            version = 1; stage = 'Infrastructure'; revision = $script:deploymentRevision
            runId = '1234'; runAttempt = '1'; status = 'Completed'
            subscriptionId = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
            resourceGroup = 'ftk-dto-hack-s-ae46'; outputs = $script:deploymentOutputs
        }
        $script:stageParameters = @{
            Revision = $script:deploymentRevision
            DeployerObjectId = [Guid]'00000000-0000-0000-0000-000000000001'
            ConfirmResourceGroup = 'ftk-dto-hack-s-ae46'
            OutputDirectory = "$TestDrive/evidence"
        }
        Mock git { $global:LASTEXITCODE = 0; return $script:deploymentRevision }
        Mock az {
            $global:LASTEXITCODE = 0
            $operation = ($Arguments | Select-Object -First 3) -join ' '
            $script:azureCalls.Add($operation)
            $result = switch ($Arguments[0]) {
                'account' { @{
                    id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
                    tenantId = '3670e846-58dd-4658-86fb-00e4029045d6'
                } }
                'group' {
                    if ($Arguments[1] -eq 'exists') { $true }
                    else { @{
                        name = 'ftk-dto-hack-s-ae46'
                        tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' }
                    } }
                }
                'deployment' {
                    if ($Arguments[2] -eq 'what-if') { @{
                        status = 'Succeeded'
                        changes = @(@{ resourceId = "$script:deploymentScope/providers/Microsoft.App/containerApps/ca-ftk-dto-hack-s-ae46"; changeType = 'Modify' })
                    } }
                    else { @{ properties = @{ outputs = $script:deploymentOutputs } } }
                }
                'acr' { @{ status = 'Succeeded' } }
                'keyvault' {
                    switch ($Arguments[2]) {
                        'list' { if ($script:secretExists) { @('sample-api-token') } else { @() } }
                        'show' { @{ value = $script:storedToken } }
                        'set' {
                            $file = $Arguments[[Array]::IndexOf($Arguments, '--file') + 1]
                            $script:storedToken = [IO.File]::ReadAllText($file)
                            @{ id = 'synthetic-secret-id' }
                        }
                    }
                }
                'containerapp' { @{ properties = @{
                    latestRevisionName = 'approved-revision'; latestReadyRevisionName = $script:readyRevision
                    template = @{ containers = @(@{ image = $script:liveImage }) }
                    configuration = @{ ingress = @{ fqdn = $script:deploymentOutputs.fqdn.value } }
                } } }
                default { throw "Unexpected mocked Azure operation: $operation." }
            }
            ConvertTo-Json -InputObject $result -Depth 12 -Compress
        }
    }
    AfterEach {
        foreach ($name in $script:savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $script:savedEnvironment[$name])
        }
    }
    It 'completes infrastructure without building images or reading secrets' {
        . $script:stageScript @script:stageParameters -Stage Infrastructure
        $report = Get-Content "$TestDrive/evidence/deployment-infrastructure.json" -Raw | ConvertFrom-Json
        $report.status | Should -Be 'Completed'
        $script:azureCalls.IndexOf('deployment sub what-if') | Should -BeLessThan $script:azureCalls.IndexOf('deployment sub create')
        ($script:azureCalls -join '|') | Should -Not -Match 'acr|keyvault'
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'deployment' -and $Arguments[2] -eq 'create' -and 'isPlaceholder=true' -in $Arguments
        }
    }
    It 'retries the image stage using a prior attempt checkpoint without repeating infrastructure' {
        $script:checkpoint | ConvertTo-Json -Depth 12 | Set-Content "$TestDrive/prerequisite.json"
        . $script:stageScript @script:stageParameters -Stage Image -CheckpointPath "$TestDrive/prerequisite.json"
        $report = Get-Content "$TestDrive/evidence/deployment-image.json" -Raw | ConvertFrom-Json
        $report.status | Should -Be 'Completed'
        $report.image | Should -Be $script:liveImage
        ($script:azureCalls -join '|') | Should -Not -Match 'deployment|keyvault'
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'acr' -and $Arguments[1] -eq 'build' -and "sample:$script:deploymentRevision" -in $Arguments
        }
    }
    It 'deploys only the approved image and reuses the token without exporting it' {
        $script:checkpoint.stage = 'Image'
        $script:checkpoint.image = $script:liveImage
        $script:checkpoint | ConvertTo-Json -Depth 12 | Set-Content "$TestDrive/prerequisite.json"
        . $script:stageScript @script:stageParameters -Stage Application -CheckpointPath "$TestDrive/prerequisite.json"
        $json = Get-Content "$TestDrive/evidence/deployment-application.json" -Raw
        ($json | ConvertFrom-Json).status | Should -Be 'Completed'
        $json | Should -Not -BeLike "*$script:storedToken*"
        ($script:azureCalls -join '|') | Should -Not -Match 'acr|keyvault secret set'
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'deployment' -and $Arguments[2] -eq 'create' -and
            'isPlaceholder=false' -in $Arguments -and "containerImage=$script:liveImage" -in $Arguments
        }
    }
    It 'rejects stale, foreign, failed, and out-of-order checkpoints before Azure calls' {
        foreach ($invalid in @(
            @{ revision = ('b' * 40) }, @{ runId = 'other-run' }, @{ stage = 'Application' },
            @{ status = 'Running' }, @{ resourceGroup = 'ftk-dto-hack-foundation' },
            @{ outputs = @{ registryName = @{ value = 'foreign-registry' } } }
        )) {
            $copy = $script:checkpoint | ConvertTo-Json -Depth 12 | ConvertFrom-Json -AsHashtable
            foreach ($name in $invalid.Keys) { $copy[$name] = $invalid[$name] }
            $copy | ConvertTo-Json -Depth 12 | Set-Content "$TestDrive/prerequisite.json"
            { . $script:stageScript @script:stageParameters -Stage Image -CheckpointPath "$TestDrive/prerequisite.json" } | Should -Throw '*checkpoint*'
        }
        $copy = $script:checkpoint | ConvertTo-Json -Depth 12 | ConvertFrom-Json -AsHashtable
        $copy.stage = 'Image'
        $copy.image = 'foreign-registry.azurecr.io/sample:latest'
        $copy | ConvertTo-Json -Depth 12 | Set-Content "$TestDrive/prerequisite.json"
        { . $script:stageScript @script:stageParameters -Stage Application -CheckpointPath "$TestDrive/prerequisite.json" } | Should -Throw '*checkpoint image*'
        $script:azureCalls.Count | Should -Be 0
        $report = Get-Content "$TestDrive/evidence/deployment-image.json" -Raw | ConvertFrom-Json
        $report.status | Should -Be 'FailedResourcesMayBeRetained'
    }
    It 'refuses validation against a placeholder without modifying Azure or calling the API' {
        $script:checkpoint.stage = 'Application'
        $script:checkpoint.image = $script:liveImage
        $script:liveImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        $script:checkpoint | ConvertTo-Json -Depth 12 | Set-Content "$TestDrive/prerequisite.json"
        { . $script:stageScript @script:stageParameters -Stage Validation -CheckpointPath "$TestDrive/prerequisite.json" } | Should -Throw '*approved image*'
        ($script:azureCalls -join '|') | Should -Not -Match 'deployment|acr|keyvault'
        $report = Get-Content "$TestDrive/evidence/deployment-validation.json" -Raw | ConvertFrom-Json
        $report.status | Should -Be 'FailedResourcesMayBeRetained'
        $report.liveVerified | Should -Not -BeTrue
    }
    It 'bounds readiness to the new revision and never creates a token during validation' {
        Mock Start-Sleep {}
        $script:checkpoint.stage = 'Application'
        $script:checkpoint.image = $script:liveImage
        $script:checkpoint | ConvertTo-Json -Depth 12 | Set-Content "$TestDrive/prerequisite.json"
        $script:readyRevision = 'old-ready-revision'
        { . $script:stageScript @script:stageParameters -Stage Validation -CheckpointPath "$TestDrive/prerequisite.json" } | Should -Throw '*revision did not become ready*'
        Should -Invoke az -Times 30 -Exactly -ParameterFilter { $Arguments[0] -eq 'containerapp' }
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'keyvault' }
        $script:readyRevision = 'approved-revision'
        $script:secretExists = $false
        { . $script:stageScript @script:stageParameters -Stage Validation -CheckpointPath "$TestDrive/prerequisite.json" } | Should -Throw '*Complete the application stage*'
        ($script:azureCalls -join '|') | Should -Not -Match 'deployment|acr|keyvault secret set'
        Test-Path "$TestDrive/evidence/api-token.private" | Should -BeFalse
    }
    It 'creates a missing token only in application setup and removes its private file' {
        $script:secretExists = $false
        New-Item -ItemType Directory -Path "$TestDrive/evidence" -Force | Out-Null
        { Get-SampleApiToken -VaultName 'kv-ftk-dto-hack-s-ae46' -OutputDirectory "$TestDrive/evidence" } | Should -Throw '*Complete the application stage*'
        $token = Get-SampleApiToken -VaultName 'kv-ftk-dto-hack-s-ae46' -OutputDirectory "$TestDrive/evidence" -CreateIfMissing
        $token | Should -Be $script:storedToken
        $token.Length | Should -BeGreaterOrEqual 32
        Test-Path "$TestDrive/evidence/api-token.private" | Should -BeFalse
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { $Arguments[2] -eq 'set' }
    }
}

Describe 'Sample ownership and price preflight' {
    It 'reports failed live requests without exposing response payloads' {
        Mock Wait-SampleReady {}
        Mock Invoke-RestMethod {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::UnprocessableEntity)
            $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Synthetic HTTP failure.', $response)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'SyntheticLiveFailure', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $errorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                '{"generatedSql":"private-generated-sql","rows":["private-row"],"token":"private-token"}')
            throw $errorRecord
        }
        $parameters = @{
            BaseUri = [Uri]'https://sample.azurecontainerapps.io'
            ApiToken = 'private-token'
            ApplicationInsightsResourceId = '/subscriptions/synthetic/providers/Microsoft.Insights/components/sample'
            WorkspaceCustomerId = [Guid]'00000000-0000-0000-0000-000000000001'
            OutputDirectory = $TestDrive
        }
        $failure = {
            . "$PSScriptRoot/../eng/Collect-Evidence.ps1" @parameters
        } | Should -Throw -PassThru -ExpectedMessage 'Live question request failed: category-revenue (HTTP 422).'
        ($failure | Out-String) | Should -Not -Match 'private-generated-sql|private-row|private-token'
        Test-Path "$TestDrive/live-evaluation.json" | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }
    It 'retries a cold-start timeout but bounds retries and refuses offline readiness' {
        $script:readinessCalls = 0
        $script:readinessMode = 'cold-start'
        Mock Start-Sleep {}
        Mock Invoke-RestMethod {
            $script:readinessCalls++
            if ($script:readinessMode -eq 'timeout' -or $script:readinessCalls -eq 1) {
                throw [System.Threading.Tasks.TaskCanceledException]::new('Synthetic readiness timeout.')
            }
            return @{
                status = 'ready'
                modelMode = if ($script:readinessMode -eq 'offline') { 'deterministic' } else { 'azure-openai' }
            }
        }
        $uri = [Uri]'https://sample.azurecontainerapps.io'
        { Wait-SampleReady -BaseUri $uri -WarningAction SilentlyContinue } | Should -Not -Throw
        $script:readinessCalls | Should -Be 2
        foreach ($mode in @('timeout', 'offline')) {
            $script:readinessCalls = 0
            $script:readinessMode = $mode
            { Wait-SampleReady -BaseUri $uri -WarningAction SilentlyContinue } | Should -Throw '*not ready*'
            $script:readinessCalls | Should -Be 30
        }
    }
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
        $script:samplePreview.changes[0].after = @{ secret = 'private-preview-payload' }
        $failure = {
            Get-SamplePreview -Arguments $arguments -Scope $scope
        } | Should -Throw -PassThru -ExpectedMessage '*Unsupported*containerApps/sample*'
        $failure.Exception.Message | Should -Not -BeLike '*private-preview-payload*'
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
    It 'accepts fulfillment rows only in the independently expected region order' {
        $cases = Get-Content "$PSScriptRoot/evaluation/questions.json" -Raw | ConvertFrom-Json
        $case = $cases | Where-Object { $_.id -eq 'fulfillment-by-region' }
        $answer = @{
            answerStatus = $case.expectedStatus; answer = $case.expectedAnswer
            data = ($case.expectedData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
            evidence = @{ agentCalls = $case.expectedCalls }
        }
        { Assert-SampleAnswer -Case $case -Answer $answer } | Should -Not -Throw
        $firstRow = $answer.data.rows[0]
        $answer.data.rows[0] = $answer.data.rows[1]
        $answer.data.rows[1] = $firstRow
        { Assert-SampleAnswer -Case $case -Answer $answer } | Should -Throw (
            '*rowIndex=0, columnIndex=0, mismatch=value, expectedRowMatches=1*')
    }
    It 'diagnoses string mismatches without logging returned or expected values' {
        $cases = Get-Content "$PSScriptRoot/evaluation/questions.json" -Raw | ConvertFrom-Json
        $case = $cases | Where-Object { $_.id -eq 'fulfillment-by-region' }
        foreach ($scenario in @(
            @{ value = 42; mismatch = 'type'; matches = 'none' }
            @{ value = 'South'; mismatch = 'value'; matches = '1' }
            @{ value = 'private-returned-value'; mismatch = 'value'; matches = 'none' }
        )) {
            $answer = @{
                answerStatus = $case.expectedStatus; answer = $case.expectedAnswer
                data = ($case.expectedData | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
                evidence = @{ agentCalls = $case.expectedCalls }
            }
            $answer.data.rows[0][0] = $scenario.value
            $failure = {
                Assert-SampleAnswer -Case $case -Answer $answer
            } | Should -Throw -PassThru -ExpectedMessage (
                "Live string value failed: fulfillment-by-region (rowIndex=0, columnIndex=0, mismatch=$($scenario.mismatch), expectedRowMatches=$($scenario.matches)).")
            ($failure | Out-String) | Should -Not -Match 'private-returned-value|North|South|West'
        }
    }
    It 'rejects exported usage and attribution that differ from provider evidence' {
        $properties = [PSCustomObject]@{
            'experiment.id' = 'experiment-hash'
            'optimization.variant' = 'baseline'
            'gen_ai.response.model' = 'gpt-5-mini'
            'agent.name' = 'coordinator'
            'gen_ai.usage.input_tokens' = 5; 'gen_ai.usage.output_tokens' = 2
        }
        $rows = @(
            [PSCustomObject]@{ Name = 'coordinator.run'; Id = 'root'; ParentId = ''; SessionId = 'session-hash'; Properties = $properties }
            [PSCustomObject]@{ Name = 'gen_ai.chat'; Id = 'child'; ParentId = 'root'; SessionId = 'session-hash'; Properties = $properties }
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
        $rows[1].SessionId = 'foreign-session'
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
        $rows[1].SessionId = ''
        $properties | Add-Member 'session.id' 'session-hash'
        { Assert-SampleTelemetry -Answer $answer -Rows $rows } | Should -Throw
    }
}

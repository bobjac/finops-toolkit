# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . "$PSScriptRoot/../Deployment-Common.ps1"
    $script:complete = "$PSScriptRoot/../Complete-HackDeployment.ps1"
    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        throw "Unexpected unmocked Azure call: $($Arguments -join ' ')"
    }
    function git {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        throw "Unexpected unmocked Git call: $($Arguments -join ' ')"
    }
    function Set-DeploymentFixture {
        param([string]$Path, $Value)
        $null = New-Item -ItemType Directory -Path (Split-Path $Path) -Force
        $Value | ConvertTo-Json -Depth 50 | Set-Content $Path
    }
}

Describe 'Complete sandbox readiness' {
    BeforeEach {
        $script:saved = @{}
        foreach ($entry in @{
                GITHUB_ACTIONS = 'true'; GITHUB_REPOSITORY = 'bobjac/finops-toolkit'; GITHUB_REF = 'refs/heads/dev'
                GITHUB_SHA = 'a' * 40; GITHUB_RUN_ID = '123'; GITHUB_RUN_ATTEMPT = '2'; GITHUB_STEP_SUMMARY = ''
                SAMPLE_DEPLOYER_OBJECT_ID = '00000000-0000-4000-8000-000000000001'; SAMPLE_PRICE_EVIDENCE = ''
            }.GetEnumerator()) {
            $script:saved[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
        $script:directory = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        $script:prices = @{
            currency = 'USD'; region = 'eastus2'; model = 'gpt-5-mini'; modelVersion = '2025-08-07'
            deploymentSku = 'GlobalStandard'; verifiedAt = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
            inputPerMillion = 0.25; cachedInputPerMillion = 0.025; outputPerMillion = 2.0; analyticsPerGB = 2.76
            sourceUrls = @('https://prices.azure.com/model', 'https://azure.microsoft.com/analytics')
        }
        $env:SAMPLE_PRICE_EVIDENCE = $script:prices | ConvertTo-Json
        $script:results = @{}
        foreach ($name in 'foundation', 'verify', 'seed_first', 'seed_second', 'infrastructure', 'image', 'application', 'validation', 'workbook') {
            $script:results[$name] = @{ result = 'success' }
        }
        $foundationId = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-foundation'
        $sampleId = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
        $script:foundation = @{
            Status = 'VerifiedAndRetained'; ReadyForDataIngestion = $true; RunId = '123'; SourceRevision = 'a' * 40
            ResourceGroupId = $foundationId; Resources = @(@{ Id = "$foundationId/providers/Microsoft.Kusto/clusters/fixture" })
        }
        $script:seed = @{
            Status = 'VerifiedAndRetained'; ReadyForSeededHistory = $true; BaselineMatch = $true
            RunId = '123'; SourceRevision = 'a' * 40; SourceFingerprint = 'unchanged-sample-and-retail-fingerprint'
            Packages = @(@{ Label = 'model-prices'; Snapshot = @{ Rows = 3 } })
        }
        $script:metadata = @{
            sourceRevision = 'a' * 40; seedVersion = 'sample-history-v1'
            modelCoverage = @{
                model = 'gpt-5-mini'; region = 'eastus2'; currency = 'USD'; deploymentSku = 'GlobalStandard'
                retrievedAt = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
                requiredMeters = @{ input = @{ usdPerMillionTokens = 0.25 }; cachedInput = @{ usdPerMillionTokens = 0.025 }
                    output = @{ usdPerMillionTokens = 2.0 } }
            }
        }
        $workbookId = "$sampleId/providers/Microsoft.Insights/workbooks/478410d0-a0ae-5679-89fe-eea6a576654c"
        $script:workbook = @{
            Status = 'VerifiedAndRetained'; ReadyForWorkbook = $true; RunId = '123'; SourceRevision = 'a' * 40
            SampleRevision = 'a' * 40; SeedRevision = 'a' * 40; WorkbookRevision = 'a' * 40
            SampleRunId = '123'; SeedRunId = '123'
            DeploymentOutputs = @{ workbookId = @{ value = $workbookId }; workbookUrl = @{ value = "https://portal.azure.com/#@/resource$workbookId/workbook" } }
        }
        $script:sample = @{
            version = 1; stage = 'Validation'; status = 'Completed'; revision = 'a' * 40; runId = '123'; runAttempt = '1'
            subscriptionId = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'; resourceGroup = 'ftk-dto-hack-s-ae46'
            liveVerified = $true; prices = $script:prices; image = "crftkdtohacksae46.azurecr.io/sample:$('a' * 40)"
            expiresOn = [DateTimeOffset]::UtcNow.AddDays(1).ToString('o')
            outputs = @{
                registryName = @{ value = 'crftkdtohacksae46' }; registryLoginServer = @{ value = 'crftkdtohacksae46.azurecr.io' }
                keyVaultName = @{ value = 'kv-ftk-dto-hack-s-ae46' }; containerAppName = @{ value = 'ca-ftk-dto-hack-s-ae46' }
                applicationInsightsResourceId = @{ value = "$sampleId/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46" }
                workspaceCustomerId = @{ value = '00000000-0000-4000-8000-000000000001' }
                fqdn = @{ value = 'ca-ftk-dto-hack-s-ae46.fixture.eastus2.azurecontainerapps.io' }
            }
        }
        foreach ($stage in 'Infrastructure', 'Image', 'Application', 'Validation') {
            $script:sample.stage = $stage
            Set-DeploymentFixture "$script:directory/sample/deployment-$($stage.ToLowerInvariant()).json" $script:sample
        }
        Set-DeploymentFixture "$script:directory/foundation/verification/foundation.json" $script:foundation
        Set-DeploymentFixture "$script:directory/seed/seed-evidence-first/seed-report.json" $script:seed
        Set-DeploymentFixture "$script:directory/seed/seed-evidence-second/seed-report.json" $script:seed
        Set-DeploymentFixture "$script:directory/seed/seed-second/seed.json" $script:metadata
        Set-DeploymentFixture "$script:directory/workbook/workbook-report.json" $script:workbook
    }
    AfterEach {
        foreach ($entry in $script:saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value) }
    }

    It 'Publishes verified links and seed provenance from one run, retaining the original successful sample attempt' {
        & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json)
        $report = Get-Content "$script:directory/readiness.json" -Raw | ConvertFrom-Json
        $report.ready | Should -BeTrue
        $report.sources.sampleAttempt | Should -Be '1'
        $report.links.application | Should -Be "https://$($script:sample.outputs.fqdn.value)"
        $report.links.workbook | Should -Be $script:workbook.DeploymentOutputs.workbookUrl.value
        $report.seed.replacementVerified | Should -BeTrue
    }
    It 'Rejects failed, canceled, skipped, or absent stages despite successful-looking old reports' -ForEach @(
        @{ Stage = 'foundation'; Result = 'failure' }, @{ Stage = 'seed_first'; Result = 'failure' }
        @{ Stage = 'seed_second'; Result = 'cancelled' }, @{ Stage = 'validation'; Result = 'skipped' }
        @{ Stage = 'workbook'; Result = $null }
    ) {
        $script:results[$Stage].result = $Result
        { & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json) } | Should -Throw '*did not succeed*'
        $report = Get-Content "$script:directory/readiness.json" -Raw | ConvertFrom-Json
        $report.ready | Should -BeFalse
        $report.PSObject.Properties.Name | Should -Not -Contain 'links'
    }
    It 'Cannot publish readiness for partial ingestion, wrong-run provenance, or an unverified workbook' -ForEach @(
        @{ Problem = 'ingestion' }, @{ Problem = 'provenance' }, @{ Problem = 'workbook' }
    ) {
        switch ($Problem) {
            ingestion {
                $script:seed.BaselineMatch = $false
                Set-DeploymentFixture "$script:directory/seed/seed-evidence-second/seed-report.json" $script:seed
            }
            provenance {
                $script:foundation.RunId = 'another-run'
                Set-DeploymentFixture "$script:directory/foundation/verification/foundation.json" $script:foundation
            }
            workbook {
                $script:workbook.ReadyForWorkbook = $false
                Set-DeploymentFixture "$script:directory/workbook/workbook-report.json" $script:workbook
            }
        }
        { & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json) } | Should -Throw
        (Get-Content "$script:directory/readiness.json" -Raw | ConvertFrom-Json).ready | Should -BeFalse
    }
    It 'Rejects stale, mismatched, or inapplicable seed prices' -ForEach @(
        @{ Problem = 'stale' }, @{ Problem = 'rate' }, @{ Problem = 'region' }
    ) {
        switch ($Problem) {
            stale { $script:metadata.modelCoverage.retrievedAt = [DateTimeOffset]::UtcNow.AddDays(-8).ToString('o') }
            rate { $script:metadata.modelCoverage.requiredMeters.input.usdPerMillionTokens = 999 }
            region { $script:metadata.modelCoverage.region = 'another-region' }
        }
        Set-DeploymentFixture "$script:directory/seed/seed-second/seed.json" $script:metadata
        { & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json) } | Should -Throw '*price*'
        (Get-Content "$script:directory/readiness.json" -Raw | ConvertFrom-Json).ready | Should -BeFalse
    }
    It 'Reports missing evidence as failure and preserves a diagnostic receipt' {
        Remove-Item "$script:directory/sample/deployment-validation.json"
        { & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json) } | Should -Throw
        (Get-Content "$script:directory/readiness.json" -Raw | ConvertFrom-Json).status | Should -Be 'Failed'
    }
    It 'Cannot publish readiness for an expired sample despite successful live verification' {
        $script:sample.expiresOn = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
        Set-DeploymentFixture "$script:directory/sample/deployment-validation.json" $script:sample
        { & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json) } | Should -Throw '*expired*'
        (Get-Content "$script:directory/readiness.json" -Raw | ConvertFrom-Json).ready | Should -BeFalse
    }
    It 'Refuses a foreign workbook link even when all stage results say success' {
        $script:workbook.DeploymentOutputs.workbookUrl.value = 'https://example.invalid/foreign'
        Set-DeploymentFixture "$script:directory/workbook/workbook-report.json" $script:workbook
        { & $script:complete -EvidenceDirectory $script:directory -StageResultsJson ($script:results | ConvertTo-Json) } | Should -Throw '*ownership*'
    }
    It 'Requires explicit confirmation and fresh verified prices before deployment' {
        { Assert-HackDeploymentInput wrong } | Should -Throw '*confirmed*'
        { Assert-HackDeploymentInput deploy-retained-hack-sandbox } | Should -Not -Throw
        $script:prices.verifiedAt = [DateTimeOffset]::UtcNow.AddDays(-8).ToString('o')
        $env:SAMPLE_PRICE_EVIDENCE = $script:prices | ConvertTo-Json
        { Assert-HackDeploymentInput deploy-retained-hack-sandbox } | Should -Throw '*seven days*'
    }
    It 'Delegates a real image stage to the existing entry point and propagates native build failure' -ForEach @(
        @{ FailBuild = $false }, @{ FailBuild = $true }
    ) {
        Mock git { $global:LASTEXITCODE = 0; $env:GITHUB_SHA }
        Mock az {
            param($Arguments)
            $global:LASTEXITCODE = 0
            $operation = $Arguments[0..1] -join ' '
            $response = switch ($operation) {
                'account show' { @{ id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'; tenantId = '3670e846-58dd-4658-86fb-00e4029045d6' } }
                'group exists' { $true }
                'group show' { @{ name = 'ftk-dto-hack-s-ae46'; tags = @{
                            repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' } } }
                'acr build' {
                    if ($FailBuild) { $global:LASTEXITCODE = 1 }
                    @{ status = if ($FailBuild) { 'Failed' } else { 'Succeeded' } }
                }
                default { throw "Unexpected Azure operation: $operation" }
            }
            ConvertTo-Json -InputObject $response -Depth 10
        }
        $invoke = {
            & "$PSScriptRoot/../Invoke-HackDeploymentStage.ps1" -Stage Image -EvidenceDirectory $script:directory `
                -Confirmation deploy-retained-hack-sandbox
        }
        if ($FailBuild) { $invoke | Should -Throw '*Azure CLI failed*' } else { $invoke | Should -Not -Throw }
        $checkpoint = Get-Content "$script:directory/sample/deployment-image.json" -Raw | ConvertFrom-Json
        $checkpoint.status | Should -Be $(if ($FailBuild) { 'FailedResourcesMayBeRetained' } else { 'Completed' })
        $checkpoint.runAttempt | Should -Be '2'
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'acr' -and $Arguments[1] -eq 'build' }
    }
}

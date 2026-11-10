# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    $script:Root = (Resolve-Path "$PSScriptRoot/../../../..").Path
    $script:Publisher = Join-Path $script:Root 'src/scripts/Publish-DesignTimeOptimizerWorkbook.ps1'
    $script:WorkbookDirectory = Join-Path $script:Root 'src/workbooks/optimization/AiAgentTokenomicsLivePrices'
    . "$script:Root/hack/sample-multi-agent-workload/eng/Sample-Common.ps1"
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Publisher, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Workbook publisher must parse.' }
    foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}

Describe 'Workbook deployment and price evidence contracts' {
    BeforeEach {
        $script:Subscription = '11111111-1111-4111-8111-111111111111'
        $script:Revision = 'a' * 40
        $script:Metadata = @{
            version = 1; sourceRevision = $script:Revision
            modelCoverage = @{
                model = 'gpt-5-mini'; region = 'eastus2'; currency = 'USD'; deploymentSku = 'GlobalStandard'
                retrievedAt = [DateTimeOffset]::UtcNow.AddHours(-1).ToString('o')
                sourceUrl = 'https://prices.azure.com/api/retail/prices?fixture=true'
                requiredMeters = @{}
            }
            packages = @(@{ label = 'model-prices'; profile = 'dto-retail-public-v1'; prices = @() })
        }
        $index = 1
        foreach ($direction in 'input', 'cachedInput', 'output') {
            $meter = "00000000-0000-4000-8000-00000000000$index"
            $price = @{ input = 0.25; cachedInput = 0.025; output = 2.0 }[$direction]
            $script:Metadata.modelCoverage.requiredMeters[$direction] = @{
                meterId = $meter; usdPerMillionTokens = $price; effectiveStart = '2025-01-01T00:00:00Z'
            }
            $script:Metadata.packages[0].prices += @{
                meterId = $meter; offer = 'PUBLIC-RETAIL'; unit = '1M'; blockSize = 1000000
                listPrice = $price; region = 'US East 2'; effectiveStart = '2025-01-01T00:00:00Z'
            }
            $index++
        }
        $script:Seed = @{ Status = 'VerifiedAndRetained'; ReadyForSeededHistory = $true; BaselineMatch = $true; SourceRevision = $script:Revision }
        $script:Foundation = @{
            Status = 'VerifiedAndRetained'; ReadyForDataIngestion = $true; ResourceGroup = 'fixture-foundation'
            ResourceGroupId = "/subscriptions/$script:Subscription/resourceGroups/fixture-foundation"
            Outputs = @{
                clusterUri = 'https://fixture.eastus2.kusto.windows.net'; ingestionDbName = 'Ingestion'
                clusterId = "/subscriptions/$script:Subscription/resourceGroups/fixture-foundation/providers/Microsoft.Kusto/clusters/fixture"
            }
        }
        $script:Sample = @{
            status = 'Completed'; stage = 'Validation'; liveVerified = $true
            revision = $script:Revision; subscriptionId = $script:Subscription; resourceGroup = 'fixture-sample'
            prices = @{ model = 'gpt-5-mini'; region = 'eastus2'; deploymentSku = 'GlobalStandard' }
            outputs = @{ applicationInsightsResourceId = @{ value = "/subscriptions/$script:Subscription/resourceGroups/fixture-sample/providers/Microsoft.Insights/components/fixture" } }
        }
        $script:Arguments = @{
            Metadata = $script:Metadata; SeedReport = $script:Seed; Foundation = $script:Foundation
            Sample = $script:Sample; Subscription = $script:Subscription
        }
    }

    It 'Binds endpoints and exact meter identities from verified predecessor outputs' {
        $result = Get-TokenomicsContext @script:Arguments
        $result.appInsightsId | Should -Be $script:Sample.outputs.applicationInsightsResourceId.value
        $result.hubClusterUri | Should -Be $script:Foundation.Outputs.clusterUri
        $result.priceContext.meters.Count | Should -Be 3
        $result.priceContext.meters[1].price | Should -Be 0.025
        $result.priceContext.retrievedAt | Should -Be $script:Metadata.modelCoverage.retrievedAt
    }

    It 'Rejects an unverified sample instead of accepting infrastructure-only readiness' {
        $script:Sample.liveVerified = $false
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*successful seed replacement*'
    }

    It 'Rejects a failed replacement even when individual price rows exist' {
        $script:Seed.BaselineMatch = $false
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*successful seed replacement*'
    }

    It 'Rejects historical or foreign resource identifiers as telemetry targets' {
        $script:Sample.outputs.applicationInsightsResourceId.value = '/subscriptions/other/resourceGroups/history/providers/Microsoft.Insights/components/fixture'
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*verified sandbox resources*'
    }

    It 'Rejects stale and future retrieval timestamps: <Days>' -TestCases @(@{ Days = -8 }, @{ Days = 1 }) {
        param($Days)
        $script:Metadata.modelCoverage.retrievedAt = [DateTimeOffset]::UtcNow.AddDays($Days).ToString('o')
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*freshness policy*'
    }

    It 'Rejects incompatible model and region evidence' {
        $script:Sample.prices.region = 'westus'
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*freshness policy*'
    }

    It 'Rejects a nonpublic source rather than silently trusting supplied rates' {
        $script:Metadata.modelCoverage.sourceUrl = 'https://example.invalid/prices'
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*freshness policy*'
    }

    It 'Rejects ambiguous meter identities' {
        $script:Metadata.modelCoverage.requiredMeters.cachedInput.meterId = $script:Metadata.modelCoverage.requiredMeters.input.meterId
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*invalid identity*'
    }

    It 'Rejects wrong blocks and invalid rates: <Field>' -TestCases @(
        @{ Field = 'blockSize'; Value = 1000 }
        @{ Field = 'unit'; Value = '1K' }
        @{ Field = 'listPrice'; Value = 0 }
        @{ Field = 'listPrice'; Value = [double]::NaN }
    ) {
        param($Field, $Value)
        $script:Metadata.packages[0].prices[0][$Field] = $Value
        { Get-TokenomicsContext @script:Arguments } | Should -Throw '*invalid identity*'
    }

    It 'Renders the same base query with encoded provenance and bounded time parameters' {
        $parameters = Get-TokenomicsContext @script:Arguments
        $base = Get-Content "$script:WorkbookDirectory/token-cost.kql" -Raw
        $query = Get-TokenomicsQuery -Query $base -Parameters $parameters
        $query | Should -Not -Match '\{(HubCluster|HubDatabase|PriceContext|TimeRange:|Experiment:|Baseline|Candidate)'
        $query | Should -Match "adx\('https://fixture.eastus2.kusto.windows.net/Ingestion'\)"
        $query | Should -Match 'Session=tostring\(session_Id\)'
        $query | Should -Not -Match "d\['session.id'\]"
    }

    It 'Keeps the shared cross-service query within repository KQL conventions' {
        $query = Get-Content "$script:WorkbookDirectory/token-cost.kql" -Raw
        $query | Should -Not -Match '\|\s*join\b(?![^(\r\n]*\bkind\s*=)'
        $query | Should -Not -Match '(?i)\bcontains(?:_cs)?\b'
        $query | Should -Not -Match '(?i)(tolower|toupper)\([^)]*\)\s*(==|!=|=~|!~|has|contains)'
    }

    It 'Rejects preview deletion, unrelated resource types, and foreign groups: <Kind>' -TestCases @(
        @{ Kind = 'Delete'; Path = '/providers/Microsoft.Insights/workbooks/00000000-0000-4000-8000-000000000001'; Foreign = $false }
        @{ Kind = 'Create'; Path = '/providers/Microsoft.Storage/storageAccounts/fixture'; Foreign = $false }
        @{ Kind = 'Create'; Path = '/providers/Microsoft.Insights/workbooks/00000000-0000-4000-8000-000000000001'; Foreign = $true }
    ) {
        param($Kind, $Path, $Foreign)
        $scope = "/subscriptions/$script:Subscription/resourceGroups/fixture-sample"
        $target = if ($Foreign) { $scope.Replace('fixture-sample', 'other-group') } else { $scope }
        $preview = @{ status = 'Succeeded'; changes = @(@{ resourceId = "$target$Path"; changeType = $Kind }) }
        { Assert-TokenomicsPreview -Preview $preview -Scope $scope } | Should -Throw '*out-of-scope change*'
    }

    It 'Rejects an unowned existing workbook before creating a deployment' {
        $scope = "/subscriptions/$script:Subscription/resourceGroups/fixture-sample"
        $preview = @{ status = 'Succeeded'; changes = @(@{
            resourceId = "$scope/providers/Microsoft.Insights/workbooks/00000000-0000-4000-8000-000000000001"; changeType = 'Modify'
        }) }
        Mock Invoke-SampleAz { @{ tags = @{} } }
        { Assert-TokenomicsPreview -Preview $preview -Scope $scope } | Should -Throw '*unowned workbook*'
    }

    It 'Rejects partial query responses instead of treating available rows as complete' {
        Mock Invoke-SampleAz { @{ error = @{ code = 'PartialError' }; tables = @(@{ name = 'PrimaryResult'; columns = @(); rows = @() }) } }
        { Invoke-TokenomicsQuery -Query 'print 1' -ApplicationInsights 'fixture' } | Should -Throw '*partial results*'
    }

    It 'Reads columns by name without hiding null estimates' {
        Mock Invoke-SampleAz {
            @{ tables = @(@{ name = 'PrimaryResult'; columns = @(@{ name = 'Calls' }, @{ name = 'EstimatedTotalUSD' }); rows = @(, @(3, $null)) }) }
        }
        $rows = @(Invoke-TokenomicsQuery -Query 'print 1' -ApplicationInsights 'fixture')
        $rows.Count | Should -Be 1
        $rows[0].Calls | Should -Be 3
        $rows[0].EstimatedTotalUSD | Should -BeNullOrEmpty
    }

    It 'Persists false readiness when predecessor validation fails before Azure access' {
        $seedDirectory = Join-Path $TestDrive 'seed'
        $sampleDirectory = Join-Path $TestDrive 'sample'
        $null = New-Item -ItemType Directory -Force "$seedDirectory/seed-second", "$seedDirectory/seed-evidence-second/foundation", $sampleDirectory
        $script:Metadata.version = 0
        $script:Metadata | ConvertTo-Json -Depth 20 | Set-Content "$seedDirectory/seed-second/seed.json"
        $script:Seed | ConvertTo-Json | Set-Content "$seedDirectory/seed-evidence-second/seed-report.json"
        $script:Foundation | ConvertTo-Json -Depth 10 | Set-Content "$seedDirectory/seed-evidence-second/foundation/foundation.json"
        $script:Sample | ConvertTo-Json -Depth 10 | Set-Content "$sampleDirectory/deployment-validation.json"
        $names = 'GITHUB_ACTIONS', 'GITHUB_REPOSITORY', 'GITHUB_REF', 'AZURE_SUBSCRIPTION_ID'
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
        try {
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_REPOSITORY = 'bobjac/finops-toolkit'
            $env:GITHUB_REF = 'refs/heads/dev'
            $env:AZURE_SUBSCRIPTION_ID = $script:Subscription
            $output = Join-Path $TestDrive 'failure'
            { & $script:Publisher -SeedDirectory $seedDirectory -SampleDirectory $sampleDirectory -OutputDirectory $output } |
                Should -Throw '*successful seed replacement*'
            $report = Get-Content "$output/workbook-report.json" -Raw | ConvertFrom-Json
            $report.Status | Should -Be 'Failed'
            $report.ReadyForWorkbook | Should -BeFalse
        }
        finally {
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }
}

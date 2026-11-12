# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    $script:Root = (Resolve-Path "$PSScriptRoot/../../../..").Path
    $script:Adapter = Join-Path $script:Root 'src/scripts/Get-DesignTimeOptimizerContext.ps1'
    $script:ContextQueryDirectory = Join-Path $script:Root 'src/design-time-optimizer/context'
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Adapter, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Context adapter must parse.' }
    foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}

Describe 'Bounded design-time context' {
    BeforeEach {
        $script:Subscription = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
        $script:Scope = "/subscriptions/$script:Subscription/resourceGroups/ftk-dto-hack-s-ae46"
        $script:FoundationId = "/subscriptions/$script:Subscription/resourceGroups/ftk-dto-hack-foundation"
        $script:Directory = Join-Path $TestDrive 'seed'
        $script:Metadata = @{
            version = 1; sourceRevision = 'a' * 40
            modelCoverage = @{
                model = 'gpt-5-mini'; region = 'eastus2'; currency = 'USD'; deploymentSku = 'GlobalStandard'
                retrievedAt = [DateTimeOffset]::UtcNow.AddHours(-1).ToString('o')
                sourceUrl = 'https://prices.azure.com/api/retail/prices?fixture=true'; requiredMeters = @{}
            }
            packages = @(@{ label = 'model-prices'; profile = 'dto-retail-public-v1'; prices = @() })
        }
        $script:Prices = @()
        $index = 1
        foreach ($direction in 'input', 'cachedInput', 'output') {
            $meter = "00000000-0000-4000-8000-00000000000$index"
            $price = @{ input = 0.25; cachedInput = 0.025; output = 2.0 }[$direction]
            $script:Metadata.modelCoverage.requiredMeters[$direction] = @{
                meterId = $meter; usdPerMillionTokens = $price; effectiveStart = '2025-01-01T00:00:00Z'
            }
            $script:Metadata.packages[0].prices += @{
                meterId = $meter; region = 'US East 2'; listPrice = $price
            }
            $script:Prices += @{
                MeterId = $meter; Offer = 'PUBLIC-RETAIL'; Price = $price; Currency = 'USD'
                Unit = '1M'; BlockSize = 1000000; Region = 'US East 2'
                EffectiveStart = '2025-01-01T00:00:00Z'; EffectiveEnd = $null
            }
            $index++
        }
        $script:Seed = @{
            SourceRevision = 'a' * 40; Status = 'VerifiedAndRetained'; ReadyForSeededHistory = $true
            BaselineMatch = $true; RunId = '123'; CompletedAt = [DateTimeOffset]::UtcNow.AddHours(-1).ToString('o')
        }
        $script:Foundation = @{
            Status = 'VerifiedAndRetained'; ReadyForDataIngestion = $true; ResourceGroupId = $script:FoundationId
            Outputs = @{
                clusterId = "$script:FoundationId/providers/Microsoft.Kusto/clusters/fixture"
                clusterUri = 'https://fixture.eastus2.kusto.windows.net'; hubDbName = 'Hub'
            }
        }
        $null = New-Item "$script:Directory/seed-second", "$script:Directory/seed-evidence-second/foundation" -ItemType Directory -Force
        $script:Metadata | ConvertTo-Json -Depth 20 | Set-Content "$script:Directory/seed-second/seed.json"
        $script:Seed | ConvertTo-Json -Depth 20 | Set-Content "$script:Directory/seed-evidence-second/seed-report.json"
        $script:Foundation | ConvertTo-Json -Depth 20 | Set-Content "$script:Directory/seed-evidence-second/foundation/foundation.json"
        Mock Invoke-ContextAzure {
            param($Arguments, $Body)
            if ($Arguments[0] -eq 'account') {
                return @{ id = $script:Subscription; tenantId = '3670e846-58dd-4658-86fb-00e4029045d6'; state = 'Enabled'; user = @{ type = 'servicePrincipal'; name = '11111111-1111-4111-8111-111111111111' } }
            }
            if ($Arguments[0] -eq 'resource') { return @{ properties = @{ uri = 'https://fixture.eastus2.kusto.windows.net' } } }
            if ($Arguments -contains 'get') { return @{ value = @() } }
            $rows = @(if ($Body.csl -match 'Prices\(\)') { $script:Prices } else {
                @(@{ ResourceId = '/subscriptions/historical/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/vm'; BillingCurrency = 'USD'; BilledCost = 25.5; Rows = 4; DataThrough = '2024-07-01T00:00:00Z' })
            })
            $names = @($rows[0].Keys)
            $values = @()
            foreach ($row in $rows) {
                $values += ,@($names | ForEach-Object { $row[$_] })
            }
            @(
                @{ FrameType = 'DataTable'; TableKind = 'PrimaryResult'; Columns = @($names | ForEach-Object { @{ ColumnName = $_ } }); Rows = $values }
                @{ FrameType = 'DataSetCompletion'; HasErrors = $false }
            )
        }
    }

    It 'Returns attributable context with explicit historical/live scope separation' {
        $result = Invoke-DesignTimeContext -Tool get_cost_summary -SeedDirectory $script:Directory -Scope $script:Scope
        $result.scope.resourceId | Should -Be $script:Scope
        $result.dataScope.kind | Should -Be 'sample-history'
        $result.dataScope.deploymentTargets | Should -BeFalse
        $result.data.rows[0].BilledCost | Should -Be 25.5
        $result.freshness.dataThrough | Should -Be '2024-07-01T00:00:00Z'
        $result.evidence[0].seedRevision | Should -Be ('a' * 40)
        $result.evidence[1].querySha256 | Should -Match '^[A-F0-9]{64}$'
        $result.warnings -join ' ' | Should -Match 'not current spend'
        $result.audit.status | Should -Be 'Succeeded'
    }

    It 'Keeps historical resource IDs as non-target context and uses fixed grouping' {
        $result = Invoke-DesignTimeContext -Tool get_cost_by_resource -SeedDirectory $script:Directory -Scope $script:Scope
        $result.data.rows[0].ResourceId | Should -Match '/historical/'
        $result.data.rows[0].DeploymentTarget | Should -BeFalse
        Should -Invoke Invoke-ContextAzure -Times 1 -ParameterFilter {
            $Body.csl -match 'by ResourceId, BillingCurrency' -and
            $Body.csl -match "x_BillingProfileId =~ 'dto-history-v1'" -and
            $Body.csl -notmatch '__START__|__END__|__GROUPING__'
        }
    }

    It 'Rejects non-allowlisted targets before contacting Azure: <Suffix>' -ForEach @(
        @{ Suffix = '/subscriptions/historical/resourceGroups/fixture' }
        @{ Suffix = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a' }
        @{ Suffix = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46-foreign' }
        @{ Suffix = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46/providers/Microsoft.Compute/virtualMachines/vm' }
    ) {
        { Invoke-DesignTimeContext -Tool get_cost_summary -SeedDirectory $script:Directory -Scope $Suffix } | Should -Throw '*exact approved sandbox*'
        Should -Invoke Invoke-ContextAzure -Times 0
    }

    It 'Rejects changed seed/foundation provenance: <Change>' -ForEach @(
        @{ Change = 'seed' }; @{ Change = 'endpoint' }; @{ Change = 'clusterId' }
    ) {
        if ($Change -eq 'seed') {
            $script:Seed.SourceRevision = 'b' * 40
            $script:Seed | ConvertTo-Json -Depth 20 | Set-Content "$script:Directory/seed-evidence-second/seed-report.json"
        }
        else {
            if ($Change -eq 'endpoint') { $script:Foundation.Outputs.clusterUri = 'https://foreign.eastus2.kusto.windows.net' }
            else { $script:Foundation.Outputs.clusterId = '/subscriptions/foreign/resourceGroups/history/providers/Microsoft.Kusto/clusters/fixture' }
            $script:Foundation | ConvertTo-Json -Depth 20 | Set-Content "$script:Directory/seed-evidence-second/foundation/foundation.json"
        }
        { Invoke-DesignTimeContext -Tool get_cost_summary -SeedDirectory $script:Directory -Scope $script:Scope } | Should -Throw
        Should -Invoke Invoke-ContextAzure -Times 0
    }

    It 'Rejects unknown tool names and invalid windows before provider access' {
        { Invoke-DesignTimeContext -Tool query -SeedDirectory $script:Directory -Scope $script:Scope } | Should -Throw '*Unsupported*'
        { Invoke-DesignTimeContext -Tool get_cost_summary -SeedDirectory $script:Directory -Scope $script:Scope -Start '2024-06-05Z' -End '2024-06-04Z' } | Should -Throw
        { Invoke-DesignTimeContext -Tool get_cost_summary -SeedDirectory $script:Directory -Scope $script:Scope -Start '2024-01-01Z' } | Should -Throw
        Should -Invoke Invoke-ContextAzure -Times 0
    }

    It 'Rejects the wrong Azure account before any data access' {
        Mock Invoke-ContextAzure { @{ id = 'foreign'; tenantId = 'foreign'; state = 'Enabled' } }
        { Invoke-DesignTimeContext -Tool get_cost_summary -SeedDirectory $script:Directory -Scope $script:Scope } | Should -Throw '*approved sandbox subscription*'
        Should -Invoke Invoke-ContextAzure -Times 1
    }

    It 'Does not mask provider failure as an empty result' {
        Mock Invoke-ContextAzure { throw 'Azure context request failed.' }
        { Invoke-DesignTimeContext -Tool get_optimization_recommendations -SeedDirectory $script:Directory -Scope $script:Scope } | Should -Throw '*request failed*'
    }

    It 'Reports empty cached recommendations explicitly without generating them' {
        $result = Invoke-DesignTimeContext -Tool get_optimization_recommendations -SeedDirectory $script:Directory -Scope $script:Scope
        $result.source | Should -Be 'azure-advisor'
        $result.data.status | Should -Be 'empty'
        $result.data.rows.Count | Should -Be 0
        $result.warnings -join ' ' | Should -Match 'does not prove'
        $result.freshness.dataThrough | Should -BeNullOrEmpty
        Should -Invoke Invoke-ContextAzure -Times 1 -ParameterFilter {
            $Arguments -contains 'get' -and ($Arguments -join ' ') -match 'Microsoft.Advisor/recommendations'
        }
        Should -Invoke Invoke-ContextAzure -Times 0 -ParameterFilter { $Arguments -contains 'post' }
    }

    It 'Rejects malformed recommendations rather than treating them as empty' {
        $configuration = Get-ContextConfiguration -Directory $script:Directory -RequestedScope $script:Scope
        Mock Invoke-ContextAzure { @{} }
        { Get-ContextRecommendation -Configuration $configuration } | Should -Throw '*invalid response*'
    }

    It 'Rejects foreign recommendation resources and foreign pagination URLs' {
        $configuration = Get-ContextConfiguration -Directory $script:Directory -RequestedScope $script:Scope
        Mock Invoke-ContextAzure { @{ value = @(@{ id = 'fixture'; properties = @{ category = 'Cost'; resourceMetadata = @{ resourceId = '/subscriptions/foreign/providers/Microsoft.Compute/virtualMachines/vm' } } }) } }
        { Get-ContextRecommendation -Configuration $configuration } | Should -Throw '*out-of-scope*'
        Mock Invoke-ContextAzure { @{ value = @(); nextLink = 'https://foreign.invalid/recommendations' } }
        { Get-ContextRecommendation -Configuration $configuration } | Should -Throw '*pagination URL*'
    }

    It 'Fails rather than accepting incomplete recommendation pagination' {
        $configuration = Get-ContextConfiguration -Directory $script:Directory -RequestedScope $script:Scope
        Mock Invoke-ContextAzure { @{ value = @(); nextLink = "https://management.azure.com/subscriptions/$script:Subscription/providers/Microsoft.Advisor/recommendations?api-version=2023-01-01" } }
        { Get-ContextRecommendation -Configuration $configuration } | Should -Throw '*five-page*'
    }

    It 'Preserves valid recommendation dates without exposing remediation commands' {
        $configuration = Get-ContextConfiguration -Directory $script:Directory -RequestedScope $script:Scope
        Mock Invoke-ContextAzure {
            @{ value = @(@{
                id = "$script:Scope/providers/Microsoft.Advisor/recommendations/fixture"
                properties = @{
                    category = 'Cost'; impact = 'Low'; lastUpdated = '2025-01-01T00:00:00Z'
                    shortDescription = @{ problem = 'Synthetic opportunity'; solution = 'Review the measured workload' }
                    resourceMetadata = @{ resourceId = "$script:Scope/providers/Microsoft.Compute/virtualMachines/fixture" }
                    remediation = @{ command = 'not-executable-context' }
                }
            }) }
        }
        $rows = @(Get-ContextRecommendation -Configuration $configuration)
        $rows.Count | Should -Be 1
        $rows[0].lastUpdated | Should -Be '2025-01-01T00:00:00Z'
        $rows[0].ContainsKey('remediation') | Should -BeFalse
        $rows[0].deploymentTarget | Should -BeFalse
    }

    It 'Returns actual applicable hub prices and their original retrieval timestamp' {
        $result = Invoke-DesignTimeContext -Tool get_current_pricing -SeedDirectory $script:Directory -Scope $script:Scope
        $result.data.rows.Count | Should -Be 3
        $result.data.rows[1].Price | Should -Be 0.025
        $result.data.rows[1].Direction | Should -Be 'cachedInput'
        [DateTimeOffset]$result.freshness.pricingAsOf | Should -Be ([DateTimeOffset]$script:Metadata.modelCoverage.retrievedAt)
        $result.dataScope.currency | Should -Be 'USD'
    }

    It 'Rejects stale/future/missing retrieval times: <Days>' -ForEach @(
        @{ Days = -8 }; @{ Days = 1 }
    ) {
        $script:Metadata.modelCoverage.retrievedAt = [DateTimeOffset]::UtcNow.AddDays($Days).ToString('o')
        { Assert-ContextPrice -Metadata $script:Metadata -Rows $script:Prices } | Should -Throw '*stale*'
    }

    It 'Rejects absent, duplicate, or changed required meter coverage: <Change>' -ForEach @(
        @{ Change = 'missing' }; @{ Change = 'duplicate' }; @{ Change = 'identity' }
    ) {
        if ($Change -eq 'missing') { $script:Prices = @($script:Prices[0]) }
        if ($Change -eq 'duplicate') { $script:Prices[1] = $script:Prices[0] }
        if ($Change -eq 'identity') { $script:Metadata.modelCoverage.requiredMeters.output.meterId = $script:Metadata.modelCoverage.requiredMeters.input.meterId }
        { Assert-ContextPrice -Metadata $script:Metadata -Rows $script:Prices } | Should -Throw
    }

    It 'Rejects price unit, scope, effective-date, or arithmetic mismatches: <Field>' -ForEach @(
        @{ Field = 'Currency'; Value = 'EUR' }
        @{ Field = 'Unit'; Value = '1K' }
        @{ Field = 'BlockSize'; Value = 1000 }
        @{ Field = 'Region'; Value = 'foreign' }
        @{ Field = 'Price'; Value = 0.01 }
        @{ Field = 'Price'; Value = [double]::NaN }
        @{ Field = 'Price'; Value = $null }
        @{ Field = 'EffectiveEnd'; Value = '2020-01-01T00:00:00Z' }
    ) {
        $script:Prices[0][$Field] = $Value
        { Assert-ContextPrice -Metadata $script:Metadata -Rows $script:Prices } | Should -Throw '*invalid units*'
    }

    It 'Rejects failed, partial, missing, or truncated ADX query results' {
        { Get-ContextTable -Frames @(@{ FrameType = 'DataSetCompletion'; HasErrors = $true }) } | Should -Throw '*incomplete*'
        { Get-ContextTable -Frames @() } | Should -Throw '*incomplete*'
        $frames = @(
            @{ FrameType = 'DataTable'; TableKind = 'PrimaryResult'; Columns = @(@{ ColumnName = 'Value' }); Rows = @() }
            @{ FrameType = 'DataSetCompletion'; HasErrors = $false }
        )
        @(Get-ContextTable -Frames $frames).Count | Should -Be 0
        $frames[0].Rows = @(1..201 | ForEach-Object { ,@($_) })
        { Get-ContextTable -Frames $frames } | Should -Throw '*200-row*'
    }

    It 'Packages the same executable context adapter and query files' {
        $destination = Join-Path $TestDrive 'plugin'
        $null = New-Item "$destination/skills/design-time-optimizer" -ItemType Directory -Force
        & "$script:Root/src/scripts/Build-AgentPlugin.ps1" -DestDir $destination
        $packaged = "$destination/skills/design-time-optimizer"
        (Get-FileHash "$packaged/scripts/Get-DesignTimeOptimizerContext.ps1").Hash |
            Should -Be (Get-FileHash $script:Adapter).Hash
        foreach ($name in 'historical-cost.kql', 'model-pricing.kql') {
            (Get-FileHash "$packaged/references/context/$name").Hash |
                Should -Be (Get-FileHash "$script:Root/src/design-time-optimizer/context/$name").Hash
        }
    }
}

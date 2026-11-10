# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Executes the actual workbook pricing query with explicitly synthetic KQL fixtures.
    .DESCRIPTION
    Internal publisher step. Uses the caller's validated query renderer and reader.
    .PARAMETER Parameters
    Validated workbook parameters.
    .PARAMETER OutputDirectory
    Destination for synthetic assertion outcomes, never presentation fallback data.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Parameters,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$base = Get-Content "$PSScriptRoot/../workbooks/optimization/AiAgentTokenomicsLivePrices/token-cost.kql" -Raw
$now = [DateTimeOffset]::UtcNow
$queryWindow = @{ Start = $now.AddDays(-1); End = $now.AddMinutes(5) }
$context = @{
    model = 'fixture-model'; retrievedAt = $now.AddMinutes(-1).ToString('o')
    meters = @(
        @{ meterId = 'input'; direction = 'input'; price = 0.25; region = 'fixture-region'; effectiveStart = '2025-01-01' }
        @{ meterId = 'cached'; direction = 'cachedInput'; price = 0.025; region = 'fixture-region'; effectiveStart = '2025-01-01' }
        @{ meterId = 'output'; direction = 'output'; price = 2.0; region = 'fixture-region'; effectiveStart = '2025-01-01' }
    )
}
$cases = @(
    @{ name = 'priced-cached-subset'; model = 'fixture-model'; cached = 20; currency = 'USD'; copies = 1; inputRows = 1; outputRows = 1; age = 1; status = 'priced'; cost = 0.0000405 }
    @{ name = 'missing-output'; model = 'fixture-model'; cached = 20; currency = 'USD'; copies = 1; inputRows = 1; outputRows = 0; age = 1; status = 'unpriced output' }
    @{ name = 'mixed-currency'; model = 'fixture-model'; cached = 20; currency = 'EUR'; copies = 1; inputRows = 1; outputRows = 1; age = 1; status = 'unpriced input' }
    @{ name = 'duplicate-price'; model = 'fixture-model'; cached = 20; currency = 'USD'; copies = 1; inputRows = 2; outputRows = 1; age = 1; status = 'unpriced input' }
    @{ name = 'duplicate-span'; model = 'fixture-model'; cached = 20; currency = 'USD'; copies = 2; inputRows = 1; outputRows = 1; age = 1; status = 'duplicate span' }
    @{ name = 'invalid-cached-tokens'; model = 'fixture-model'; cached = 101; currency = 'USD'; copies = 1; inputRows = 1; outputRows = 1; age = 1; status = 'invalid or missing usage' }
    @{ name = 'unmatched-model'; model = 'other-model'; cached = 20; currency = 'USD'; copies = 1; inputRows = 1; outputRows = 1; age = 1; status = 'unmatched model' }
    @{ name = 'stale-pricing'; model = 'fixture-model'; cached = 20; currency = 'USD'; copies = 1; inputRows = 1; outputRows = 1; age = 8; status = 'stale or future price evidence' }
)
$results = @()
foreach ($case in $cases)
{
    $context.retrievedAt = $now.AddDays(-$case.age).ToString('o')
    $fixtureParameters = @{
        priceContext = $context; hubClusterUri = $Parameters.hubClusterUri; hubDatabase = $Parameters.hubDatabase
    }
    $fixtures = @"
let FixturePrices =
    datatable(x_SkuMeterId:string, ListUnitPrice:real, PricingCurrency:string, x_SkuRegion:string, x_PricingUnitDescription:string, x_PricingBlockSize:real, x_EffectivePeriodStart:datetime, x_EffectivePeriodEnd:datetime, x_BillingProfileId:string, x_SkuOfferId:string)
    ['input', 0.25, '$($case.currency)', 'fixture-region', '1M', 1000000, datetime(2025-01-01), datetime(null), 'dto-retail-public-v1', 'PUBLIC-RETAIL',
     'cached', 0.025, 'USD', 'fixture-region', '1M', 1000000, datetime(2025-01-01), datetime(null), 'dto-retail-public-v1', 'PUBLIC-RETAIL',
     'output', 2.0, 'USD', 'fixture-region', '1M', 1000000, datetime(2025-01-01), datetime(null), 'dto-retail-public-v1', 'PUBLIC-RETAIL']
    | extend N=case(x_SkuMeterId == 'input', $($case.inputRows), x_SkuMeterId == 'output', $($case.outputRows), 1)
    | mv-expand Repeat=range(1, N, 1)
    | where N > 0;
let FixtureDependencies =
    print timestamp=now(), operation_Id='fixture-operation', id='fixture-model-span', session_Id='fixture-session', duration=100.0,
        customDimensions=dynamic({'agent.name':'fixture-agent','gen_ai.response.model':'$($case.model)','experiment.id':'fixture','optimization.variant':'baseline','gen_ai.usage.input_tokens':100,'gen_ai.usage.cache_read.input_tokens':$($case.cached),'gen_ai.usage.output_tokens':10})
    | extend Repeats=range(1, $($case.copies), 1)
    | mv-expand Repeat=Repeats;
"@
    $query = Get-TokenomicsQuery -Query $base -Parameters $fixtureParameters @queryWindow
    $query = $query.Replace("adx('$($Parameters.hubClusterUri)/$($Parameters.hubDatabase)').Prices_final_v1_2", 'FixturePrices').
        Replace("    dependencies`n", "    FixtureDependencies`n")
    $query = "$fixtures`n$query`nTokenCosts | project PriceStatus, EstimatedCost, Copies, InputTokens, CachedTokens, OutputTokens"
    $rows = @(Invoke-TokenomicsQuery -Query $query -ApplicationInsights $Parameters.appInsightsId @queryWindow)
    if ($rows.Count -ne 1 -or $rows[0].PriceStatus -cne $case.status -or
        ($case.ContainsKey('cost') -and ($null -eq $rows[0].EstimatedCost -or [Math]::Abs($rows[0].EstimatedCost - $case.cost) -gt 0.000000000001)) -or
        (-not $case.ContainsKey('cost') -and $null -ne $rows[0].EstimatedCost) -or
        $rows[0].Copies -ne $case.copies)
    {
        throw "Synthetic workbook pricing assertion failed: $($case.name)."
    }
    $results += @{ Case = $case.name; Passed = $true; Synthetic = $true }
    $results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'synthetic-query-tests.json')
}

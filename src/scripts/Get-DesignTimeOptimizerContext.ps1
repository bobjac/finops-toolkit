# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Retrieves bounded, read-only FinOps context for the approved hack sandbox.

    .DESCRIPTION
    Uses verified H03 artifacts, fixed Hub queries, and cached Azure Advisor
    recommendations. Historical sample identifiers never become Azure targets.
    Provider errors, incomplete results, and invalid prices fail explicitly.

    .PARAMETER Tool
    One of the four version 1 context tools.

    .PARAMETER SeedDirectory
    Downloaded sandbox-seed artifact containing the second successful seed pass.

    .PARAMETER Scope
    Exact approved foundation or sample resource-group ARM identifier.

    .PARAMETER Start
    Inclusive historical charge start. Defaults to the original sample period.

    .PARAMETER End
    Exclusive historical charge start bound. Maximum period is 31 days.

    .EXAMPLE
    ./src/scripts/Get-DesignTimeOptimizerContext.ps1 -Tool get_cost_summary -SeedDirectory .tmp/seed -Scope /subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46

    Returns labeled sample history, not actual charges for the live sample group.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('get_cost_summary', 'get_cost_by_resource', 'get_optimization_recommendations', 'get_current_pricing')]
    [string]$Tool,
    [Parameter(Mandatory)][string]$SeedDirectory,
    [Parameter(Mandatory)][string]$Scope,
    [DateTimeOffset]$Start = [DateTimeOffset]'2024-06-01T00:00:00Z',
    [DateTimeOffset]$End = [DateTimeOffset]'2024-07-01T00:00:00Z'
)

$ErrorActionPreference = 'Stop'
$script:ContextQueryDirectory = Join-Path $PSScriptRoot '../design-time-optimizer/context'
if (-not (Test-Path -LiteralPath $script:ContextQueryDirectory))
{
    $script:ContextQueryDirectory = Join-Path $PSScriptRoot '../references/context'
}

function Invoke-ContextAzure
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments, [System.Collections.IDictionary]$Body)
    $bodyPath = $null
    try
    {
        if ($Body)
        {
            $bodyPath = [IO.Path]::GetTempFileName()
            $Body | ConvertTo-Json -Depth 20 -Compress | Set-Content -LiteralPath $bodyPath -Encoding utf8
            $Arguments += @('--body', "@$bodyPath")
        }
        $output = & az @Arguments --only-show-errors --output json 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            # Provider diagnostics can contain sensitive response bodies.
            throw "Azure context request failed (exit $LASTEXITCODE). Check identity and read permissions; no fallback was used."
        }
        if (-not $output) { throw 'Azure context request returned no JSON response.' }
        try
        {
            return (($output -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100)
        }
        catch [ArgumentException]
        {
            throw 'Azure context request returned invalid JSON; no fallback was used.'
        }
    }
    finally
    {
        if ($bodyPath) { Remove-Item -LiteralPath $bodyPath -Force }
    }
}

function Get-ContextConfiguration
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$RequestedScope)
    $subscription = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
    $prefix = "/subscriptions/$subscription/resourceGroups"
    if ($RequestedScope -inotmatch "^$prefix/(ftk-dto-hack-foundation|ftk-dto-hack-s-ae46)$")
    {
        throw 'Context scope must be an exact approved sandbox resource group; historical sample IDs are not targets.'
    }
    $metadata = Get-Content -LiteralPath "$Directory/seed-second/seed.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $seed = Get-Content -LiteralPath "$Directory/seed-evidence-second/seed-report.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $foundation = Get-Content -LiteralPath "$Directory/seed-evidence-second/foundation/foundation.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $foundationId = "$prefix/ftk-dto-hack-foundation"
    if ($metadata.version -ne 1 -or $metadata.sourceRevision -cnotmatch '^[a-f0-9]{40}$' -or
        $seed.SourceRevision -cne $metadata.sourceRevision -or
        $seed.Status -cne 'VerifiedAndRetained' -or $seed.ReadyForSeededHistory -ne $true -or $seed.BaselineMatch -ne $true -or
        $seed.RunId -notmatch '^[0-9]+$' -or -not $seed.CompletedAt -or
        [DateTimeOffset]$seed.CompletedAt -gt [DateTimeOffset]::UtcNow -or
        $foundation.Status -cne 'VerifiedAndRetained' -or $foundation.ReadyForDataIngestion -ne $true -or
        $foundation.ResourceGroupId -ine $foundationId -or
        $foundation.Outputs.clusterId -inotmatch "^$foundationId/providers/Microsoft[.]Kusto/clusters/[a-z0-9]+$" -or
        $foundation.Outputs.hubDbName -cne 'Hub' -or
        $foundation.Outputs.clusterUri -cnotmatch '^https://[a-z0-9]+[.]eastus2[.]kusto[.]windows[.]net/?$')
    {
        throw 'Context requires verified seed replacement and owned foundation artifacts with matching provenance.'
    }
    $clusterName = $foundation.Outputs.clusterId.Split('/')[-1]
    if (([Uri]$foundation.Outputs.clusterUri).Host -cne "$clusterName.eastus2.kusto.windows.net")
    {
        throw 'Foundation cluster URI does not match its resource identifier.'
    }
    @{
        subscriptionId = $subscription; scope = $RequestedScope; group = $RequestedScope.Split('/')[-1]
        clusterUri = $foundation.Outputs.clusterUri.TrimEnd('/'); clusterId = $foundation.Outputs.clusterId
        metadata = $metadata; seed = $seed; foundationId = $foundationId
    }
}

function Get-ContextTable
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Frames)
    $completion = @($Frames | Where-Object { $_.FrameType -eq 'DataSetCompletion' -and $_.HasErrors -eq $false })
    $tables = @($Frames | Where-Object { $_.FrameType -eq 'DataTable' -and $_.TableKind -eq 'PrimaryResult' })
    if ($completion.Count -ne 1 -or $tables.Count -ne 1 -or
        @($Frames | Where-Object { $_.HasErrors -or $_.Cancelled -or $_.error }).Count -or
        $null -eq $tables[0].Columns -or $null -eq $tables[0].Rows)
    {
        throw 'Hub context query failed or returned incomplete results.'
    }
    if ($tables[0].Rows.Count -gt 200) { throw 'Context exceeds the 200-row limit; refusing to publish truncated context.' }
    foreach ($row in $tables[0].Rows)
    {
        if ($row.Count -ne $tables[0].Columns.Count) { throw 'Hub context row has an invalid shape.' }
        $record = @{}
        for ($index = 0; $index -lt $row.Count; $index++)
        {
            $name = $tables[0].Columns[$index].ColumnName
            if (-not $name -or $record.Contains($name)) { throw 'Hub context columns must be named and unique.' }
            $record[$name] = $row[$index]
        }
        $record
    }
}

function Get-ContextRecommendation
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Configuration)
    $path = "/subscriptions/$($Configuration.subscriptionId)/providers/Microsoft.Advisor/recommendations"
    $filter = [Uri]::EscapeDataString("Category eq 'Cost' and ResourceGroup eq '$($Configuration.group)'")
    $url = "https://management.azure.com${path}?api-version=2023-01-01&`$filter=$filter&`$top=100"
    $records = @()
    for ($page = 0; $url -and $page -lt 5; $page++)
    {
        $uri = [Uri]$url
        if ($uri.Scheme -cne 'https' -or $uri.Host -cne 'management.azure.com' -or
            $uri.AbsolutePath -ine $path -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Fragment)
        {
            throw 'Advisor pagination URL is outside the approved read-only endpoint.'
        }
        $response = Invoke-ContextAzure -Arguments @('rest', '--method', 'get', '--url', $url)
        if ($null -eq $response.value -or $response.error) { throw 'Advisor returned an invalid response, not an empty recommendation list.' }
        foreach ($item in $response.value)
        {
            $properties = $item.properties
            $resourceId = [string]$properties.resourceMetadata.resourceId
            if (-not $resourceId.StartsWith("$($Configuration.scope)/providers/", [StringComparison]::OrdinalIgnoreCase) -or
                $properties.category -cne 'Cost' -or -not $item.id -or -not $properties.lastUpdated -or
                [DateTimeOffset]$properties.lastUpdated -gt [DateTimeOffset]::UtcNow)
            {
                throw 'Advisor returned an out-of-scope recommendation or invalid provenance.'
            }
            $records += @{
                id = $item.id; resourceId = $resourceId; category = 'Cost'; impact = $properties.impact
                problem = $properties.shortDescription.problem; solution = $properties.shortDescription.solution
                lastUpdated = $properties.lastUpdated; deploymentTarget = $false
            }
        }
        if ($records.Count -gt 200) { throw 'Advisor context exceeds the 200-row limit.' }
        $url = [string]$response.nextLink
    }
    if ($url) { throw 'Advisor context exceeds the five-page limit; results are incomplete.' }
    $records
}

function Assert-ContextPrice
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows
    )
    $coverage = $Metadata.modelCoverage
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]$coverage.retrievedAt
    if (-not $coverage.retrievedAt -or $age.TotalSeconds -lt 0 -or $age.TotalDays -gt 7 -or
        $coverage.model -cne 'gpt-5-mini' -or $coverage.region -cne 'eastus2' -or
        $coverage.currency -cne 'USD' -or $coverage.deploymentSku -cne 'GlobalStandard' -or
        $coverage.sourceUrl -cnotmatch '^https://prices[.]azure[.]com/api/retail/prices[?]' -or
        (($coverage.requiredMeters.Keys | Sort-Object) -join ',') -cne 'cachedInput,input,output' -or $Rows.Count -ne 3)
    {
        throw 'Required model pricing is missing, stale, future-dated, or has invalid scope/provenance.'
    }
    $packages = @($Metadata.packages | Where-Object { $_.label -ceq 'model-prices' })
    if ($packages.Count -ne 1 -or $packages[0].profile -cne 'dto-retail-public-v1' -or $packages[0].prices.Count -ne 3)
    {
        throw 'Model price package provenance is incomplete.'
    }
    $ids = @()
    foreach ($direction in 'input', 'cachedInput', 'output')
    {
        $meter = $coverage.requiredMeters[$direction]
        $expected = @($packages[0].prices | Where-Object { $_.meterId -ceq $meter.meterId })
        $matched = @($Rows | Where-Object { $_.MeterId -ceq $meter.meterId })
        if ($meter.meterId -cnotmatch '^[a-f0-9-]{36}$' -or $meter.meterId -in $ids -or
            $expected.Count -ne 1 -or $matched.Count -ne 1)
        {
            throw "Required model price '$direction' is missing or ambiguous."
        }
        $row = $matched[0]
        if ($row.Currency -cne 'USD' -or $row.Offer -cne 'PUBLIC-RETAIL' -or
            $row.Unit -cne '1M' -or $row.BlockSize -ne 1000000 -or
            -not $row.Region -or $row.Region -cne $expected[0].region -or
            $null -eq $row.Price -or -not [double]::IsFinite([double]$row.Price) -or $row.Price -le 0 -or
            $row.Price -ne $meter.usdPerMillionTokens -or $row.Price -ne $expected[0].listPrice -or
            -not $row.EffectiveStart -or
            [DateTimeOffset]$row.EffectiveStart -ne [DateTimeOffset]$meter.effectiveStart -or
            [DateTimeOffset]$row.EffectiveStart -gt [DateTimeOffset]::UtcNow -or
            ($row.EffectiveEnd -and [DateTimeOffset]$row.EffectiveEnd -le [DateTimeOffset]::UtcNow))
        {
            throw "Required model price '$direction' has invalid units, currency, rate, region, or effective dates."
        }
        $ids += $meter.meterId
        $row.Direction = $direction
    }
}

function Invoke-DesignTimeContext
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string]$SeedDirectory,
        [Parameter(Mandatory)][string]$Scope,
        [DateTimeOffset]$Start = [DateTimeOffset]'2024-06-01T00:00:00Z',
        [DateTimeOffset]$End = [DateTimeOffset]'2024-07-01T00:00:00Z'
    )
    if ($Tool -cnotin @('get_cost_summary', 'get_cost_by_resource', 'get_current_pricing', 'get_optimization_recommendations'))
    {
        throw 'Unsupported context tool.'
    }
    if ($Start -ge $End -or ($End - $Start).TotalDays -gt 31 -or
        $Start -lt [DateTimeOffset]'2024-06-01T00:00:00Z' -or $End -gt [DateTimeOffset]'2024-07-01T00:00:00Z')
    {
        throw 'Historical context requires a nonempty period within the original June 2024 sample window (maximum 31 days).'
    }
    $configuration = Get-ContextConfiguration -Directory $SeedDirectory -RequestedScope $Scope
    $account = Invoke-ContextAzure -Arguments @('account', 'show')
    if ($account.id -ine $configuration.subscriptionId -or
        $account.tenantId -ine '3670e846-58dd-4658-86fb-00e4029045d6' -or
        $account.state -cne 'Enabled' -or -not $account.user.name)
    {
        throw 'Azure account must match the enabled approved sandbox subscription and tenant.'
    }
    $actualCluster = Invoke-ContextAzure -Arguments @('resource', 'show', '--ids', $configuration.clusterId, '--api-version', '2025-02-14')
    if (([string]$actualCluster.properties.uri).TrimEnd('/') -ine $configuration.clusterUri)
    {
        throw 'Verified cluster outputs no longer match Azure.'
    }
    $requestId = [Guid]::NewGuid().ToString()
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $warnings = @()
    $freshness = @{ dataThrough = $null; pricingAsOf = $null; seedVerifiedAt = $configuration.seed.CompletedAt }
    $evidence = @(@{ seedRunId = $configuration.seed.RunId; seedRevision = $configuration.metadata.sourceRevision })
    $source = 'finops-hub'
    if ($Tool -ceq 'get_optimization_recommendations')
    {
        $rows = @(Get-ContextRecommendation -Configuration $configuration)
        $source = 'azure-advisor'
        $dataScope = @{ kind = 'cached-advisor'; deploymentTargets = $false }
        $warnings += 'Cached Advisor recommendations are read-only context, not measured savings or permission to apply changes. No recommendation generation was requested.'
        if (-not $rows.Count) { $warnings += 'No cached cost recommendations were returned for this scope; this does not prove that the workload is optimized.' }
        if ($rows.Count) { $freshness.dataThrough = ($rows.lastUpdated | Sort-Object | Select-Object -First 1) }
        $evidence += @{ endpoint = 'Azure Advisor recommendations'; apiVersion = '2023-01-01' }
    }
    else
    {
        $name = if ($Tool -ceq 'get_current_pricing') { 'model-pricing.kql' } else { 'historical-cost.kql' }
        $queryPath = Join-Path $script:ContextQueryDirectory $name
        $query = Get-Content -LiteralPath $queryPath -Raw
        $grouping = if ($Tool -ceq 'get_cost_by_resource') { 'ResourceId, BillingCurrency' } else { 'BillingCurrency' }
        $query = $query.Replace('__START__', $Start.UtcDateTime.ToString('o')).Replace('__END__', $End.UtcDateTime.ToString('o')).Replace('__GROUPING__', $grouping)
        $body = @{
            db = 'Hub'; csl = $query
            properties = @{ Options = @{ servertimeout = '00:00:30'; truncationmaxrecords = 201; queryconsistency = 'strongconsistency' } } | ConvertTo-Json -Compress
        }
        $frames = @(Invoke-ContextAzure -Arguments @('rest', '--method', 'post', '--url', "$($configuration.clusterUri)/v2/rest/query", '--resource', 'https://api.kusto.windows.net') -Body $body)
        $rows = @(Get-ContextTable -Frames $frames)
        $evidence += @{
            clusterId = $configuration.clusterId; database = 'Hub'; query = $name
            querySha256 = (Get-FileHash -LiteralPath $queryPath -Algorithm SHA256).Hash
        }
        if ($Tool -ceq 'get_current_pricing')
        {
            Assert-ContextPrice -Metadata $configuration.metadata -Rows $rows
            $freshness.pricingAsOf = $configuration.metadata.modelCoverage.retrievedAt
            $dataScope = @{ kind = 'public-retail-model-prices'; profile = 'dto-retail-public-v1'; model = 'gpt-5-mini'; region = 'eastus2'; currency = 'USD'; deploymentSku = 'GlobalStandard'; deploymentTargets = $false }
            $evidence += @{ sourceUrl = $configuration.metadata.modelCoverage.sourceUrl }
            $warnings += 'Public-retail model estimates exclude negotiated rates and infrastructure. Rates are per 1,000,000 tokens; cached input is included in total input, not an additional token subtraction.'
        }
        else
        {
            foreach ($row in $rows)
            {
                if ($row.BillingCurrency -cne 'USD' -or $null -eq $row.BilledCost -or
                    -not [double]::IsFinite([double]$row.BilledCost) -or $row.Rows -le 0 -or
                    -not $row.DataThrough -or [DateTimeOffset]$row.DataThrough -gt $End -or
                    ($Tool -ceq 'get_cost_by_resource' -and -not $row.ResourceId))
                {
                    throw 'Historical cost context has invalid currency, totals, dates, or resource identity.'
                }
                $row.DeploymentTarget = $false
            }
            $dataScope = @{
                kind = 'sample-history'; profile = 'dto-history-v1'; deploymentTargets = $false
                start = $Start.ToUniversalTime().ToString('o'); end = $End.ToUniversalTime().ToString('o')
            }
            if ($rows.Count) { $freshness.dataThrough = ($rows.DataThrough | Sort-Object | Select-Object -Last 1) }
            $warnings += 'June 2024 sample history is not current spend for the requested live resource group. Historical resource IDs are context only, never deployment targets or measured savings.'
            if (-not $rows.Count) { $warnings += 'No sample-history rows were returned for this period. Missing history does not mean zero current spend.' }
        }
    }
    $timer.Stop()
    [pscustomobject]@{
        version = 1; requestId = $requestId; tool = $Tool; source = $source
        scope = @{ subscriptionId = $configuration.subscriptionId; resourceGroup = $configuration.group; resourceId = $Scope }
        observedAt = [DateTimeOffset]::UtcNow.ToString('o'); freshness = $freshness; dataScope = $dataScope
        data = @{ status = $(if ($rows.Count) { 'available' } else { 'empty' }); rows = @($rows) }
        warnings = @($warnings); evidence = @($evidence)
        audit = @{
            requestId = $requestId; tool = $Tool; scope = $Scope; status = 'Succeeded'
            caller = @{
                type = $account.user.type
                idHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$account.user.name)))
            }
            durationMs = $timer.ElapsedMilliseconds
        }
    }
}

$elapsed = [Diagnostics.Stopwatch]::StartNew()
try
{
    $result = Invoke-DesignTimeContext @PSBoundParameters
    Write-Information ($result.audit | ConvertTo-Json -Compress)
    $result
}
catch
{
    Write-Information (@{
        tool = $Tool; scope = $Scope; status = 'Failed'; durationMs = $elapsed.ElapsedMilliseconds
    } | ConvertTo-Json -Compress)
    throw
}

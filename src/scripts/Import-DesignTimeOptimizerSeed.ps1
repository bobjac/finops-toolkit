# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Imports prepared sample history and prices through the hub ingestion trigger.

    .DESCRIPTION
    Requires a verified owned foundation, explicit group confirmation, typed seed
    packages, and 36-month final retention. Uploads manifests last, waits for the
    actual Data Factory runs, and checks hub rows and scoped totals. Replacement
    is confined to three dedicated seed folders. Failures never report readiness.

    .PARAMETER SeedDirectory
    Directory produced by seed/prepare.py.

    .PARAMETER OutputDirectory
    Directory for nonsecret ingestion and verification evidence.

    .PARAMETER Path
    Sandbox configuration JSON.

    .PARAMETER ConfirmResourceGroup
    Exact owned resource group name required before any uploads or deletions.

    .PARAMETER BaselineReport
    Optional successful first seed report used to verify an identical rerun.

    .PARAMETER TimeoutMinutes
    Maximum elapsed time for ingestion and verification in this seed pass.

    .EXAMPLE
    ./src/scripts/Import-DesignTimeOptimizerSeed.ps1 -SeedDirectory ./.tmp/seed -ConfirmResourceGroup ftk-dto-hack-foundation -Confirm:$false

    Replaces only the owned sample partitions and verifies ingestion.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$SeedDirectory,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../.tmp/seed-evidence'),
    [string]$Path = (Join-Path $PSScriptRoot '../../hack/sandbox.config.json'),
    [Parameter(Mandatory)][string]$ConfirmResourceGroup,
    [string]$BaselineReport,
    [ValidateRange(1, 30)][int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
$groupName = "$($config.resourceGroupPrefix)-foundation"
if ($ConfirmResourceGroup -cne $groupName) { throw 'Enter the exact owned foundation resource group name to confirm seed replacement.' }
if ($WhatIfPreference)
{
    $null = $PSCmdlet.ShouldProcess($groupName, 'Replace only dto-history-v1 and dto-retail-public-v1 seed partitions')
    return
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$reportPath = Join-Path $OutputDirectory 'seed-report.json'
$report = [ordered]@{
    Version = 1; Status = 'Started'; ReadyForSeededHistory = $false
    RunId = $env:GITHUB_RUN_ID; Packages = @(); BaselineMatch = $null
}
$deadline = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
$baseline = $null
$seedFilePattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}__seed\.parquet$'

function Invoke-SeedAzure
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        $code = 'Unclassified'
        if (($output -join "`n") -match '\bAADSTS\d+\b') { $code = $Matches[0] }
        elseif (($output -join "`n") -match '(?i)(?:ErrorCode[:=]\s*|"code"\s*:\s*")([A-Za-z][A-Za-z0-9]+)') { $code = $Matches[1] }
        $operation = $Arguments[0..1] -join ' '
        throw "Azure CLI failed during '$operation' (exit $LASTEXITCODE; $code)."
    }
    if ($output) { ($output -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100 }
}

function Get-SeedQuery
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Query)
    $body = @{ db = 'Hub'; csl = $Query } | ConvertTo-Json -Compress
    $frames = @(Invoke-SeedAzure -Arguments @('rest', '--method', 'post', '--url', "$clusterUri/v2/rest/query", '--resource', 'https://api.kusto.windows.net', '--body', $body))
    if (@($frames | Where-Object { $_.FrameType -eq 'DataSetCompletion' -and $_.HasErrors -eq $false }).Count -ne 1 -or
        @($frames | Where-Object { $_.HasErrors -or $_.Cancelled -or $_.error }).Count)
    {
        throw 'Hub query failed or returned an incomplete result.'
    }
    $tables = @($frames | Where-Object { $_.FrameType -eq 'DataTable' -and $_.TableKind -eq 'PrimaryResult' })
    if ($tables.Count -ne 1) { throw 'Expected exactly one primary hub result table.' }
    foreach ($row in $tables[0].Rows)
    {
        $record = @{}
        for ($column = 0; $column -lt $tables[0].Columns.Count; $column++)
        {
            $record[$tables[0].Columns[$column].ColumnName] = $row[$column]
        }
        $record
    }
}

function Get-SeedPipelineRun
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][DateTimeOffset]$Since)
    $body = @{
        lastUpdatedAfter = $Since.ToString('o')
        lastUpdatedBefore = [DateTimeOffset]::UtcNow.ToString('o')
        filters = @(@{ operand = 'PipelineName'; operator = 'Equals'; values = @('ingestion_ExecuteETL') })
    } | ConvertTo-Json -Depth 5 -Compress
    $page = Invoke-SeedAzure -Arguments @('rest', '--method', 'post', '--url', "$factoryUri/queryPipelineRuns?api-version=2018-06-01", '--body', $body)
    if ($page.continuationToken) { throw 'Pipeline run window requires pagination; refusing to infer completion from an incomplete result.' }
    $page.value
}

function Wait-SeedPipeline
{
    [CmdletBinding()]
    param([string]$Folder, [DateTimeOffset]$Since, [switch]$BeforeUpload, [string[]]$ExcludeRunId = @())
    while ([DateTimeOffset]::UtcNow -lt $deadline)
    {
        $runs = @(Get-SeedPipelineRun -Since $Since | Where-Object { ([string]$_.parameters.folderPath).TrimEnd('/') -ceq "ingestion/$Folder" -and $_.runId -notin $ExcludeRunId })
        if (-not $BeforeUpload -and @($runs | Where-Object { $_.status -in @('Failed', 'Cancelled') }).Count)
        {
            throw "Data Factory ingestion failed or was cancelled for '$Folder'."
        }
        $active = @($runs | Where-Object { $_.status -notin @('Succeeded', 'Failed', 'Cancelled') })
        if ($BeforeUpload -and -not $active.Count) { return }
        if (-not $BeforeUpload -and $runs.Count -and -not $active.Count)
        {
            return @($runs | ForEach-Object { @{ RunId = $_.runId; Status = $_.status } })
        }
        Start-Sleep -Seconds 15
    }
    throw "Timed out waiting for Data Factory ingestion for '$Folder'."
}

function Test-SeedTotal
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Package)
    if ($Package.dataset -eq 'Costs')
    {
        $rows = @(Get-SeedQuery -Query @"
Costs()
| where x_BillingProfileId =~ 'dto-history-v1'
| summarize Rows=count(), BilledCost=sum(BilledCost), PricingQuantity=sum(PricingQuantity),
    InvalidTags=countif(tostring(Tags['ftk-dataset']) !~ 'sample-history-v1'),
    InvalidDates=countif(isnull(ChargePeriodStart) or isnull(ChargePeriodEnd) or ChargePeriodStart < datetime(2024-06-01) or ChargePeriodEnd > datetime(2024-07-01))
"@)
        if ($rows.Count -ne 1 -or $rows[0].Rows -ne $Package.rowCount -or $rows[0].InvalidTags -ne 0 -or $rows[0].InvalidDates -ne 0)
        {
            throw 'History row count, sample labels, or original dates failed verification.'
        }
        foreach ($pair in @(@('BilledCost', 'billedCost'), @('PricingQuantity', 'pricingQuantity')))
        {
            if ($null -eq $rows[0][$pair[0]] -or -not [double]::IsFinite([double]$rows[0][$pair[0]]) -or
                [Math]::Abs($rows[0][$pair[0]] - $Package[$pair[1]]) -gt [Math]::Max(0.00000001, [Math]::Abs($Package[$pair[1]]) * 0.00000001))
            {
                throw "History scoped total '$($pair[0])' does not match the typed source package."
            }
        }
        return $rows[0]
    }
    $rows = @(Get-SeedQuery -Query @"
Prices()
| where x_BillingProfileId =~ '$($Package.profile)'
| project MeterId=x_SkuMeterId, Offer=x_SkuOfferId, Price=ListUnitPrice, ContractedPrice=ContractedUnitPrice,
    Currency=PricingCurrency, Unit=x_PricingUnitDescription, BlockSize=x_PricingBlockSize,
    Region=x_SkuRegion, EffectiveStart=x_EffectivePeriodStart
| order by MeterId asc, Offer asc
"@)
    if ($rows.Count -ne $Package.rowCount) { throw "Price row count failed for '$($Package.label)'." }
    foreach ($expected in $Package.prices)
    {
        $matched = @($rows | Where-Object { $_.MeterId -eq $expected.meterId -and $_.Offer -eq $expected.offer })
        if ($matched.Count -ne 1 -or $matched[0].Currency -ne 'USD' -or
            $matched[0].Unit -cne $expected.unit -or $null -eq $matched[0].Price -or
            -not [double]::IsFinite([double]$matched[0].Price) -or
            [Math]::Abs($matched[0].Price - $expected.listPrice) -gt 0.000000001 -or
            $null -eq $matched[0].ContractedPrice -or -not [double]::IsFinite([double]$matched[0].ContractedPrice) -or
            [Math]::Abs($matched[0].ContractedPrice - $expected.contractedPrice) -gt 0.000000001 -or
            $null -eq $matched[0].BlockSize -or $matched[0].BlockSize -ne $expected.blockSize -or
            $matched[0].Region -cne $expected.region -or
            [DateTimeOffset]$matched[0].EffectiveStart -ne [DateTimeOffset]$expected.effectiveStart)
        {
            throw "Required price, currency, or unit coverage failed for meter '$($expected.meterId)'."
        }
    }
    @{ Rows = $rows.Count; Prices = $rows }
}

function Set-SeedStaging
{
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Package)
    if (-not $PSCmdlet.ShouldProcess($Package.folder, 'Replace dedicated seed staging files, upload manifest last, and wait for ingestion')) { throw 'Seed staging was not approved.' }
    Wait-SeedPipeline -Folder $Package.folder -Since ([DateTimeOffset]::UtcNow.AddDays(-1)) -BeforeUpload
    $started = [DateTimeOffset]::UtcNow.AddSeconds(-5)
    $priorRuns = @(Get-SeedPipelineRun -Since $started.AddDays(-1) |
        Where-Object { ([string]$_.parameters.folderPath).TrimEnd('/') -ceq "ingestion/$($Package.folder)" } |
        ForEach-Object { $_.runId })
    $existing = @(Invoke-SeedAzure -Arguments (@('storage', 'blob', 'list', '--container-name', 'ingestion', '--prefix', "$($Package.folder)/") + $storageArguments))
    if ($existing.Count -gt 100) { throw 'Unexpected number of blobs in the dedicated seed partition; refusing replacement.' }
    foreach ($blob in $existing)
    {
        if (-not $blob.name.StartsWith("$($Package.folder)/", [StringComparison]::Ordinal)) { throw 'Blob is outside the exact owned seed partition.' }
        $leaf = $blob.name.Substring($Package.folder.Length + 1)
        if ($leaf -cne 'manifest.json' -and $leaf -cnotmatch $seedFilePattern)
        {
            throw 'Unexpected blob in the dedicated seed partition; refusing to delete unrecognized data.'
        }
    }
    foreach ($blob in $existing)
    {
        $null = Invoke-SeedAzure -Arguments (@('storage', 'blob', 'delete', '--container-name', 'ingestion', '--name', $blob.name) + $storageArguments)
    }
    $localDirectory = Join-Path $SeedDirectory $Package.label
    $null = Invoke-SeedAzure -Arguments (@('storage', 'blob', 'upload', '--container-name', 'ingestion', '--name', "$($Package.folder)/$($Package.file)", '--file', (Join-Path $localDirectory $Package.file), '--overwrite', 'false', '--no-progress') + $storageArguments)
    $null = Invoke-SeedAzure -Arguments (@('storage', 'blob', 'upload', '--container-name', 'ingestion', '--name', "$($Package.folder)/manifest.json", '--file', (Join-Path $localDirectory 'manifest.json'), '--overwrite', 'false', '--no-progress') + $storageArguments)
    Wait-SeedPipeline -Folder $Package.folder -Since $started -ExcludeRunId $priorRuns
}

try
{
    $metadata = Get-Content -LiteralPath (Join-Path $SeedDirectory 'seed.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    if ($metadata.version -ne 1 -or $metadata.seedVersion -cne 'sample-history-v1' -or
        ($env:GITHUB_SHA -and $metadata.sourceRevision -ne $env:GITHUB_SHA) -or $metadata.packages.Count -ne 3)
    {
        throw 'Prepared seed metadata does not match this workflow revision or seed contract.'
    }
    $expectedFolders = @{
        'history-prices' = 'Prices/2024/06/providers/microsoft.billing/billingaccounts/dto-history-v1'
        'model-prices' = 'Prices/2024/06/providers/microsoft.billing/billingaccounts/dto-retail-public-v1'
        'history-costs' = 'Costs/2024/06/providers/microsoft.billing/billingaccounts/dto-history-v1'
    }
    $labels = @($metadata.packages | ForEach-Object { $_.label })
    if (($labels -join ',') -cne 'history-prices,model-prices,history-costs') { throw 'Prices must be prepared and ingested before the unique history package.' }
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]$metadata.modelCoverage.retrievedAt
    if ($age.TotalDays -gt 7 -or $age.TotalSeconds -lt 0 -or
        (($metadata.modelCoverage.requiredMeters.Keys | Sort-Object) -join ',') -cne 'cachedInput,input,output' -or
        $metadata.packages[1].rowCount -ne 3)
    {
        throw 'Model price coverage is stale, future-dated, or incomplete.'
    }
    foreach ($package in $metadata.packages)
    {
        if ($package.folder -cne $expectedFolders[$package.label] -or $package.rowCount -le 0 -or
            $package.file -cnotmatch $seedFilePattern -or
            $package.dataset -cne $expectedFolders[$package.label].Split('/')[0] -or
            $package.profile -cne $expectedFolders[$package.label].Split('/')[-1])
        {
            throw 'Package folder, row count, or run-aware file name is invalid.'
        }
        if ($package.dataset -eq 'Prices' -and @($package.prices).Count -ne $package.rowCount)
        {
            throw 'Every prepared price row must have an explicit expected rate and unit.'
        }
        $localDirectory = Join-Path $SeedDirectory $package.label
        if ((Get-FileHash -LiteralPath (Join-Path $localDirectory $package.file) -Algorithm SHA256).Hash -ne $package.sha256) { throw 'Prepared parquet checksum does not match the seed metadata.' }
        $manifest = Get-Content -LiteralPath (Join-Path $localDirectory 'manifest.json') -Raw | ConvertFrom-Json
        if ($manifest.blobCount -ne 1 -or $manifest.dataRowCount -ne $package.rowCount -or
            @($manifest.blobs).Count -ne 1 -or $manifest.blobs[0].blobName -cne "$($package.folder)/$($package.file)")
        {
            throw 'Manifest must identify the nonempty typed package that will be uploaded.'
        }
    }
    $fingerprint = @($metadata.sourceFiles.Values) + @($metadata.schemaFiles.Values) + @((Get-FileHash -LiteralPath (Join-Path $SeedDirectory 'retail-source.json') -Algorithm SHA256).Hash)
    $report.SourceFingerprint = ($fingerprint | Sort-Object) -join '-'
    $report.SourceRevision = $metadata.sourceRevision
    if ($BaselineReport)
    {
        $baseline = Get-Content -LiteralPath $BaselineReport -Raw | ConvertFrom-Json -AsHashtable -Depth 30
        if (-not $baseline.ReadyForSeededHistory -or $baseline.SourceFingerprint -ne $report.SourceFingerprint -or $baseline.SourceRevision -ne $report.SourceRevision)
        {
            throw 'The rerun baseline must be successful and use the same source revision, schemas, history, and retail snapshot.'
        }
    }
    $foundation = & "$PSScriptRoot/Invoke-DesignTimeOptimizerFoundation.ps1" -Operation Verify -Path $Path -OutputDirectory (Join-Path $OutputDirectory 'foundation')
    $accountName = $foundation.Outputs.storageAccountName
    $clusterUri = $foundation.Outputs.clusterUri.TrimEnd('/')
    $factoryUri = "https://management.azure.com$($foundation.ResourceGroupId)/providers/Microsoft.DataFactory/factories/$($foundation.Outputs.dataFactoryName)"
    $storageArguments = @('--account-name', $accountName, '--auth-mode', 'login', '--subscription', $env:AZURE_SUBSCRIPTION_ID)
    $settingsPath = Join-Path $OutputDirectory 'hub-settings.json'
    $null = Invoke-SeedAzure -Arguments (@('storage', 'blob', 'download', '--container-name', 'config', '--name', 'settings.json', '--file', $settingsPath, '--overwrite', 'true', '--no-progress') + $storageArguments)
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($settings.retention.final.months -lt 36) { throw 'The approved 36-month final retention must be deployed before importing June 2024 history.' }
    if (-not $PSCmdlet.ShouldProcess($foundation.ResourceGroupId, 'Replace only the three prepared seed partitions and verify hub ingestion')) { throw 'Seed replacement was not approved.' }
    $report.Status = 'Ingesting'
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportPath
    foreach ($package in $metadata.packages)
    {
        $runs = @(Set-SeedStaging -Package $package -Confirm:$false)
        $snapshot = Test-SeedTotal -Package $package
        if ($baseline)
        {
            $previous = @($baseline.Packages | Where-Object { $_.Label -ceq $package.label })
            if ($previous.Count -ne 1 -or $previous[0].Snapshot.Rows -ne $snapshot.Rows) { throw 'Seed rerun changed the logical row count.' }
            if ($package.dataset -eq 'Costs')
            {
                foreach ($key in 'BilledCost', 'PricingQuantity')
                {
                    if ([Math]::Abs($previous[0].Snapshot[$key] - $snapshot[$key]) -gt 0.00000001) { throw "Seed rerun changed scoped total '$key'." }
                }
            }
        }
        $report.Packages += @{ Label = $package.label; Folder = $package.folder; PipelineRuns = $runs; Snapshot = $snapshot }
        $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportPath
    }
    $report.BaselineMatch = if ($baseline) { $true } else { $null }
    $report.ReadyForSeededHistory = $true
    $report.Status = 'VerifiedAndRetained'
}
catch
{
    $report.Status = 'Failed'
    $report.Error = $_.Exception.Message
    $report.ReadyForSeededHistory = $false
    throw
}
finally
{
    $report.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportPath
}
[pscustomobject]$report

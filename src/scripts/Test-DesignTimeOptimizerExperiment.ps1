# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Validates a FinOps design-time optimizer experiment specification.

    .DESCRIPTION
    Validates the JSON structure against the versioned experiment schema and
    applies semantic checks that JSON Schema cannot express.

    .PARAMETER Path
    Path to the experiment JSON file.

    .PARAMETER SchemaPath
    Optional. Path to the experiment JSON Schema file.

    .PARAMETER CheckReferencedFiles
    Optional. Verifies that relative files referenced by the experiment exist.

    .EXAMPLE
    ./src/scripts/Test-DesignTimeOptimizerExperiment.ps1 `
        -Path ./src/design-time-optimizer/examples/sample-api-rightsize.experiment.json

    Validates the sample experiment specification.

    .EXAMPLE
    ./src/scripts/Test-DesignTimeOptimizerExperiment.ps1 `
        -Path ./experiment.json `
        -CheckReferencedFiles

    Validates the specification and verifies that its load-test file exists.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path,

    [Parameter()]
    [string]
    $SchemaPath,

    [Parameter()]
    [switch]
    $CheckReferencedFiles
)

$resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction Stop

if (-not $SchemaPath)
{
    $SchemaPath = @(
        (Join-Path $PSScriptRoot '../design-time-optimizer/schemas/experiment.schema.json')
        (Join-Path $PSScriptRoot '../references/experiment.schema.json')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    if (-not $SchemaPath)
    {
        throw "Unable to locate the design-time optimizer experiment schema relative to '$PSScriptRoot'."
    }
}

$resolvedSchemaPath = Resolve-Path -LiteralPath $SchemaPath -ErrorAction Stop
$content = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop

try
{
    $experiment = $content | ConvertFrom-Json -Depth 100 -ErrorAction Stop
}
catch
{
    throw "Experiment file '$resolvedPath' is not valid JSON. $($_.Exception.Message)"
}

$schemaErrors = @()
$isValid = $content | Test-Json `
    -SchemaFile $resolvedSchemaPath `
    -ErrorAction SilentlyContinue `
    -ErrorVariable schemaErrors

if (-not $isValid)
{
    $details = $schemaErrors `
    | ForEach-Object { $_.Exception.Message } `
    | Where-Object { $_ } `
    | Select-Object -Unique

    $message = if ($details)
    {
        $details -join [Environment]::NewLine
    }
    else
    {
        'The file does not match the experiment schema.'
    }

    throw "Experiment file '$resolvedPath' is invalid. $message"
}

if ($experiment.variants.baseline.ref -eq $experiment.variants.candidate.ref)
{
    throw 'The baseline and candidate refs must be different.'
}

$loadMinutes = $experiment.load.warmupMinutes + $experiment.load.durationMinutes
if ($experiment.cleanup.maximumLifetimeMinutes -le $loadMinutes)
{
    throw 'cleanup.maximumLifetimeMinutes must be greater than the combined warm-up and measured load duration.'
}

if ($experiment.adapter -eq 'sample-multi-agent')
{
    $required = @('input', 'cachedInput', 'output')
    if ($experiment.load.virtualUsers -ne 1 -or $experiment.load.baselineRepetitions -ne 2 -or
        $experiment.load.warmupMinutes -ne 1 -or $experiment.load.durationMinutes -ne 10 -or
        $experiment.load.requestIntervalSeconds -ne 60 -or
        $experiment.cleanup.maximumLifetimeMinutes -ne 90 -or
        $experiment.guardrails.answerQualityPercent.minimum -ne 100 -or
        $experiment.guardrails.errorRatePercent.maximum -ne 0 -or
        $experiment.guardrails.p95LatencyRegressionPercent.maximum -ne 20 -or
        $experiment.cost.minimumImprovementPercent -ne 5 -or
        $experiment.workloadUnit.name -cne 'successful evaluated answers' -or
        $experiment.workloadUnit.quantity -ne 1000 -or
        $experiment.load.testFile -cne '../tests/evaluation/questions.json' -or
        (@($experiment.guardrails.PSObject.Properties.Name | Sort-Object) -join ',') -cne
            'answerQualityPercent,errorRatePercent,p95LatencyRegressionPercent' -or
        $experiment.cost.currency -cne 'USD' -or $experiment.cost.pricingSource -cne 'finops-hub' -or
        (@($experiment.cost.requiredMeters | Sort-Object) -join ',') -cne (($required | Sort-Object) -join ',') -or
        $experiment.scope.subscriptionId -cne '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a' -or
        $experiment.scope.resourceGroupPrefix -cne 'ftk-dto-hack-s-ae46' -or $experiment.scope.region -cne 'eastus2')
    {
        throw 'The sample adapter must preserve the approved scope, load bounds, pricing basis, and guardrails.'
    }
}

if ($CheckReferencedFiles)
{
    $experimentDirectory = Split-Path -Parent $resolvedPath
    $testFile = $experiment.load.testFile
    $testFilePath = if ([IO.Path]::IsPathRooted($testFile))
    {
        $testFile
    }
    else
    {
        Join-Path $experimentDirectory $testFile
    }

    if (-not (Test-Path -LiteralPath $testFilePath -PathType Leaf))
    {
        throw "The load-test file '$testFile' does not exist relative to '$experimentDirectory'."
    }
}

[pscustomobject]@{
    PSTypeName = 'FinOpsToolkit.DesignTimeOptimizer.ExperimentValidation'
    Path = $resolvedPath.Path
    SchemaPath = $resolvedSchemaPath.Path
    Version = $experiment.version
    Name = $experiment.name
    BaselineRef = $experiment.variants.baseline.ref
    CandidateRef = $experiment.variants.candidate.ref
    WorkloadUnit = $experiment.workloadUnit.name
    WorkloadQuantity = $experiment.workloadUnit.quantity
    Valid = $true
}

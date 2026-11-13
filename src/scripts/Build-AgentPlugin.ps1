# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]
    $DestDir
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$skillsDir = Join-Path $DestDir 'skills'

function Remove-PluginBundle([string]$Path)
{
    if (-not (Test-Path -LiteralPath $Path))
    {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    else
    {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
}

if (-not (Test-Path $skillsDir))
{
    return
}

$finopsSkill = Join-Path $skillsDir 'finops-toolkit'
if (Test-Path $finopsSkill)
{
    $queryDest = Join-Path $finopsSkill 'references/queries'
    Remove-PluginBundle $queryDest
    Copy-Item (Join-Path $repoRoot 'src/queries') -Destination $queryDest -Recurse -Force

    $docsDest = Join-Path $finopsSkill 'references/docs-mslearn'
    Remove-PluginBundle $docsDest
    $docsSource = Join-Path $repoRoot 'docs-mslearn'
    Get-ChildItem $docsSource -File -Recurse -Filter '*.md' | ForEach-Object {
        $relativePath = $_.FullName.Substring($docsSource.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $destination = Join-Path $docsDest $relativePath
        New-Item (Split-Path $destination) -ItemType Directory -Force | Out-Null
        Copy-Item $_ -Destination $destination -Force
    }
}

$optimizerSkill = Join-Path $skillsDir 'design-time-optimizer'
if (Test-Path $optimizerSkill)
{
    $optimizerReferences = Join-Path $optimizerSkill 'references'
    Remove-PluginBundle $optimizerReferences
    New-Item $optimizerReferences -ItemType Directory -Force | Out-Null

    Copy-Item `
        (Join-Path $repoRoot 'src/design-time-optimizer/schemas/experiment.schema.json') `
        -Destination (Join-Path $optimizerReferences 'experiment.schema.json') `
        -Force

    Copy-Item `
        (Join-Path $repoRoot 'src/design-time-optimizer/examples/sample-api-rightsize.experiment.json') `
        -Destination (Join-Path $optimizerReferences 'sample-api-rightsize.experiment.json') `
        -Force

    Copy-Item `
        (Join-Path $repoRoot 'hack/sample-multi-agent-workload/experiments/optimizer.md') `
        -Destination (Join-Path $optimizerReferences 'sample-optimization.md') `
        -Force

    $optimizerScripts = Join-Path $optimizerSkill 'scripts'
    Remove-PluginBundle $optimizerScripts
    New-Item $optimizerScripts -ItemType Directory -Force | Out-Null

    Copy-Item `
        (Join-Path $repoRoot 'src/scripts/Test-DesignTimeOptimizerExperiment.ps1') `
        -Destination $optimizerScripts `
        -Force

    Copy-Item `
        (Join-Path $repoRoot 'src/scripts/Get-DesignTimeOptimizerContext.ps1') `
        -Destination $optimizerScripts `
        -Force

    Copy-Item `
        (Join-Path $repoRoot 'src/design-time-optimizer/context') `
        -Destination (Join-Path $optimizerReferences 'context') `
        -Recurse -Force
}

Get-ChildItem $DestDir -Force -Recurse -Filter '.DS_Store' | Remove-Item -Force

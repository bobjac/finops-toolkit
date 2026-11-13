# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Runs one existing deployment entry point with the current run's structured evidence.
    .PARAMETER Stage
    Foundation build/deploy, data-plane verification, seed passes, sample stages, or workbook.
    .PARAMETER EvidenceDirectory
    Cumulative nonsecret checkpoints downloaded from the exact successful predecessor.
    .PARAMETER Confirmation
    Enter deploy-retained-hack-sandbox.
    .EXAMPLE
    ./hack/deployment/Invoke-HackDeploymentStage.ps1 -Stage SeedFirst -EvidenceDirectory .tmp/hack -Confirmation deploy-retained-hack-sandbox
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Foundation', 'Verify', 'SeedFirst', 'SeedSecond',
        'Infrastructure', 'Image', 'Application', 'Validation', 'Workbook')][string]$Stage,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][string]$Confirmation
)
. "$PSScriptRoot/Deployment-Common.ps1"
Assert-HackDeploymentInput $Confirmation
Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force
$seed = "$EvidenceDirectory/seed"
$sample = "$EvidenceDirectory/sample"
switch ($Stage) {
    Foundation {
        foreach ($pass in 'first', 'second') {
            $arguments = @("$root/src/design-time-optimizer/seed/prepare.py", '--output', "$seed/seed-$pass",
                '--source-revision', $env:GITHUB_SHA)
            if ($pass -eq 'second') { $arguments += @('--retail-snapshot', "$seed/seed-first/retail-source.json") }
            & python3 @arguments
            if ($LASTEXITCODE -ne 0) { throw "Seed preparation failed for pass '$pass'." }
        }
        Assert-HackSeedPrice (Get-Content "$seed/seed-first/seed.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40)
        & "$root/src/scripts/Build-Toolkit.ps1" -Template finops-hub
        & bicep build "$root/release/finops-hub/main.bicep" --outfile "$root/release/finops-hub/azuredeploy.json"
        if ($LASTEXITCODE -ne 0) { throw 'Canonical hub compilation failed.' }
        & bicep build "$root/hack/foundation.bicep" --outfile "$root/release/hack-foundation.json"
        if ($LASTEXITCODE -ne 0 -or (Get-Content "$root/release/hack-foundation.json" -Raw).Contains('$$ftkver$$')) {
            throw 'Foundation compilation or version expansion failed.'
        }
        & "$root/src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1" -Operation Deploy `
            -ConfirmResourceGroup ftk-dto-hack-foundation -OutputDirectory "$EvidenceDirectory/foundation/deployment" `
            -DeploymentPasses 1 -DeferDataPlaneVerification -Confirm:$false
    }
    Verify {
        & "$root/src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1" -Operation Verify `
            -OutputDirectory "$EvidenceDirectory/foundation/verification"
    }
    { $_ -in 'SeedFirst', 'SeedSecond' } {
        $pass = if ($Stage -eq 'SeedFirst') { 'first' } else { 'second' }
        $arguments = @{
            SeedDirectory = "$seed/seed-$pass"; OutputDirectory = "$seed/seed-evidence-$pass"
            ConfirmResourceGroup = 'ftk-dto-hack-foundation'; Confirm = $false
        }
        if ($Stage -eq 'SeedSecond') { $arguments.BaselineReport = "$seed/seed-evidence-first/seed-report.json" }
        & "$root/src/scripts/Import-DesignTimeOptimizerSeed.ps1" @arguments
    }
    Workbook {
        & "$root/src/scripts/Publish-DesignTimeOptimizerWorkbook.ps1" -SeedDirectory $seed -SampleDirectory $sample `
            -Operation Deploy -ConfirmResourceGroup ftk-dto-hack-s-ae46 `
            -OutputDirectory "$EvidenceDirectory/workbook" -Confirm:$false
    }
    default {
        $arguments = @{
            Stage = $Stage; Revision = $env:GITHUB_SHA; DeployerObjectId = $env:SAMPLE_DEPLOYER_OBJECT_ID
            ConfirmResourceGroup = 'ftk-dto-hack-s-ae46'; OutputDirectory = $sample
        }
        if ($Stage -ne 'Infrastructure') {
            $previous = @{ Image = 'infrastructure'; Application = 'image'; Validation = 'application' }[$Stage]
            $arguments.CheckpointPath = "$sample/deployment-$previous.json"
        }
        & "$root/hack/sample-multi-agent-workload/eng/Deploy-Sample.ps1" @arguments
    }
}

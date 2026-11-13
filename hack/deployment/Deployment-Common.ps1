# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. "$PSScriptRoot/../sample-multi-agent-workload/eng/Sample-Common.ps1"

function Assert-HackDeploymentInput {
    param([Parameter(Mandatory)][string]$Confirmation)
    if ($Confirmation -cne 'deploy-retained-hack-sandbox' -or
        $env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'bobjac/finops-toolkit' -or
        $env:GITHUB_REF -cne 'refs/heads/dev' -or $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
        $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{1,12}$' -or $env:GITHUB_RUN_ATTEMPT -cnotmatch '^[1-9][0-9]*$') {
        throw 'Use the confirmed protected fork dev sandbox deployment.'
    }
    $principal = [Guid]::Empty
    if (-not [Guid]::TryParse($env:SAMPLE_DEPLOYER_OBJECT_ID, [ref]$principal) -or $principal -eq [Guid]::Empty) {
        throw 'The sandbox deployment principal object ID is missing or invalid.'
    }
    $null = Assert-SamplePrice $env:SAMPLE_PRICE_EVIDENCE
    $config = Get-Content "$PSScriptRoot/../sandbox.config.json" -Raw | ConvertFrom-Json
    if ([DateTimeOffset]$config.expiresOn -le [DateTimeOffset]::UtcNow) { throw 'The sandbox has expired.' }
}

function Assert-HackSeedPrice {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Metadata,
        [string]$PriceJson = $env:SAMPLE_PRICE_EVIDENCE
    )
    $prices = Assert-SamplePrice $PriceJson
    $coverage = $Metadata.modelCoverage
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]$coverage.retrievedAt
    if ($Metadata.sourceRevision -cne $env:GITHUB_SHA -or $Metadata.seedVersion -cne 'sample-history-v1' -or
        $coverage.model -cne $prices.model -or $coverage.region -cne $prices.region -or
        $coverage.deploymentSku -cne $prices.deploymentSku -or $coverage.currency -cne $prices.currency -or
        $age.TotalSeconds -lt 0 -or $age.TotalDays -gt 7) {
        throw 'Fresh seed price provenance does not match the selected sample deployment.'
    }
    foreach ($pair in @(@('input', 'inputPerMillion'), @('cachedInput', 'cachedInputPerMillion'), @('output', 'outputPerMillion'))) {
        if ($null -eq $coverage.requiredMeters[$pair[0]].usdPerMillionTokens -or
            $coverage.requiredMeters[$pair[0]].usdPerMillionTokens -ne $prices.($pair[1])) {
            throw "Sample price evidence differs from the authoritative seed meter '$($pair[0])'."
        }
    }
}

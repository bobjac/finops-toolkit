# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Publishes readiness only when every deployment stage and its scoped evidence succeed.
    .PARAMETER EvidenceDirectory
    Cumulative evidence from the exact workbook predecessor artifact.
    .PARAMETER StageResultsJson
    GitHub needs results for all nine protected deployment jobs.
    .EXAMPLE
    ./hack/deployment/Complete-HackDeployment.ps1 -EvidenceDirectory .tmp/hack -StageResultsJson $env:HACK_STAGE_RESULTS
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][string]$StageResultsJson
)
. "$PSScriptRoot/Deployment-Common.ps1"
$null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force
$report = [ordered]@{
    ready = $false; status = 'Incomplete'; revision = $env:GITHUB_SHA
    runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT
    failures = @(); stages = @{}
    limitations = @('Retained scope; clean rebuild rehearsal remains in issue #14',
        'Public retail estimates are not billed costs or measured savings',
        'Retained resources incur charges; tags, budgets, and queued approvals are not shutdown',
        'No retained resource group is automatically deleted on failure')
}
try {
    if ($env:GITHUB_REPOSITORY -cne 'bobjac/finops-toolkit' -or $env:GITHUB_REF -cne 'refs/heads/dev' -or
        $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{1,12}$' -or
        $env:GITHUB_RUN_ATTEMPT -cnotmatch '^[1-9][0-9]*$') { throw 'Readiness requires a valid fork dev run identity.' }
    $results = $StageResultsJson | ConvertFrom-Json -AsHashtable
    foreach ($stage in 'foundation', 'verify', 'seed_first', 'seed_second', 'infrastructure', 'image', 'application', 'validation', 'workbook') {
        $report.stages[$stage] = $results[$stage].result
        if ($results[$stage].result -cne 'success') { throw "Deployment stage '$stage' did not succeed." }
    }
    $foundation = Get-Content "$EvidenceDirectory/foundation/verification/foundation.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $first = Get-Content "$EvidenceDirectory/seed/seed-evidence-first/seed-report.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $second = Get-Content "$EvidenceDirectory/seed/seed-evidence-second/seed-report.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $metadata = Get-Content "$EvidenceDirectory/seed/seed-second/seed.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    $workbook = Get-Content "$EvidenceDirectory/workbook/workbook-report.json" -Raw | ConvertFrom-Json -AsHashtable -Depth 40
    foreach ($evidence in @($foundation, $first, $second, $workbook)) {
        if ($evidence.SourceRevision -cne $env:GITHUB_SHA -or $evidence.RunId -cne $env:GITHUB_RUN_ID) {
            throw 'Readiness evidence belongs to another source revision or workflow run.'
        }
    }
    if ($foundation.Status -cne 'VerifiedAndRetained' -or $foundation.ReadyForDataIngestion -ne $true -or
        $first.Status -cne 'VerifiedAndRetained' -or $first.ReadyForSeededHistory -ne $true -or
        $second.Status -cne 'VerifiedAndRetained' -or $second.ReadyForSeededHistory -ne $true -or
        $second.BaselineMatch -ne $true -or -not $first.SourceFingerprint -or $first.SourceFingerprint -cne $second.SourceFingerprint -or
        $workbook.Status -cne 'VerifiedAndRetained' -or $workbook.ReadyForWorkbook -ne $true -or
        $workbook.SampleRevision -cne $env:GITHUB_SHA -or $workbook.SeedRevision -cne $env:GITHUB_SHA -or
        $workbook.SampleRunId -cne $env:GITHUB_RUN_ID -or $workbook.SeedRunId -cne $env:GITHUB_RUN_ID) {
        throw 'Foundation, seed replacement, or workbook verification is incomplete.'
    }
    $sample = $null
    foreach ($stage in 'Infrastructure', 'Image', 'Application', 'Validation') {
        $checkpoint = Get-Content "$EvidenceDirectory/sample/deployment-$($stage.ToLowerInvariant()).json" -Raw | ConvertFrom-Json -AsHashtable -Depth 30
        Assert-SampleCheckpoint -Checkpoint $checkpoint -Revision $env:GITHUB_SHA -RunId $env:GITHUB_RUN_ID `
            -PreviousStage $stage -Scope '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
        if ($checkpoint.runAttempt -cnotmatch '^[1-9][0-9]*$' -or [int]$checkpoint.runAttempt -gt [int]$env:GITHUB_RUN_ATTEMPT) {
            throw 'Sample checkpoint attempt is invalid.'
        }
        $sample = $checkpoint
    }
    if ($sample.liveVerified -ne $true -or [DateTimeOffset]$sample.expiresOn -le [DateTimeOffset]::UtcNow) {
        throw 'Sample live validation is incomplete or expired.'
    }
    Assert-HackSeedPrice -Metadata $metadata -PriceJson ($sample.prices | ConvertTo-Json -Depth 15)
    $foundationId = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-foundation'
    $workbookId = $workbook.DeploymentOutputs.workbookId.value
    if ($foundation.ResourceGroupId -ine $foundationId -or
        $workbookId -ine '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46/providers/Microsoft.Insights/workbooks/478410d0-a0ae-5679-89fe-eea6a576654c' -or
        $workbook.WorkbookRevision -cne $env:GITHUB_SHA -or
        $workbook.DeploymentOutputs.workbookUrl.value -cne "https://portal.azure.com/#@/resource$workbookId/workbook") {
        throw 'Readiness links or ownership are outside the verified sandbox.'
    }
    $report.links = @{
        application = "https://$($sample.outputs.fqdn.value)"
        workbook = $workbook.DeploymentOutputs.workbookUrl.value
        workflow = "https://github.com/bobjac/finops-toolkit/actions/runs/$($env:GITHUB_RUN_ID)"
    }
    $report.sources = @{ foundation = $foundation.SourceRevision; sample = $sample.revision
        seed = $metadata.sourceRevision; workbook = $workbook.SourceRevision; sampleAttempt = $sample.runAttempt }
    $report.seed = @{ version = $metadata.seedVersion; modelCoverage = $metadata.modelCoverage
        sourceFingerprint = $second.SourceFingerprint; packages = $second.Packages; replacementVerified = $second.BaselineMatch }
    $report.ownership = @{ repository = 'bobjac/finops-toolkit'; foundation = $foundationId
        sample = $sample.resourceGroup; expiresOn = $sample.expiresOn; foundationResources = $foundation.Resources
        sharedEndpointsExcluded = $true }
    $report.ready = $true
    $report.status = 'VerifiedAndRetained'
}
catch {
    $report.status = 'Failed'
    $report.failures += $_.Exception.Message
    throw
}
finally {
    $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 50 | Set-Content "$EvidenceDirectory/readiness.json"
    $lines = @('# Hack sandbox readiness', "Ready: $($report.ready); status: $($report.status)",
        "Revision: $($report.revision); run: $($report.runId); attempt: $($report.runAttempt)")
    if ($report.ready) {
        $lines += @("Application: $($report.links.application)", "Workbook: $($report.links.workbook)")
    }
    $lines += $report.limitations
    $lines += $report.failures
    $lines | Set-Content "$EvidenceDirectory/readiness.md"
    if ($env:GITHUB_STEP_SUMMARY) { $lines >> $env:GITHUB_STEP_SUMMARY }
}

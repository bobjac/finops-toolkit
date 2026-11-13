# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Exercises expiration and full teardown using explicitly approved cleanup fixtures.
    .DESCRIPTION
    Creates two zero-minimum-replica apps without ingress or model traffic, and an isolated
    resource group containing one managed identity. Always attempts exact fixture cleanup.
    Does not remove, retag, or redeploy the retained demo or foundation.
    .PARAMETER Confirmation
    Enter validate-owned-cleanup-fixtures.
    .PARAMETER OutputDirectory
    Nonsecret validation evidence directory.
    .EXAMPLE
    ./hack/cleanup/Test-HackCleanupLive.ps1 -Confirmation validate-owned-cleanup-fixtures -OutputDirectory .tmp/cleanup-live
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateSet('validate-owned-cleanup-fixtures')][string]$Confirmation,
    [Parameter(Mandatory)][string]$OutputDirectory
)
. "$PSScriptRoot/Cleanup-Common.ps1"
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force -WhatIf:$false
$run = $env:GITHUB_RUN_ID
$revision = $env:GITHUB_SHA
$groupName = Get-HackCleanupGroup Validation
$sampleGroup = Get-HackCleanupGroup Sample
$sampleId = "/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/$sampleGroup"
$report = [ordered]@{ verified = $false; runId = $run; revision = $revision; group = $groupName; confirmation = $Confirmation
    fixtureOnly = $true; retainedTeardownTested = $false; stages = @(); failures = @() }
$attemptedGroup = $false
$attemptedApps = $false
try {
    if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'bobjac/finops-toolkit' -or
        $env:GITHUB_REF -cne 'refs/heads/dev' -or $run -cnotmatch '^[0-9]{1,12}$' -or $revision -cnotmatch '^[a-f0-9]{40}$') {
        throw 'Live fixtures require the protected fork dev workflow and exact revision.'
    }
    Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
    Assert-HackCleanupGroup -Group (Invoke-SampleAz @('group', 'show', '--name', $sampleGroup)) -Component Sample
    if (Invoke-SampleAz @('group', 'exists', '--name', $groupName) -ExpectedType Boolean) {
        throw 'The validation group already exists; inspect and recover it explicitly before creating new fixtures.'
    }
    $retained = Invoke-SampleAz @('containerapp', 'show', '--name', 'ca-ftk-dto-hack-s-ae46', '--resource-group', $sampleGroup)
    $image = $retained.properties.template.containers[0].image
    if ($image -cnotmatch '^crftkdtohacksae46\.azurecr\.io/sample:[a-f0-9]{40}$') { throw 'The retained image is not the approved sample source.' }
    $report.retainedImageBefore = $image
    if (-not $PSCmdlet.ShouldProcess($groupName, 'Create isolated cleanup fixtures and delete only those fixtures')) {
        throw 'Fixture validation was not approved.'
    }
    $tags = @('repository=bobjac/finops-toolkit', 'ftk-tool=design-time-optimizer-cleanup-validation',
        "fixture-run-id=$run", "revision=$revision")
    $attemptedGroup = $true
    Invoke-SampleAz (@('group', 'create', '--name', $groupName, '--location', 'eastus2', '--tags') + $tags) | Out-Null
    Invoke-SampleAz (@('identity', 'create', '--name', 'id-dto-cleanup-validation', '--resource-group', $groupName, '--tags') + $tags) | Out-Null
    $report.stages += 'Isolated identity fixture created'
    foreach ($variant in 'baseline', 'candidate') {
        $name = Get-ExperimentAppName -RunId $run -Variant $variant
        $expires = if ($variant -eq 'baseline') { [DateTimeOffset]::UtcNow.AddMinutes(-1) } else { [DateTimeOffset]::UtcNow.AddMinutes(90) }
        $appTags = @('repository=bobjac/finops-toolkit', 'ftk-tool=design-time-optimizer-experiment',
            "experiment-run-id=$run", "experiment-id=h09-$run", "variant=$variant",
            "revision=$revision", "expires-on=$($expires.ToString('o'))")
        $attemptedApps = $true
        Invoke-SampleAz (@('containerapp', 'create', '--name', $name, '--resource-group', $sampleGroup,
                '--environment', "$sampleId/providers/Microsoft.App/managedEnvironments/cae-ftk-dto-hack-s-ae46",
                '--image', $image, '--user-assigned', "$sampleId/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ftk-dto-hack-s-ae46",
                '--registry-server', 'crftkdtohacksae46.azurecr.io',
                '--registry-identity', "$sampleId/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ftk-dto-hack-s-ae46",
                '--cpu', '0.25', '--memory', '0.5Gi', '--min-replicas', '0', '--max-replicas', '1',
                '--env-vars', 'SAMPLE_MODEL_MODE=deterministic', 'SAMPLE_DATABASE=/app/data/retail.db', "SAMPLE_REVISION=$revision",
                '--tags') + $appTags) | Out-Null
    }
    & "$PSScriptRoot/Invoke-HackCleanup.ps1" -Operation Expired -ExperimentRunId $run -OutputDirectory "$OutputDirectory/expiration" -Confirm:$false
    $apps = @(Invoke-SampleAz @('containerapp', 'list', '--resource-group', $sampleGroup) -ExpectedType Array)
    $baseline = Get-ExperimentAppName -RunId $run -Variant baseline
    $candidate = Get-ExperimentAppName -RunId $run -Variant candidate
    if ($baseline -cin $apps.name -or $candidate -cnotin $apps.name) {
        throw 'Expiration must remove the expired fixture and preserve the fresh fixture.'
    }
    $report.stages += 'Expired fixture removed; fresh fixture preserved'
    Invoke-SampleAz @('tag', 'update', '--resource-id', "$sampleId/providers/Microsoft.App/containerApps/$candidate",
        '--operation', 'Merge', '--tags', "expires-on=$([DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o'))") | Out-Null
    & "$PSScriptRoot/Invoke-HackCleanup.ps1" -Operation Expired -ExperimentRunId $run -OutputDirectory "$OutputDirectory/recovery" -Confirm:$false
    $report.stages += 'Simulated interrupted-run orphan recovered; not an actual workflow cancellation'
    & "$PSScriptRoot/Invoke-HackCleanup.ps1" -Operation Teardown -Component Validation `
        -Confirmation $groupName -OutputDirectory "$OutputDirectory/teardown" -Confirm:$false
    $after = Invoke-SampleAz @('containerapp', 'show', '--name', 'ca-ftk-dto-hack-s-ae46', '--resource-group', $sampleGroup)
    $report.retainedImageAfter = $after.properties.template.containers[0].image
    if ($report.retainedImageAfter -cne $image) { throw 'The retained demo image changed during validation.' }
    $report.stages += 'Full isolated group teardown verified; retained image unchanged'
    $report.verified = $true
}
catch {
    $report.failures += $_.Exception.Message
    throw
}
finally {
    if ($attemptedApps) {
        try {
            & "$PSScriptRoot/../sample-multi-agent-workload/eng/Remove-Experiment.ps1" `
                -RunId $run -OutputDirectory "$OutputDirectory/final-app-cleanup" -Confirm:$false
        }
        catch { $report.failures += $_.Exception.Message; $report.verified = $false; Write-Warning 'Fixture app cleanup failed; retry exact experiment cleanup.' }
    }
    if ($attemptedGroup) {
        try {
            $exists = Invoke-SampleAz @('group', 'exists', '--name', $groupName) -ExpectedType Boolean
            if ($exists) {
                $group = Invoke-SampleAz @('group', 'show', '--name', $groupName)
                Assert-HackCleanupGroup -Group $group -Component Validation
                if ($group.tags.'fixture-run-id' -cne $run) { throw 'Refusing to clean a different fixture run.' }
                & "$PSScriptRoot/Invoke-HackCleanup.ps1" -Operation Teardown -Component Validation `
                    -Confirmation $groupName -OutputDirectory "$OutputDirectory/final-group-cleanup" -Confirm:$false
            }
        }
        catch { $report.failures += $_.Exception.Message; $report.verified = $false; Write-Warning 'Fixture group cleanup failed; retry confirmed validation group teardown.' }
    }
    $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 20 | Set-Content "$OutputDirectory/validation.json" -WhatIf:$false
    if ($report.failures.Count) { throw 'Cleanup fixture validation failed; inspect validation.json and cleanup receipts.' }
}

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Plans owned cleanup, removes expired experiment apps, or tears down one confirmed group.
    .PARAMETER Operation
    Plan is read-only. Expired never removes retained resources. Teardown requires exact confirmation.
    .PARAMETER Component
    Experiments, Sample, Foundation, or the isolated Validation fixture.
    .PARAMETER Confirmation
    Exact group name for Teardown.
    .PARAMETER OutputDirectory
    Nonsecret evidence outside Azure resources being removed.
    .PARAMETER ExperimentRunId
    Optional exact experiment run filter, used to isolate live validation fixtures.
    .EXAMPLE
    ./hack/cleanup/Invoke-HackCleanup.ps1 -Operation Plan -Component Sample -OutputDirectory .tmp/cleanup
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Plan', 'Expired', 'Teardown')][string]$Operation = 'Plan',
    [ValidateSet('Experiments', 'Sample', 'Foundation', 'Validation')][string]$Component = 'Experiments',
    [string]$Confirmation,
    [ValidatePattern('^[0-9]{1,12}$')][string]$ExperimentRunId,
    [Parameter(Mandatory)][string]$OutputDirectory
)
. "$PSScriptRoot/Cleanup-Common.ps1"
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force -WhatIf:$false
$report = [ordered]@{
    operation = $Operation; component = $Component; verified = $false; status = 'Started'
    runId = $env:GITHUB_RUN_ID; revision = $env:GITHUB_SHA
    targets = @(); removed = @(); skipped = @(); failures = @()
    exclusions = @('External/shared model endpoints', 'Evidence artifacts outside the selected group',
        'Soft-deleted recovery state is not purged', 'Retained resources are never expiration targets')
}
try {
    if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'bobjac/finops-toolkit' -or
        $env:GITHUB_REF -cne 'refs/heads/dev') { throw 'Use the protected fork dev cleanup workflow.' }
    if (($Operation -eq 'Expired' -and $Component -ne 'Experiments') -or
        ($Operation -eq 'Teardown' -and ($Component -eq 'Experiments' -or
            $Confirmation -cne (Get-HackCleanupGroup $Component)))) {
        throw 'Teardown requires an exact allowlisted group confirmation; expiration only targets experiment apps.'
    }
    Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
    $groupName = if ($Component -eq 'Experiments') { Get-HackCleanupGroup Sample } else { Get-HackCleanupGroup $Component }
    if (-not (Invoke-SampleAz @('group', 'exists', '--name', $groupName) -ExpectedType Boolean)) {
        $report.status = 'AlreadyAbsent'
        $report.verified = $true
    }
    else {
        $group = Invoke-SampleAz @('group', 'show', '--name', $groupName)
        $groupComponent = if ($Component -eq 'Experiments') { 'Sample' } else { $Component }
        Assert-HackCleanupGroup -Group $group -Component $groupComponent
        if ($Component -eq 'Experiments') {
            $apps = @(Invoke-SampleAz @('containerapp', 'list', '--resource-group', $groupName) -ExpectedType Array)
            foreach ($app in $apps) {
                if ($app.name -cnotmatch '^ca-dto-x-([0-9]{1,12})-[bc]$') {
                    $report.skipped += $app.id
                    continue
                }
                $run = $Matches[1]
                if ($ExperimentRunId -and $run -cne $ExperimentRunId) {
                    $report.skipped += $app.id
                    continue
                }
                try {
                    Assert-ExperimentApp -App $app -RunId $run -Name $app.name
                    $expiry = Get-HackExpiration $app.tags.'expires-on'
                    if ($expiry -gt [DateTimeOffset]::UtcNow) { $report.skipped += $app.id; continue }
                    $report.targets += $app.id
                    $report | ConvertTo-Json -Depth 20 | Set-Content "$OutputDirectory/cleanup.json" -WhatIf:$false
                    if ($Operation -eq 'Plan') { continue }
                    # Re-read ownership and expiry immediately before the destructive call.
                    $current = Invoke-SampleAz @('containerapp', 'show', '--name', $app.name, '--resource-group', $groupName)
                    Assert-ExperimentApp -App $current -RunId $run -Name $app.name
                    if ((Get-HackExpiration $current.tags.'expires-on') -ne $expiry) { throw 'Expiration changed during cleanup; retry with a new plan.' }
                    if (-not $PSCmdlet.ShouldProcess($app.id, 'Delete this expired owned experiment app')) { throw 'Cleanup was not approved.' }
                    Invoke-SampleAz @('containerapp', 'delete', '--name', $app.name, '--resource-group', $groupName, '--yes') | Out-Null
                    if (@(Invoke-SampleAz @('containerapp', 'list', '--resource-group', $groupName) -ExpectedType Array |
                            Where-Object { $_.name -ceq $app.name }).Count) { throw 'The deleted app is still present.' }
                    $report.removed += $app.id
                }
                catch {
                    $report.failures += @{ resourceId = $app.id; reason = $_.Exception.Message }
                    Write-Warning "Expired app cleanup failed for '$($app.id)': $($_.Exception.Message) Retry the protected cleanup workflow."
                }
            }
            if ($report.failures.Count) { throw 'Expired experiment cleanup is incomplete; inspect the receipt and retry.' }
        }
        else {
            $resources = @(Invoke-SampleAz @('resource', 'list', '--resource-group', $groupName) -ExpectedType Array)
            $report.targets = @($group.id) + @($resources.id)
            $report | ConvertTo-Json -Depth 20 | Set-Content "$OutputDirectory/cleanup.json" -WhatIf:$false
            $config = Get-Content "$PSScriptRoot/../sandbox.config.json" -Raw | ConvertFrom-Json
            Assert-HackTeardownInventory -Group $group -Component $Component -Resources $resources -OwnsModel:($config.model.ownership -ceq 'sandbox')
            if ($Operation -eq 'Teardown') {
                if (-not $PSCmdlet.ShouldProcess($group.id, 'Delete the confirmed group and its verified owned resources')) { throw 'Teardown was not approved.' }
                $currentGroup = Invoke-SampleAz @('group', 'show', '--name', $groupName)
                Assert-HackCleanupGroup -Group $currentGroup -Component $Component
                $current = @(Invoke-SampleAz @('resource', 'list', '--resource-group', $groupName) -ExpectedType Array)
                Assert-HackTeardownInventory -Group $currentGroup -Component $Component -Resources $current -OwnsModel:($config.model.ownership -ceq 'sandbox')
                if ((@($resources.id | Sort-Object) -join "`n") -cne (@($current.id | Sort-Object) -join "`n")) {
                    throw 'Group inventory changed during teardown; retry with a new plan.'
                }
                Invoke-SampleAz @('group', 'delete', '--name', $groupName, '--yes', '--no-wait') | Out-Null
                $absent = $false
                for ($attempt = 0; $attempt -lt 60; $attempt++) {
                    if (-not (Invoke-SampleAz @('group', 'exists', '--name', $groupName) -ExpectedType Boolean)) { $absent = $true; break }
                    Start-Sleep -Seconds 30
                }
                if (-not $absent) { throw 'Group deletion remains incomplete after 30 minutes; retry and inspect Azure.' }
                $report.removed = $report.targets
            }
        }
        $report.status = if ($Operation -eq 'Plan') { 'Planned' } else { 'Completed' }
        $report.verified = $Operation -ne 'Plan'
    }
}
catch {
    $report.status = 'Failed'
    $report.failures += @{ reason = $_.Exception.Message }
    throw
}
finally {
    $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 20 | Set-Content "$OutputDirectory/cleanup.json" -WhatIf:$false
    @(
        '# Hack cleanup'
        "Operation: $Operation; component: $Component; status: $($report.status); verified: $($report.verified)"
        "Removed resources: $($report.removed.Count); failures: $($report.failures.Count). Inspect cleanup.json for exact IDs."
        'Scheduled runs require sandbox approval. Tags, budgets, and queued approvals do not stop resources.'
        'Retained demo teardown is manual. Shared endpoints are excluded; soft-deleted recovery state is not purged.'
    ) | Set-Content "$OutputDirectory/cleanup.md" -WhatIf:$false
}

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Removes only the two temporary apps owned by an exact experiment run.
    .PARAMETER RunId
    Original GitHub experiment workflow run ID.
    .PARAMETER OutputDirectory
    Nonsecret cleanup evidence directory.
    .EXAMPLE
    ./eng/Remove-Experiment.ps1 -RunId 123 -OutputDirectory .tmp/experiment -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9]{1,12}$')][string]$RunId,
    [Parameter(Mandatory)][string]$OutputDirectory
)
. "$PSScriptRoot/Experiment-Common.ps1"
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -cne 'bobjac/finops-toolkit' -or $env:GITHUB_REF -cne 'refs/heads/dev') {
    throw 'Use the approved fork dev experiment workflow and sandbox environment.'
}
Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
$group = 'ftk-dto-hack-s-ae46'
Assert-SampleOwnership (Invoke-SampleAz @('group', 'show', '--name', $group))
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$report = @{ verified = $false; runId = $RunId; removed = @(); failures = @(); excluded = @('Retained sample app and shared environment, identity, registry, model, Key Vault, and telemetry', 'Build image digests and deployment records retained as provenance artifacts') }
if (Test-Path -LiteralPath "$OutputDirectory/cleanup.json") {
    $previous = Get-Content "$OutputDirectory/cleanup.json" -Raw | ConvertFrom-Json
    if ($previous.runId -cne $RunId) { throw 'Cleanup evidence belongs to a different experiment.' }
    $report.removed = @($previous.removed)
}
try {
    foreach ($variant in 'baseline', 'candidate') {
        $name = Get-ExperimentAppName -RunId $RunId -Variant $variant
        $apps = @(Invoke-SampleAz @('containerapp', 'list', '--resource-group', $group))
        $ownedApps = @($apps | Where-Object { $_.name -ceq $name })
        if ($ownedApps.Count -eq 0) { continue }
        try {
            Assert-ExperimentApp -App $ownedApps[0] -RunId $RunId -Name $name
            if (-not $PSCmdlet.ShouldProcess($ownedApps[0].id, 'Delete only this owned temporary experiment app')) { throw 'Experiment cleanup was not approved.' }
            Invoke-SampleAz @('containerapp', 'delete', '--name', $name, '--resource-group', $group, '--yes') | Out-Null
            $remaining = @(Invoke-SampleAz @('containerapp', 'list', '--resource-group', $group) | Where-Object { $_.name -ceq $name })
            if ($remaining.Count) { throw 'The deleted temporary app is still present.' }
            $report.removed += $ownedApps[0].id
        }
        catch {
            $report.failures += $name
            Write-Warning "Cleanup failed for temporary app '$name'; retry this exact experiment cleanup."
        }
    }
    if ($report.failures.Count) { throw 'Temporary experiment app cleanup is incomplete.' }
    $report.verified = $true
}
finally {
    $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 10 | Set-Content "$OutputDirectory/cleanup.json"
}

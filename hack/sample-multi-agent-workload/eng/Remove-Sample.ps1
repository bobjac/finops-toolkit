# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateSet('ftk-dto-hack-s-ae46')][string]$ConfirmResourceGroup
)
. "$PSScriptRoot/Sample-Common.ps1"
Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
$group = Invoke-SampleAz @('group', 'show', '--name', $ConfirmResourceGroup)
Assert-SampleOwnership $group
. "$PSScriptRoot/../../cleanup/Cleanup-Common.ps1"
Assert-HackCleanupGroup -Group $group -Component Sample
$resources = @(Invoke-SampleAz @('resource', 'list', '--resource-group', $ConfirmResourceGroup) -ExpectedType Array)
$config = Get-Content "$PSScriptRoot/../../sandbox.config.json" -Raw | ConvertFrom-Json
Assert-HackTeardownInventory -Group $group -Component Sample -Resources $resources -OwnsModel:($config.model.ownership -ceq 'sandbox')
if ($PSCmdlet.ShouldProcess($ConfirmResourceGroup, 'Delete only the independently owned sample group')) {
    Invoke-SampleAz @('group', 'delete', '--name', $ConfirmResourceGroup, '--yes') | Out-Null
    if (Invoke-SampleAz @('group', 'exists', '--name', $ConfirmResourceGroup) -ExpectedType Boolean) {
        throw 'Sample removal did not complete.'
    }
}

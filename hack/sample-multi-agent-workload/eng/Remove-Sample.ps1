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
if ($PSCmdlet.ShouldProcess($ConfirmResourceGroup, 'Delete only the independently owned sample group')) {
    Invoke-SampleAz @('group', 'delete', '--name', $ConfirmResourceGroup, '--yes') | Out-Null
    if (Invoke-SampleAz @('group', 'exists', '--name', $ConfirmResourceGroup)) {
        throw 'Sample removal did not complete.'
    }
}

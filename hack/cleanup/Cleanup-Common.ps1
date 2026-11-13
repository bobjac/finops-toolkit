# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. "$PSScriptRoot/../sample-multi-agent-workload/eng/Experiment-Common.ps1"

function Get-HackCleanupGroup {
    param([Parameter(Mandatory)][ValidateSet('Sample', 'Foundation', 'Validation')][string]$Component)
    switch ($Component) {
        Sample { 'ftk-dto-hack-s-ae46' }
        Foundation { 'ftk-dto-hack-foundation' }
        Validation { 'ftk-dto-hack-cleanup-validation' }
    }
}

function Get-HackExpiration {
    param([Parameter(Mandatory)]$Value)
    # ConvertFrom-Json can promote ISO timestamps to DateTime on newer PowerShell.
    $text = if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) { $Value.ToString('o') } else { [string]$Value }
    $expiry = [DateTimeOffset]::MinValue
    if ($text -cnotmatch '^\d{4}-\d{2}-\d{2}T.*(Z|[+-]\d{2}:\d{2})$' -or
        -not [DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$expiry)) {
        throw 'An explicit ISO 8601 expiration with a UTC offset is required.'
    }
    return $expiry
}

function Assert-HackCleanupGroup {
    param([Parameter(Mandatory)]$Group, [Parameter(Mandatory)][string]$Component)
    $name = Get-HackCleanupGroup $Component
    $id = "/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/$name"
    if ($Group.id -ine $id -or $Group.name -cne $name -or $Group.location -ine 'eastus2') {
        throw 'Cleanup group identity or location does not match the fixed allowlist.'
    }
    switch ($Component) {
        Sample { Assert-SampleOwnership $Group }
        Foundation {
            $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
                [Text.Encoding]::UTF8.GetBytes($id.ToLowerInvariant()))).Substring(0, 12).ToLowerInvariant()
            if ($Group.tags.'ftk-owner' -cne 'bobjac/finops-toolkit' -or
                $Group.tags.'ftk-component' -cne 'dto-foundation' -or $Group.tags.'ftk-sandbox' -cne $hash) {
                throw 'Foundation cleanup ownership does not match.'
            }
        }
        Validation {
            if ($Group.tags.repository -cne 'bobjac/finops-toolkit' -or
                $Group.tags.'ftk-tool' -cne 'design-time-optimizer-cleanup-validation' -or
                $Group.tags.'fixture-run-id' -cnotmatch '^[0-9]{1,12}$') {
                throw 'Validation cleanup ownership does not match.'
            }
        }
    }
}

function Assert-HackTeardownInventory {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][ValidateSet('Sample', 'Foundation', 'Validation')][string]$Component,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resources,
        [bool]$OwnsModel = $false
    )
    $sampleNames = @{
        'Microsoft.ContainerRegistry/registries' = 'crftkdtohacksae46'
        'Microsoft.ManagedIdentity/userAssignedIdentities' = 'id-ftk-dto-hack-s-ae46'
        'Microsoft.KeyVault/vaults' = 'kv-ftk-dto-hack-s-ae46'
        'Microsoft.CognitiveServices/accounts' = 'oai-ftk-dto-hack-s-ae46'
        'Microsoft.OperationalInsights/workspaces' = 'log-ftk-dto-hack-s-ae46'
        'Microsoft.Insights/components' = 'appi-ftk-dto-hack-s-ae46'
        'Microsoft.App/managedEnvironments' = 'cae-ftk-dto-hack-s-ae46'
        'Microsoft.App/containerApps' = 'ca-ftk-dto-hack-s-ae46'
    }
    foreach ($resource in $Resources) {
        if (-not ([string]$resource.id).StartsWith("$($Group.id)/providers/", [StringComparison]::OrdinalIgnoreCase) -or
            $resource.tags.'cleanup-exclude' -eq 'true' -or $resource.tags.'model-ownership' -eq 'shared') {
            throw "Refusing teardown of excluded or out-of-scope resource '$($resource.id)'."
        }
        if ($resource.type -ieq 'Microsoft.CognitiveServices/accounts' -and
            ($Component -ne 'Sample' -or -not $OwnsModel)) {
            throw "Shared model endpoints are excluded from teardown: '$($resource.id)'."
        }
        $owned = $false
        switch ($Component) {
            Validation {
                $owned = $resource.type -ieq 'Microsoft.ManagedIdentity/userAssignedIdentities' -and
                    $resource.name -ceq 'id-dto-cleanup-validation' -and
                    $resource.tags.repository -ceq 'bobjac/finops-toolkit' -and
                    $resource.tags.'ftk-tool' -ceq 'design-time-optimizer-cleanup-validation' -and
                    $resource.tags.'fixture-run-id' -ceq $Group.tags.'fixture-run-id'
            }
            Foundation {
                $owned = $resource.type -in @('Microsoft.Storage/storageAccounts', 'Microsoft.Kusto/clusters',
                    'Microsoft.DataFactory/factories', 'Microsoft.KeyVault/vaults', 'Microsoft.ManagedIdentity/userAssignedIdentities') -and
                    $resource.tags.'ftk-owner' -ceq 'bobjac/finops-toolkit' -and
                    $resource.tags.'ftk-component' -ceq 'dto-foundation' -and
                    $resource.tags.'ftk-sandbox' -ceq $Group.tags.'ftk-sandbox'
                if (-not $owned -and $resource.type -ieq 'Microsoft.EventGrid/systemTopics') {
                    $detail = Invoke-SampleAz @('resource', 'show', '--ids', $resource.id)
                    $sources = @($Resources | Where-Object {
                        $_.type -ieq 'Microsoft.Storage/storageAccounts' -and
                        $_.tags.'ftk-owner' -ceq 'bobjac/finops-toolkit' -and
                        $_.tags.'ftk-sandbox' -ceq $Group.tags.'ftk-sandbox'
                    })
                    $owned = $detail.properties.topicType -ieq 'Microsoft.Storage.StorageAccounts' -and
                        $detail.properties.source -iin $sources.id
                }
            }
            Sample {
                $owned = $sampleNames.ContainsKey([string]$resource.type) -and
                    $resource.name -ceq $sampleNames[[string]$resource.type] -and
                    $resource.tags.repository -ceq 'bobjac/finops-toolkit' -and
                    $resource.tags.'ftk-tool' -ceq 'design-time-optimizer-sample'
                if ($resource.type -ieq 'Microsoft.App/containerApps' -and $resource.name -cmatch '^ca-dto-x-([0-9]{1,12})-[bc]$') {
                    $run = $Matches[1]
                    Assert-ExperimentApp -App $resource -RunId $run -Name $resource.name
                    $owned = $true
                }
                if ($resource.type -ieq 'Microsoft.Insights/workbooks') {
                    $owned = $resource.name -ceq '478410d0-a0ae-5679-89fe-eea6a576654c' -and
                        $resource.tags.'ftk-owner' -ceq 'bobjac/finops-toolkit' -and
                        $resource.tags.'ftk-component' -ceq 'dto-workbook'
                }
                $insights = "$($Group.id)/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46"
                $actionGroup = "$($Group.id)/providers/Microsoft.Insights/actionGroups/Application Insights Smart Detection"
                if ($resource.type -ieq 'Microsoft.AlertsManagement/smartDetectorAlertRules' -and
                    $resource.name -ieq 'Failure Anomalies - appi-ftk-dto-hack-s-ae46') {
                    $detail = Invoke-SampleAz @('resource', 'show', '--ids', $resource.id)
                    $owned = $detail.properties.detector.id -ceq 'FailureAnomaliesDetector' -and
                        @($detail.properties.scope).Count -eq 1 -and $detail.properties.scope[0] -ieq $insights -and
                        @($detail.properties.actionGroups.groupIds).Count -eq 1 -and
                        $detail.properties.actionGroups.groupIds[0] -ieq $actionGroup
                }
                if ($resource.id -ieq $actionGroup) {
                    $detail = Invoke-SampleAz @('resource', 'show', '--ids', $resource.id)
                    $receivers = @('automationRunbookReceivers', 'azureAppPushReceivers', 'azureFunctionReceivers',
                        'emailReceivers', 'eventHubReceivers', 'itsmReceivers', 'logicAppReceivers', 'smsReceivers',
                        'voiceReceivers', 'webhookReceivers')
                    $customReceivers = @($receivers | Where-Object { @($detail.properties.$_).Count -gt 0 })
                    $roles = @($detail.properties.armRoleReceivers)
                    $owned = $detail.properties.groupShortName -ceq 'SmartDetect' -and $customReceivers.Count -eq 0 -and
                        $roles.Count -eq 2 -and @($roles.roleId | Sort-Object -Unique).Count -eq 2 -and @($roles | Where-Object {
                            $_.roleId -notin @('749f88d5-cbae-40b8-bcfc-e573ddc772fa', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
                        }).Count -eq 0 -and @($Resources | Where-Object {
                            $_.type -ieq 'Microsoft.AlertsManagement/smartDetectorAlertRules' -and
                            $_.name -ieq 'Failure Anomalies - appi-ftk-dto-hack-s-ae46'
                        }).Count -eq 1
                }
            }
        }
        if (-not $owned) { throw "Unrecognized or unowned resource blocks group teardown: '$($resource.id)'." }
    }
}

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . "$PSScriptRoot/../Cleanup-Common.ps1"
    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        throw 'Azure must be mocked in cleanup tests.'
    }
    $script:sampleId = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
    function New-CleanupTestApp {
        param([string]$Variant = 'baseline', [int]$Minutes = -1, [string]$RunId = '123')
        $name = Get-ExperimentAppName -RunId $RunId -Variant $Variant
        @{
            id = "$script:sampleId/providers/Microsoft.App/containerApps/$name"; name = $name
            type = 'Microsoft.App/containerApps'
            tags = @{
                repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-experiment'
                'experiment-run-id' = $RunId; 'experiment-id' = "h09-$RunId"; revision = 'a' * 40
                variant = $Variant; 'expires-on' = [DateTimeOffset]::UtcNow.AddMinutes($Minutes).ToString('o')
            }
        }
    }
}

Describe 'Owned resource teardown boundaries' {
    BeforeEach {
        $script:group = @{ id = $script:sampleId; name = 'ftk-dto-hack-s-ae46'; location = 'eastus2'
            tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' } }
        $script:model = @{ id = "$script:sampleId/providers/Microsoft.CognitiveServices/accounts/oai-ftk-dto-hack-s-ae46"
            name = 'oai-ftk-dto-hack-s-ae46'; type = 'Microsoft.CognitiveServices/accounts'; tags = $script:group.tags.Clone() }
    }
    It 'Requires exact group identity and ownership rather than a name prefix' {
        { Assert-HackCleanupGroup -Group $script:group -Component Sample } | Should -Not -Throw
        $script:group.id += '-foreign'
        { Assert-HackCleanupGroup -Group $script:group -Component Sample } | Should -Throw
    }
    It 'Excludes shared model endpoints even inside a confirmed group' {
        { Assert-HackTeardownInventory -Group $script:group -Component Sample -Resources @($script:model) } | Should -Throw '*Shared model*'
        { Assert-HackTeardownInventory -Group $script:group -Component Sample -Resources @($script:model) -OwnsModel $true } | Should -Not -Throw
        $script:model.tags.'model-ownership' = 'shared'
        { Assert-HackTeardownInventory -Group $script:group -Component Sample -Resources @($script:model) -OwnsModel $true } | Should -Throw '*excluded*'
    }
    It 'Rejects foreign resources, unrecognized types, and outside IDs' -ForEach @(
        @{ Change = 'owner' }, @{ Change = 'type' }, @{ Change = 'scope' }, @{ Change = 'exclude' }
    ) {
        switch ($Change) {
            owner { $script:model.tags.repository = 'another/repository' }
            type { $script:model.type = 'Microsoft.Compute/virtualMachines' }
            scope { $script:model.id = '/subscriptions/foreign/resourceGroups/foreign/providers/Microsoft.CognitiveServices/accounts/model' }
            exclude { $script:model.tags.'cleanup-exclude' = 'true' }
        }
        { Assert-HackTeardownInventory -Group $script:group -Component Sample -Resources @($script:model) -OwnsModel $true } | Should -Throw
    }
    It 'Does not require expired tags or current prices for confirmed teardown' {
        $script:model.tags.'expires-on' = 'invalid'
        { Assert-HackTeardownInventory -Group $script:group -Component Sample -Resources @($script:model) -OwnsModel $true } | Should -Not -Throw
    }
    It 'Checks the linked owned storage account for a provider-created Event Grid topic' {
        $group = @{ id = '/subscriptions/test/resourceGroups/foundation'; tags = @{
            'ftk-owner' = 'bobjac/finops-toolkit'; 'ftk-component' = 'dto-foundation'; 'ftk-sandbox' = 'fixture' } }
        $storage = @{ id = "$($group.id)/providers/Microsoft.Storage/storageAccounts/owned"; type = 'Microsoft.Storage/storageAccounts'; tags = $group.tags }
        $topic = @{ id = "$($group.id)/providers/Microsoft.EventGrid/systemTopics/generated"; type = 'Microsoft.EventGrid/systemTopics' }
        Mock Invoke-SampleAz { @{ properties = @{ topicType = 'Microsoft.Storage.StorageAccounts'; source = $storage.id } } }
        { Assert-HackTeardownInventory -Group $group -Component Foundation -Resources @($storage, $topic) } | Should -Not -Throw
        Mock Invoke-SampleAz { @{ properties = @{ topicType = 'Microsoft.Storage.StorageAccounts'; source = '/foreign/storage' } } }
        { Assert-HackTeardownInventory -Group $group -Component Foundation -Resources @($storage, $topic) } | Should -Throw
    }
    It 'Checks generated monitoring relationships and refuses custom or foreign recipients' -ForEach @(
        @{ Change = 'none' }, @{ Change = 'scope' }, @{ Change = 'roles' }, @{ Change = 'receivers' }
    ) {
        $insights = @{ id = "$script:sampleId/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46"
            name = 'appi-ftk-dto-hack-s-ae46'; type = 'Microsoft.Insights/components'; tags = $script:group.tags }
        $action = @{ id = "$script:sampleId/providers/Microsoft.Insights/actionGroups/Application Insights Smart Detection"
            type = 'Microsoft.Insights/actionGroups'; name = 'Application Insights Smart Detection' }
        $rule = @{ id = "$script:sampleId/providers/Microsoft.AlertsManagement/smartDetectorAlertRules/Failure Anomalies - appi-ftk-dto-hack-s-ae46"
            type = 'Microsoft.AlertsManagement/smartDetectorAlertRules'; name = 'Failure Anomalies - appi-ftk-dto-hack-s-ae46' }
        $script:actionProperties = @{ groupShortName = 'SmartDetect'; armRoleReceivers = @(
                @{ roleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa' }, @{ roleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05' }) }
        foreach ($name in @('automationRunbookReceivers', 'azureAppPushReceivers', 'azureFunctionReceivers',
                'emailReceivers', 'eventHubReceivers', 'itsmReceivers', 'logicAppReceivers', 'smsReceivers',
                'voiceReceivers', 'webhookReceivers')) { $script:actionProperties[$name] = @() }
        $script:ruleProperties = @{ detector = @{ id = 'FailureAnomaliesDetector' }; scope = @($insights.id)
            actionGroups = @{ groupIds = @($action.id) } }
        switch ($Change) {
            scope { $script:ruleProperties.scope = @('/foreign/insights') }
            roles { $script:actionProperties.armRoleReceivers[1].roleId = $script:actionProperties.armRoleReceivers[0].roleId }
            receivers { $script:actionProperties.emailReceivers = @(@{ emailAddress = 'fixture@example.invalid' }) }
        }
        Mock Invoke-SampleAz {
            if ($Arguments[-1] -like '*/Application Insights Smart Detection') { @{ properties = $script:actionProperties } }
            else { @{ properties = $script:ruleProperties } }
        }
        $check = { Assert-HackTeardownInventory -Group $script:group -Component Sample -Resources @($insights, $rule, $action) }
        if ($Change -eq 'none') { $check | Should -Not -Throw } else { $check | Should -Throw }
    }
}

Describe 'Expiration and retry receipts' {
    BeforeEach {
        $script:savedEnvironment = @{}
        foreach ($entry in @{ GITHUB_ACTIONS = 'true'; GITHUB_REPOSITORY = 'bobjac/finops-toolkit'
                GITHUB_REF = 'refs/heads/dev'; GITHUB_RUN_ID = '456'; GITHUB_SHA = 'b' * 40 }.GetEnumerator()) {
            $script:savedEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
        $global:cleanupState = @{
            Apps = [Collections.Generic.List[object]]::new()
            Deleted = [Collections.Generic.List[string]]::new()
            Exists = $true; FailDelete = $false; RenewExpiry = $false; ForeignInventory = $false
            FixtureExists = $true; FixtureIdentity = $false; AppCreates = 0; FailAt = ''; VerificationFailed = $false
            BadOperation = ''; BadResponse = ''
        }
        $global:cleanupState.Apps.Add((New-CleanupTestApp))
        $global:cleanupState.Apps.Add((New-CleanupTestApp -Variant candidate -Minutes 30))
        $script:output = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        Mock Start-Sleep {}
        Mock az {
            param($Arguments)
            $global:LASTEXITCODE = 0
            $state = $global:cleanupState
            $operation = $Arguments[0..1] -join ' '
            if ($state.BadOperation -eq $operation) { return $state.BadResponse }
            if ($operation -eq 'resource list' -and -not $state.ForeignInventory -and -not $state.FixtureIdentity) { return '[]' }
            $result = switch ($operation) {
                'account show' { @{ id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'; tenantId = '3670e846-58dd-4658-86fb-00e4029045d6' } }
                'group exists' {
                    $name = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                    if ($name -eq 'ftk-dto-hack-cleanup-validation') { $state.FixtureExists } else { $state.Exists }
                }
                'group show' {
                    $name = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                    @{ id = "/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/$name"
                        name = $name; location = 'eastus2'; tags = @{
                            repository = 'bobjac/finops-toolkit'; 'ftk-tool' = if ($name -eq 'ftk-dto-hack-s-ae46') { 'design-time-optimizer-sample' } else { 'design-time-optimizer-cleanup-validation' }
                            'fixture-run-id' = '456'
                        } }
                }
                'resource list' {
                    $items = if ($state.ForeignInventory) { @(@{ id = '/foreign/model'; type = 'Microsoft.CognitiveServices/accounts' }) }
                    elseif ($state.FixtureIdentity) {
                        @(@{ id = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-cleanup-validation/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-dto-cleanup-validation'
                            type = 'Microsoft.ManagedIdentity/userAssignedIdentities'; name = 'id-dto-cleanup-validation'
                            tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-cleanup-validation'; 'fixture-run-id' = '456' } })
                    }
                    return (ConvertTo-Json -InputObject @($items) -Depth 20)
                }
                'group create' { $state.FixtureExists = $true }
                'identity create' {
                    $state.FixtureIdentity = $true
                    if ($state.FailAt -eq 'deployment') { throw 'Synthetic partial fixture deployment failure.' }
                }
                'group delete' { $state.Deleted.Add('group'); $state.FixtureExists = $false; $state.FixtureIdentity = $false }
                'containerapp create' {
                    $name = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                    $variant = if ($name.EndsWith('-b')) { 'baseline' } else { 'candidate' }
                    $minutes = if ($variant -eq 'baseline') { -1 } else { 90 }
                    $state.Apps.Add((New-CleanupTestApp -RunId 456 -Variant $variant -Minutes $minutes))
                    $state.AppCreates++
                }
                'tag update' {
                    $app = @($state.Apps | Where-Object { $_.name -eq 'ca-dto-x-456-c' })[0]
                    $app.tags.'expires-on' = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
                }
                'containerapp list' {
                    if ($state.FailAt -eq 'verification' -and $state.AppCreates -eq 2 -and -not $state.VerificationFailed) {
                        $state.VerificationFailed = $true
                        throw 'Synthetic fixture verification failure.'
                    }
                    return (ConvertTo-Json -InputObject @($state.Apps.ToArray()) -Depth 20)
                }
                'containerapp show' {
                    $name = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                    if ($name -eq 'ca-ftk-dto-hack-s-ae46') {
                        return (@{ properties = @{ template = @{ containers = @(@{ image = "crftkdtohacksae46.azurecr.io/sample:$('a' * 40)" }) } } } | ConvertTo-Json -Depth 10)
                    }
                    $app = @($state.Apps | Where-Object { $_.name -eq $name })[0]
                    if ($state.RenewExpiry) { $app.tags.'expires-on' = [DateTimeOffset]::UtcNow.AddMinutes(30).ToString('o') }
                    $app
                }
                'containerapp delete' {
                    $name = $Arguments[[Array]::IndexOf($Arguments, '--name') + 1]
                    if ($state.FailDelete -and $name.EndsWith('-b')) { throw 'Synthetic delete failure.' }
                    $app = @($state.Apps | Where-Object { $_.name -eq $name })[0]
                    $state.Deleted.Add($name)
                    $state.Apps.Remove($app) | Out-Null
                }
                default { throw "Unexpected Azure operation: $operation" }
            }
            ConvertTo-Json -InputObject $result -Depth 20 -Compress
        }
    }
    AfterEach {
        foreach ($entry in $script:savedEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value) }
        Remove-Variable cleanupState -Scope Global
    }
    It 'Plans without deleting and keeps fresh apps and the retained demo' {
        $global:cleanupState.Apps.Add(@{ name = 'ca-ftk-dto-hack-s-ae46'; id = "$script:sampleId/providers/Microsoft.App/containerApps/ca-ftk-dto-hack-s-ae46" })
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -OutputDirectory $script:output
        $global:cleanupState.Deleted.Count | Should -Be 0
        $receipt = Get-Content "$script:output/cleanup.json" -Raw | ConvertFrom-Json
        $receipt.status | Should -Be 'Planned'
        $receipt.verified | Should -BeFalse
        $receipt.targets.Count | Should -Be 1
        $receipt.skipped.Count | Should -Be 2
    }
    It 'Removes only an expired owned app and supports an idempotent retry' {
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory $script:output -Confirm:$false
        $global:cleanupState.Deleted | Should -Contain 'ca-dto-x-123-b'
        $global:cleanupState.Deleted | Should -Not -Contain 'ca-dto-x-123-c'
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory "$script:output/retry" -Confirm:$false
        $global:cleanupState.Deleted.Count | Should -Be 1
        (Get-Content "$script:output/retry/cleanup.json" -Raw | ConvertFrom-Json).verified | Should -BeTrue
    }
    It 'Filters validation expiration to its exact run without deleting another expired experiment' {
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -ExperimentRunId 456 -OutputDirectory $script:output -Confirm:$false
        $global:cleanupState.Deleted.Count | Should -Be 0
        $global:cleanupState.Apps.Count | Should -Be 2
    }
    It 'Rejects ambiguous expiration, invalid ownership, and changed expiration' -ForEach @(
        @{ Problem = 'timestamp' }, @{ Problem = 'owner' }, @{ Problem = 'renewed' }
    ) {
        switch ($Problem) {
            timestamp { $global:cleanupState.Apps[0].tags.'expires-on' = '01/01/2020 00:00:00' }
            owner { $global:cleanupState.Apps[0].tags.repository = 'another/repository' }
            renewed { $global:cleanupState.RenewExpiry = $true }
        }
        { & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory $script:output -Confirm:$false } | Should -Throw '*incomplete*'
        $global:cleanupState.Deleted.Count | Should -Be 0
        (Get-Content "$script:output/cleanup.json" -Raw | ConvertFrom-Json).verified | Should -BeFalse
    }
    It 'Attempts the other expired app after a deletion failure and records retryable failure' {
        $global:cleanupState.Apps[1].tags.'expires-on' = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
        $global:cleanupState.FailDelete = $true
        { & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory $script:output -Confirm:$false } | Should -Throw '*incomplete*'
        $global:cleanupState.Deleted | Should -Contain 'ca-dto-x-123-c'
        $receipt = Get-Content "$script:output/cleanup.json" -Raw | ConvertFrom-Json
        $receipt.status | Should -Be 'Failed'
        $receipt.failures[0].resourceId | Should -Match 'ca-dto-x-123-b'
        $global:cleanupState.FailDelete = $false
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory "$script:output/retry" -Confirm:$false
        (Get-Content "$script:output/retry/cleanup.json" -Raw | ConvertFrom-Json).verified | Should -BeTrue
    }
    It 'Recovers fault-injected orphan states without rewriting failure evidence' -ForEach @(
        @{ Stage = 'deployment'; State = 'Failed'; Count = 1 }
        @{ Stage = 'load'; State = 'Succeeded'; Count = 2 }
        @{ Stage = 'cancellation'; State = 'Updating'; Count = 2 }
    ) {
        # The orphan survives the failed controller; this is a later backstop invocation.
        $global:cleanupState.Apps[0].properties = @{ provisioningState = $State }
        if ($Count -eq 2) { $global:cleanupState.Apps[1].tags.'expires-on' = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o') }
        @{ failedStage = $Stage; status = 'Incomplete' } | ConvertTo-Json | Set-Content "$TestDrive/failed-controller.json"
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory $script:output -Confirm:$false
        $global:cleanupState.Deleted | Should -Contain 'ca-dto-x-123-b'
        $global:cleanupState.Deleted.Count | Should -Be $Count
        (Get-Content "$TestDrive/failed-controller.json" -Raw | ConvertFrom-Json).status | Should -Be 'Incomplete'
    }
    It 'Requires exact teardown confirmation before any deletion' {
        { & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Teardown -Component Sample -Confirmation wrong -OutputDirectory $script:output -Confirm:$false } | Should -Throw '*exact*'
        $global:cleanupState.Deleted.Count | Should -Be 0
    }
    It 'Rejects invalid Azure response shapes instead of claiming absence or empty inventory' -ForEach @(
        @{ AzureOperation = 'group exists'; Response = 'null'; Component = 'Experiments' }
        @{ AzureOperation = 'group exists'; Response = '"false"'; Component = 'Experiments' }
        @{ AzureOperation = 'containerapp list'; Response = 'null'; Component = 'Experiments' }
        @{ AzureOperation = 'containerapp list'; Response = '{}'; Component = 'Experiments' }
        @{ AzureOperation = 'resource list'; Response = 'null'; Component = 'Validation' }
        @{ AzureOperation = 'resource list'; Response = '{}'; Component = 'Validation' }
    ) {
        $global:cleanupState.BadOperation = $AzureOperation
        $global:cleanupState.BadResponse = $Response
        { & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Component $Component -OutputDirectory $script:output } | Should -Throw '*invalid*response*'
        $global:cleanupState.Deleted.Count | Should -Be 0
        (Get-Content "$script:output/cleanup.json" -Raw | ConvertFrom-Json).verified | Should -BeFalse
    }
    It 'Never claims verified cleanup when WhatIf prevents deletion' {
        { & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Expired -OutputDirectory $script:output -WhatIf } | Should -Throw '*incomplete*'
        $global:cleanupState.Deleted.Count | Should -Be 0
        (Get-Content "$script:output/cleanup.json" -Raw | ConvertFrom-Json).verified | Should -BeFalse
    }
    It 'Confirms full validation group removal and handles an already absent group' {
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Teardown -Component Validation -Confirmation ftk-dto-hack-cleanup-validation -OutputDirectory $script:output -Confirm:$false
        $global:cleanupState.Deleted | Should -Contain 'group'
        (Get-Content "$script:output/cleanup.json" -Raw | ConvertFrom-Json).verified | Should -BeTrue
        & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Teardown -Component Validation -Confirmation ftk-dto-hack-cleanup-validation -OutputDirectory "$script:output/retry" -Confirm:$false
        (Get-Content "$script:output/retry/cleanup.json" -Raw | ConvertFrom-Json).status | Should -Be 'AlreadyAbsent'
    }
    It 'Refuses full group deletion when inventory contains an unowned resource' {
        $global:cleanupState.ForeignInventory = $true
        { & "$PSScriptRoot/../Invoke-HackCleanup.ps1" -Operation Teardown -Component Validation -Confirmation ftk-dto-hack-cleanup-validation -OutputDirectory $script:output -Confirm:$false } | Should -Throw '*out-of-scope*'
        $global:cleanupState.Deleted.Count | Should -Be 0
        Test-Path "$script:output/cleanup.json" | Should -BeTrue
    }
    It 'Also blocks the existing sample removal entry point when a foreign resource is present' {
        $global:cleanupState.ForeignInventory = $true
        { & "$PSScriptRoot/../../sample-multi-agent-workload/eng/Remove-Sample.ps1" -ConfirmResourceGroup ftk-dto-hack-s-ae46 -Confirm:$false } | Should -Throw '*out-of-scope*'
        $global:cleanupState.Deleted.Count | Should -Be 0
    }
    It 'Validates live-fixture control flow without touching other runs or retained resources' {
        $global:cleanupState.FixtureExists = $false
        & "$PSScriptRoot/../Test-HackCleanupLive.ps1" -Confirmation validate-owned-cleanup-fixtures -OutputDirectory $script:output -Confirm:$false
        $receipt = Get-Content "$script:output/validation.json" -Raw | ConvertFrom-Json
        $receipt.verified | Should -BeTrue
        $receipt.retainedTeardownTested | Should -BeFalse
        $global:cleanupState.FixtureExists | Should -BeFalse
        $global:cleanupState.Apps.Count | Should -Be 2
        $global:cleanupState.Deleted | Should -Not -Contain 'ca-dto-x-123-b'
    }
    It 'Always attempts fixture cleanup after partial deployment or verification failure' -ForEach @(
        @{ FailAt = 'deployment' }, @{ FailAt = 'verification' }
    ) {
        $global:cleanupState.FixtureExists = $false
        $global:cleanupState.FailAt = $FailAt
        { & "$PSScriptRoot/../Test-HackCleanupLive.ps1" -Confirmation validate-owned-cleanup-fixtures -OutputDirectory $script:output -Confirm:$false } | Should -Throw '*fixture validation failed*'
        $global:cleanupState.FixtureExists | Should -BeFalse
        $global:cleanupState.Apps.Count | Should -Be 2
        $receipt = Get-Content "$script:output/validation.json" -Raw | ConvertFrom-Json
        $receipt.verified | Should -BeFalse
        $receipt.failures.Count | Should -BeGreaterThan 0
    }
}

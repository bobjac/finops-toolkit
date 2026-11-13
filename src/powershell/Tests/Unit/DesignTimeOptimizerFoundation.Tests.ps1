# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
    $script:Lifecycle = Join-Path $script:Root 'src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1'
    $script:PriorState = Get-Variable DesignTimeOptimizerFoundationTestState -Scope Global -ErrorAction SilentlyContinue
    $script:Environment = @{}
    foreach ($name in 'AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_ID') {
        $script:Environment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        throw "Unexpected unmocked Azure call: $($Arguments -join ' ')"
    }
}

AfterAll {
    foreach ($name in $script:Environment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:Environment[$name])
    }
    if ($script:PriorState) {
        Set-Variable DesignTimeOptimizerFoundationTestState -Scope Global -Value $script:PriorState.Value
    }
    else {
        Remove-Variable DesignTimeOptimizerFoundationTestState -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Owned sandbox foundation lifecycle' {
    BeforeEach {
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_TENANT_ID = '22222222-2222-2222-2222-222222222222'
        $env:AZURE_CLIENT_ID = '33333333-3333-3333-3333-333333333333'
        $script:Config = Get-Content (Join-Path $script:Root 'hack/sandbox.config.json') -Raw | ConvertFrom-Json -AsHashtable
        $script:Config.expiresOn = [DateTimeOffset]::UtcNow.AddDays(7).ToString('yyyy-MM-ddTHH:mm:sszzz')
        $script:ConfigPath = Join-Path $TestDrive 'sandbox.json'
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Output = Join-Path $TestDrive 'evidence'
        $script:Template = Join-Path $TestDrive 'template.json'
        '{}' | Set-Content $script:Template
        $script:Plan = & $script:Lifecycle -Path $script:ConfigPath -WhatIf
        $tags = $script:Plan.Ownership.Clone()
        $tags['ftk-expires-on'] = $script:Config.expiresOn
        $tags['ftk-source'] = 'initial-revision'
        $script:State = @{
            Calls = [Collections.Generic.List[string]]::new()
            Exists = $true; DeleteFails = $false; DeployFails = $false; MissingAdmin = $false; ForeignResource = $false
            Group = @{ id = $script:Plan.ResourceGroupId; location = $script:Config.region; tags = $tags }
            Account = @{
                id = $env:AZURE_SUBSCRIPTION_ID; tenantId = $env:AZURE_TENANT_ID; state = 'Enabled'
                user = @{ type = 'servicePrincipal'; name = $env:AZURE_CLIENT_ID }
            }
            Outputs = @{
                storageAccountId = @{ value = "$($script:Plan.ResourceGroupId)/providers/Microsoft.Storage/storageAccounts/teststorage" }
                clusterId = @{ value = "$($script:Plan.ResourceGroupId)/providers/Microsoft.Kusto/clusters/testcluster" }
                dataFactoryName = @{ value = 'testfactory' }
                hubDbName = @{ value = 'Hub' }; ingestionDbName = @{ value = 'Ingestion' }
            }
        }
        $global:DesignTimeOptimizerFoundationTestState = $script:State
        Mock az {
            param($Arguments)
            $state = $global:DesignTimeOptimizerFoundationTestState
            $call = $Arguments -join ' '
            $state.Calls.Add($call)
            $global:LASTEXITCODE = 0
            if ($call -like 'account show*') { $response = $state.Account }
            elseif ($call -like 'group exists*') { $response = $state.Exists }
            elseif ($call -like 'group show*') { $response = $state.Group }
            elseif ($call -like 'group delete*') {
                if ($state.DeleteFails) { $global:LASTEXITCODE = 1; return 'Deletion denied' }
                $state.Exists = $false
                $response = $null
            }
            elseif ($call -like 'group create*') {
                $state.Exists = $true
                foreach ($argument in $Arguments) {
                    if ($argument -match '^(ftk-[^=]+)=(.*)$') { $state.Group.tags[$Matches[1]] = $Matches[2] }
                }
                $response = $state.Group
            }
            elseif ($call -like 'deployment group validate*') { $response = @{} }
            elseif ($call -like 'deployment group create*' -or $call -like 'deployment group show*') {
                if ($state.DeployFails) { $global:LASTEXITCODE = 1; return 'Provisioning denied' }
                $response = @{ properties = @{ provisioningState = 'Succeeded'; outputs = $state.Outputs } }
            }
            elseif ($call -like 'resource list*') {
                $response = @(@{ id = $state.Outputs.clusterId.value; type = 'Microsoft.Kusto/clusters'; name = 'testcluster'; tags = $state.Group.tags })
                if ($state.ForeignResource) { $response[0].tags = @{ 'ftk-owner' = 'another/repository' } }
            }
            elseif ($call -match '/databases/(Hub|Ingestion)\?') { $response = @{ properties = @{ provisioningState = 'Succeeded' } } }
            elseif ($call -match '/databases/(Hub|Ingestion)/principalAssignments\?') {
                $response = @{ value = @() }
                if (-not $state.MissingAdmin) {
                    $response.value = @(@{ properties = @{ principalType = 'App'; role = 'Admin'; tenantId = $env:AZURE_TENANT_ID; principalId = $env:AZURE_CLIENT_ID } })
                }
            }
            elseif ($call -like 'provider list*') {
                $response = @('Storage', 'DataFactory', 'KeyVault', 'EventGrid', 'CostManagementExports', 'Kusto', 'Network', 'ContainerInstance', 'Quota', 'ManagedIdentity', 'OperationalInsights', 'Insights', 'App', 'ContainerRegistry', 'CognitiveServices', 'LoadTestService') |
                    ForEach-Object { @{ namespace = "Microsoft.$_"; registrationState = 'Registered' } }
            }
            elseif ($call -match '/Microsoft.Authorization/permissions\?') { $response = @{ value = @(@{ actions = @('*'); dataActions = @('*') }) } }
            elseif ($call -match '/Microsoft.Kusto/locations/.*/skus\?') { $response = @{ value = @(@{ name = 'Dev(No SLA)_Standard_E2a_v4' }) } }
            elseif ($call -like 'quota list*' -or $call -like 'storage container list*') { $response = @() }
            elseif ($call -like 'cognitiveservices model list*') {
                $response = @(@{ kind = 'OpenAI'; model = @{
                            name = 'gpt-5-mini'; version = 'test'; lifecycleStatus = 'Stable'
                            skus = @(@{ name = 'GlobalStandard'; usageName = 'test-quota'; capacity = @{ minimum = 1; maximum = 100 } })
                        } })
            }
            elseif ($call -like 'cognitiveservices usage list*') { $response = @(@{ name = @{ value = 'test-quota' }; limit = 100; currentValue = 0 }) }
            elseif ($call -match '/storageAccounts/teststorage\?') { $response = @{ name = 'teststorage' } }
            elseif ($call -match '/clusters/testcluster\?') { $response = @{ properties = @{ uri = 'https://testcluster.eastus2.kusto.windows.net' } } }
            elseif ($call -match '/v2/rest/query ') { $response = @(@{ FrameType = 'DataSetCompletion'; HasErrors = $false }) }
            else { throw "Unexpected Azure call: $call" }
            ConvertTo-Json -InputObject $response -Depth 30 -Compress
        }
    }

    It 'Plans without Azure access or evidence writes' {
        & $script:Lifecycle -Path $script:ConfigPath -OutputDirectory $script:Output -WhatIf
        $script:State.Calls.Count | Should -Be 0
        Test-Path $script:Output | Should -BeFalse
    }

    It 'Rejects missing write confirmation before Azure access' {
        { & $script:Lifecycle -Operation Remove -Path $script:ConfigPath -Confirm:$false } | Should -Throw '*exact resource group name*'
        $script:State.Calls.Count | Should -Be 0
    }

    It 'Rejects the wrong signed-in subscription without resource operations' {
        $script:State.Account.id = '44444444-4444-4444-4444-444444444444'
        { & $script:Lifecycle -Path $script:ConfigPath -OutputDirectory $script:Output } | Should -Throw '*configured enabled sandbox*'
        $script:State.Calls.Count | Should -Be 1
    }

    It 'Refuses to remove an existing unowned group' {
        $script:State.Group.tags.Remove('ftk-owner')
        { & $script:Lifecycle -Operation Remove -Path $script:ConfigPath -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -Confirm:$false } | Should -Throw '*ownership tag*'
        @($script:State.Calls | Where-Object { $_ -like 'group delete*' }).Count | Should -Be 0
    }

    It 'Allows confirmed owned cleanup after expiration without model or provider checks' {
        $script:Config.expiresOn = [DateTimeOffset]::UtcNow.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:sszzz')
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $result = & $script:Lifecycle -Operation Remove -Path $script:ConfigPath -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -Confirm:$false
        $result.Status | Should -Be 'Removed'
        @($script:State.Calls | Where-Object { $_ -match '^(provider|quota|cognitiveservices)' }).Count | Should -Be 0
    }

    It 'Records deletion failure rather than claiming successful cleanup' {
        $script:State.DeleteFails = $true
        { & $script:Lifecycle -Operation Remove -Path $script:ConfigPath -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -Confirm:$false } | Should -Throw '*Deletion denied*'
        (Get-Content (Join-Path $script:Output 'foundation.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Failed'
    }

    It 'Preserves a tagged foundation group containing an unowned resource' {
        $script:State.ForeignResource = $true
        { & $script:Lifecycle -Operation Remove -Path $script:ConfigPath -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -Confirm:$false } | Should -Throw '*unowned*'
        @($script:State.Calls | Where-Object { $_ -like 'group delete*' }).Count | Should -Be 0
        (Get-Content (Join-Path $script:Output 'foundation.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Failed'
    }

    It 'Verifies real data-plane calls without deploying or deleting resources' {
        $result = & $script:Lifecycle -Path $script:ConfigPath -OutputDirectory $script:Output
        $result.ReadyForDataIngestion | Should -BeTrue
        @($script:State.Calls | Where-Object { $_ -match '^group (create|delete)|^deployment group (create|validate)' }).Count | Should -Be 0
        @($script:State.Calls | Where-Object { $_ -match '/v2/rest/query ' }).Count | Should -Be 2
    }

    It 'Deploys twice to the same identities and retains the verified new foundation' {
        $script:State.Exists = $false
        $result = & $script:Lifecycle -Operation Deploy -Path $script:ConfigPath -TemplateFile $script:Template -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -DeploymentPasses 2 -Confirm:$false
        $result.Status | Should -Be 'VerifiedAndRetained'
        $result.CreatedThisRun | Should -BeTrue
        $result.Passes.Count | Should -Be 2
        @($script:State.Calls | Where-Object { $_ -like 'deployment group create*' }).Count | Should -Be 2
        @($script:State.Calls | Where-Object { $_ -like 'group delete*' }).Count | Should -Be 0
    }

    It 'Rejects missing database administration access rather than assuming creator grants' {
        $script:State.MissingAdmin = $true
        { & $script:Lifecycle -Path $script:ConfigPath -OutputDirectory $script:Output } | Should -Throw '*no verified Admin assignment*'
        (Get-Content (Join-Path $script:Output 'foundation.json') -Raw | ConvertFrom-Json).ReadyForDataIngestion | Should -BeFalse
    }

    It 'Defers only data-plane verification without claiming readiness or final success' {
        $script:State.Exists = $false
        $result = & $script:Lifecycle -Operation Deploy -Path $script:ConfigPath -TemplateFile $script:Template -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -DeploymentPasses 2 -DeferDataPlaneVerification -Confirm:$false
        $result.Status | Should -Be 'DeployedAwaitingDataPlaneVerification'
        $result.ReadyForDataIngestion | Should -BeFalse
        $result.Passes.Count | Should -Be 2
        $result.Passes[1].Verification | Should -Be 'ControlPlaneOnly'
        @($script:State.Calls | Where-Object { $_ -like 'storage container list*' -or $_ -match '/v2/rest/query ' }).Count | Should -Be 0
    }

    It 'Does not allow Verify to bypass actual data-plane verification' {
        { & $script:Lifecycle -Path $script:ConfigPath -OutputDirectory $script:Output -DeferDataPlaneVerification } | Should -Throw '*only valid for Deploy*'
        $script:State.Calls.Count | Should -Be 0
    }

    It 'Preserves a previously retained foundation when redeployment fails' {
        $script:State.DeployFails = $true
        { & $script:Lifecycle -Operation Deploy -Path $script:ConfigPath -TemplateFile $script:Template -OutputDirectory $script:Output -ConfirmResourceGroup $script:Plan.ResourceGroup -Confirm:$false } | Should -Throw '*Provisioning denied*'
        $report = Get-Content (Join-Path $script:Output 'foundation.json') -Raw | ConvertFrom-Json
        $report.Status | Should -Be 'Failed'
        $report.CreatedThisRun | Should -BeFalse
        @($script:State.Calls | Where-Object { $_ -like 'group delete*' }).Count | Should -Be 0
    }
}

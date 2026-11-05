# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
    $script:Validator = Join-Path $script:RepoRoot 'src/scripts/Test-DesignTimeOptimizerSandbox.ps1'
    $script:Example = Join-Path $script:RepoRoot 'hack/sandbox.config.json'
    $script:PriorTestState = Get-Variable -Name DesignTimeOptimizerSandboxTestState -Scope Global -ErrorAction SilentlyContinue
    $script:SavedEnvironment = @{}
    foreach ($name in 'AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_ID') {
        $script:SavedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }

    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
        throw "Unexpected unmocked Azure call: $($Arguments -join ' ')"
    }
}

AfterAll {
    foreach ($name in $script:SavedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:SavedEnvironment[$name])
    }
    if ($script:PriorTestState) {
        Set-Variable -Name DesignTimeOptimizerSandboxTestState -Scope Global -Value $script:PriorTestState.Value
    }
    else {
        Remove-Variable -Name DesignTimeOptimizerSandboxTestState -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Design-time optimizer sandbox preflight' {
    BeforeEach {
        $script:Config = Get-Content $script:Example -Raw | ConvertFrom-Json -AsHashtable
        $script:Config.expiresOn = [DateTimeOffset]::UtcNow.AddDays(7).ToString('yyyy-MM-ddTHH:mm:sszzz')
        $script:ConfigPath = Join-Path $TestDrive 'sandbox.json'
        $script:ReportPath = Join-Path $TestDrive 'preflight.json'
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_TENANT_ID = '22222222-2222-2222-2222-222222222222'
        $env:AZURE_CLIENT_ID = '33333333-3333-3333-3333-333333333333'
        $script:Azure = @{}
        $script:Azure.Account = @{
            id = $env:AZURE_SUBSCRIPTION_ID; tenantId = $env:AZURE_TENANT_ID; state = 'Enabled'
            user = @{ type = 'servicePrincipal'; name = $env:AZURE_CLIENT_ID }
        }
        $script:Azure.Providers = @(
            'Microsoft.Storage', 'Microsoft.DataFactory', 'Microsoft.KeyVault', 'Microsoft.EventGrid',
            'Microsoft.CostManagementExports', 'Microsoft.Kusto', 'Microsoft.Network', 'Microsoft.ContainerInstance', 'Microsoft.Quota',
            'Microsoft.ManagedIdentity', 'Microsoft.OperationalInsights', 'Microsoft.Insights',
            'Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.CognitiveServices', 'Microsoft.LoadTestService'
        ) | ForEach-Object { @{ namespace = $_; registrationState = 'Registered' } }
        $script:Azure.Permissions = @(@{ actions = @('*'); notActions = @(); dataActions = @(); notDataActions = @() })
        $script:Azure.Skus = @{ value = @(@{ name = $script:Config.dataExplorerSku; restrictions = @() }) }
        $script:Azure.Models = @(@{
                kind = 'OpenAI'
                model = @{
                    name = $script:Config.model.preferredNames[0]; version = 'test-version'; lifecycleStatus = 'GenerallyAvailable'
                    skus = @(@{
                            name = 'GlobalStandard'; usageName = 'discovered-usage-name'
                            capacity = @{ minimum = 1; maximum = 100; step = 1 }
                        })
                }
            })
        $script:Azure.Usage = @(@{ name = @{ value = 'discovered-usage-name' }; limit = 10; currentValue = 0 })
        $script:Azure.QuotaError = ''
        $script:Azure.StorageError = ''
        $script:Azure.QueryResult = @(@{ FrameType = 'DataSetCompletion'; HasErrors = $false })
        $script:Azure.Calls = [Collections.Generic.List[string]]::new()
        # Native-command mocks run in the invoked script's scope, not this test's script scope.
        $global:DesignTimeOptimizerSandboxTestState = $script:Azure
        Mock az {
            param($Arguments)
            $state = $global:DesignTimeOptimizerSandboxTestState
            $call = $Arguments -join ' '
            $state.Calls.Add($call)
            $global:LASTEXITCODE = 0
            if ($call -like 'account show*') { $response = $state.Account }
            elseif ($call -like 'provider list*') { $response = $state.Providers }
            elseif ($call -match '/Microsoft.Authorization/permissions\?') { $response = @{ value = $state.Permissions } }
            elseif ($call -match '/Microsoft.Kusto/locations/.*/skus\?') { $response = $state.Skus }
            elseif ($call -like 'quota list*') {
                if ($state.QuotaError) {
                    $global:LASTEXITCODE = 1
                    return $state.QuotaError
                }
                $response = @()
            }
            elseif ($call -like 'cognitiveservices model list*') { $response = $state.Models }
            elseif ($call -like 'cognitiveservices usage list*') { $response = $state.Usage }
            elseif ($call -match '/Microsoft.Storage/storageAccounts/teststorage\?') { $response = @{ name = 'teststorage' } }
            elseif ($call -like 'storage container list*') {
                if ($state.StorageError) { $global:LASTEXITCODE = 1; return $state.StorageError }
                $response = @()
            }
            elseif ($call -match '/Microsoft.Kusto/clusters/testcluster\?') { $response = @{ properties = @{ uri = 'https://testcluster.eastus2.kusto.windows.net' } } }
            elseif ($call -match '/v2/rest/query ') { $response = $state.QueryResult }
            else { throw "Unexpected Azure operation in test: $call" }
            ConvertTo-Json -InputObject $response -Depth 30 -Compress
        }
    }

    It 'Validates configuration offline without claiming deployment readiness' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $result = & $script:Validator -Path $script:ConfigPath -ConfigurationOnly
        $result.ReadyForInfrastructureDeployment | Should -BeFalse
        $result.ReadyForDataIngestion | Should -BeFalse
        Should -Invoke az -Times 0
    }

    It 'Rejects missing, invalid, and expired configuration before contacting Azure' -ForEach @(
        @{ Change = { $script:Config.Remove('region') > $null }; Expected = '*JSON Schema*' }
        @{ Change = { $script:Config.budget.maximumSpend = 0 }; Expected = '*JSON Schema*' }
        @{ Change = { $script:Config.experiments.maximumParallelVariants = 3 }; Expected = '*JSON Schema*' }
        @{ Change = { $script:Config.expiresOn = '2020-01-01T00:00:00Z' }; Expected = '*expiration*' }
        @{ Change = { $script:Config.expiresOn = '2030-02-31T12:00:00Z' }; Expected = '*valid timestamp*' }
    ) {
        & $Change
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        { & $script:Validator -Path $script:ConfigPath } | Should -Throw $Expected
        Should -Invoke az -Times 0
    }

    It 'Rejects missing environment IDs before contacting Azure' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $env:AZURE_CLIENT_ID = ''
        { & $script:Validator -Path $script:ConfigPath } | Should -Throw '*AZURE_CLIENT_ID*'
        Should -Invoke az -Times 0
    }

    It 'Stops when the signed-in identity targets another subscription' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Account.id = '44444444-4444-4444-4444-444444444444'
        { & $script:Validator -Path $script:ConfigPath } | Should -Throw '*configured sandbox deployment identity*'
        Should -Invoke az -Times 1 -Exactly
    }

    It 'Separates infrastructure eligibility from deferred data-plane and runtime access' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $result = & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath
        $result.ReadyForInfrastructureDeployment | Should -BeTrue
        $result.ReadyForDataIngestion | Should -BeFalse
        ($result.Checks | Where-Object Name -EQ 'Data-plane access').Status | Should -Be 'Deferred'
        ($result.Checks | Where-Object Name -EQ 'Model runtime access').Status | Should -Be 'Deferred'
        @($script:Azure.Calls | Where-Object { $_ -match '(group create|provider register|role assignment create|deployment create)' }).Count | Should -Be 0
        Get-Content $script:ReportPath -Raw | Should -Not -Match ([regex]::Escape($env:AZURE_SUBSCRIPTION_ID))
    }

    It 'Blocks administrator prerequisites and honors role exclusions' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Providers[0].registrationState = 'NotRegistered'
        $script:Azure.Permissions[0].notActions = @('Microsoft.Authorization/roleAssignments/*')
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Resource providers, Deployment permissions*'
        $report = Get-Content $script:ReportPath -Raw | ConvertFrom-Json
        $report.ReadyForInfrastructureDeployment | Should -BeFalse
        ($report.Checks | Where-Object Name -EQ 'Deployment permissions').Detail | Should -Match 'roleAssignments/write'
    }

    It 'Does not mistake an unrelated quota meter for model capacity' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Usage[0].name.value = 'unrelated-meter'
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Model capacity*'
    }

    It 'Rejects exhausted model quota and unknown capacity limits' -ForEach @(
        @{ Limit = 10; Current = 10 }
        @{ Limit = $null; Current = 0 }
    ) {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Usage[0].limit = $Limit
        $script:Azure.Usage[0].currentValue = $Current
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Model capacity*'
        $report = Get-Content $script:ReportPath -Raw | ConvertFrom-Json
        $evidence = ($report.Checks | Where-Object Name -EQ 'Model capacity').Evidence
        $evidence.ModelsObserved[0].Skus[0].Usage[0].Limit | Should -Be $Limit
        $evidence.ModelsObserved[0].Skus[0].Usage[0].CurrentValue | Should -Be $Current
    }

    It 'Uses service-specific quota only for an explicitly unsupported generic provider' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.QuotaError = 'This resource provider is not supported by the quota API.'
        $result = & $script:Validator -Path $script:ConfigPath
        ($result.Checks | Where-Object Name -EQ 'Model capacity').Evidence.Source | Should -Match 'explicitly does not support'
        $script:Azure.QuotaError = 'AuthorizationFailed: private-diagnostic-value'
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Model capacity*'
        Get-Content $script:ReportPath -Raw | Should -Not -Match 'private-diagnostic-value'
    }

    It 'Rejects nonstable model versions even when their quota is available' -ForEach @(
        @{ Lifecycle = 'Legacy' }
        @{ Lifecycle = 'Deprecating' }
    ) {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Models[0].model.lifecycleStatus = $Lifecycle
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Model capacity*'
        $report = Get-Content $script:ReportPath -Raw | ConvertFrom-Json
        ($report.Checks | Where-Object Name -EQ 'Model capacity').Evidence.ModelsObserved[0].Lifecycle | Should -Be $Lifecycle
    }

    It 'Does not use fine-tuned model quota to approve a base model deployment' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Usage[0].limit = 0
        $script:Azure.Models[0].model.skus += @{
            name = 'GlobalStandard'; usageName = 'discovered-usage-name-finetune'
            capacity = @{ minimum = 1; maximum = 100; step = 1 }
        }
        $script:Azure.Usage += @{ name = @{ value = 'discovered-usage-name-finetune' }; limit = 100; currentValue = 0 }
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Model capacity*'
    }

    It 'Rejects restricted SKUs and untrusted pagination links' -ForEach @(
        @{ SkuResponse = @{ value = @(@{ name = 'Dev(No SLA)_Standard_E2a_v4'; restrictions = @('restricted') }) } }
        @{ SkuResponse = @{ value = @(); nextLink = 'https://untrusted.example/skus' } }
    ) {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Skus = $SkuResponse
        { & $script:Validator -Path $script:ConfigPath -ReportPath $script:ReportPath } | Should -Throw '*Data Explorer SKU*'
    }

    It 'Requires actual resources before the seeding gate can pass' {
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        { & $script:Validator -Path $script:ConfigPath -RequireDataPlane -ReportPath $script:ReportPath } | Should -Throw '*Data-plane access*'
        $report = Get-Content $script:ReportPath -Raw | ConvertFrom-Json
        $report.ReadyForDataIngestion | Should -BeFalse
    }

    It 'Checks real data access and rejects partial query failures' {
        $script:Config.dataPlane.storageAccountResourceId = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/teststorage"
        $script:Config.dataPlane.dataExplorerResourceId = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/test/providers/Microsoft.Kusto/clusters/testcluster"
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Permissions[0].dataActions = @('Microsoft.Storage/storageAccounts/blobServices/containers/blobs/*')
        $result = & $script:Validator -Path $script:ConfigPath -RequireDataPlane
        $result.ReadyForDataIngestion | Should -BeTrue
        @($script:Azure.Calls | Where-Object { $_ -like 'storage container list*--auth-mode login*' }).Count | Should -Be 1
        @($script:Azure.Calls | Where-Object { $_ -match '/v2/rest/query ' }).Count | Should -Be 2
        @($script:Azure.Calls | Where-Object { $_ -match '/v2/rest/query .*--resource https://api.kusto.windows.net ' }).Count | Should -Be 2
        $script:Azure.QueryResult[0].HasErrors = $true
        { & $script:Validator -Path $script:ConfigPath -RequireDataPlane -ReportPath $script:ReportPath } | Should -Throw '*Data-plane access*'
        (Get-Content $script:ReportPath -Raw | ConvertFrom-Json).ReadyForDataIngestion | Should -BeFalse
    }

    It 'Rejects data-plane resources outside the configured subscription' {
        $script:Config.dataPlane.storageAccountResourceId = '/subscriptions/other/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/teststorage'
        $script:Config.dataPlane.dataExplorerResourceId = '/subscriptions/other/resourceGroups/test/providers/Microsoft.Kusto/clusters/testcluster'
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        { & $script:Validator -Path $script:ConfigPath -RequireDataPlane -ReportPath $script:ReportPath } | Should -Throw '*Data-plane access*'
        (Get-Content $script:ReportPath -Raw | ConvertFrom-Json).Checks |
            Where-Object Name -EQ 'Data-plane access' |
            Select-Object -ExpandProperty Detail |
            Should -Match 'configured sandbox subscription'
    }

    It 'Records a sanitized authentication error code without persisting native credential text' {
        $script:Config.dataPlane.storageAccountResourceId = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/teststorage"
        $script:Config.dataPlane.dataExplorerResourceId = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/test/providers/Microsoft.Kusto/clusters/testcluster"
        $script:Config | ConvertTo-Json -Depth 20 | Set-Content $script:ConfigPath
        $script:Azure.Permissions[0].dataActions = @('*')
        $script:Azure.StorageError = 'ERROR: AADSTS700024: client assertion expired. do-not-record-test-token'
        { & $script:Validator -Path $script:ConfigPath -RequireDataPlane -ReportPath $script:ReportPath } | Should -Throw '*Data-plane access*'
        $text = Get-Content $script:ReportPath -Raw
        $text | Should -Not -Match 'do-not-record-test-token'
        (($text | ConvertFrom-Json).Checks | Where-Object Name -EQ 'Data-plane access').Evidence.ErrorCode | Should -Be 'AADSTS700024'
    }
}

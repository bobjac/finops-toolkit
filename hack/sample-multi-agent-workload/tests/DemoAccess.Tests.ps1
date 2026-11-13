# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . "$PSScriptRoot/../eng/Experiment-Common.ps1"
    $script:entryPoint = "$PSScriptRoot/../eng/Prepare-DemoAccess.ps1"
    $script:demoScope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
    function az { throw 'Azure CLI must not run in unit tests.' }
}

Describe 'Read-only presentation checks and separately approved capture' {
    BeforeEach {
        $script:calls = [Collections.Generic.List[string]]::new()
        $script:identityType = 'user'
        $script:liveRevision = 'a' * 40
        $script:inputRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path "$script:inputRoot/sample", "$script:inputRoot/experiment",
            "$script:inputRoot/seed/seed-evidence-second/foundation" -Force
        @{
            historicalEvidenceVerified = $true; experimentId = 'h09-123'; experimentHash = 'f' * 64
            deploymentRevision = 'a' * 40
            links = @{ application = 'https://ca-ftk-dto-hack-s-ae46.synthetic.eastus2.azurecontainerapps.io/docs' }
        } | ConvertTo-Json -Depth 10 | Set-Content "$script:inputRoot/preparation.json"
        @{
            revision = 'a' * 40
            outputs = @{
                fqdn = @{ value = 'ca-ftk-dto-hack-s-ae46.synthetic.eastus2.azurecontainerapps.io' }
                applicationInsightsResourceId = @{ value = "$script:demoScope/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46" }
                workspaceCustomerId = @{ value = '00000000-0000-0000-0000-000000000001' }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content "$script:inputRoot/sample/deployment-validation.json"
        @(
            @{ experimentId = 'h09-123' }, @{ experimentId = 'h09-123' }, @{ experimentId = 'h09-123' }
        ) | ConvertTo-Json | Set-Content "$script:inputRoot/experiment/runs.json"
        @{
            Status = 'VerifiedAndRetained'
            ResourceGroupId = $script:demoScope.Replace('ftk-dto-hack-s-ae46', 'ftk-dto-hack-foundation')
            Outputs = @{
                clusterUri = 'https://testcluster.eastus2.kusto.windows.net'
                clusterId = "$($script:demoScope.Replace('ftk-dto-hack-s-ae46', 'ftk-dto-hack-foundation'))/providers/Microsoft.Kusto/clusters/testcluster"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content "$script:inputRoot/seed/seed-evidence-second/foundation/foundation.json"
        $script:arguments = @{
            InputDirectory = $script:inputRoot; PreparationFile = "$script:inputRoot/preparation.json"
            OutputFile = "$script:inputRoot/viewer.json"
        }
        Mock Invoke-SampleAz {
            param($Arguments)
            $operation = $Arguments -join ' '
            $script:calls.Add($operation)
            switch -Regex ($operation) {
                '^account show' {
                    return @{
                        id = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
                        tenantId = '3670e846-58dd-4658-86fb-00e4029045d6'
                        user = @{ type = $script:identityType; name = 'do-not-export-identity' }
                    }
                }
                '^group show' { return @{
                    name = 'ftk-dto-hack-s-ae46'
                    tags = @{ repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-sample' }
                } }
                '^containerapp show' { return @{
                    id = "$script:demoScope/providers/Microsoft.App/containerApps/ca-ftk-dto-hack-s-ae46"
                    properties = @{
                        template = @{ containers = @(@{ image = "crftkdtohacksae46.azurecr.io/sample:$script:liveRevision" }) }
                        configuration = @{ activeRevisionsMode = 'Single' }
                        latestReadyRevisionName = 'ready'; latestRevisionName = 'ready'
                    }
                } }
                '^rest ' { return @(
                    @{ FrameType = 'DataTable'; TableKind = 'PrimaryResult'; Rows = ,@(1) }
                    @{ FrameType = 'DataSetCompletion'; HasErrors = $false }
                ) }
                '^keyvault secret show' { return 'synthetic-private-token-12345678901234567890' }
                default { throw "Unexpected operation: $operation" }
            }
        }
        Mock Get-ExperimentTelemetry { @(@{ Name = 'gen_ai.chat' }) }
        Mock Invoke-WebRequest { @{ StatusCode = 200 } }
        $script:case = Get-Content "$PSScriptRoot/evaluation/questions.json" -Raw |
            ConvertFrom-Json | Where-Object { $_.id -ceq 'inventory-below-reorder' }
        Mock Invoke-RestMethod {
            @{
                answerStatus = $script:case.expectedStatus; answer = $script:case.expectedAnswer
                data = $script:case.expectedData
                evidence = @{
                    modelMode = 'azure-openai'; agentCalls = $script:case.expectedCalls
                    rowCount = 2; modelUsage = @(1, 2, 3, 4); traceId = 'a' * 32
                }
            }
        }
    }

    It 'checks viewer access without secret retrieval, paid requests, or resource writes' {
        . $script:entryPoint @script:arguments -WorkbookRendered
        $receipt = Get-Content $script:arguments.OutputFile -Raw | ConvertFrom-Json
        $receipt.identityType | Should -BeExactly 'user'
        $receipt.workbookRendered | Should -BeTrue
        $receipt.ingestionQuery | Should -BeTrue
        Get-Content $script:arguments.OutputFile -Raw | Should -Not -Match 'do-not-export-identity'
        @($script:calls | Where-Object { $_ -match 'keyvault|create|delete|update|set' }).Count | Should -Be 0
        Should -Invoke Get-ExperimentTelemetry -Times 3 -Exactly
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'does not infer successful workbook rendering from query permissions' {
        . $script:entryPoint @script:arguments
        (Get-Content $script:arguments.OutputFile -Raw | ConvertFrom-Json).workbookRendered | Should -BeFalse
    }

    It 'rejects incomplete Ingestion responses without publishing a viewer receipt' {
        Mock Invoke-SampleAz {
            @{ FrameType = 'DataTable'; TableKind = 'PrimaryResult'; Rows = ,@(1) }
        } -ParameterFilter { $Arguments[0] -eq 'rest' }
        { . $script:entryPoint @script:arguments } | Should -Throw '*Ingestion*'
        Test-Path $script:arguments.OutputFile | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects automation as interactive viewer evidence' {
        $script:identityType = 'servicePrincipal'
        { . $script:entryPoint @script:arguments } | Should -Throw '*interactive viewer*'
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'rejects source drift before reading secrets or invoking the application' {
        $script:liveRevision = 'b' * 40
        { . $script:entryPoint @script:arguments -Operation Capture -Confirmation capture-one-inventory-question } |
            Should -Throw '*recorded deployment*'
        @($script:calls | Where-Object { $_ -match 'keyvault' }).Count | Should -Be 0
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'requires explicit paid capture confirmation before any Azure operation' {
        { . $script:entryPoint @script:arguments -Operation Capture } | Should -Throw '*confirmation*'
        $script:calls.Count | Should -Be 0
    }

    It 'captures exactly one approved question without exporting the token' {
        . $script:entryPoint @script:arguments -Operation Capture -Confirmation capture-one-inventory-question
        $json = Get-Content $script:arguments.OutputFile -Raw
        $json | Should -Not -Match 'synthetic-private-token'
        ($json | ConvertFrom-Json).question | Should -BeExactly $script:case.question
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        Should -Invoke Get-ExperimentTelemetry -Times 0
        @($script:calls | Where-Object { $_ -match 'secret set' }).Count | Should -Be 0
    }

    It 'does not retry or create success evidence after a paid-request failure' {
        Mock Invoke-RestMethod { throw 'provider body that must not be logged' }
        { . $script:entryPoint @script:arguments -Operation Capture -Confirmation capture-one-inventory-question } |
            Should -Throw '*No retry was made*'
        Test-Path $script:arguments.OutputFile | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }
}

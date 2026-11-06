# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
    $script:Importer = Join-Path $script:Root 'src/scripts/Import-DesignTimeOptimizerSeed.ps1'
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Importer, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Seed script must parse before testing ingestion helpers.' }
    # Load the actual helper bodies without executing top-level Azure operations.
    foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}

Describe 'Seed staging and ingestion verification' {
    BeforeEach {
        $script:SeedDirectory = $TestDrive
        $script:storageArguments = @('--account-name', 'teststorage', '--auth-mode', 'login')
        $script:seedFilePattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}__seed\.parquet$'
        $script:deadline = [DateTimeOffset]::UtcNow.AddMinutes(1)
        $script:clusterUri = 'https://test.eastus2.kusto.windows.net'
        $script:Calls = [Collections.Generic.List[string]]::new()
        $script:Package = @{
            label = 'history-costs'; dataset = 'Costs'; profile = 'dto-history-v1'
            folder = 'Costs/2024/06/providers/microsoft.billing/billingaccounts/dto-history-v1'
            file = '11111111-1111-4111-8111-111111111111__seed.parquet'
            rowCount = 1; billedCost = 2.5; pricingQuantity = 4
        }
        Mock Invoke-SeedAzure { throw 'Unexpected Azure request.' }
        Mock Get-SeedPipelineRun {}
        Mock Start-Sleep { throw 'Unexpected polling delay.' }
    }

    It 'Uploads parquet before the nonempty manifest and waits on the event-triggered pipeline' {
        Mock Wait-SeedPipeline { if (-not $BeforeUpload) { @{ RunId = 'actual-run'; Status = 'Succeeded' } } }
        Mock Invoke-SeedAzure { $script:Calls.Add($Arguments -join ' ') }
        $result = @(Set-SeedStaging -Package $script:Package -Confirm:$false)
        $result[0].RunId | Should -Be 'actual-run'
        Should -Invoke Invoke-SeedAzure -Times 1 -ParameterFilter { $Arguments[2] -eq 'list' -and ($Arguments -join ' ') -like "*--prefix $($script:Package.folder)/*" }
        Should -Invoke Invoke-SeedAzure -Times 2 -ParameterFilter { $Arguments[2] -eq 'upload' }
        $uploads = @($script:Calls | Where-Object { $_ -like 'storage blob upload*' })
        $uploads[0] | Should -Match '__seed\.parquet'
        $uploads[1] | Should -Match '/manifest\.json'
        $uploads[0] | Should -Match '--no-progress'
        $uploads[1] | Should -Match '--no-progress'
        Should -Invoke Wait-SeedPipeline -Times 1 -ParameterFilter { $BeforeUpload }
        Should -Invoke Wait-SeedPipeline -Times 1 -ParameterFilter { -not $BeforeUpload }
    }

    It 'Refuses an unexpected blob without deleting or uploading anything' {
        Mock Wait-SeedPipeline {}
        Mock Invoke-SeedAzure { @{ name = "$($script:Package.folder)/unrecognized.parquet" } } -ParameterFilter { $Arguments[2] -eq 'list' }
        { Set-SeedStaging -Package $script:Package -Confirm:$false } | Should -Throw '*unrecognized data*'
        Should -Invoke Invoke-SeedAzure -Times 0 -ParameterFilter { $Arguments[2] -in @('delete', 'upload') }
    }

    It 'Deletes only previously recognized files in the exact dedicated folder' {
        Mock Wait-SeedPipeline {}
        Mock Invoke-SeedAzure {}
        Mock Invoke-SeedAzure {
            @(
                @{ name = "$($script:Package.folder)/manifest.json" }
                @{ name = "$($script:Package.folder)/22222222-2222-4222-8222-222222222222__seed.parquet" }
            )
        } -ParameterFilter { $Arguments[2] -eq 'list' }
        Set-SeedStaging -Package $script:Package -Confirm:$false
        Should -Invoke Invoke-SeedAzure -Times 2 -ParameterFilter { $Arguments[2] -eq 'delete' -and ($Arguments -join ' ') -like "*--name $($script:Package.folder)/*" }
    }

    It 'Fails rather than treating an ingestion failure as readiness' {
        Mock Get-SeedPipelineRun { @{ parameters = @{ folderPath = "ingestion/$($script:Package.folder)" }; status = 'Failed' } }
        { Wait-SeedPipeline -Folder $script:Package.folder -Since ([DateTimeOffset]::UtcNow.AddMinutes(-1)) } | Should -Throw '*failed or was cancelled*'
    }

    It 'Times out without claiming a pipeline succeeded' {
        $script:deadline = [DateTimeOffset]::UtcNow.AddSeconds(-1)
        { Wait-SeedPipeline -Folder $script:Package.folder -Since ([DateTimeOffset]::UtcNow) } | Should -Throw '*Timed out*'
    }

    It 'Matches a new successful storage-event run with a trailing folder delimiter' {
        Mock Get-SeedPipelineRun { @{ runId = 'new'; parameters = @{ folderPath = "ingestion/$($script:Package.folder)/" }; status = 'Succeeded' } }
        $runs = @(Wait-SeedPipeline -Folder $script:Package.folder -Since ([DateTimeOffset]::UtcNow.AddMinutes(-1)))
        $runs.Count | Should -Be 1
        $runs[0].RunId | Should -Be 'new'
    }

    It 'Does not mistake the preceding successful ingestion for the new manifest run' {
        Mock Get-SeedPipelineRun { @{ runId = 'previous'; parameters = @{ folderPath = "ingestion/$($script:Package.folder)" }; status = 'Succeeded' } }
        Mock Start-Sleep { $script:deadline = [DateTimeOffset]::UtcNow.AddSeconds(-1) }
        { Wait-SeedPipeline -Folder $script:Package.folder -Since ([DateTimeOffset]::UtcNow.AddMinutes(-1)) -ExcludeRunId previous } | Should -Throw '*Timed out*'
    }

    It 'Rejects duplicate hub rows even when the pipeline succeeded' {
        Mock Get-SeedQuery { @{ Rows = 2; BilledCost = 2.5; PricingQuantity = 4; InvalidTags = 0; InvalidDates = 0 } }
        { Test-SeedTotal -Package $script:Package } | Should -Throw '*row count*'
    }

    It 'Checks scoped totals instead of accepting only the expected count' {
        Mock Get-SeedQuery { @{ Rows = 1; BilledCost = 5; PricingQuantity = 4; InvalidTags = 0; InvalidDates = 0 } }
        { Test-SeedTotal -Package $script:Package } | Should -Throw '*BilledCost*'
    }

    It 'Rejects nonfinite hub totals instead of treating NaN as an equal total' {
        Mock Get-SeedQuery { @{ Rows = 1; BilledCost = [double]::NaN; PricingQuantity = 4; InvalidTags = 0; InvalidDates = 0 } }
        { Test-SeedTotal -Package $script:Package } | Should -Throw '*BilledCost*'
    }

    It 'Verifies applicable price rates and blocks instead of accepting only meter presence' {
        $price = @{
            dataset = 'Prices'; label = 'model-prices'; profile = 'dto-retail-public-v1'; rowCount = 1
            prices = @(@{
                meterId = 'input'; offer = 'PUBLIC-RETAIL'; listPrice = 0.25; contractedPrice = 0.25
                unit = '1M'; blockSize = 1000000; region = 'US East 2'; effectiveStart = '2025-08-01T00:00:00Z'
            })
        }
        Mock Get-SeedQuery {
            @{
                MeterId = 'input'; Offer = 'PUBLIC-RETAIL'; Price = 0.25; ContractedPrice = 0.25
                Currency = 'USD'; Unit = '1M'; BlockSize = 1000000
                Region = 'US East 2'; EffectiveStart = '2025-08-01T00:00:00Z'
            }
        }
        (Test-SeedTotal -Package $price).Rows | Should -Be 1
        $price.prices[0].blockSize = 1000
        { Test-SeedTotal -Package $price } | Should -Throw '*unit coverage*'
    }

    It 'Rejects partial ADX results with error or missing completion frames' {
        Mock Invoke-SeedAzure { @{ FrameType = 'DataTable'; TableKind = 'PrimaryResult'; Columns = @(); Rows = @() } }
        { Get-SeedQuery -Query 'print 1' } | Should -Throw '*incomplete result*'
    }

    It 'Persists false readiness when invalid prepared metadata fails before Azure access' {
        $seed = Join-Path $TestDrive 'bad-seed'
        $null = New-Item -ItemType Directory -Path $seed
        '{"version":0}' | Set-Content (Join-Path $seed 'seed.json')
        $evidence = Join-Path $TestDrive 'failed-evidence'
        { & $script:Importer -SeedDirectory $seed -OutputDirectory $evidence -ConfirmResourceGroup ftk-dto-hack-foundation -Confirm:$false } | Should -Throw '*seed contract*'
        $report = Get-Content (Join-Path $evidence 'seed-report.json') -Raw | ConvertFrom-Json
        $report.Status | Should -Be 'Failed'
        $report.ReadyForSeededHistory | Should -BeFalse
    }
}

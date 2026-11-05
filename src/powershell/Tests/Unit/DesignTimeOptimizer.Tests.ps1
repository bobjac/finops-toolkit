# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
    $script:Validator = Join-Path $script:RepoRoot 'src/scripts/Test-DesignTimeOptimizerExperiment.ps1'
    $script:Schema = Join-Path $script:RepoRoot 'src/design-time-optimizer/schemas/experiment.schema.json'
    $script:Example = Join-Path $script:RepoRoot 'src/design-time-optimizer/examples/sample-api-rightsize.experiment.json'
}

Describe 'Design-time optimizer experiment contract' {
    It 'Ships a valid JSON Schema' {
        { Get-Content $script:Schema -Raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Accepts the sample experiment' {
        $result = & $script:Validator -Path $script:Example

        $result.Valid | Should -BeTrue
        $result.Version | Should -Be 1
        $result.Name | Should -Be 'sample-api-rightsize'
        $result.BaselineRef | Should -Be 'main'
        $result.CandidateRef | Should -Be 'current'
    }

    It 'Rejects identical baseline and candidate refs' {
        $experiment = Get-Content $script:Example -Raw | ConvertFrom-Json -Depth 100
        $experiment.variants.candidate.ref = $experiment.variants.baseline.ref
        $path = Join-Path $TestDrive 'same-ref.experiment.json'
        $experiment | ConvertTo-Json -Depth 100 | Set-Content $path

        { & $script:Validator -Path $path } | Should -Throw '*baseline and candidate refs must be different*'
    }

    It 'Rejects missing required properties' {
        $experiment = Get-Content $script:Example -Raw | ConvertFrom-Json -Depth 100
        $experiment.PSObject.Properties.Remove('cost')
        $path = Join-Path $TestDrive 'missing-cost.experiment.json'
        $experiment | ConvertTo-Json -Depth 100 | Set-Content $path

        { & $script:Validator -Path $path } | Should -Throw '*is invalid*'
    }

    It 'Rejects a cleanup lifetime that cannot cover the load stages' {
        $experiment = Get-Content $script:Example -Raw | ConvertFrom-Json -Depth 100
        $experiment.load.warmupMinutes = 5
        $experiment.load.durationMinutes = 10
        $experiment.cleanup.maximumLifetimeMinutes = 15
        $path = Join-Path $TestDrive 'short-lifetime.experiment.json'
        $experiment | ConvertTo-Json -Depth 100 | Set-Content $path

        { & $script:Validator -Path $path } | Should -Throw '*maximumLifetimeMinutes must be greater*'
    }

    It 'Can verify referenced load-test files' {
        $experiment = Get-Content $script:Example -Raw | ConvertFrom-Json -Depth 100
        $experiment.load.testFile = 'load/test.jmx'
        $path = Join-Path $TestDrive 'referenced-file.experiment.json'
        $loadDirectory = Join-Path $TestDrive 'load'
        New-Item $loadDirectory -ItemType Directory | Out-Null
        Set-Content (Join-Path $loadDirectory 'test.jmx') '<jmeterTestPlan />'
        $experiment | ConvertTo-Json -Depth 100 | Set-Content $path

        { & $script:Validator -Path $path -CheckReferencedFiles } | Should -Not -Throw
    }
}

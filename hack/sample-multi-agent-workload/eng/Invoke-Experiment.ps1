# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Builds and measures two baseline passes and one candidate in temporary apps.
    .PARAMETER BaselineRevision
    Exact fork dev ancestor used as the baseline.
    .PARAMETER CandidateRevision
    Different exact fork dev ancestor used as the candidate.
    .PARAMETER SampleDirectory
    Verified successful sample deployment artifact directory.
    .PARAMETER SeedDirectory
    Verified successful seed artifact directory with fresh model prices.
    .PARAMETER OutputDirectory
    Sanitized, retained experiment evidence directory.
    .EXAMPLE
    ./eng/Invoke-Experiment.ps1 -BaselineRevision $baseline -CandidateRevision $candidate `
        -SampleDirectory .tmp/sample -SeedDirectory .tmp/seed -OutputDirectory .tmp/experiment
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$BaselineRevision,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$CandidateRevision,
    [Parameter(Mandatory)][string]$SampleDirectory,
    [Parameter(Mandatory)][string]$SeedDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
. "$PSScriptRoot/Experiment-Common.ps1"
$root = (Resolve-Path "$PSScriptRoot/../../..").Path
$sampleRoot = (Resolve-Path "$PSScriptRoot/..").Path
$group = 'ftk-dto-hack-s-ae46'
$scope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -cne 'bobjac/finops-toolkit' -or
    $env:GITHUB_REF -cne 'refs/heads/dev' -or $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{1,12}$') {
    throw 'Use the approved fork dev experiment workflow and sandbox environment.'
}
$runId = $env:GITHUB_RUN_ID
$experimentId = "h09-$runId"
$expires = [DateTimeOffset]::UtcNow.AddMinutes(90)
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$sourceVerification = & python -m sample_workload.experiment_sources --baseline $BaselineRevision --candidate $CandidateRevision
if ($LASTEXITCODE -ne 0) { throw 'Exact source equivalence verification failed.' }
$sourceVerification | Set-Content "$OutputDirectory/source-verification.json"
$spec = Get-Content "$sampleRoot/experiments/schema-context.experiment.json" -Raw | ConvertFrom-Json
$spec.variants.baseline.ref = $BaselineRevision
$spec.variants.candidate.ref = $CandidateRevision
$spec | ConvertTo-Json -Depth 20 | Set-Content "$OutputDirectory/definition.json"
& "$root/src/scripts/Test-DesignTimeOptimizerExperiment.ps1" -Path "$OutputDirectory/definition.json" | Out-Null
$conditions = @{
    source = $sourceVerification | ConvertFrom-Json
    policy = $spec | Select-Object adapter, workloadUnit, scope, load, guardrails, cost, cleanup
    runtime = @{ cpu = 0.25; memory = '0.5Gi'; replicas = 1; seed = 42; model = 'gpt-5-mini'; modelVersion = '2025-08-07'; sku = 'GlobalStandard' }
    controller = @{}
}
foreach ($path in @('src/sample_workload/experiment.py', 'src/sample_workload/experiment_load.py', 'src/sample_workload/experiment_sources.py', 'infra/experiment.bicep', 'infra/modules/container-app.bicep', 'eng/Invoke-Experiment.ps1', 'eng/Experiment-Common.ps1')) {
    $conditions.controller[$path] = (Get-FileHash "$sampleRoot/$path" -Algorithm SHA256).Hash
}
$conditions | ConvertTo-Json -Depth 30 | Set-Content "$OutputDirectory/conditions.json"
$conditionsHash = (Get-FileHash "$OutputDirectory/conditions.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$conditionsHash | Set-Content "$OutputDirectory/conditions.sha256"
$reportPath = Join-Path $SampleDirectory 'deployment-validation.json'
$checkpoint = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
Assert-SampleCheckpoint -Checkpoint $checkpoint -Revision $checkpoint.revision -RunId $checkpoint.runId -PreviousStage Validation -Scope $scope
if ($checkpoint.liveVerified -ne $true) { throw 'The retained sample must have verified live acceptance.' }
$outputs = $checkpoint.outputs
if ($outputs.modelEndpoint.value -cnotmatch '^https://oai-ftk-dto-hack-s-ae46[.]openai[.]azure[.]com/?$' -or
    $outputs.modelDeployment.value -cne 'gpt-5-mini') {
    throw 'The model endpoint/deployment must match the verified sandbox.'
}
Assert-SampleAccount (Invoke-SampleAz @('account', 'show'))
Assert-SampleOwnership (Invoke-SampleAz @('group', 'show', '--name', $group))
$model = Invoke-SampleAz @('cognitiveservices', 'account', 'deployment', 'show', '--resource-group', $group, '--name', 'oai-ftk-dto-hack-s-ae46', '--deployment-name', $outputs.modelDeployment.value)
if ($model.properties.model.name -cne 'gpt-5-mini' -or $model.properties.model.version -cne '2025-08-07' -or $model.sku.name -cne 'GlobalStandard' -or $model.sku.capacity -ne 10) {
    throw 'The existing model version, SKU, or capacity differs from the controlled conditions.'
}
$pricing = & "$root/src/scripts/Get-DesignTimeOptimizerContext.ps1" -Tool get_current_pricing -SeedDirectory $SeedDirectory -Scope $scope
$pricing | ConvertTo-Json -Depth 30 | Set-Content "$OutputDirectory/pricing.json"
$pricePreflight = @'
import json
import sys
from datetime import UTC, datetime, timedelta
from sample_workload.experiment import price_rows, validate_definition
with open(sys.argv[1]) as source:
    validate_definition(json.load(source))
with open(sys.argv[2]) as source:
    prices = json.load(source)
now = datetime.now(UTC)
for offset in (0, 90):
    rates, errors = price_rows(prices, now + timedelta(minutes=offset))
    if len(rates) != 3 or errors:
        raise ValueError("Fresh prices must cover the entire approved experiment lifetime.")
'@
& python -c $pricePreflight "$OutputDirectory/definition.json" "$OutputDirectory/pricing.json"
if ($LASTEXITCODE -ne 0) { throw 'Approved policy and fresh, complete prices are required before any deployment.' }
$retainedBefore = Invoke-SampleAz @('containerapp', 'show', '--resource-group', $group, '--name', 'ca-ftk-dto-hack-s-ae46')
$retainedImage = $retainedBefore.properties.template.containers[0].image
$plan = @{ runId = $runId; experimentId = $experimentId; expiresOn = $expires.ToString('o'); apps = @('baseline', 'candidate' | ForEach-Object { Get-ExperimentAppName -RunId $runId -Variant $_ }); retainedAppImage = $retainedImage }
$plan | ConvertTo-Json | Set-Content "$OutputDirectory/ownership-plan.json"
if (-not $PSCmdlet.ShouldProcess("$group/$experimentId", 'Build two images, deploy two temporary apps, send at most 24 requests / 96 model calls, then delete only these apps')) {
    throw 'The bounded paid experiment was not approved.'
}
$runs = [Collections.Generic.List[object]]::new()
$parameterPath = Join-Path $env:RUNNER_TEMP "experiment-$runId.parameters.private"
$context = $null
try {
    $apps = @(Invoke-SampleAz @('containerapp', 'list', '--resource-group', $group))
    if (@($apps | Where-Object { $_.name -cin $plan.apps }).Count) {
        throw 'A planned temporary name already exists. Cleanup will verify ownership before deletion; rerun only after it succeeds.'
    }
    $identity = Invoke-SampleAz @('identity', 'show', '--resource-group', $group, '--name', 'id-ftk-dto-hack-s-ae46')
    $insights = Invoke-SampleAz @('resource', 'show', '--ids', $outputs.applicationInsightsResourceId.value, '--api-version', '2020-02-02')
    $connection = [string]$insights.properties.ConnectionString
    if (-not $connection) { throw 'The existing Application Insights connection is missing.' }
    Write-Information "::add-mask::$connection" -InformationAction Continue
    $env:SAMPLE_API_TOKEN = Get-SampleApiToken -VaultName 'kv-ftk-dto-hack-s-ae46' -OutputDirectory $OutputDirectory
    foreach ($variant in 'baseline', 'candidate') {
        if ([DateTimeOffset]::UtcNow.AddMinutes(25) -gt $expires) { throw 'Insufficient experiment lifetime remains for measurement and cleanup.' }
        $revision = $spec.variants.$variant.ref
        $name = Get-ExperimentAppName -RunId $runId -Variant $variant
        $context = Join-Path $env:RUNNER_TEMP "experiment-$runId-$variant"
        $null = New-Item -ItemType Directory -Path $context -Force
        $archive = Join-Path $context 'source.tar'
        & git archive --format=tar "--output=$archive" "${revision}:hack/sample-multi-agent-workload"
        if ($LASTEXITCODE -ne 0) { throw 'Exact source archive failed.' }
        & tar -xf $archive -C $context
        if ($LASTEXITCODE -ne 0) { throw 'Exact source extraction failed.' }
        Remove-Item -LiteralPath $archive -Force
        $tag = "experiment:$runId-$env:GITHUB_RUN_ATTEMPT-$variant"
        Invoke-SampleAz @('acr', 'build', '--registry', 'crftkdtohacksae46', '--image', $tag, '--no-logs', '--timeout', '900', '--file', "$context/Dockerfile", $context) | Out-Null
        $manifest = Invoke-SampleAz @('acr', 'repository', 'show', '--name', 'crftkdtohacksae46', '--image', $tag)
        if ($manifest.digest -cnotmatch '^sha256:[a-f0-9]{64}$') { throw 'The experiment build has no immutable digest.' }
        $image = "crftkdtohacksae46.azurecr.io/experiment@$($manifest.digest)"
        @{ variant = $variant; revision = $revision; image = $image; tag = $tag } | ConvertTo-Json | Set-Content "$OutputDirectory/image-$variant.json"
        $tags = @{
            repository = 'bobjac/finops-toolkit'; 'ftk-tool' = 'design-time-optimizer-experiment'
            revision = $revision; 'experiment-run-id' = $runId; 'experiment-id' = $experimentId
            variant = $variant; 'expires-on' = $expires.ToString('o')
        }
        $parameters = @{ appName = $name; image = $image; identityClientId = $identity.clientId; appInsightsConnectionString = $connection; modelEndpoint = $outputs.modelEndpoint.value; modelDeployment = $outputs.modelDeployment.value; tags = $tags }
        $deploymentParameters = @{}
        foreach ($key in $parameters.Keys) { $deploymentParameters[$key] = @{ value = $parameters[$key] } }
        @{ parameters = $deploymentParameters } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterPath
        $arguments = @('deployment', 'group', 'what-if', '--resource-group', $group, '--name', $name, '--template-file', "$sampleRoot/infra/experiment.bicep", '--parameters', "@$parameterPath")
        $preview = Invoke-SampleAz ($arguments + @('--no-pretty-print', '--result-format', 'FullResourcePayloads'))
        Assert-ExperimentPreview -Preview $preview -AppName $name
        $arguments[2] = 'create'
        $deployment = Invoke-SampleAz $arguments
        Remove-Item -LiteralPath $parameterPath -Force
        $app = Invoke-SampleAz @('containerapp', 'show', '--resource-group', $group, '--name', $name)
        Assert-ExperimentApp -App $app -RunId $runId -Name $name
        if ($app.tags.revision -cne $revision -or
            [DateTimeOffset]$app.tags.'expires-on' -ne $expires -or
            $app.properties.template.containers[0].image -cne $image -or $app.properties.template.scale.minReplicas -ne 1 -or
            $app.properties.template.scale.maxReplicas -ne 1 -or
            $app.properties.template.containers[0].resources.cpu -ne 0.25 -or
            $app.properties.template.containers[0].resources.memory -cne '0.5Gi') {
            throw 'The running image, compute, or replica bounds differ from the controlled conditions.'
        }
        $fqdn = [string]$deployment.properties.outputs.fqdn.value
        if ($fqdn -cne $app.properties.configuration.ingress.fqdn) { throw 'The temporary endpoint differs from the verified deployment.' }
        Wait-SampleReady -BaseUri "https://$fqdn"
        $repetitions = if ($variant -ceq 'baseline') { 2 } else { 1 }
        for ($repetition = 1; $repetition -le $repetitions; $repetition++) {
            $arguments = @('-m', 'sample_workload.experiment_load', '--base-uri', "https://$fqdn", '--application-name', $name, '--questions', "$sampleRoot/tests/evaluation/questions.json", '--experiment-id', $experimentId, '--variant', $variant, '--repetition', "$repetition", '--revision', $revision, '--image', $image, '--conditions-hash', $conditionsHash)
            & python @arguments --warmup --output "$OutputDirectory/warmup-$variant-$repetition.json"
            if ($LASTEXITCODE -ne 0) { throw 'The bounded experiment warm-up failed.' }
            $path = "$OutputDirectory/run-$variant-$repetition.json"
            & python @arguments --output $path
            $loadExit = $LASTEXITCODE
            if (Test-Path -LiteralPath $path) {
                $run = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                $run.telemetry = @(Get-ExperimentTelemetry -Run $run -WorkspaceId $outputs.workspaceCustomerId.value -AppInsightsId $outputs.applicationInsightsResourceId.value)
                $run | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path
                $runs.Add($run)
                ConvertTo-Json -InputObject @($runs.ToArray()) -Depth 40 | Set-Content "$OutputDirectory/runs.json"
            }
            if ($loadExit -ne 0) { throw 'The measured experiment load was incomplete; no acceptance is possible.' }
        }
        & "$PSScriptRoot/Remove-Experiment.ps1" -RunId $runId -OutputDirectory $OutputDirectory -Confirm:$false
    }
}
finally {
    Remove-Item Env:SAMPLE_API_TOKEN -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $parameterPath) { Remove-Item -LiteralPath $parameterPath -Force }
    & "$PSScriptRoot/Remove-Experiment.ps1" -RunId $runId -OutputDirectory $OutputDirectory -Confirm:$false
    $retainedAfter = Invoke-SampleAz @('containerapp', 'show', '--resource-group', $group, '--name', 'ca-ftk-dto-hack-s-ae46')
    if ($retainedAfter.properties.template.containers[0].image -cne $retainedImage) {
        throw 'The retained demo app changed during the experiment; investigate before interpreting results.'
    }
}

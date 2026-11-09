# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Infrastructure', 'Image', 'Application', 'Validation')][string]$Stage,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Revision,
    [Parameter(Mandatory)][Guid]$DeployerObjectId,
    [Parameter(Mandatory)][ValidateSet('ftk-dto-hack-s-ae46')][string]$ConfirmResourceGroup,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$CheckpointPath
)

. "$PSScriptRoot/Sample-Common.ps1"
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'bobjac/finops-toolkit' -or
    $env:GITHUB_REF -ne 'refs/heads/dev') {
    throw 'Deploy through the approved fork dev workflow and sandbox environment.'
}
$sample = Split-Path $PSScriptRoot -Parent
$config = Get-Content "$sample/../sandbox.config.json" -Raw | ConvertFrom-Json
$scope = "/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/$ConfirmResourceGroup"
if ([DateTimeOffset]::Parse($config.expiresOn) -le [DateTimeOffset]::UtcNow) {
    throw 'The sandbox has expired. Refusing paid deployment.'
}
if ($config.version -ne 1 -or $config.sampleRepository -ne 'bobjac/finops-toolkit' -or
    $config.samplePath -ne 'hack/sample-multi-agent-workload' -or
    $config.region -ne 'eastus2' -or $config.budget.currency -ne 'USD' -or
    $config.budget.maximumSpend -le 0 -or $config.budget.maximumSpend -gt 300 -or
    $config.model.ownership -ne 'sandbox' -or
    $config.model.deploymentSku -ne 'GlobalStandard' -or
    $config.model.preferredNames -notcontains 'gpt-5-mini' -or
    $config.model.minimumCapacity -le 0 -or $config.model.minimumCapacity -gt 10) {
    throw 'The sandbox configuration does not match the approved deployment plan.'
}
if (-not $env:SAMPLE_PRICE_EVIDENCE) { throw 'Verified model and Analytics price evidence is missing.' }
$prices = Assert-SamplePrice $env:SAMPLE_PRICE_EVIDENCE
if ($DeployerObjectId -eq [Guid]::Empty) { throw 'The deployment principal object ID is missing.' }
$current = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $current -ne $Revision) { throw 'The checkout does not match the approved CI revision.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$report = @{
    version = 1; stage = $Stage
    revision = $Revision; resourceGroup = $ConfirmResourceGroup
    subscriptionId = '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a'
    runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT; status = 'Running'
    startedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    prices = $prices; expiresOn = $config.expiresOn
    budgetIsBillingCap = $false; expirationDeletesResources = $false
}
$reportPath = Join-Path $OutputDirectory "deployment-$($Stage.ToLowerInvariant()).json"
$report | ConvertTo-Json -Depth 12 | Set-Content $reportPath
try {
    if ($Stage -ne 'Infrastructure') {
        if (-not $CheckpointPath) { throw 'The completed prerequisite checkpoint is required.' }
        $previousStage = @{ Image = 'Infrastructure'; Application = 'Image'; Validation = 'Application' }[$Stage]
        $checkpoint = Get-Content -LiteralPath $CheckpointPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-SampleCheckpoint -Checkpoint $checkpoint -Revision $Revision -RunId $env:GITHUB_RUN_ID `
            -PreviousStage $previousStage -Scope $scope
        $report.outputs = $checkpoint.outputs
        if ($checkpoint.image) { $report.image = $checkpoint.image }
    }
    $account = Invoke-SampleAz @('account', 'show')
    Assert-SampleAccount $account
    $groupExists = Invoke-SampleAz @('group', 'exists', '--name', $ConfirmResourceGroup)
    $report.resourceGroupExistedBefore = [bool]$groupExists
    if ($groupExists) {
        Assert-SampleOwnership (Invoke-SampleAz @('group', 'show', '--name', $ConfirmResourceGroup))
    }
    elseif ($Stage -ne 'Infrastructure') {
        throw 'The owned sample group is missing. Complete the infrastructure stage first.'
    }
    $placeholder = if ($Stage -eq 'Infrastructure') { 'true' } else { 'false' }
    $arguments = @(
        'deployment', 'sub', 'create', '--name', "sample-$($Revision.Substring(0, 12))-$($Stage.ToLowerInvariant())",
        '--location', $config.region, '--template-file', "$sample/infra/main.bicep",
        '--parameters', "@$sample/infra/main.parameters.json",
        "deployerObjectId=$DeployerObjectId", "revision=$Revision",
        "expiresOn=$($config.expiresOn)", "isPlaceholder=$placeholder"
    )
    switch ($Stage) {
        'Infrastructure' {
            $report.preview = @(Get-SamplePreview -Arguments $arguments -Scope $scope)
            $deployment = Invoke-SampleAz $arguments
            $report.outputs = $deployment.properties.outputs
            Assert-SampleOwnership (Invoke-SampleAz @('group', 'show', '--name', $ConfirmResourceGroup))
        }
        'Image' {
            $registry = $report.outputs.registryName.value
            Invoke-SampleAz @('acr', 'build', '--registry', $registry, '--image', "sample:$Revision",
                '--no-logs', $sample) | Out-Null
            $report.image = "$($report.outputs.registryLoginServer.value)/sample:$Revision"
        }
        'Application' {
            Get-SampleApiToken -VaultName $report.outputs.keyVaultName.value `
                -OutputDirectory $OutputDirectory -CreateIfMissing | Out-Null
            $arguments += "containerImage=$($report.image)"
            $report.preview = @(Get-SamplePreview -Arguments $arguments -Scope $scope)
            $deployment = Invoke-SampleAz $arguments
            $report.outputs = $deployment.properties.outputs
        }
        'Validation' {
            $revisionReady = $false
            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                $app = Invoke-SampleAz @('containerapp', 'show', '--name', $report.outputs.containerAppName.value,
                    '--resource-group', $ConfirmResourceGroup)
                if ($app.properties.template.containers[0].image -cne $report.image -or
                    $app.properties.configuration.ingress.fqdn -ne $report.outputs.fqdn.value) {
                    throw 'Live validation requires the approved image and owned application endpoint.'
                }
                if ($app.properties.latestReadyRevisionName -and
                    $app.properties.latestReadyRevisionName -eq $app.properties.latestRevisionName) {
                    $revisionReady = $true
                    break
                }
                Start-Sleep -Seconds 3
            }
            if (-not $revisionReady) { throw 'The approved application revision did not become ready.' }
            $apiToken = Get-SampleApiToken -VaultName $report.outputs.keyVaultName.value `
                -OutputDirectory $OutputDirectory
            & "$PSScriptRoot/Collect-Evidence.ps1" -BaseUri "https://$($report.outputs.fqdn.value)" `
                -ApiToken $apiToken -ApplicationInsightsResourceId $report.outputs.applicationInsightsResourceId.value `
                -WorkspaceCustomerId $report.outputs.workspaceCustomerId.value `
                -OutputDirectory $OutputDirectory
            $report.liveVerified = $true
        }
    }
    $report.status = 'Completed'
    Assert-SampleCheckpoint -Checkpoint $report -Revision $Revision -RunId $env:GITHUB_RUN_ID `
        -PreviousStage $Stage -Scope $scope
}
catch {
    $report.status = 'FailedResourcesMayBeRetained'
    # Never automatically delete a group that may contain a previous successful deployment.
    throw
}
finally {
    $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 12 | Set-Content $reportPath
}

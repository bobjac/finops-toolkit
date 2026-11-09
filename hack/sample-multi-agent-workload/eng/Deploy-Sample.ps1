# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Revision,
    [Parameter(Mandatory)][Guid]$DeployerObjectId,
    [Parameter(Mandatory)][ValidateSet('ftk-dto-hack-s-ae46')][string]$ConfirmResourceGroup,
    [Parameter(Mandatory)][string]$OutputDirectory
)

. "$PSScriptRoot/Sample-Common.ps1"
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REPOSITORY -ne 'bobjac/finops-toolkit' -or
    $env:GITHUB_REF -ne 'refs/heads/dev') {
    throw 'Deploy through the approved fork dev workflow and sandbox environment.'
}
$sample = Split-Path $PSScriptRoot -Parent
$config = Get-Content "$sample/../sandbox.config.json" -Raw | ConvertFrom-Json
$account = Invoke-SampleAz @('account', 'show')
Assert-SampleAccount $account
$scope = "/subscriptions/$($account.id)/resourceGroups/$ConfirmResourceGroup"
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
$groupExists = Invoke-SampleAz @('group', 'exists', '--name', $ConfirmResourceGroup)
if ($groupExists) {
    Assert-SampleOwnership (Invoke-SampleAz @('group', 'show', '--name', $ConfirmResourceGroup))
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$report = @{
    revision = $Revision; resourceGroup = $ConfirmResourceGroup
    subscriptionId = $account.id; createdThisRun = -not $groupExists
    runId = $env:GITHUB_RUN_ID; status = 'Deploying'
    prices = $prices; expiresOn = $config.expiresOn
    budgetIsBillingCap = $false; expirationDeletesResources = $false
}
$tokenFile = Join-Path $OutputDirectory 'api-token.private'
try {
    $arguments = @(
        'deployment', 'sub', 'create', '--name', "sample-$($Revision.Substring(0, 12))",
        '--location', $config.region, '--template-file', "$sample/infra/main.bicep",
        '--parameters', "@$sample/infra/main.parameters.json",
        "deployerObjectId=$DeployerObjectId", "revision=$Revision",
        "expiresOn=$($config.expiresOn)", 'isPlaceholder=true'
    )
    $report.bootstrapPreview = @(Get-SamplePreview -Arguments $arguments -Scope $scope)
    $bootstrap = Invoke-SampleAz $arguments
    $outputs = $bootstrap.properties.outputs
    Assert-SampleOwnership (Invoke-SampleAz @('group', 'show', '--name', $ConfirmResourceGroup))
    $vault = $outputs.keyVaultName.value
    $secretExists = Invoke-SampleAz @('keyvault', 'secret', 'list', '--vault-name', $vault,
        '--query', "[?name=='sample-api-token'].name")
    if ($secretExists) {
        $secret = Invoke-SampleAz @('keyvault', 'secret', 'show', '--vault-name', $vault,
            '--name', 'sample-api-token')
        $apiToken = $secret.value
    }
    else {
        $apiToken = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
        Write-Output "::add-mask::$apiToken"
        [IO.File]::WriteAllText($tokenFile, $apiToken)
        Invoke-SampleAz @('keyvault', 'secret', 'set', '--vault-name', $vault,
            '--name', 'sample-api-token', '--file', $tokenFile) | Out-Null
    }
    Write-Output "::add-mask::$apiToken"
    $registry = $outputs.registryName.value
    $image = "$($outputs.registryLoginServer.value)/sample:$Revision"
    Invoke-SampleAz @('acr', 'build', '--registry', $registry, '--image', "sample:$Revision",
        '--no-logs', $sample) | Out-Null
    $arguments[-1] = 'isPlaceholder=false'
    $arguments += "containerImage=$image"
    $report.runtimePreview = @(Get-SamplePreview -Arguments $arguments -Scope $scope)
    $deployment = Invoke-SampleAz $arguments
    $outputs = $deployment.properties.outputs
    $report.outputs = $outputs
    & "$PSScriptRoot/Collect-Evidence.ps1" -BaseUri "https://$($outputs.fqdn.value)" `
        -ApiToken $apiToken -ApplicationInsightsResourceId $outputs.applicationInsightsResourceId.value `
        -WorkspaceCustomerId $outputs.workspaceCustomerId.value `
        -OutputDirectory $OutputDirectory
    $report.status = 'VerifiedAndRetained'
}
catch {
    $report.status = 'FailedResourcesMayBeRetained'
    # Never automatically delete a group that may contain a previous successful deployment.
    throw
}
finally {
    if (Test-Path -LiteralPath $tokenFile) { Remove-Item -LiteralPath $tokenFile -Force }
    $report | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'deployment.json')
}

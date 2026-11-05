# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Deploys, verifies, or removes the owned hack foundation using Azure CLI.

    .DESCRIPTION
    Uses the sandbox environment identity and the canonical built FinOps hub.
    Deploy and Remove require the exact resource group name as confirmation.
    Successful deployments are retained. The workflow removes a failed new group,
    but never automatically removes an existing foundation after failed redeployment.
    Removal remains available after expiration and does not require model quota.

    .PARAMETER Operation
    Deploy, Verify (default), or Remove.

    .PARAMETER Path
    Sandbox configuration JSON.

    .PARAMETER OutputDirectory
    Directory for nonsecret evidence and the resolved ingestion configuration.

    .PARAMETER TemplateFile
    Compiled hack foundation template produced after Build-Toolkit.

    .PARAMETER ConfirmResourceGroup
    Exact deterministic group name, required for Deploy and Remove.

    .PARAMETER DeploymentPasses
    Number of deployment and verification passes. Use two to validate redeployment.

    .PARAMETER DeferDataPlaneVerification
    Verifies deployment metadata only and reports data-plane readiness as false.
    Allows workflows to refresh OIDC sign-in after long deployments, then Verify.

    .EXAMPLE
    ./src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1 -Operation Verify

    Verifies the retained foundation without changing Azure resources.

    .EXAMPLE
    ./src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1 -Operation Remove -ConfirmResourceGroup ftk-dto-hack-foundation -WhatIf

    Shows the removal plan without accessing Azure or deleting resources.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Deploy', 'Verify', 'Remove')][string]$Operation = 'Verify',
    [string]$Path = (Join-Path $PSScriptRoot '../../hack/sandbox.config.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../.tmp/foundation'),
    [string]$TemplateFile = (Join-Path $PSScriptRoot '../../release/hack-foundation.json'),
    [string]$ConfirmResourceGroup,
    [ValidateRange(1, 2)][int]$DeploymentPasses = 1,
    [switch]$DeferDataPlaneVerification
)

$ErrorActionPreference = 'Stop'
$content = Get-Content -LiteralPath $Path -Raw
$schema = Join-Path $PSScriptRoot '../design-time-optimizer/schemas/sandbox.schema.json'
if (-not ($content | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue))
{
    throw 'Sandbox configuration does not match the sandbox JSON Schema.'
}
$config = $content | ConvertFrom-Json -AsHashtable -Depth 30
if ($DeferDataPlaneVerification -and $Operation -ne 'Deploy')
{
    throw 'DeferDataPlaneVerification is only valid for Deploy; run Verify separately after refreshing sign-in.'
}
foreach ($name in 'AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID')
{
    $identifier = [guid]::Empty
    if (-not [guid]::TryParse([Environment]::GetEnvironmentVariable($name), [ref]$identifier) -or $identifier -eq [guid]::Empty)
    {
        throw "$name must contain the expected nonempty sandbox GUID."
    }
}
$subscription = $env:AZURE_SUBSCRIPTION_ID
$groupName = "$($config.resourceGroupPrefix)-foundation"
$groupId = "/subscriptions/$subscription/resourceGroups/$groupName"
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($groupId.ToLowerInvariant()))).Substring(0, 12).ToLowerInvariant()
$ownership = @{
    'ftk-owner' = 'bobjac/finops-toolkit'
    'ftk-component' = 'dto-foundation'
    'ftk-sandbox' = $hash
}
if ($Operation -ne 'Verify' -and $ConfirmResourceGroup -cne $groupName)
{
    throw "Enter the exact resource group name '$groupName' to confirm $Operation."
}
if ($WhatIfPreference)
{
    $null = $PSCmdlet.ShouldProcess($groupId, $Operation)
    return [pscustomobject]@{ Operation = $Operation; ResourceGroup = $groupName; ResourceGroupId = $groupId; Ownership = $ownership }
}

function Invoke-FoundationAzure
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & az @Arguments --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        # Azure resource errors are needed to diagnose policy and provisioning failures.
        throw "Azure CLI failed during '$($Arguments[0..1] -join ' ')' (exit $LASTEXITCODE): $($output -join "`n")"
    }
    if ($output) { ($output -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100 }
}

function Assert-FoundationOwnership
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Group)

    foreach ($key in $ownership.Keys)
    {
        if (-not $Group.tags -or $Group.tags[$key] -cne $ownership[$key])
        {
            throw "Refusing to adopt, modify, or remove '$groupName': ownership tag '$key' does not match."
        }
    }
    if ($Group.id -ne $groupId -or $Group.location -ne $config.region)
    {
        throw 'Foundation resource group identity or location does not match the configuration.'
    }
}

function Save-FoundationReport
{
    [CmdletBinding()]
    param()
    $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $reportPath
}

function Test-FoundationDeployment
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Outputs)

    foreach ($key in 'storageAccountId', 'clusterId')
    {
        if (-not $Outputs[$key].value -or -not $Outputs[$key].value.StartsWith("$groupId/providers/", [StringComparison]::OrdinalIgnoreCase))
        {
            throw "Deployment output '$key' is missing or outside the owned resource group."
        }
    }
    if ($Outputs.hubDbName.value -cne 'Hub' -or $Outputs.ingestionDbName.value -cne 'Ingestion')
    {
        throw 'The foundation must expose Hub and Ingestion databases.'
    }
    $resources = @(Invoke-FoundationAzure -Arguments @('resource', 'list', '--resource-group', $groupName, '--subscription', $subscription))
    foreach ($resource in $resources | Where-Object { $_.type -in @('Microsoft.Storage/storageAccounts', 'Microsoft.Kusto/clusters', 'Microsoft.DataFactory/factories', 'Microsoft.KeyVault/vaults', 'Microsoft.ManagedIdentity/userAssignedIdentities') })
    {
        foreach ($key in @($ownership.Keys) + @('ftk-expires-on', 'ftk-source'))
        {
            if (-not $resource.tags[$key] -or $resource.tags[$key] -cne $group.tags[$key])
            {
                throw "Resource '$($resource.id)' has missing or inconsistent tag '$key'."
            }
        }
    }
    foreach ($database in 'Hub', 'Ingestion')
    {
        $databaseResource = Invoke-FoundationAzure -Arguments @('rest', '--method', 'get', '--url', "https://management.azure.com$($Outputs.clusterId.value)/databases/${database}?api-version=2025-02-14")
        if ($databaseResource.properties.provisioningState -ne 'Succeeded') { throw "Database '$database' is not successfully provisioned." }
        # ADX grants its database creator Admin automatically; a second ARM assignment conflicts.
        $assignments = Invoke-FoundationAzure -Arguments @('rest', '--method', 'get', '--url', "https://management.azure.com$($Outputs.clusterId.value)/databases/$database/principalAssignments?api-version=2025-02-14")
        $admins = @($assignments.value | Where-Object {
                $_.properties.principalId -and $_.properties.principalType -eq 'App' -and $_.properties.role -eq 'Admin' -and
                $_.properties.tenantId -eq $env:AZURE_TENANT_ID -and
                $_.properties.principalId -in @($env:AZURE_CLIENT_ID, $Outputs.workflowObjectId.value)
            })
        if (-not $admins.Count) { throw "The workflow identity has no verified Admin assignment on database '$database'." }
    }
    $resolved = $config.Clone()
    $resolved.dataPlane = @{
        storageAccountResourceId = $Outputs.storageAccountId.value
        dataExplorerResourceId = $Outputs.clusterId.value
        database = $Outputs.hubDbName.value
    }
    $resolvedPath = Join-Path $OutputDirectory 'sandbox.resolved.json'
    $resolved | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resolvedPath
    if (-not $DeferDataPlaneVerification)
    {
        for ($attempt = 1; $attempt -le 6; $attempt++)
        {
            try
            {
                $readiness = & "$PSScriptRoot/Test-DesignTimeOptimizerSandbox.ps1" -Path $resolvedPath -RequireDataPlane -ReportPath (Join-Path $OutputDirectory 'data-plane.json')
                if (-not $readiness.ReadyForDataIngestion) { throw 'Deployed foundation is not ready for data ingestion.' }
                $report.ReadyForDataIngestion = $true
                break
            }
            catch
            {
                if ($attempt -eq 6 -or @($_.Exception.Data['FailedChecks']).Count -ne 1 -or $_.Exception.Data['FailedChecks'][0] -ne 'Data-plane access') { throw }
                Write-Warning "Data-plane verification failed; allowing role propagation before retry $($attempt + 1)/6. $($_.Exception.Message)"
                Start-Sleep -Seconds 60
            }
        }
    }
    $report.Resources = @($resources | ForEach-Object { @{ Id = $_.id; Type = $_.type; Name = $_.name } })
    $report.Outputs = @{}
    foreach ($key in $Outputs.Keys) { $report.Outputs[$key] = $Outputs[$key].value }
}

$account = Invoke-FoundationAzure -Arguments @('account', 'show')
if ($account.id -ne $subscription -or $account.tenantId -ne $env:AZURE_TENANT_ID -or $account.state -ne 'Enabled')
{
    throw 'Azure CLI does not target the configured enabled sandbox subscription and tenant.'
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$reportPath = Join-Path $OutputDirectory 'foundation.json'
$report = [ordered]@{
    Version = 1; Operation = $Operation; Status = 'Started'
    ResourceGroup = $groupName; ResourceGroupId = $groupId
    Region = $config.region; ExpiresOn = $config.expiresOn
    RunId = $env:GITHUB_RUN_ID; CreatedThisRun = $false
    ReadyForDataIngestion = $false; Passes = @(); Outputs = @(); Resources = @()
}
try
{
    $exists = Invoke-FoundationAzure -Arguments @('group', 'exists', '--name', $groupName, '--subscription', $subscription)
    if ($exists)
    {
        $group = Invoke-FoundationAzure -Arguments @('group', 'show', '--name', $groupName, '--subscription', $subscription)
        Assert-FoundationOwnership $group
    }
    if ($Operation -eq 'Remove')
    {
        if ($exists)
        {
            if (-not $PSCmdlet.ShouldProcess($groupId, 'Delete the owned foundation and all resources in this group')) { throw 'Removal was not approved.' }
            $null = Invoke-FoundationAzure -Arguments @('group', 'delete', '--name', $groupName, '--subscription', $subscription, '--yes')
            if (Invoke-FoundationAzure -Arguments @('group', 'exists', '--name', $groupName, '--subscription', $subscription)) { throw 'Foundation deletion has not completed.' }
        }
        $report.Status = if ($exists) { 'Removed' } else { 'AlreadyAbsent' }
    }
    elseif ($Operation -eq 'Deploy')
    {
        if (-not (Test-Path -LiteralPath $TemplateFile -PathType Leaf)) { throw 'Build the canonical hub and compile hack/foundation.bicep before deploying.' }
        $null = & "$PSScriptRoot/Test-DesignTimeOptimizerSandbox.ps1" -Path $Path -ReportPath (Join-Path $OutputDirectory 'preflight.json')
        $revision = & git -C (Join-Path $PSScriptRoot '../..') rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $revision -notmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve the foundation source revision.' }
        $tags = $ownership.Clone()
        $tags['ftk-expires-on'] = ([DateTimeOffset]$config.expiresOn).ToUniversalTime().ToString('o')
        $tags['ftk-source'] = $revision
        if (-not $PSCmdlet.ShouldProcess($groupId, "Deploy paid foundation and verify $DeploymentPasses pass(es); retain after success")) { throw 'Deployment was not approved.' }
        $report.CreatedThisRun = -not $exists
        $report.SourceRevision = $revision
        $report.Status = 'Deploying'
        Save-FoundationReport
        $tagArguments = @($tags.Keys | Sort-Object | ForEach-Object { "$_=$($tags[$_])" })
        $group = Invoke-FoundationAzure -Arguments (@('group', 'create', '--name', $groupName, '--location', $config.region, '--subscription', $subscription, '--tags') + $tagArguments)
        Assert-FoundationOwnership $group
        $parameters = @{
            hubName = @{ value = "dto$hash" }; clusterName = @{ value = "dto$hash" }
            location = @{ value = $config.region }; clusterSku = @{ value = $config.dataExplorerSku }
            tags = @{ value = $tags }
        }
        $parameterPath = Join-Path $OutputDirectory 'foundation.parameters.json'
        @{ parameters = $parameters } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterPath
        $deploymentArguments = @('--name', 'hack-foundation', '--resource-group', $groupName, '--subscription', $subscription, '--template-file', $TemplateFile, '--parameters', "@$parameterPath")
        $null = Invoke-FoundationAzure -Arguments (@('deployment', 'group', 'validate') + $deploymentArguments)
        for ($pass = 1; $pass -le $DeploymentPasses; $pass++)
        {
            $deployment = Invoke-FoundationAzure -Arguments (@('deployment', 'group', 'create') + $deploymentArguments)
            if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Foundation deployment did not succeed.' }
            $previous = $report.Outputs
            Test-FoundationDeployment $deployment.properties.outputs
            if ($pass -gt 1)
            {
                foreach ($key in 'storageAccountId', 'clusterId', 'dataFactoryName', 'hubDbName', 'ingestionDbName')
                {
                    if ($previous[$key] -ne $report.Outputs[$key]) { throw "Redeployment changed the foundation identity '$key'." }
                }
            }
            $report.Passes += @{
                Pass = $pass; VerifiedAt = [DateTimeOffset]::UtcNow.ToString('o'); Outputs = $report.Outputs
                Verification = if ($DeferDataPlaneVerification) { 'ControlPlaneOnly' } else { 'ControlAndDataPlane' }
            }
            Save-FoundationReport
        }
        $report.Status = if ($DeferDataPlaneVerification) { 'DeployedAwaitingDataPlaneVerification' } else { 'VerifiedAndRetained' }
    }
    else
    {
        if (-not $exists) { throw 'Foundation does not exist. Deploy it explicitly before verification.' }
        $deployment = Invoke-FoundationAzure -Arguments @('deployment', 'group', 'show', '--name', 'hack-foundation', '--resource-group', $groupName, '--subscription', $subscription)
        if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'The last foundation deployment did not succeed.' }
        Test-FoundationDeployment $deployment.properties.outputs
        $report.SourceRevision = $group.tags['ftk-source']
        $report.Status = 'VerifiedAndRetained'
    }
}
catch
{
    $report.Status = 'Failed'
    $report.Error = $_.Exception.Message
    $report.ReadyForDataIngestion = $false
    throw
}
finally
{
    $report.CompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Save-FoundationReport
}
[pscustomobject]$report

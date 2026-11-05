# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
    .SYNOPSIS
    Checks design-time optimizer sandbox configuration and Azure prerequisites.

    .DESCRIPTION
    Uses read-only Azure CLI operations with the existing signed-in identity.
    Azure identifiers come from AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID, and
    AZURE_CLIENT_ID. No resource providers, roles, quotas, or resources are changed.
    Failed checks are recorded before the command throws.

    .PARAMETER Path
    Sandbox configuration JSON. Defaults to hack/sandbox.config.json.

    .PARAMETER ConfigurationOnly
    Validates configuration without Azure access. Does not report deployment readiness.

    .PARAMETER RequireDataPlane
    Requires deployed storage and Data Explorer resources and verifies their access.
    Otherwise, missing resources are explicitly deferred, never treated as verified.

    .PARAMETER ReportPath
    Optional path for the nonsecret JSON evidence report.

    .EXAMPLE
    ./src/scripts/Test-DesignTimeOptimizerSandbox.ps1 -ConfigurationOnly

    Validates the checked-in nonsecret configuration.

    .EXAMPLE
    ./src/scripts/Test-DesignTimeOptimizerSandbox.ps1 -ReportPath ./preflight.json

    Checks the signed-in workflow identity without deploying resources.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path $PSScriptRoot '../../hack/sandbox.config.json'),

    [Parameter()]
    [switch]$ConfigurationOnly,

    [Parameter()]
    [switch]$RequireDataPlane,

    [Parameter()]
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$checks = [Collections.Generic.List[object]]::new()
$schemaPath = Join-Path $PSScriptRoot '../design-time-optimizer/schemas/sandbox.schema.json'
$content = Get-Content -LiteralPath $Path -Raw
if (-not ($content | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue))
{
    throw 'Sandbox configuration does not match the sandbox JSON Schema.'
}
$config = $content | ConvertFrom-Json -AsHashtable -Depth 30
$expiration = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($config.expiresOn, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$expiration))
{
    throw 'Sandbox expiration must be a valid timestamp with an explicit time zone.'
}
if ($expiration -le [DateTimeOffset]::UtcNow.AddMinutes($config.experiments.maximumLifetimeMinutes))
{
    throw 'Sandbox expiration must be in the future and leave time for the maximum experiment lifetime.'
}
if ($ConfigurationOnly -and $RequireDataPlane)
{
    throw 'ConfigurationOnly and RequireDataPlane cannot be used together.'
}
$checks.Add(@{ Name = 'Configuration'; Status = 'Passed'; Detail = 'Schema, limits, and expiration are valid.' })

function Invoke-SandboxAzureRead
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & az @Arguments --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        $diagnostic = 'Unclassified'
        $text = $output -join "`n"
        if ($text -match '\bAADSTS\d+\b') { $diagnostic = $Matches[0] }
        elseif ($text -match '(?i)(?:ErrorCode[:=]\s*|"code"\s*:\s*")([A-Za-z][A-Za-z0-9]+)') { $diagnostic = $Matches[1] }
        $exception = [InvalidOperationException]::new("Azure CLI failed during '$Operation' (exit $LASTEXITCODE; $diagnostic). Check the identity's access and service availability.")
        $exception.Data['Evidence'] = @{ Operation = $Operation; ExitCode = $LASTEXITCODE; ErrorCode = $diagnostic }
        if ($Operation -eq 'Model quota API' -and ($output -join "`n") -match '(?i)(not supported|UnsupportedResourceProvider|ResourceProviderNotSupported)')
        {
            $exception.Data['UnsupportedQuotaProvider'] = $true
        }
        throw $exception
    }
    try
    {
        return ($output -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100
    }
    catch
    {
        throw "Azure CLI returned invalid JSON during '$Operation'."
    }
}

function Get-SandboxAzurePage
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)

    $seen = [Collections.Generic.HashSet[string]]::new()
    while ($Uri)
    {
        if (-not $Uri.StartsWith('https://management.azure.com/', [StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($Uri) -or $seen.Count -gt 100)
        {
            throw 'Azure returned an invalid, repeated, or excessive pagination link.'
        }
        $page = Invoke-SandboxAzureRead -Operation 'Management API' -Arguments @('rest', '--method', 'get', '--url', $Uri)
        if (-not $page.ContainsKey('value')) { throw 'Azure returned an incomplete paged response.' }
        $page.value
        $Uri = $page.nextLink
    }
}

function Test-SandboxPermission
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Permissions,
        [Parameter(Mandatory)][string]$Action,
        [Parameter()][switch]$DataAction
    )

    $allowKey = if ($DataAction) { 'dataActions' } else { 'actions' }
    $excludeKey = if ($DataAction) { 'notDataActions' } else { 'notActions' }
    foreach ($permission in $Permissions)
    {
        $allowed = @($permission[$allowKey] | Where-Object { $Action -like $_ }).Count -gt 0
        $excluded = @($permission[$excludeKey] | Where-Object { $Action -like $_ }).Count -gt 0
        if ($allowed -and -not $excluded) { return $true }
    }
    return $false
}

function Invoke-SandboxCheck
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Test
    )

    try
    {
        $evidence = & $Test
        $checks.Add(@{ Name = $Name; Status = 'Passed'; Evidence = $evidence })
    }
    catch
    {
        $check = @{ Name = $Name; Status = 'Failed'; Detail = $_.Exception.Message }
        if ($_.Exception.Data['Evidence']) { $check.Evidence = $_.Exception.Data['Evidence'] }
        $checks.Add($check)
        Write-Warning "$Name failed: $($_.Exception.Message)"
    }
}

if (-not $ConfigurationOnly)
{
    foreach ($name in 'AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_ID')
    {
        $value = [Environment]::GetEnvironmentVariable($name)
        $identifier = [guid]::Empty
        if (-not [guid]::TryParse($value, [ref]$identifier) -or $identifier -eq [guid]::Empty)
        {
            throw "$name must contain a nonempty GUID from the sandbox environment."
        }
    }
    $subscription = $env:AZURE_SUBSCRIPTION_ID
    $scope = "/subscriptions/$subscription"
    $account = Invoke-SandboxAzureRead -Operation 'Account verification' -Arguments @('account', 'show')
    if ($account.id -ne $subscription -or $account.tenantId -ne $env:AZURE_TENANT_ID -or $account.state -ne 'Enabled' -or
        $account.user.type -ne 'servicePrincipal' -or $account.user.name -ne $env:AZURE_CLIENT_ID)
    {
        throw 'Azure CLI must be signed in as the configured sandbox deployment identity in the configured enabled subscription and tenant.'
    }
    $checks.Add(@{ Name = 'Identity'; Status = 'Passed'; Detail = 'Signed-in subscription, tenant, and deployment identity match the environment.' })

    Invoke-SandboxCheck -Name 'Resource providers' -Test {
        $required = @(
            'Microsoft.Storage', 'Microsoft.DataFactory', 'Microsoft.KeyVault', 'Microsoft.EventGrid',
            'Microsoft.CostManagementExports', 'Microsoft.Kusto', 'Microsoft.Network', 'Microsoft.ContainerInstance', 'Microsoft.Quota',
            'Microsoft.ManagedIdentity', 'Microsoft.OperationalInsights', 'Microsoft.Insights',
            'Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.CognitiveServices', 'Microsoft.LoadTestService'
        )
        $providers = @(Invoke-SandboxAzureRead -Operation 'Provider registration' -Arguments @('provider', 'list', '--subscription', $subscription))
        $missing = @($required | Where-Object {
                $namespace = $_
                -not ($providers | Where-Object { $_.namespace -eq $namespace -and $_.registrationState -eq 'Registered' })
            })
        if ($missing.Count) { throw "Administrator setup required: register these providers: $($missing -join ', ')." }
        @{ RegisteredProviders = $required }
    }

    Invoke-SandboxCheck -Name 'Deployment permissions' -Test {
        $permissions = @(Get-SandboxAzurePage -Uri "https://management.azure.com$scope/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
        $actions = @(
            'Microsoft.Resources/subscriptions/resourceGroups/write', 'Microsoft.Resources/deployments/write',
            'Microsoft.Authorization/roleAssignments/write', 'Microsoft.Kusto/clusters/write',
            'Microsoft.Storage/storageAccounts/write', 'Microsoft.DataFactory/factories/write',
            'Microsoft.KeyVault/vaults/write', 'Microsoft.ManagedIdentity/userAssignedIdentities/write',
            'Microsoft.App/managedEnvironments/write', 'Microsoft.App/containerApps/write',
            'Microsoft.ContainerRegistry/registries/write', 'Microsoft.OperationalInsights/workspaces/write',
            'Microsoft.Insights/components/write', 'Microsoft.CognitiveServices/accounts/write',
            'Microsoft.CognitiveServices/accounts/deployments/write', 'Microsoft.LoadTestService/loadTests/write'
        )
        $missing = @($actions | Where-Object { -not (Test-SandboxPermission -Permissions $permissions -Action $_) })
        if ($missing.Count) { throw "Administrator setup required: the workflow identity lacks these management actions: $($missing -join ', ')." }
        @{ RequiredActions = $actions; Limitation = 'RBAC permission evidence does not bypass Azure Policy, deny assignments, or role-assignment conditions.' }
    }

    Invoke-SandboxCheck -Name 'Data Explorer SKU' -Test {
        $skus = @(Get-SandboxAzurePage -Uri "https://management.azure.com$scope/providers/Microsoft.Kusto/locations/$($config.region)/skus?api-version=2025-02-14")
        $available = @($skus | Where-Object { $_.name -eq $config.dataExplorerSku -and -not $_.restrictions })
        if (-not $available.Count) { throw 'The selected development-tier Data Explorer SKU is unavailable or restricted in the selected region.' }
        @{ Region = $config.region; Sku = $config.dataExplorerSku; Limitation = 'SKU listing does not reserve physical capacity.' }
    }

    Invoke-SandboxCheck -Name 'Model capacity' -Test {
        $quotaSource = 'Azure Quota CLI and Cognitive Services usage'
        try
        {
            $null = Invoke-SandboxAzureRead -Operation 'Model quota API' -Arguments @('quota', 'list', '--scope', "$scope/providers/Microsoft.CognitiveServices/locations/$($config.region)")
        }
        catch
        {
            if (-not $_.Exception.Data['UnsupportedQuotaProvider']) { throw }
            $quotaSource = 'Cognitive Services usage (Azure Quota API explicitly does not support this provider)'
            Write-Warning $quotaSource
        }
        $models = @(Invoke-SandboxAzureRead -Operation 'Model availability' -Arguments @('cognitiveservices', 'model', 'list', '--location', $config.region, '--subscription', $subscription))
        $usage = @(Invoke-SandboxAzureRead -Operation 'Model usage' -Arguments @('cognitiveservices', 'usage', 'list', '--location', $config.region, '--subscription', $subscription))
        $observed = @(
            foreach ($entry in $models)
            {
                if ($entry.model.name -notin $config.model.preferredNames) { continue }
                @{
                    Model = $entry.model.name; Version = $entry.model.version; Kind = $entry.kind
                    Lifecycle = $entry.model.lifecycleStatus; InferenceRetirement = $entry.model.deprecation.inference
                    Skus = @(
                        foreach ($sku in $entry.model.skus)
                        {
                            @{
                                Sku = $sku.name; QuotaName = $sku.usageName; Capacity = $sku.capacity
                                Usage = @($usage | Where-Object { $_.name.value -eq $sku.usageName } | ForEach-Object {
                                        @{ Limit = $_.limit; CurrentValue = $_.currentValue; Status = $_.status }
                                    })
                            }
                        }
                    )
                }
            }
        )
        $candidates = @(
            foreach ($entry in $models)
            {
                $model = $entry.model
                if ($entry.kind -ne 'OpenAI' -or $model.name -notin $config.model.preferredNames -or -not $model.version -or $model.lifecycleStatus -notin @('Stable', 'GenerallyAvailable')) { continue }
                if ($model.deprecation.inference -and [DateTimeOffset]::Parse($model.deprecation.inference) -le $expiration) { continue }
                foreach ($sku in @($model.skus | Where-Object { $_.name -eq $config.model.deploymentSku -and $_.usageName -notmatch '[.-]finetune$' }))
                {
                    if ($sku.deprecationDate -and [DateTimeOffset]::Parse($sku.deprecationDate) -le $expiration) { continue }
                    $capacity = [Math]::Max($config.model.minimumCapacity, $sku.capacity.minimum)
                    if (-not $sku.usageName -or -not $sku.capacity.maximum -or $capacity -gt $sku.capacity.maximum) { continue }
                    if ($sku.capacity.allowedValues -and $capacity -notin $sku.capacity.allowedValues) { continue }
                    if ($sku.capacity.step -and (($capacity - $sku.capacity.minimum) % $sku.capacity.step) -ne 0) { continue }
                    $meter = @($usage | Where-Object { $_.name.value -eq $sku.usageName })
                    if ($meter.Count -ne 1 -or $null -eq $meter[0].limit -or $null -eq $meter[0].currentValue -or $meter[0].status -eq 'Blocked') { continue }
                    $available = $meter[0].limit - $meter[0].currentValue
                    if ($available -lt $capacity) { continue }
                    @{ Model = $model.name; Version = $model.version; Sku = $sku.name; QuotaName = $sku.usageName; Capacity = $capacity; AvailableCapacity = $available }
                }
            }
        )
        if (-not $candidates.Count)
        {
            $exception = [InvalidOperationException]::new('No approved stable model/SKU has a verified quota match and sufficient capacity. Review the observed versions, lifecycle, SKU limits, and quota evidence with an administrator.')
            $exception.Data['Evidence'] = @{ Source = $quotaSource; PreferredModels = $config.model.preferredNames; ModelsObserved = $observed }
            throw $exception
        }
        @{ Source = $quotaSource; Candidates = $candidates; Limitation = 'Candidates are not deployed or priced; runtime identity access and performance must be verified after deployment.' }
    }

    $storageId = $config.dataPlane.storageAccountResourceId
    $clusterId = $config.dataPlane.dataExplorerResourceId
    if (-not $storageId -or -not $clusterId)
    {
        $status = if ($RequireDataPlane) { 'Failed' } else { 'Deferred' }
        $checks.Add(@{ Name = 'Data-plane access'; Status = $status; Detail = 'Supply deployed storage and Data Explorer resource IDs before seeding. Management roles alone do not prove data access.' })
    }
    else
    {
        Invoke-SandboxCheck -Name 'Data-plane access' -Test {
            $prefix = "$scope/resourceGroups/"
            if (-not $storageId.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $storageId -notmatch '/providers/Microsoft.Storage/storageAccounts/[^/]+$' -or
                -not $clusterId.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $clusterId -notmatch '/providers/Microsoft.Kusto/clusters/[^/]+$')
            {
                throw 'Data-plane resources must be storage and Data Explorer resources in the configured sandbox subscription.'
            }
            $storage = Invoke-SandboxAzureRead -Operation 'Storage resource' -Arguments @('rest', '--method', 'get', '--url', "https://management.azure.com${storageId}?api-version=2023-05-01")
            $permissions = @(Get-SandboxAzurePage -Uri "https://management.azure.com$storageId/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
            foreach ($action in 'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read', 'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write')
            {
                if (-not (Test-SandboxPermission -Permissions $permissions -Action $action -DataAction)) { throw "The workflow identity lacks storage data action: $action." }
            }
            $null = Invoke-SandboxAzureRead -Operation 'Storage data-plane read' -Arguments @('storage', 'container', 'list', '--account-name', $storage.name, '--auth-mode', 'login', '--subscription', $subscription)
            $cluster = Invoke-SandboxAzureRead -Operation 'Data Explorer resource' -Arguments @('rest', '--method', 'get', '--url', "https://management.azure.com${clusterId}?api-version=2025-02-14")
            $uri = [uri]$cluster.properties.uri
            if ($uri.Scheme -ne 'https' -or -not $uri.Host.EndsWith('.kusto.windows.net', [StringComparison]::OrdinalIgnoreCase)) { throw 'Data Explorer returned an unexpected query endpoint.' }
            foreach ($function in 'Costs', 'Prices')
            {
                $body = @{ db = $config.dataPlane.database; csl = "$function() | take 0" } | ConvertTo-Json -Compress
                $result = @(Invoke-SandboxAzureRead -Operation 'Data Explorer query' -Arguments @('rest', '--method', 'post', '--url', "$($uri.AbsoluteUri.TrimEnd('/'))/v2/rest/query", '--resource', 'https://api.kusto.windows.net', '--body', $body))
                $complete = @($result | Where-Object { $_.FrameType -eq 'DataSetCompletion' -and $_.HasErrors -eq $false }).Count -eq 1
                if (-not $complete -or @($result | Where-Object { $_.HasErrors -or $_.error }).Count) { throw 'Data Explorer reported an incomplete or failed read-only query.' }
            }
            @{ StorageRead = 'Verified'; StorageWrite = 'RBAC checked; no write probe performed'; HubFunctions = @('Costs', 'Prices') }
        }
    }
    $checks.Add(@{ Name = 'Model runtime access'; Status = 'Deferred'; Detail = 'Verify the application managed identity against the sandbox-owned model endpoint after H05 deployment. No billable inference was attempted.' })
}

$failures = @($checks | Where-Object { $_.Status -eq 'Failed' })
$dataPlanePassed = @($checks | Where-Object { $_.Name -eq 'Data-plane access' -and $_.Status -eq 'Passed' }).Count -gt 0
$report = [ordered]@{
    Version = 1
    Mode = if ($ConfigurationOnly) { 'ConfigurationOnly' } else { 'ReadOnlyAzure' }
    CheckedAt = [DateTimeOffset]::UtcNow.ToString('o')
    ConfigurationHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Region = $config.region
    ExpiresOn = $config.expiresOn
    Budget = $config.budget
    SampleRepository = $config.sampleRepository
    ReadyForInfrastructureDeployment = (-not $ConfigurationOnly -and $failures.Count -eq 0)
    ReadyForDataIngestion = (-not $ConfigurationOnly -and $failures.Count -eq 0 -and $dataPlanePassed)
    Checks = $checks.ToArray()
    Warnings = @(
        'The spending ceiling is configuration, not an automatic billing cap. Budgets do not stop resources.'
        'Retaining paid services until the configured expiration can exhaust the budget. Cleanup and runtime limits must be enforced by deployment workflows.'
        'Successful preflight does not reserve capacity or prove policy approval, current prices, model invocation, answer quality, or an end-to-end deployment.'
    )
}
if ($ReportPath)
{
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ReportPath
}
if ($failures.Count)
{
    $exception = [InvalidOperationException]::new("Sandbox preflight blocked: $(($failures | ForEach-Object { $_.Name }) -join ', '). Review the evidence report and administrator setup.")
    $exception.Data['FailedChecks'] = @($failures | ForEach-Object { $_.Name })
    throw $exception
}
[pscustomobject]$report

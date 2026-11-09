# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = 'Stop'

function Invoke-SampleAz {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $operation = ($Arguments | Select-Object -First 3) -join ' '
    Write-Information "Azure CLI started: $operation" -InformationAction Continue
    $result = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $operation." }
    Write-Information "Azure CLI completed: $operation" -InformationAction Continue
    if ($result) { return (($result -join "`n") | ConvertFrom-Json) }
}

function Assert-SampleAccount {
    param([Parameter(Mandatory)]$Account)
    if ($Account.id -ne '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a' -or
        $Account.tenantId -ne '3670e846-58dd-4658-86fb-00e4029045d6') {
        throw 'The Azure account does not match the approved sample subscription and tenant.'
    }
}

function Get-SamplePreview {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Scope
    )
    if ($Arguments.Count -lt 3 -or $Arguments[0] -ne 'deployment' -or
        $Arguments[1] -ne 'sub' -or $Arguments[2] -ne 'create') {
        throw 'A sample preview requires subscription deployment arguments.'
    }
    $previewArguments = @($Arguments)
    $previewArguments[2] = 'what-if'
    $preview = Invoke-SampleAz ($previewArguments + @(
        '--no-pretty-print', '--result-format', 'FullResourcePayloads'))
    if ($preview.status -ne 'Succeeded' -or $null -eq $preview.changes) {
        throw 'The sample deployment preview did not complete successfully.'
    }
    foreach ($change in $preview.changes) {
        $resourceId = [string]$change.resourceId
        if (($resourceId -ne $Scope -and
            -not $resourceId.StartsWith("$Scope/", [StringComparison]::OrdinalIgnoreCase)) -or
            $change.changeType -notin @('Create', 'Modify', 'NoChange', 'Ignore', 'Deploy')) {
            throw "The preview rejected '$($change.changeType)' for '$resourceId': deletion, unsupported changes, or a resource outside the sample."
        }
    }
    return @($preview.changes | Select-Object resourceId, changeType)
}

function Assert-SampleOwnership {
    param([Parameter(Mandatory)]$Group)
    if ($Group.name -ne 'ftk-dto-hack-s-ae46' -or
        $Group.tags.repository -ne 'bobjac/finops-toolkit' -or
        $Group.tags.'ftk-tool' -ne 'design-time-optimizer-sample') {
        throw 'The resource group is not the independently owned sample. Refusing changes.'
    }
}

function Assert-SampleCheckpoint {
    param(
        [Parameter(Mandatory)]$Checkpoint,
        [Parameter(Mandatory)][string]$Revision,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$PreviousStage,
        [Parameter(Mandatory)][string]$Scope
    )
    if ($Checkpoint.version -ne 1 -or $Checkpoint.revision -cne $Revision -or
        $Checkpoint.runId -cne $RunId -or $Checkpoint.stage -cne $PreviousStage -or
        $Checkpoint.status -cne 'Completed' -or
        $Checkpoint.subscriptionId -ne '6e87e78d-fe02-4f01-bd7b-4f2157eabd5a' -or
        $Checkpoint.resourceGroup -ne 'ftk-dto-hack-s-ae46') {
        throw 'The checkpoint must be a completed prerequisite from this workflow run and revision.'
    }
    $expected = @{
        registryName = 'crftkdtohacksae46'
        registryLoginServer = 'crftkdtohacksae46.azurecr.io'
        keyVaultName = 'kv-ftk-dto-hack-s-ae46'
        containerAppName = 'ca-ftk-dto-hack-s-ae46'
        applicationInsightsResourceId = "$Scope/providers/Microsoft.Insights/components/appi-ftk-dto-hack-s-ae46"
    }
    foreach ($name in $expected.Keys) {
        if ($Checkpoint.outputs.$name.value -ne $expected[$name]) {
            throw "The checkpoint does not match the owned sample resource: $name."
        }
    }
    $workspaceId = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$Checkpoint.outputs.workspaceCustomerId.value, [ref]$workspaceId) -or
        $workspaceId -eq [Guid]::Empty -or
        $Checkpoint.outputs.fqdn.value -notlike 'ca-ftk-dto-hack-s-ae46.*.eastus2.azurecontainerapps.io') {
        throw 'The checkpoint workspace or application endpoint is invalid.'
    }
    if ($PreviousStage -ne 'Infrastructure' -and
        $Checkpoint.image -cne "crftkdtohacksae46.azurecr.io/sample:$Revision") {
        throw 'The checkpoint image does not match the approved revision.'
    }
}

function Get-SampleApiToken {
    param(
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [switch]$CreateIfMissing
    )
    $secretExists = Invoke-SampleAz @('keyvault', 'secret', 'list', '--vault-name', $VaultName,
        '--query', "[?name=='sample-api-token'].name")
    if ($secretExists) {
        $secret = Invoke-SampleAz @('keyvault', 'secret', 'show', '--vault-name', $VaultName,
            '--name', 'sample-api-token')
        $token = $secret.value
    }
    elseif ($CreateIfMissing) {
        $token = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
        Write-Information "::add-mask::$token" -InformationAction Continue
        $tokenFile = Join-Path $OutputDirectory 'api-token.private'
        try {
            [IO.File]::WriteAllText($tokenFile, $token)
            Invoke-SampleAz @('keyvault', 'secret', 'set', '--vault-name', $VaultName,
                '--name', 'sample-api-token', '--file', $tokenFile) | Out-Null
        }
        finally {
            if (Test-Path -LiteralPath $tokenFile) { Remove-Item -LiteralPath $tokenFile -Force }
        }
    }
    else {
        throw 'The API token is missing. Complete the application stage before live validation.'
    }
    if ($token -isnot [string] -or $token.Length -lt 32) {
        throw 'The stored API token is invalid. Refusing to replace it automatically.'
    }
    Write-Information "::add-mask::$token" -InformationAction Continue
    return $token
}

function Wait-SampleReady {
    param([Parameter(Mandatory)][Uri]$BaseUri)
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $ready = Invoke-RestMethod -Uri "$($BaseUri.AbsoluteUri.TrimEnd('/'))/ready" -TimeoutSec 10
            if ($ready.status -eq 'ready' -and $ready.modelMode -eq 'azure-openai') { return }
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException], [System.Threading.Tasks.TaskCanceledException] {
            Write-Warning 'The deployed revision is not ready yet.'
        }
        Start-Sleep -Seconds 3
    }
    throw 'The live runtime is not ready; an offline container is not live acceptance.'
}

function Assert-SamplePrice {
    param([Parameter(Mandatory)][string]$Json)
    $prices = $Json | ConvertFrom-Json
    if ($prices.currency -ne 'USD' -or $prices.region -ne 'eastus2' -or
        $prices.model -ne 'gpt-5-mini' -or $prices.modelVersion -ne '2025-08-07' -or
        $prices.deploymentSku -ne 'GlobalStandard') {
        throw 'Price evidence does not match the approved model, region, SKU, and currency.'
    }
    foreach ($name in @('inputPerMillion', 'cachedInputPerMillion', 'outputPerMillion', 'analyticsPerGB')) {
        $value = 0.0
        if (-not [double]::TryParse([string]$prices.$name,
                [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture,
                [ref]$value) -or $value -le 0 -or [double]::IsInfinity($value) -or [double]::IsNaN($value)) {
            throw "Applicable positive price evidence is missing: $name."
        }
    }
    $verified = [DateTimeOffset]::Parse($prices.verifiedAt)
    $now = [DateTimeOffset]::UtcNow
    if ($verified -gt $now -or $verified -lt $now.AddDays(-7)) {
        throw 'Price evidence must have been verified within the last seven days.'
    }
    if (-not $prices.sourceUrls -or @($prices.sourceUrls).Count -lt 2) {
        throw 'Model and Analytics pricing sources are required.'
    }
    foreach ($source in $prices.sourceUrls) {
        $uri = [Uri]$source
        if ($uri.Scheme -ne 'https' -or $uri.Host -notin @(
            'prices.azure.com', 'azure.microsoft.com', 'learn.microsoft.com')) {
            throw 'Price sources must be authoritative Azure HTTPS URLs.'
        }
    }
    return $prices
}

function Assert-SampleAnswer {
    param([Parameter(Mandatory)]$Case, [Parameter(Mandatory)]$Answer)
    if ($Answer.answerStatus -cne $Case.expectedStatus -or
        $Answer.answer -cne $Case.expectedAnswer -or
        ($Answer.data.columns -join '|') -cne ($Case.expectedData.columns -join '|') -or
        @($Answer.data.rows).Count -ne @($Case.expectedData.rows).Count -or
        ($Answer.evidence.agentCalls -join '|') -cne ($Case.expectedCalls -join '|')) {
        throw "Live golden contract failed: $($Case.id)."
    }
    for ($row = 0; $row -lt @($Case.expectedData.rows).Count; $row++) {
        $actual = @($Answer.data.rows[$row])
        $expected = @($Case.expectedData.rows[$row])
        if ($actual.Count -ne $expected.Count) { throw "Live row shape failed: $($Case.id)." }
        for ($column = 0; $column -lt $expected.Count; $column++) {
            if ($expected[$column] -is [string]) {
                if ($actual[$column] -isnot [string] -or $actual[$column] -cne $expected[$column]) {
                    $mismatch = if ($actual[$column] -is [string]) { 'value' } else { 'type' }
                    $matchingRows = @(
                        for ($candidate = 0; $candidate -lt @($Case.expectedData.rows).Count; $candidate++) {
                            $candidateValue = $Case.expectedData.rows[$candidate][$column]
                            if ($actual[$column] -is [string] -and $candidateValue -is [string] -and
                                $actual[$column] -ceq $candidateValue) {
                                $candidate
                            }
                        }
                    )
                    $matchSummary = if ($matchingRows.Count) { $matchingRows -join ',' } else { 'none' }
                    throw "Live string value failed: $($Case.id) (rowIndex=$row, columnIndex=$column, mismatch=$mismatch, expectedRowMatches=$matchSummary)."
                }
            }
            elseif ($null -eq $expected[$column]) {
                if ($null -ne $actual[$column]) { throw "Live null value failed: $($Case.id)." }
            }
            elseif ($actual[$column] -is [string] -or $actual[$column] -is [bool] -or
                $null -eq $actual[$column] -or [decimal]$actual[$column] -ne [decimal]$expected[$column]) {
                throw "Live numeric value failed: $($Case.id)."
            }
        }
    }
}

function Assert-SampleTelemetry {
    param([Parameter(Mandatory)]$Answer, [Parameter(Mandatory)][object[]]$Rows)
    $modelRows = @($Rows | Where-Object { $_.Name -eq 'gen_ai.chat' })
    $usage = @($Answer.evidence.modelUsage)
    if (-not $usage.Count -or $modelRows.Count -ne $usage.Count -or
        @($Rows | Where-Object { $_.Name -eq 'coordinator.run' }).Count -ne 1) {
        throw 'Exported model spans and measured model usage do not match.'
    }
    $measurements = @{}
    foreach ($row in $Rows) {
        $properties = $row.Properties
        if ($properties -is [string]) { $properties = $properties | ConvertFrom-Json }
        if ($row.SessionId -cne $Answer.evidence.sessionHash -or
            $properties.'experiment.id' -cne $Answer.evidence.experimentHash -or
            $properties.'optimization.variant' -cne 'baseline') {
            throw 'Exported experiment, variant, or session attribution is missing.'
        }
        foreach ($key in @('gen_ai.input.messages', 'gen_ai.output.messages', 'gen_ai.prompt',
                'gen_ai.completion', 'db.statement', 'db.query.text')) {
            if ($properties.PSObject.Properties.Name -contains $key) {
                throw 'Sensitive content was found in ordinary telemetry.'
            }
        }
        if ($row.Name -eq 'gen_ai.chat') {
            if (-not $properties.'gen_ai.response.model' -or
                $null -eq $properties.'gen_ai.usage.input_tokens' -or
                $null -eq $properties.'gen_ai.usage.output_tokens' -or
                -not $row.ParentId -or $row.ParentId -notin $Rows.Id) {
                throw 'Exported model identity, usage, or parent correlation is missing.'
            }
            $role = $properties.'agent.name'
            if (-not $role -or $measurements.ContainsKey($role)) {
                throw 'Exported model agent attribution is missing or duplicated.'
            }
            $measurements[$role] = $properties
        }
    }
    for ($index = 0; $index -lt $usage.Count; $index++) {
        $properties = $measurements[$Answer.evidence.agentCalls[$index]]
        $expected = $usage[$index]
        if (-not $properties -or $properties.'gen_ai.response.model' -cne $expected.model -or
            [long]$properties.'gen_ai.usage.input_tokens' -ne $expected.inputTokens -or
            [long]$properties.'gen_ai.usage.output_tokens' -ne $expected.outputTokens) {
            throw 'Exported model identity and token usage do not match provider measurements.'
        }
        $cacheKey = 'gen_ai.usage.cache_read.input_tokens'
        if ($null -eq $expected.cachedInputTokens) {
            if ($properties.PSObject.Properties.Name -contains $cacheKey) {
                throw 'Exported cached tokens were not reported by the provider.'
            }
        }
        elseif ($null -eq $properties.$cacheKey -or
            [long]$properties.$cacheKey -ne $expected.cachedInputTokens) {
            throw 'Exported cached tokens do not match provider measurements.'
        }
    }
}

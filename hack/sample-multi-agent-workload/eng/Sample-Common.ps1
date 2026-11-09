# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$ErrorActionPreference = 'Stop'

function Invoke-SampleAz {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0])." }
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
            throw 'The preview contains deletion, unsupported changes, or a resource outside the sample.'
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
                    throw "Live string value failed: $($Case.id)."
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
        if ($properties.'session.id' -cne $Answer.evidence.sessionHash -or
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

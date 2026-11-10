# AI agent tokenomics with live hub prices

This standalone hack workbook reads actual model spans from Application Insights and joins them to verified public-retail model meters in the FinOps hub through the supported `adx()` cross-service proxy. It does not write telemetry or prices.

## Deploy from verified outputs

Use the fork's **Sandbox workbook** workflow on `dev`. Supply a successful **Sandbox seed data** run ID and **Sample workload CD** run ID whose artifacts are still available. Run IDs select evidence, not Azure endpoints. The workflow downloads and verifies their revisions and provenance, then derives resource IDs, cluster/database names, exact meters, units, and price applicability automatically.

After separately approving deployment:

```bash
gh workflow run sandbox-workbook.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Deploy -f seed_run_id=<successful-seed-run> \
  -f sample_run_id=<successful-live-sample-run> -f confirmation=ftk-dto-hack-s-ae46
```

Approve the protected `sandbox` job. It previews changes, permits only workbook changes inside the owned sample group, refuses to overwrite an unowned workbook, deploys, reads back the configuration, runs every panel query, and executes explicitly synthetic pricing regressions. It never redeploys the foundation/sample, refreshes prices automatically, or generates model traffic.

The summary and seven-day `sandbox-workbook-<run-id>` artifact contain the workbook link, source/seed/sample revisions, exact deployment parameters, query results, and assertion outcomes. Open the workbook and visually check the panels before closing #8. Viewers need query access to both Application Insights and the hub ingestion database; the workflow grants no new access.

`operation=Validate` reruns checks against the existing deployed workbook without Azure mutations. A missing workbook, stale evidence, partial query response, or configuration mismatch fails explicitly. If predecessor artifacts expire, rerun their approved workflows rather than inventing outputs or bypassing verification.

The `.workbook` file is a source template, not an import-ready dashboard. `deploy.bicep` injects the shared `token-cost.kql` and configuration. Other deployments can supply `appInsightsId`, `hubClusterUri`, `hubDatabase`, and the documented `priceContext` object directly; no sandbox resource IDs are embedded in either source.

## Measurement and price coverage

The price context is scoped to the verified seed's model, region, USD public retail GlobalStandard meters, effective dates, and seven-day retrieval freshness. It carries model/region/provenance plus three meter records (`direction`, `meterId`, `price`, `region`, and `effectiveStart`). The numbers validate the hub rows; they never replace absent hub prices. Unknown models, including unmatched deployments, stay unpriced.

Only token-bearing spans contribute usage. Agent identity supports `agent.name`, `gen_ai.agent.name`, and Foundry's main-agent name. Sessions use Azure's standard `session_Id` column. Experiment identifiers are the hashes emitted by the workload, not original user labels. Snapshot suffixes on response model names are removed for matching the configured model family; the rate card does not provide model-version-specific prices.

Cached input is included in total input. Cost is `(input - cached) * inputRate + cached * cachedRate + output * outputRate`, with rates expressed per million tokens. Missing cache quantities are unknown, not silently zero. Invalid counts, duplicate spans, duplicate price rows, stale evidence, wrong currencies/units, and missing applicable prices cannot produce a complete cost total.

The summary preserves a **known priced subtotal**, unpriced call counts, coverage percentage, and a nullable total. Baseline/candidate rows remain visible when one variant has no measured calls. Missing variants and incomplete coverage never appear as free workloads. Model-call latency and cost per model call are observations, not cost per successful evaluated answer.

This workbook does **not** establish equivalent load, answer quality, total infrastructure cost, billing accuracy, or optimization savings. Those experiment decisions belong to H09/H10. Resource retention and expiration enforcement remain H11 concerns. Existing sample/foundation removal workflows remain the cleanup paths; this workbook is in the sample group and is removed with it.

## Validate locally

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = @(
    './src/powershell/Tests/Unit/DesignTimeOptimizerWorkbook.Tests.ps1'
    './src/powershell/Tests/Unit/HubsKqlOperators.Tests.ps1'
    './src/powershell/Tests/Lint/KqlJoinKinds.Tests.ps1'
)
$configuration.Filter.FullName = @(
    'Workbook deployment and price evidence contracts*'
    'HubsKqlOperators*'
    'KqlJoinKinds.Should not add bare joins*'
)
Invoke-Pester -Configuration $configuration
Invoke-ScriptAnalyzer -Path ./src/scripts/Publish-DesignTimeOptimizerWorkbook.ps1 -Severity Warning,Error
Invoke-ScriptAnalyzer -Path ./src/scripts/Test-DesignTimeOptimizerWorkbook.ps1 -Severity Warning,Error
```

```bash
az bicep build --file src/workbooks/optimization/AiAgentTokenomicsLivePrices/deploy.bicep --stdout
git diff --check
```

Offline checks do not execute KQL. Live validation executes the actual shared query with explicitly synthetic inputs for known cached-token arithmetic, missing prices, currency mismatch, duplicate prices/spans, invalid cache counts, unknown models, and stale evidence. These fixtures are test-only and never a fallback for failed live telemetry.

The join tests run the explicit-join rule across repository surfaces. An unfiltered repository run currently fails on six existing `lookup` operators in the unrelated static `AiAgentTokenomics.workbook`, which the broad ARG rule misclassifies. That workbook and lint rule are unchanged by this issue.

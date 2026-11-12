# Bounded FinOps context

H08 ([#10](https://github.com/bobjac/finops-toolkit/issues/10)) exposes four read-only context tools for the hack's approved sandbox. They run through Azure CLI with the existing signed-in identity. No new server, application deployment, autonomous harness, or model call is required.

## Run a tool

Use PowerShell 7. Download a successful **Sandbox seed data** artifact from the fork's `dev` branch into `.tmp/context-seed`. Verify its workflow, conclusion, run ID, and revision before use. The directory must contain `seed-second/seed.json`, `seed-evidence-second/seed-report.json`, and `seed-evidence-second/foundation/foundation.json`.

From the repository root:

```powershell
$scope = '/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46'
$arguments = @{
    SeedDirectory = '.tmp/context-seed'
    Scope = $scope
}
./src/scripts/Get-DesignTimeOptimizerContext.ps1 @arguments -Tool get_cost_summary |
    ConvertTo-Json -Depth 30
./src/scripts/Get-DesignTimeOptimizerContext.ps1 @arguments -Tool get_cost_by_resource |
    ConvertTo-Json -Depth 30
./src/scripts/Get-DesignTimeOptimizerContext.ps1 @arguments -Tool get_optimization_recommendations |
    ConvertTo-Json -Depth 30
./src/scripts/Get-DesignTimeOptimizerContext.ps1 @arguments -Tool get_current_pricing |
    ConvertTo-Json -Depth 30
```

In the packaged agent plugin, use `skills/design-time-optimizer/scripts/Get-DesignTimeOptimizerContext.ps1` with the same arguments. The plugin includes the same query templates. This adapter complements the existing read-only Azure MCP Kusto integration; it does not expose a new MCP server or accept arbitrary KQL.

The approved subscription/tenant match the existing sample account guard. `Scope` must be the exact ARM ID of `ftk-dto-hack-s-ae46` or `ftk-dto-hack-foundation`, not a subscription-wide scope, nested resource, historical ID, prefix match, or another group. The adapter verifies its source cluster against Azure before querying. Local artifact files are trusted operator inputs, not cryptographic proof of a GitHub run; use the protected workflow below for a verified artifact handoff.

The identity needs read access to the cluster resource, query access to `Hub`, and Azure Advisor recommendation read access for the selected scope. The tools never grant permissions or generate Advisor recommendations. If the current identity lacks access, stop and request the approved access path; do not broaden permissions automatically.

## Tools and response contract

| Tool | Source | Data and limits |
| --- | --- | --- |
| `get_cost_summary` | `Hub.Costs()` | USD billed-cost totals for the labeled historical dataset, grouped by currency |
| `get_cost_by_resource` | `Hub.Costs()` | The same historical dataset, grouped by resource ID and currency; every row is marked as not a deployment target |
| `get_optimization_recommendations` | Azure Advisor cached recommendations | Cost category for the exact live group; no refresh/mutation; at most five pages and 200 rows |
| `get_current_pricing` | `Hub.Prices()` plus verified seed provenance | Exactly three applicable GPT-5 mini GlobalStandard public-retail token meters, USD, `eastus2`, with seven-day retrieval freshness |

Each successful response includes `version`, `requestId`, `tool`, `source`, `scope`, `observedAt`, `freshness`, `dataScope`, `data`, `warnings`, `evidence`, and `audit`. `data.status` is `available` or `empty`; empty data is explicit and is not an authoritative zero-cost estimate. Evidence includes seed run/revision and query hash/source endpoint. Advisor rows preserve their individual `lastUpdated` timestamps; the envelope's `dataThrough` is the oldest returned recommendation timestamp, not a guarantee of current coverage.

Cost periods use inclusive `Start` and exclusive `End` charge-start bounds. Both must be within the original June 2024 sample window; the maximum duration is 31 days. The default is June 1 through July 1, 2024, in UTC. Query totals are never silently truncated: more than 200 rows, partial ADX results, invalid shape/currency, malformed Advisor results, and excess pagination fail explicitly.

The source queries reuse the query catalog's `Costs()` aggregation pattern and the seed/workbook's normalized `Prices()` columns. They are separate templates because the catalog's rolling current-month defaults would hide the original historical fixtures. UTC dates and a fixed grouping choice are the only substitutions; agents cannot supply query text.

## Evidence boundaries

**Historical cost is sample context, not sandbox spend.** `dto-history-v1` and `sample-history-v1` identify the explicitly seeded June 2024 workload. Its original resource IDs are not resolved against Azure and never authorize mutations. The response distinguishes the requested live scope from this historical `dataScope`. Do not claim those costs are billed charges for the current sample or evidence of savings.

**Pricing is not a fallback.** Returned hub rows must match verified meter identities, price values, original `1M` units, a 1,000,000-token block, region, currency, offer, and effective dates. Missing, duplicate, stale, future, or mismatched required prices throw rather than returning an estimate. `pricingAsOf` is the actual seed price retrieval time, not the current query time. The tool does not ingest or refresh prices. Use the separately approved seed workflow when a refresh is needed.

**Recommendations are suggestions, not approval.** Cached Advisor data may be old or empty. The tool returns only the needed description, impact, resource, and timestamps, not provider remediation commands or arbitrary extended properties. It validates every returned resource against the requested group. No recommendations does not establish that the workload is optimized.

**No provider fallback exists.** Azure authentication, authorization, network, JSON, or query failures terminate the operation. Native CLI errors are sanitized rather than copying potentially sensitive provider response bodies. Use deployment/workflow logs and approved diagnostics to resolve access separately.

H08 provides context only. Equivalent baseline/candidate execution, answer-quality evaluation, telemetry consumption, and a savings decision remain H09/H10.

## Protected live verification

After publication and separate sandbox approval, run **Sandbox context** on fork `dev` with a successful `seed_run_id`. It verifies the actual protected-job approval and current revision, downloads the trusted artifact, checks its run/revision binding, and executes all four read-only tools. Any failed tool fails the job. The seven-day artifact contains sanitized responses and the trusted predecessor metadata, not credentials.

The workflow does not provision infrastructure, ingest data, invoke models, generate recommendations, or delete resources. It uses the same sandbox concurrency group as foundation lifecycle work.

## Validation

```powershell
Invoke-Pester -Path ./src/powershell/Tests/Unit/DesignTimeOptimizerContext.Tests.ps1 -Output Detailed
Invoke-ScriptAnalyzer -Path ./src/scripts/Get-DesignTimeOptimizerContext.ps1 -Severity Warning,Error
```

The protected workflow also runs the existing KQL string-operator and explicit-join ratchets. Contract tests use explicitly synthetic fixtures and mocked providers; they do not prove live access. Record the actual live workflow result before accepting this issue.

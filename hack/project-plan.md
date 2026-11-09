# FinOps design-time optimizer hack delivery plan

## Status and purpose

This plan tracks a fully seeded Azure sandbox and a credible design-time optimization demonstration through [tracking issue #2](https://github.com/bobjac/finops-toolkit/issues/2) and the [Design-time optimizer hack milestone](https://github.com/bobjac/finops-toolkit/milestone/1). The GitHub OIDC connection test has succeeded on the fork's `dev` branch and created an empty resource group. The full toolkit deployment, seeding, sample workload, and experiment runner are not yet verified.

All source, tracking issues, pull requests, and GitHub Actions workflows stay in `bobjac/finops-toolkit`. The sample lives under `hack/sample-multi-agent-workload/`. No upstream pull requests or automatic merges are part of this hack.

Read the [optimizer architecture](./specs/repositories/finops-toolkit-design-time-optimizer/architecture.md) and [sample architecture](./sample-multi-agent-workload/architecture.md) for component contracts. This plan takes precedence over their delivery order for the hack.

## Target demonstration

```text
Deploy the sandbox and seed data through GitHub Actions
  -> run a real multi-agent workload
  -> show agent usage and estimated cost in the workbook
  -> ask the optimizer to propose one bounded change
  -> test baseline and candidate with identical questions
  -> show cost, answer quality, and performance comparisons
  -> retain evidence and clean up experiment resources
```

The result is an evidence-supported accept, reject, or repeat decision. Savings are not a required outcome, and reduced cost cannot override a failed quality or performance requirement.

## First optimization scenario

Reduce unnecessary schema context sent to one specialist agent. Use the same model, retail data, question mix, and infrastructure for baseline and candidate. Change only the schema-context selection behavior.

This moves AI token measurement earlier than the reference plan because the existing tokenomics workbook is central to the demonstration. Container Apps rightsizing is a second scenario, not a prerequisite for the first hack.

Compare estimated cost per 1,000 successfully answered, evaluated questions. Record all measured calls and their priced consumption in the numerator, including work consumed by failed requests; use only successful, quality-validated answers in the denominator. Preserve failed and intentionally unsupported outcomes separately.

Choose latency, error-rate, throughput, and answer-quality thresholds before running comparisons. Do not reuse the illustrative sample API thresholds without measuring the actual agent workload.

## Deployment boundary

"Everything" means everything required for this demonstration, not every FinOps Toolkit component.

| Component | Purpose |
| --- | --- |
| FinOps hubs with development-tier Azure Data Explorer | Historical cost context and applicable prices |
| Log Analytics and Application Insights | Actual application, agent, token, and performance telemetry |
| Container Apps and container registry | Independently deployed sample workload |
| Approved model endpoint and deployment | Real agent calls within sandbox quotas and cost limits |
| Live-price tokenomics workbook | Agent/model usage, estimated cost, price coverage, and experiment comparisons |
| Optimizer agent and bounded tools | Retrieve context, propose a change, and coordinate experiments |
| GitHub Actions | Build, deploy, seed, verify, compare, retain evidence, and clean up |

The optimizer remains in this repository and does not require the autonomous harness. The interactive agent can run in the developer environment; an always-running Azure-hosted optimizer service is not required.

The sample remains independently buildable, testable, and deployable from `hack/sample-multi-agent-workload/` without a FinOps hub. The coordinating workflows live in the repository-root `.github/workflows/` and use the same pinned repository revision for the hub and sample, with explicit deployment outputs. No separate sample repository or sibling checkout is required.

Prefer a model deployment owned by the hack when quotas allow. An existing approved endpoint is an explicit external dependency: record its owner, access requirements, region, model version, and cleanup exclusion. Never imply that full teardown deletes a shared endpoint.

## Sample data and evidence

| Data | Source and treatment |
| --- | --- |
| Historical cost context | Filter the existing FOCUS sample under `src/open-data/dataset-examples/`; convert to valid typed ingestion packages and label as sample history |
| Applicable pricing | Load verified model and compute prices with source, currency, units, region/offer applicability, and effective time |
| Application input | Generate fixed-seed retail data and a fixed golden question set |
| Experiment evidence | Collect actual agent calls, token usage, performance, evaluated answer outcomes, source revisions, and exact measurement windows |

Requirements:

- Do not load actual, amortized, and FOCUS versions as independent workloads; they contain overlapping history.
- Keep sample resource IDs separate from real deployment targets. Historical context must not authorize a resource mutation.
- Expose historical sample periods in queries. Any date-adjusted demo history needs documented provenance; do not silently move price effective dates.
- The 2024 sample price sheet is ingestion-test material, not a current model rate card.
- Ingest through supported staging and transformation paths. Generate typed parquet, use valid run identifiers and folder paths, and upload nonempty manifests last.
- A seed rerun replaces its logical dataset without duplicate rows.
- Historical fixtures do not count as measured optimization savings.
- Synthetic telemetry is an explicitly selected, labeled presentation fallback, never an automatic response to a live provider failure.
- Preserve unpriced quantities. Missing, stale, or inapplicable required prices must block an authoritative savings recommendation.
- Validate cached-token semantics and parent/child attribution so tokens are not subtracted or counted twice.
- The application never writes directly to core FinOps hub tables. Its costs arrive through supported exports; agent telemetry goes to Application Insights.

## GitHub Actions experience

Keep the existing [sandbox connection test](../.github/workflows/sandbox-smoke-test.yml). Add three workflows:

| Workflow | Behavior |
| --- | --- |
| Deploy hack sandbox | Build pinned revisions, deploy the retained demo foundation and workload, seed data, generate demonstration telemetry, and verify readiness |
| Run optimization experiment | Validate the contract, build exact baseline/candidate revisions, deploy temporary variants, evaluate equivalent load, publish evidence, and clean up |
| Remove hack sandbox | Require explicit confirmation and remove only identified hack-owned resources |

All Azure management operations use Azure CLI. PowerShell or other repository-native scripts can orchestrate builds, data preparation, and validation while calling `az` for Azure operations.

Workflow requirements:

- Run manually from the fork's approved `dev` branch through the `sandbox` environment.
- Use OIDC, pinned actions, explicit permissions, and noninteractive authentication.
- Validate management-plane and storage/ADX data-plane permissions separately. The resource-group smoke test does not prove hub role assignments, ingestion access, or model access.
- Pass deployment outputs to later jobs through structured, nonsecret artifacts or outputs. Do not copy endpoint IDs by hand.
- Bound polling for deployment, ingestion, telemetry readiness, and cleanup. Timeout or provider failure must fail the affected stage explicitly.
- Publish source revisions, seed versions, application and workbook links, deployment ownership, readiness checks, and known exclusions.
- Preserve machine-readable evidence before teardown. Separate retained demo infrastructure from temporary experiments.
- Control concurrent runs so redeployments and cleanup do not affect another experiment.
- Do not add automatic upstream pull requests, merges, or deployments of unapproved PR code.

## GitHub delivery backlog

`H01` through `H12` are planning IDs, not GitHub issue numbers. All 12 delivery issues are sub-issues of tracking issue #2 in the fork, carry the `hack` label, and belong to the hack milestone. Native GitHub blocked-by relationships match the prerequisites below. Dependencies are prerequisites, not merely the order of this list.

| ID | Issue | Title | Depends on |
| --- | --- | --- | --- |
| H01 | [#3](https://github.com/bobjac/finops-toolkit/issues/3) | Define sandbox configuration and deployment preflight | None |
| H02 | [#4](https://github.com/bobjac/finops-toolkit/issues/4) | Deploy the FinOps demo foundation with Azure CLI | H01 |
| H03 | [#5](https://github.com/bobjac/finops-toolkit/issues/5) | Build repeatable cost and pricing seed ingestion | H02 |
| H04 | [#6](https://github.com/bobjac/finops-toolkit/issues/6) | Implement the deterministic multi-agent sample | H01 |
| H05 | [#7](https://github.com/bobjac/finops-toolkit/issues/7) | Deploy the sample and add correlated telemetry | H01, H04 |
| H06 | [#8](https://github.com/bobjac/finops-toolkit/issues/8) | Make the live-price workbook portable and trustworthy | H02, H03, H05 |
| H07 | [#9](https://github.com/bobjac/finops-toolkit/issues/9) | Orchestrate the complete seeded sandbox deployment | H02, H03, H05, H06 |
| H08 | [#10](https://github.com/bobjac/finops-toolkit/issues/10) | Add bounded FinOps context and pricing tools | H02, H03 |
| H09 | [#11](https://github.com/bobjac/finops-toolkit/issues/11) | Implement the experiment runner and cost evaluator | H04, H05, H08 |
| H10 | [#12](https://github.com/bobjac/finops-toolkit/issues/12) | Connect the optimizer agent to the experiment workflow | H09 |
| H11 | [#13](https://github.com/bobjac/finops-toolkit/issues/13) | Add explicit cleanup and expiration enforcement | H02, H05 |
| H12 | [#14](https://github.com/bobjac/finops-toolkit/issues/14) | Rehearse and document the complete hack demonstration | H07, H10, H11 |

### Dependency-aware execution order

| Wave | Work items |
| --- | --- |
| 1 | H01 |
| 2 | H02, H04 |
| 3 | H03, H05 |
| 4 | H06, H08, H11 |
| 5 | H07, H09 |
| 6 | H10 |
| 7 | H12 |

Items in a wave can proceed independently once their actual prerequisites are complete. The wave order is a presentation aid, not an extra serial dependency. Start with H01; do not postpone basic teardown in H02/H05 until H11.

Use the tracking issue's checklist and native sub-issue progress to show delivery. Close each issue only after its acceptance criteria pass and its implementation revision or fork-local pull request and exact validation results are recorded. Update dependencies in both GitHub and this plan if the approved scope changes.

### H01: Define sandbox configuration and deployment preflight

**Scope:** Define the selected subscription, tenant, region, model access, sample repository and directory, resource naming, expiration, spending ceiling, and experiment limits.

**Acceptance:** Validate required providers, role-assignment privileges, ADX SKU availability, model permissions and quota, and workflow data-plane access. Missing prerequisites stop deployment. Identify any administrator-only setup and shared resources.

**Validation:** Configuration tests cover missing and invalid values. A read-only preflight run records evidence for the selected sandbox without exposing credentials.

### H02: Deploy the FinOps demo foundation with Azure CLI

**Scope:** Reuse existing FinOps hubs Bicep/build paths for the required foundation, identities, and access configuration.

**Acceptance:** The foundation deploys from the selected fork revision, returns machine-readable outputs, and safely redeploys. Unneeded features such as managed exports can be disabled during fixture-first setup. Resource ownership and cleanup behavior are defined before deployment.

**Validation:** Existing Bicep/build checks pass. Deploy and redeploy in the sandbox; verify databases, required functions, resource tags, and access.

### H03: Build repeatable cost and pricing seed ingestion

**Scope:** Prepare a filtered FOCUS history dataset and applicable prices with provenance. Use appropriate hub normalization and ingestion paths for each dataset.

**Acceptance:** Generate typed packages, upload manifests last, wait for ingestion, and verify expected rows through hub queries. Reruns do not duplicate history. Sample provenance, dates, units, and required-meter price coverage are explicit.

**Validation:** Test schema/type conversion, dataset replacement, and price coverage. Seed twice and compare logical row counts and scoped totals. A failed ingestion cannot report a ready sandbox.

### H04: Implement the deterministic multi-agent sample

**Scope:** Build the synthetic retail database, coordinator and specialist agents, safe read-only SQL, health endpoints, and golden question set under `hack/sample-multi-agent-workload/`.

**Acceptance:** Fixed-seed data and evaluation expectations are reproducible. Supported questions return correct structured answers. The intentional unsupported question reports an explicit gap. Dependency failures remain distinct from data gaps.

**Validation:** Run local functional, SQL-safety, and golden evaluation tests without Azure. Incorrect results, invented explanations, writes, and multiple SQL statements fail.

### H05: Deploy the sample and add correlated telemetry

**Scope:** Independently deploy the containerized sample, monitoring, and model access through repository-root GitHub Actions workflows using the sample's directory-local entry scripts. Instrument actual model calls and agent spans.

**Acceptance:** The workload runs on Container Apps with approved identity-based model access. Telemetry includes model, tokens, experiment, variant, session, and parent/child correlation. No sensitive prompts, credentials, or database rows enter ordinary spans.

**Validation:** Build/start the container, validate Bicep, exercise readiness and actual model calls, and query the resulting Application Insights telemetry. In-memory exporter tests verify attribution and token accounting.

### H06: Make the live-price workbook portable and trustworthy

**Scope:** Remove embedded environment IDs and enrich the existing live workbook with price coverage and experiment/variant selection.

**Acceptance:** Deploy using outputs rather than manual query edits. Show populated agent/model/token results, unpriced usage, and useful baseline/candidate comparisons. Preserve supported cross-service joins and repository KQL conventions.

**Validation:** Run workbook JSON/Bicep checks and applicable KQL lint tests. Execute representative queries in the sandbox and visually inspect the workbook. Missing prices remain visible and cannot appear as free usage.

### H07: Orchestrate the complete seeded sandbox deployment

**Scope:** Compose building, deploying, seeding, generating demonstration traffic, and readiness verification into one manual workflow.

**Acceptance:** A workflow from the fork's `dev` creates the complete retained demo environment. It publishes application/workbook links, resolved source revisions, seed metadata, ownership, and verification results. No undocumented endpoint-copying steps remain.

**Validation:** Run from a clean hack-owned scope, then rerun safely. Test partial deployment and ingestion failures. Failed stages cannot publish a successful readiness summary.

### H08: Add bounded FinOps context and pricing tools

**Scope:** Reuse the existing Azure MCP integration and query catalog where appropriate. Expose scoped cost summary, resource cost, recommendation, and pricing context.

**Acceptance:** Responses preserve scope, source, freshness, and warnings. Out-of-scope requests fail. Historical sample IDs are not deployment targets. Empty recommendations are explicit, and provider failures never silently return fixture data.

**Validation:** Contract tests cover scope enforcement, empty results, provider failures, stale prices, units, and provenance. Verify the coding agent can retrieve the sandbox context through approved read-only paths.

### H09: Implement the experiment runner and cost evaluator

**Scope:** Extend the existing experiment contract with the required workload adapter and evaluated-answer evidence. Implement deploy, load, collect, compare, and cleanup stages.

**Acceptance:** Resolve exact baseline/candidate revisions and use identical data, load, region, and measurement rules. Record performance, quality, consumption, price coverage, and cost per successful answer. Failed guardrails or incomplete evidence cannot produce acceptance.

**Validation:** Test known calculations, failed requests, zero successful answers, mixed currencies, stale/missing prices, cached tokens, and duplicate attribution. Run repeated baselines to establish variance before interpreting candidate differences.

### H10: Connect the optimizer agent to the experiment workflow

**Scope:** Use existing optimizer agent/skill/command instructions to retrieve context, propose one bounded schema-context change, and request an approved experiment.

**Acceptance:** The agent does not modify measurement logic or weaken guardrails. Publish JSON and Markdown evidence with revisions, cost, quality, performance, coverage, limitations, and cleanup status. No automatic merge or upstream PR occurs.

**Validation:** Rehearse from a clean agent session. Verify an approved experiment produces a traceable decision record and that incomplete evidence is reported honestly.

### H11: Add explicit cleanup and expiration enforcement

**Scope:** Separate retained demo resources from temporary experiments. Add unconditional cleanup attempts, a scheduled expiration backstop, and confirmed full teardown.

**Acceptance:** Cleanup only targets identified hack-owned resources. Shared model endpoints are excluded. Failure is visible and retryable. Tags and budgets are not treated as automatic shutdown mechanisms.

**Validation:** Exercise success, failed deployment, failed load, cancellation recovery, and expiration paths. Verify evidence survives and full teardown removes every owned resource. Begin basic teardown alongside H02/H05; do not wait for this issue to close before adding failure cleanup.

### H12: Rehearse and document the complete hack demonstration

**Scope:** Create the demonstration runbook, verify the complete scenario, and retain presentation fallback evidence.

**Acceptance:** Recreate the environment without undocumented setup beyond recorded identity prerequisites. Demonstrate baseline/candidate workbook results, a failed guardrail or missing-price case, and successful cleanup. Label snapshots or simulated fallback data explicitly.

**Validation:** Run the full clean-environment rehearsal and record exact commands, workflow links, outcomes, and limitations. Confirm the application, workbook, agent tools, and evidence artifacts agree.

## Delivery gates

| Gate | Required work | Exit condition |
| --- | --- | --- |
| Workbook-ready sandbox | H01-H07 and the initial H11 cleanup path | One Action creates a populated, inspectable environment with teardown available |
| Credible optimization loop | H08-H10 | Equivalent experiments produce auditable cost, quality, and performance decisions |
| Presentation-ready hack | H11-H12 | Fresh deployment, failure handling, evidence retention, and teardown are proven |

Start basic cleanup with the infrastructure work. H11 tracks completion and failure-path verification, not permission to postpone teardown.

## Decisions to resolve before implementation

| Decision | Required result |
| --- | --- |
| Hack deadline | Delivery window and permitted scope |
| Spending ceiling | Total budget, model-call limits, experiment duration, and maximum resource lifetime |
| Model access | Approved endpoint/model, quota, pricing basis, deployment ownership, and any external dependency |
| Sample repository | Fork-owned location and revision/artifact handoff to the coordinating workflow |
| Guardrails | Quality, latency, error-rate, throughput, and acceptable measurement variance |
| Evidence retention | Artifact retention and how long the presentation environment remains deployed |

## Deferred work

Defer the autonomous harness, customer integration, standalone provider packaging, broad recommendation coverage, Fabric/Power BI integration, production hardening, and additional optimization scenarios.

Their specifications remain in the [repository blueprint index](./specs/repositories/README.md) for reference. They are not required dependencies for this hack.

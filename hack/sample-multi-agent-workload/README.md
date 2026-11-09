# FinOps multi-agent sample workload

For this hack, follow the [hack delivery plan](../project-plan.md). Its `H*` backlog controls scope and sequencing; the `SMP-*` backlog is a detailed implementation reference.

## H04 local sample

The local sample implements the five supported retail questions, the intentional shipment-delay gap, and clarification for questions outside that fixed set. Four typed agent instances cooperate through a replaceable JSON model-client contract. The explicitly selected `deterministic` adapter provides offline responses; it is not a live language model and does not establish model access, token usage, pricing, or savings.

The synthetic database contains six products, three customers, seven orders, and four shipments. Seed `42` reproduces identical database contents. The reference date is fixed at October 1, 2026, so "last month" means September 2026 regardless of the machine clock. Revenue uses order-item values in synthetic USD; fulfillment time means days from order placement to shipment. Curated business records are stable; the seed controls synthetic customer segments and reserved inventory.

Use Python 3.12 or later. From this directory:

```bash
python3.12 -m venv .venv
.venv/bin/python -m pip install -e '.[dev]'
.venv/bin/python -m sample_workload initialize --database data/retail.db --seed 42
.venv/bin/python -m sample_workload evaluate --database data/retail.db \
  --model-mode deterministic --questions tests/evaluation/questions.json \
  --output evidence/evaluation.json
.venv/bin/python -m sample_workload run --database data/retail.db \
  --model-mode deterministic --host 127.0.0.1 --port 8000
```

On Windows, use `.venv\Scripts\python.exe` in place of `.venv/bin/python`. Initialization refuses to overwrite a database; use a new output path to verify reproducibility. Database files and evaluation reports are ignored by source control.

In another terminal:

```bash
curl --fail http://127.0.0.1:8000/ready
curl --fail http://127.0.0.1:8000/api/questions \
  -H 'Content-Type: application/json' \
  -d '{"question":"Which products are below their reorder point?","sessionId":"local-1","experimentId":"offline-1","variant":"baseline"}'
```

Responses include `modelMode`, the actual agent-call sequence, schema version, reference date, and generated SQL. The coordinator returns `unable-to-answer` for shipment-delay causes without executing SQL. Unknown questions return `clarification-required`. Model failures, timeouts, invalid contracts, rejected queries, and query failures remain explicit; no failure falls back to fixture data.

SQL validation permits a single `SELECT`, restricts tables, and denies CTEs, `SELECT INTO`, writes, and multiple statements. SQLite additionally enforces read-only connections, a table/function authorizer, bounded rows, and execution timeouts. Over-limit queries fail instead of returning a partial answer. Direct `sqlite3` access is intentional: the connection-level authorizer provides the enforcement boundary.

The API's `/health` checks process availability. `/ready` checks the local schema without model calls; its response explicitly defers live endpoint and telemetry-exporter checks to H05. Dependency failures return HTTP 503, rejected queries return 422, and execution or answer-verification failures return 500. Model diagnostic text is not logged or copied into responses.

### Validation

```bash
.venv/bin/python -m pytest -q
.venv/bin/python -m ruff format --check .
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src tests
```

Golden expectations are checked-in values, not regenerated from the application. Evaluation compares statuses, answer text, columns, ordered rows, row counts, and agent calls, and exits nonzero on any mismatch. The tests also exercise unsafe SQL, provider failures at each agent, timeouts, incorrect results, and invented explanations. The root [sample CI workflow](../../.github/workflows/sample-workload-ci.yml) runs these checks and retains the offline evaluation report.

Container packaging, Azure deployment, managed-identity model access, OpenTelemetry export, load tests, and cleanup remain later hack work. The commands below those sections are planned interfaces, not implemented H04 capabilities.

## Source and deployment boundary

Build the sample in `hack/sample-multi-agent-workload/` within `bobjac/finops-toolkit`. The sample is a synthetic retail operations assistant that uses multiple agents to answer natural-language questions through NL2SQL.

Keep the application, synthetic data, tests, container, infrastructure, and entry scripts in this directory. Keep GitHub Actions workflows in the repository-root `.github/workflows/`; GitHub does not discover workflows nested under the sample directory. Use the same pinned repository revision for the sample and coordinating sandbox deployment.

The sample must build, test, and deploy without a FinOps hub. A separately deployed hub can monitor the sample's Azure scope and consume its cost and OpenTelemetry evidence. Sharing a source repository does not introduce a runtime dependency on the toolkit.

## Documents

- [Architecture](./architecture.md)
- [Project plan](./project-plan.md)

## Coding-agent startup instructions

1. Read both documents before creating application or infrastructure files.
2. Create dependency-aware tasks from the `SMP-*` backlog.
3. Build the local application and deterministic evaluation suite before provisioning Azure.
4. Use synthetic data only.
5. Implement parent and child OpenTelemetry spans before optimizing agent behavior.
6. Keep FinOps Toolkit connectivity optional and configuration-based.
7. Never write directly to FinOps hub core tables.
8. For this hack, start with schema-context reduction under equivalent infrastructure and load. Keep Container Apps rightsizing as a later reference scenario.
9. Implement [H04, issue #6](https://github.com/bobjac/finops-toolkit/issues/6) first: local deterministic data, agents, safe SQL, health endpoints, and golden evaluation. H05 adds Azure deployment and correlated telemetry; do not treat the broader roadmap as H04 scope.

## Independent deployment model

The hub and sample have separate deployment entry points in the same repository. The coordinating GitHub Actions workflows can deploy both:

```text
bobjac/finops-toolkit
  |-- FinOps hub deployment
  |-- hack/sample-multi-agent-workload/
  |     `-- Application, telemetry, load test, and synthetic data deployment
  `-- .github/workflows/
        `-- Coordinating sandbox deployment, experiments, and cleanup
```

The sample's subscription or resource group must be included in the hub's Cost Management export scope. Resource tags connect cost records to workload, experiment, variant, and revision.

Application and agent telemetry flows to the sample's Application Insights resource. FinOps Toolkit queries use that resource for token and agent attribution while FinOps hub supplies cost and pricing context.

## Full sample delivery target

Across the applicable hack issues, the sample must provide:

- A containerized HTTP API.
- At least three cooperating agents.
- A synthetic SQLite retail database.
- Supported and intentionally unsupported question sets.
- OpenTelemetry traces with agent and token attributes.
- Bicep deployment to Azure Container Apps.
- Azure Load Testing configuration.
- Baseline and candidate resource parameters.
- Functional, answer-quality, and performance guardrails.
- Resource tags compatible with FinOps analysis.
- Automated cleanup.

## Required commands

The following entry scripts are planned. Run them from `hack/sample-multi-agent-workload/`, or use that path as the working directory in repository-root workflows:

```powershell
./eng/Initialize-Local.ps1
./eng/Test-Sample.ps1
./eng/Deploy-Sample.ps1
./eng/Run-Evaluation.ps1
./eng/Run-LoadTest.ps1
./eng/Collect-Evidence.ps1
./eng/Remove-Sample.ps1
```

Each command must support noninteractive execution for GitHub Actions.

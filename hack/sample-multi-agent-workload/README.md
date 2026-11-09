# FinOps multi-agent sample workload

For this hack, follow the [hack delivery plan](../project-plan.md). Its `H*` backlog controls scope and sequencing; the `SMP-*` backlog is a detailed implementation reference.

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

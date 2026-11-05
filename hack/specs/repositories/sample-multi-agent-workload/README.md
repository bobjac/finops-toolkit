# FinOps multi-agent sample workload repository handoff

For this hack, follow the [hack delivery plan](../../../project-plan.md). Its `H*` backlog controls scope and sequencing; the `SMP-*` backlog is a detailed implementation reference.

## Target repository

Create a new standalone repository for the sample workload. The sample is a synthetic retail operations assistant that uses multiple agents to answer natural-language questions through NL2SQL.

The repository must deploy independently from FinOps Toolkit. A FinOps hub deployed from a development branch can monitor the sample's Azure scope and consume its cost and OpenTelemetry evidence.

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

## Independent deployment model

The two repositories deploy separately:

```text
FinOps Toolkit repository
  └── Deploy FinOps hub from the selected branch

Sample workload repository
  └── Deploy application, telemetry, load test, and synthetic data
```

The sample's subscription or resource group must be included in the hub's Cost Management export scope. Resource tags connect cost records to workload, experiment, variant, and revision.

Application and agent telemetry flows to the sample's Application Insights resource. FinOps Toolkit queries use that resource for token and agent attribution while FinOps hub supplies cost and pricing context.

## First implementation milestone

The initial deployment must provide:

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

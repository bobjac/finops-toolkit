# Sandbox configuration and preflight

Use the **Sandbox connection test** workflow in `bobjac/finops-toolkit` with **mode** set to `preflight`. This mode runs unit tests and PowerShell lint, signs in with OIDC, and reads Azure prerequisites. It never creates resources, registers providers, grants roles, requests quota, or calls a model. The default `smoke-test` mode still creates only `rg-ftk-sandbox-smoke`.

## Configuration

[sandbox.config.json](./sandbox.config.json) contains nonsecret settings, validated by the [sandbox schema](../src/design-time-optimizer/schemas/sandbox.schema.json).

| Setting | Hack configuration |
| --- | --- |
| Subscription, tenant, deployment identity | `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, and `AZURE_CLIENT_ID` in the fork's `sandbox` environment secrets |
| Region | `eastus2` |
| Resource group naming | `ftk-dto-hack-<component>-<run-id>`; downstream deployments must use this prefix and sandbox ownership tags |
| Expiration | February 1, 2027, at 11 PM US Eastern (`2027-02-02T04:00:00Z`) |
| Spending ceiling | USD 300 for the sandbox; this declaration is not an Azure spending cap |
| Sample repository | `bobjac/finops-toolkit-sample-workload`; H01 does not create it |
| Data Explorer | Development tier, `Dev(No SLA)_Standard_E2a_v4`; an unavailable or restricted SKU blocks deployment |
| Model ownership | A new sandbox-owned deployment; no external model endpoint or shared production resources |
| Preferred model | `gpt-5-mini`, with `GlobalStandard` and at least one capacity unit; not yet deployed or cost-validated |
| Experiment defaults | Maximum lifetime 90 minutes; at most two parallel variants |

Model capacity units are service-specific, not requests per second. Preflight discovers each model/SKU's `usageName` and maps it to the regional usage response. Fine-tuned model quota cannot approve a base model deployment. Unknown, exhausted, or unmatched limits fail. It tries Azure Quota CLI first; only an explicitly unsupported provider permits the documented Cognitive Services usage check instead. Other CLI failures remain blockers.

The report lists stable model versions with sufficient quota. H05 must pin the selected name, version, SKU, and capacity after checking current token prices and workload requirements. Baseline and candidate can share this sandbox-owned model, but must have separate telemetry labels.

The sandbox administrator approved GPT-5 mini after the regional catalog reported version `2025-08-07` as generally available, with retirement on July 13, 2027, and available `GlobalStandard` quota. These are discovery observations, not a capacity reservation or a pinned deployment. Preflight must recheck them before deployment.

Versions marked `Legacy` or `Deprecating` fail the conservative model gate even if they have quota and a future retirement date. The failure report includes lifecycle and quota observations so an administrator can distinguish outdated model preferences from insufficient quota. Select a current stable model before deployment; do not silently relax the gate.

## One-time administrator setup

1. Configure the Entra application and GitHub OIDC federation for the fork's `sandbox` environment. Do not copy client secrets or access tokens into configuration or source control. The verified federation subject for this fork is `repo:bobjac@1582053/finops-toolkit@1376015361:environment:sandbox`.
2. Keep the environment restricted to the fork's `dev` branch. A feature-branch trial requires explicit approval for that exact branch, then removal of its temporary branch policy after validation. Do not allow arbitrary branches.
3. Give the deployment identity the required resource management actions and permission to assign scoped roles. Contributor alone does **not** grant `Microsoft.Authorization/roleAssignments/write`. An administrator can grant Contributor plus appropriately scoped Role Based Access Control Administrator, or a narrower equivalent. Role-assignment conditions must permit the specific downstream identities and roles.
4. Register the providers named in the preflight report. The script only reports missing registrations; it does not change subscription settings. Review regional model access, quota, Azure Policy, and deny assignments with the subscription administrator.
5. After H02/H05 deploy resources and managed identities, grant the workflow the intended storage data access and Data Explorer database access. Grant the application identity model invocation access on the sandbox model resource, such as Cognitive Services OpenAI User. Wait for role propagation, then verify access. Deployment role grants are not proof of data-plane access.

For this temporary sandbox, the administrator explicitly approved unconditioned Role Based Access Control Administrator for the verified `finops-toolkit-sandbox-github` identity, scoped only to the sandbox subscription, alongside its existing Contributor role. This permits managing role assignments, including privileged roles; do not copy this unrestricted grant to a production subscription. Conditional delegation is the recommended alternative outside this approved temporary setup.

All planned resources are owned by this sandbox. The subscription, tenant, Entra deployment application, and GitHub environment are administrator-managed prerequisites. No paid shared external resources are assumed. Changing this boundary requires an explicit configuration/design decision.

## Readiness gates

The report separates these states:

| Gate | Meaning |
| --- | --- |
| Configuration only | JSON structure, limits, and expiration are valid; no Azure readiness is claimed |
| Infrastructure prerequisites | Identity matches the expected enabled subscription and tenant; providers, management actions including role assignment, development SKU listing, model access, and quota checks pass |
| Data ingestion | Infrastructure checks pass, and the actual deployed storage and Data Explorer data-plane checks pass |
| Model runtime access | Deferred until the application identity and endpoint exist; H05 must verify an actual authorized model call |

Set `dataPlane.storageAccountResourceId` and `dataPlane.dataExplorerResourceId` to deployment outputs, not guessed endpoints. Run with `-RequireDataPlane` before seeding. Both resources must be in the configured subscription. The read-only check lists storage containers using Entra authentication, checks blob read/write RBAC actions, and queries `Costs()` and `Prices()` in the Hub database. It does not write a probe blob, ingest data, or validate model inference. H03 must verify actual uploads/ingestion, including policy and network restrictions.

Missing resources are **Deferred**, not passed. `-RequireDataPlane` makes them blockers. A failed check throws after writing the evidence report, so deployment callers must stop rather than continue. No deployment pipeline is implemented in H01; H02/H07 must consume this gate. A passing SKU/quota check is not a capacity reservation or a guarantee against policy, conditional RBAC, regional stock changes, or later expiration.

```powershell
# Offline configuration check; no Azure calls.
./src/scripts/Test-DesignTimeOptimizerSandbox.ps1 -ConfigurationOnly

# Read-only Azure check using the signed-in workflow identity and environment IDs.
./src/scripts/Test-DesignTimeOptimizerSandbox.ps1 -ReportPath ./sandbox-preflight.json

# Required after deployment and before seeding.
./src/scripts/Test-DesignTimeOptimizerSandbox.ps1 -RequireDataPlane -ReportPath ./sandbox-preflight.json
```

In GitHub Actions, the workflow summary links each check to its result and a seven-day JSON artifact contains nonsecret evidence. CLI responses and authentication identifiers are not copied into that artifact. Authentication failures, test failures, and invalid configuration stop before Azure evidence is produced and remain visible as failed steps. Use Actions for tests when local PowerShell modules are unavailable:

```powershell
Invoke-Pester -Path ./src/powershell/Tests/Unit/DesignTimeOptimizerSandbox.Tests.ps1 -Output Detailed
Invoke-ScriptAnalyzer -Path ./src/scripts/Test-DesignTimeOptimizerSandbox.ps1 -Severity Warning,Error
```

## Cost and expiration limits

Budgets and expiration tags do not shut down Azure resources. Keeping paid Data Explorer and other services running until February can exceed USD 300. Deploy only for rehearsal windows, track cumulative subscription spend, and delete or stop resources promptly after each session. H02/H07 must apply ownership/expiration tags and cost controls; H11 must enforce cleanup and lifetime limits. Until those issues are delivered, do not treat these configuration fields as enforced safeguards or deploy unattended.

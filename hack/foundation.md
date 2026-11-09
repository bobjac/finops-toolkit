# Sandbox foundation

H02 uses the existing FinOps hub build, not a second implementation of its infrastructure. The fork-only **Sandbox foundation** workflow deploys `dev` through the `sandbox` environment using Azure CLI and OIDC.

## Scope and costs

The owned resource group is `ftk-dto-hack-foundation`, derived from `resourceGroupPrefix` in `sandbox.config.json`. Hub and cluster names include a deterministic subscription-and-group hash. The existing smoke-test group is separate.

The foundation includes the canonical hub's storage, Data Factory, managed identities, deployment scripts, Event Grid topic, and development-tier Azure Data Explorer with `Hub` and `Ingestion` databases. This fixture-first configuration does not create a Key Vault. Managed exports and recommendations are disabled, and no monitored billing scopes are configured. The workflow receives Blob Data Contributor on the hub storage account. Azure Data Explorer automatically grants its database creator Admin; verification requires a matching workflow application assignment in each database rather than creating duplicate assignments.

**Successful resources are retained and incur charges.** Data Explorer auto-stop is disabled by the canonical template. The USD 300 declaration is not a billing cap. The configured expiration is tagged, not automatically enforced by this workflow. H11 adds the scheduled cleanup backstop; remove unused resources manually until then.

H02 does not deploy the sample application, a model, telemetry, seeded cost/pricing fixtures, or the workbook. Those remain separate dependent issues. The canonical hub initialization references external toolkit open data; it is not the hack's pinned fixture ingestion or a current model rate card.

## Deploy and verify

Run these commands against the fork only:

```bash
gh workflow run sandbox-foundation.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Deploy -f confirmation=ftk-dto-hack-foundation

gh workflow run sandbox-foundation.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Verify
```

Deploy runs focused Pester tests and PowerShell lint, builds the canonical hub with `Build-Toolkit -Template finops-hub`, and compiles `foundation.bicep` against the generated `release/finops-hub` module. It runs read-only preflight before Azure writes, validates the deployment, then deploys twice with metadata verification. It refreshes Azure OIDC sign-in after the long-running deployments before verifying actual data-plane access. This avoids requesting new service-audience tokens with an expired GitHub assertion.

Metadata verification checks database provisioning, workflow database administration assignments, and ownership/source/expiration tags, and compares primary resource identities between passes. Final verification requires actual storage container listing, storage read/write RBAC, and read-only `Costs()` and `Prices()` calls as the workflow identity. Only data-plane-only preflight failures receive bounded propagation retries (six attempts, one minute apart); other failures stop immediately. Until final verification succeeds, deployment reports `DeployedAwaitingDataPlaneVerification`, with ingestion readiness false, not success.

Download the seven-day `sandbox-foundation-<run-id>` artifact. `foundation/foundation.json` contains the source revision, scope, inventory, deployment outputs, and per-pass metadata evidence. For Deploy, `foundation-verification/foundation.json` records final data-plane readiness; a standalone Verify records this in `foundation/foundation.json`. `sandbox.resolved.json` in the corresponding directory contains the actual storage/cluster IDs and can be passed as `-Path` to the read-only preflight or later ingestion tooling. The checked-in configuration is not rewritten. Readiness does not mean data has been uploaded or ingested; H03 must verify actual writes and ingestion.

The workflow's default is read-only `Verify`. Deploy and Remove require the exact resource group name. Arbitrary branches and upstream workflow runs are rejected.

## Remove the foundation

```bash
gh workflow run sandbox-foundation.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Remove -f confirmation=ftk-dto-hack-foundation
```

Removal verifies the signed-in subscription and tenant, deterministic group identity, location, and three ownership tags before deleting that group. It waits for deletion and verifies absence. It works after expiration and does not require Bicep, model availability, provider checks, or data-plane access. It never deletes the smoke-test group, application registration, subscription-level role grants, or unrelated resource groups. Key Vault soft-deleted vaults follow Azure retention rules; this workflow does not purge them.

For an offline plan, set the expected nonsecret `AZURE_SUBSCRIPTION_ID` and `AZURE_TENANT_ID`, then run:

```powershell
./src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1 -Operation Remove `
  -ConfirmResourceGroup ftk-dto-hack-foundation -WhatIf
```

`-WhatIf` makes no Azure calls and therefore does not prove ownership or access.

Before any writes, an existing group must have matching ownership tags; it is never adopted. If deployment fails, evidence is retained. The workflow automatically removes only a foundation first created by that run. It preserves any previously retained foundation after a failed redeployment; inspect the failure and explicitly remove it when appropriate. Cleanup failure fails its step and is recorded separately rather than reported as success.

## Verified sandbox deployment

[Workflow run 42098068765](https://github.com/bobjac/finops-toolkit/actions/runs/42098068765) passed on November 5, 2026, from fork revision `fca1552250ddc4b2a0abd8d722bc968cd08fe9a4`. The run took about 42 minutes overall: the first deployment pass took about 32 minutes, and redeployment took about eight minutes. These are observed timings, not a completion guarantee.

| Validation | Result |
| --- | --- |
| Pester: `DesignTimeOptimizerSandbox.Tests.ps1` and `DesignTimeOptimizerFoundation.Tests.ps1` | 35 passed, zero failed or skipped |
| PSScriptAnalyzer: foundation lifecycle and sandbox preflight scripts | No warnings or errors |
| `./src/scripts/Build-Toolkit.ps1 -Template finops-hub` | Passed |
| `bicep build ./release/finops-hub/main.bicep --outfile ./release/finops-hub/azuredeploy.json` | Passed |
| `bicep build ./hack/foundation.bicep --outfile ./release/hack-foundation.json` | Passed |
| Two deployment passes | Passed; storage, cluster, factory, and database identities unchanged |
| Final workflow-identity data-plane verification after refreshed sign-in | Passed; `ReadyForDataIngestion=true` |
| Failure cleanup in earlier runs | Newly created groups removed; absence independently verified |

The retained resources are in `eastus2`:

| Resource | Name |
| --- | --- |
| Resource group | `ftk-dto-hack-foundation` |
| Data Explorer cluster | `dtoa70ffd577ce4` |
| Databases | `Hub`, `Ingestion` |
| Storage account | `dtoa70ffd573365tbne7qfzy` |
| Data Factory | `dtoa70ffd577ce4-engine-3365tbne7qfzy` |

The cluster query endpoint is `https://dtoa70ffd577ce4.eastus2.kusto.windows.net`. Ownership, source, and expiration tags were verified. The tagged expiration is February 2, 2027, at 04:00 UTC, equivalent to the configured February 1 at 23:00 UTC-05:00. Resources remain running and billable; no automatic expiration shutdown or enforced spending cap is installed. Use the confirmed Remove command above when the foundation is no longer needed.

Storage reads and database function queries were exercised, but storage writes were checked only through RBAC. Fixture upload, actual ingestion, sample/model deployment, and workbook validation are not completed by this result.

For H03, [run 42158132682](https://github.com/bobjac/finops-toolkit/actions/runs/42158132682) deployed revision `e3ac06094ce7d8573b45442ca793ae57f96f79dd` twice to the same retained resource identities with 36-month final retention configured in the wrapper. The 35 unit tests, PowerShell lint, canonical hub build, wrapper compilation, and refreshed storage/ADX data-plane verification passed. The run took about 30 minutes and retained the resources. Actual seed upload and ingestion remain a separate validation gate in [sandbox seed data](./seed-data.md).

That seed gate subsequently passed in [run 42163169602](https://github.com/bobjac/finops-toolkit/actions/runs/42163169602): actual storage writes, six successful ingestion runs, and two matching hub snapshots were verified. The deployed settings confirmed 36-month final retention. See the seed document for source revision, sample counts, scoped totals, pricing coverage, and the remaining application/model/workbook boundaries.

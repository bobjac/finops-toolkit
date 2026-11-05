# Sandbox foundation

H02 uses the existing FinOps hub build, not a second implementation of its infrastructure. The fork-only **Sandbox foundation** workflow deploys `dev` through the `sandbox` environment using Azure CLI and OIDC.

## Scope and costs

The owned resource group is `ftk-dto-hack-foundation`, derived from `resourceGroupPrefix` in `sandbox.config.json`. Hub and cluster names include a deterministic subscription-and-group hash. The existing smoke-test group is separate.

The foundation includes the canonical hub's storage, Data Factory, Key Vault, managed identities, deployment scripts, and development-tier Azure Data Explorer with `Hub` and `Ingestion` databases. Managed exports and recommendations are disabled, and no monitored billing scopes are configured. The workflow receives Blob Data Contributor on the hub storage account. Azure Data Explorer automatically grants its database creator Admin; verification requires a matching workflow application assignment in each database rather than creating duplicate assignments.

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

Deploy runs focused Pester tests and PowerShell lint, builds the canonical hub with `Build-Toolkit -Template finops-hub`, and compiles `foundation.bicep` against the generated `release/finops-hub` module. It runs read-only preflight before Azure writes, validates the deployment, then deploys and verifies twice.

Verification checks database provisioning, ownership/source/expiration tags, actual storage container listing, storage read/write RBAC, and read-only `Costs()` and `Prices()` calls as the workflow identity. It compares primary resource identities between passes. Only data-plane-only preflight failures during deployment receive bounded propagation retries (six attempts, one minute apart); other failures stop immediately.

Download the seven-day `sandbox-foundation-<run-id>` artifact. `foundation.json` contains the source revision, scope, inventory, deployment outputs, and per-pass evidence. `sandbox.resolved.json` contains the actual storage/cluster IDs and can be passed as `-Path` to the read-only preflight or later ingestion tooling. The checked-in configuration is not rewritten. Readiness does not mean data has been uploaded or ingested; H03 must verify actual writes and ingestion.

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

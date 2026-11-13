# Deploy the complete hack sandbox

Use **Deploy hack sandbox** in `bobjac/finops-toolkit` on `dev` to build, deploy,
seed, generate live demonstration traffic, and verify the retained environment.
It composes the existing foundation, ingestion, sample, and workbook entry
points. The sample remains independently buildable and deployable.

The approved #9 validation preserves the retained groups and telemetry. A
clean-scope rebuild rehearsal is deferred to #14 and needs separate approval.
This workflow does not delete retained groups or claim that a clean deployment
has been tested.

## Prerequisites

Keep the existing `sandbox` required-reviewer protection and Azure OIDC
configuration. Its secrets are `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and
`AZURE_SUBSCRIPTION_ID`. The identity needs the existing foundation management,
storage/ADX data-plane, sample provisioning, scoped role-assignment, registry,
vault, and monitoring permissions. Missing permissions fail the affected stage.

The `sandbox` variables are:

| Variable | Requirement |
|---|---|
| `SAMPLE_DEPLOYER_OBJECT_ID` | Nonempty deployment principal object ID |
| `SAMPLE_PRICE_EVIDENCE` | Existing model and Analytics price JSON described in the [sample deployment guide](../sample-multi-agent-workload/README.md) |

Prices must be positive, applicable to the selected model/region/offer, and
verified within seven days. The freshly retrieved seed model prices must match
the configured sample rates. Stale or different rates stop deployment; the
workflow never refreshes an old timestamp or substitutes zero.

All stages use the same selected repository SHA. No endpoint, seed-run ID,
sample-run ID, or workbook ID is copied between stages by an operator.

## Start a deployment

Obtain approval for the paid operation, then dispatch:

```bash
gh workflow run sandbox-deploy.yml --repo bobjac/finops-toolkit --ref dev \
  -f confirmation=deploy-retained-hack-sandbox
```

In GitHub Actions, open **Deploy hack sandbox** and approve each intended
`sandbox` stage. A manual dispatch does not bypass those approvals. Each stage
rechecks the current `dev` revision and actual approval before Azure sign-in.
Publishing a newer `dev` commit can invalidate later stages of an older run.

The workflow holds both foundation and sample lifecycle concurrency locks,
including across approvals and fresh runners. It does not dispatch child
workflows that would deadlock on those locks. GitHub can replace pending
concurrency entries; do not assume waiting runs execute in order. Cancel a
specific redundant run only with separate approval.

## Deployment stages

| Stage | Work |
|---|---|
| Foundation | Prepare two typed seed packages from one fresh public price snapshot, check rates, build the canonical hub and wrapper, and deploy once |
| Verify | Verify foundation management and actual storage/ADX data-plane access with a fresh sign-in |
| SeedFirst | Ingest history and prices through supported staging paths and verify rows/totals |
| SeedSecond | Replace the same logical dataset and verify identical fingerprints, rows, and scoped totals |
| Infrastructure | Preview and provision the independently owned sample resources |
| Image | Build the selected sample revision in its registry |
| Application | Reuse or create the vault token and activate that source-tagged image |
| Validation | Run the seven golden questions and verify actual usage and correlated exported telemetry |
| Workbook | Deploy from verified outputs, read back its content, and run query/price-coverage checks |
| Readiness | Require every successful stage and current-run evidence before publishing links |

Each protected stage uses a fresh runner and Azure sign-in. Provisioning can
temporarily return the sample to its bootstrap image before application
activation. It is not a zero-downtime deployment or an automatic rollback.

One complete run builds one sample image and sends seven evaluated workload
requests, with up to 22 model calls under the existing fixed question mix.
There is no optimization experiment in this workflow and no savings claim.
Repeating the complete workflow repeats those paid operations.

## Inspect evidence and retry

The final summary links the application endpoint, workbook, and workflow run.
`hack-readiness-<run-id>-<attempt>` contains the machine-readable readiness
record, resolved source revisions, original sample attempt, seed provenance,
ownership, expiry, stage results, limitations, and failures.

Each stage uploads its cumulative nonsecret checkpoint as
`hack-stage-<stage>-<run-id>-<attempt>`, including diagnostics after failure.
Only JSON and prepared sample parquet files are uploaded, never API tokens.
Artifacts are retained for 30 days; download presentation evidence before expiry.

Successful readiness also publishes `sandbox-seed-<run-id>-<attempt>` and
`sample-validation-<run-id>-<attempt>`. Use the deployment's run ID for both
inputs in the existing context, workbook, or experiment workflows. Their
producer checks accept only the designated successful fork workflows. Original
checkpoint provenance is not rewritten when a later attempt packages it.

For a failed stage, inspect its artifact and fix the reported cause. A targeted
retry reuses the exact completed predecessor artifact, including its original
attempt, rather than downloading an arbitrary latest checkpoint. A new complete
manual run is the retained-scope rerun used for #9 validation.

A failed, skipped, canceled, partial, missing, stale, or mismatched stage cannot
publish successful readiness. The readiness job runs after failures when the
runner is available and writes a failed receipt. Hard cancellation or runner
loss can prevent receipt upload; absence is not success.

No retained group is automatically deleted on failure. Partial seed state and
paid resources can remain for diagnosis and a confirmed retry. Use the
[cleanup workflow](../cleanup/README.md) for separately approved removal.
Tags, budget declarations, expiry timestamps, and pending approvals do not
stop charges. Shared endpoints and soft-delete recovery state remain subject
to the documented cleanup exclusions.

## Offline validation

With PowerShell, Pester 6, PSScriptAnalyzer, and Git installed:

```powershell
$paths = @(
    './hack/deployment/tests/Deployment.Tests.ps1'
    './hack/sample-multi-agent-workload/tests/SampleDeployment.Tests.ps1'
    './src/powershell/Tests/Unit/DesignTimeOptimizerFoundation.Tests.ps1'
    './src/powershell/Tests/Unit/DesignTimeOptimizerSeed.Tests.ps1'
)
$result = Invoke-Pester -Path $paths -Output Detailed -PassThru
if ($result.Result -ne 'Passed') { throw 'Orchestration tests failed.' }
$issues = @(Get-ChildItem ./hack/deployment -File -Filter *.ps1 |
    ForEach-Object { Invoke-ScriptAnalyzer $_.FullName -Severity Warning,Error })
if ($issues.Count) { $issues; throw 'Orchestration lint failed.' }
```

```bash
node --test hack/deployment/tests/predecessor.test.mjs \
  hack/sample-multi-agent-workload/tests/deployment.test.mjs
python3 -m unittest discover -s src/design-time-optimizer/seed -p 'test_*.py' -v
actionlint .github/workflows/sandbox-deploy.yml \
  .github/workflows/sandbox-deploy-stages.yml .github/workflows/sandbox-context.yml \
  .github/workflows/sandbox-workbook.yml .github/workflows/sample-experiment.yml
git diff --check
```

The Python checks need the existing `src/design-time-optimizer/seed/requirements.txt`.
Offline failure injection is not evidence of an actual failed Azure deployment,
failed ingestion, or successful live rerun.

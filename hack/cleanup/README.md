# Sandbox cleanup

Use the **Sandbox cleanup** workflow in `bobjac/finops-toolkit` on `dev`.
It preserves the retained demo unless you explicitly confirm one resource
group's teardown. Every Azure operation, including a scheduled run, requires
the existing `sandbox` environment approval.

**Pending approval is not shutdown.** Tags, budgets, and expiration timestamps
do not stop resources. The hourly backstop can remove expired experiment apps
only after approval and successful execution. Review failed or waiting runs.

## Choose an operation

| Operation | Scope | Effect |
|---|---|---|
| `Plan` | Any component | Read-only ownership and inventory checks; writes a receipt |
| `Expired` | `Experiments` | Deletes only expired, exactly owned temporary experiment apps |
| `Teardown` | `Sample`, `Foundation`, or `Validation` | Deletes one exactly confirmed group after ownership checks |
| `Validate` | Isolated fixtures | Creates and removes cleanup fixtures; preserves the retained demo |

The schedule requests `Expired` for `Experiments` at minute 17 of each hour.
It never requests retained group teardown. GitHub schedules can be delayed,
and pending runs can be replaced by newer runs. Do not rely on the schedule
for an unattended expiration guarantee.

Cleanup holds the existing foundation and sample deployment concurrency
locks. A deployment or another protected operation can delay it. Approve only
the intended run at the current `dev` revision; the workflow rejects stale
revisions and missing approval evidence before Azure sign-in.

## Inspect a read-only plan

Run this command from an authenticated GitHub CLI session:

```bash
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Plan -f component=Experiments
```

In GitHub Actions, open **Sandbox cleanup**, select that run, and approve its
`sandbox` deployment. Inspect the summary and downloaded
`sandbox-cleanup-<run-id>-<attempt>` artifact. For retained groups, run a separate
plan with `component=Sample` or `component=Foundation`.

Plans report eligible targets but do not claim verified removal. An already
absent group is reported separately. Missing, malformed, or failed Azure
responses are errors, not evidence that resources are absent.

## Remove expired experiments

After inspecting the plan, request cleanup and approve that specific run:

```bash
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Expired -f component=Experiments
```

An eligible app must have the exact subscription, sample group, experiment
name, run ID, variant, source revision, and repository ownership tags. Its
`expires-on` value must be an unambiguous ISO 8601 timestamp with an explicit
UTC offset. Cleanup rechecks ownership and expiration immediately before
deletion and verifies the app is absent afterward.

Fresh apps and the retained demo are skipped. Invalid ownership or expiration
on an experiment-shaped app fails the run visibly; cleanup still attempts
other eligible apps. Correct the underlying problem after inspection, then
retry. Do not copy ownership tags onto an unrelated resource to make it pass.

## Validate without deleting the demo

Obtain separate approval for fixture creation and deletion, then dispatch:

```bash
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Validate -f confirmation=validate-owned-cleanup-fixtures
```

Approve that run's `sandbox` deployment. Validation creates one isolated group,
`ftk-dto-hack-cleanup-validation`, containing the managed identity
`id-dto-cleanup-validation`. It also creates two current-run experiment apps
in the existing sample environment, using the retained image and identity.
They have no ingress, a minimum of zero replicas, and deterministic model mode.
Validation builds no image and sends no workload or model requests.

The controller verifies expired-app removal, fresh-app preservation, and
recovery after explicitly expiring the remaining fixture. This recovery is
a **simulated interrupted run**, not an actual canceled workflow. It then
deletes the entire isolated group, verifies the retained image is unchanged,
and attempts exact fixture cleanup in `finally`, including after deployment
or verification failure.

Expiration during validation is filtered to the exact fixture run. Other
experiment runs are not validation targets. An existing validation group
blocks fixture creation; inspect its receipt and ownership before explicitly
recovering it.

Inspect `validation.json` and the nested cleanup receipts. A successful fixture
run does **not** prove teardown of the retained sample or foundation. Retained
teardown remains untested until separately approved and exercised.

## Tear down a retained group

**These operations remove the demo or its foundation. Do not run them before
recording unless you intend to rebuild.** First download any required evidence
and inspect a fresh plan for each group. Obtain separate approval for each
exact deletion.

To delete the sample, including its registry, vault, sandbox-owned model,
monitoring, workbook, and apps:

```bash
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Teardown -f component=Sample \
  -f confirmation=ftk-dto-hack-s-ae46
```

After that operation succeeds, request foundation teardown separately:

```bash
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=Teardown -f component=Foundation \
  -f confirmation=ftk-dto-hack-foundation
```

Approve each specific `sandbox` deployment. Cleanup checks every resource in
the group inventory, including known provider-generated monitoring and Event
Grid relationships. A shared, excluded, unrecognized, or unowned resource
blocks whole-group deletion. A name prefix alone never authorizes deletion.
Inventory and ownership are checked again before the destructive call.

External/shared model endpoints are not targets. If a shared endpoint is
inside a selected group, teardown refuses the entire group instead of
deleting it. Confirmed teardown does not require expired tags or current model
prices. It polls for group absence for up to 30 minutes and fails visibly if
deletion remains incomplete.

Group deletion does not purge soft-deleted recovery state or establish zero
total cost. Resource locks, permissions, provider failures, and recovery
retention can require operator follow-up.

## Recover and retain evidence

Every cleanup attempt writes nonsecret JSON receipts outside the Azure groups
being removed. Artifacts are retained for 30 days; download them before expiry.
Failures remain failures even if later cleanup succeeds. Keep the failed run's
receipts alongside the successful retry.

A canceled runner might not finish `finally` or upload its artifact. Inspect
Azure inventory and the original workflow logs. After expiration, request
`Expired` or approve the scheduled backstop. For an owned validation group left
behind, inspect a `Plan` and separately confirm its exact group name with
`Teardown`. Never cancel an active deployment merely to acquire a cleanup lock
without separate approval.

Local `-WhatIf` prevents deletion but does not count as verified cleanup.
Receipts can still be written. Use `Plan` for the supported read-only workflow.
There is no automatic failure-issue creation, unattended deletion identity,
soft-delete purge, or retained-resource expiration.

## Run offline checks

Use PowerShell with Pester 6, PSScriptAnalyzer, and Git installed:

```powershell
$paths = @(
    './hack/cleanup/tests/Cleanup.Tests.ps1'
    './hack/sample-multi-agent-workload/tests/Experiment.Tests.ps1'
    './hack/sample-multi-agent-workload/tests/SampleDeployment.Tests.ps1'
    './src/powershell/Tests/Unit/DesignTimeOptimizerFoundation.Tests.ps1'
)
$result = Invoke-Pester -Path $paths -Output Detailed -PassThru
if ($result.Result -ne 'Passed') { throw 'Cleanup lifecycle tests failed.' }
$scripts = @((Get-ChildItem ./hack/cleanup -File -Filter *.ps1).FullName) + @(
    './hack/sample-multi-agent-workload/eng/Remove-Sample.ps1'
    './hack/sample-multi-agent-workload/eng/Sample-Common.ps1'
    './src/scripts/Invoke-DesignTimeOptimizerFoundation.ps1'
)
$issues = @($scripts | ForEach-Object {
    Invoke-ScriptAnalyzer $_ -Severity Warning,Error
})
if ($issues.Count) { $issues; throw 'Cleanup lint failed.' }
```

```bash
node --test hack/sample-multi-agent-workload/tests/deployment.test.mjs
actionlint .github/workflows/sandbox-cleanup.yml
git diff --check
```

Offline tests inject deployment, load-orphan, cancellation-orphan, and deletion
failures. They do not constitute live failure or cancellation evidence.

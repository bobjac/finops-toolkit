# Record the FinOps design-time optimizer PoC

Prepare off camera, then record a **3-5 minute** walkthrough. Target **4 minutes
30 seconds**. This is a working proof of concept, not a production-readiness
claim. Keep [issue #14](https://github.com/bobjac/finops-toolkit/issues/14) open
until the clean rehearsal, video, and portal submission are verified.

## Safety and readiness

| Entry point | Effects |
|---|---|
| `python -m sample_workload.demo prepare` | Reads local originals, reproduces the original decision, tests an isolated missing-price copy, and writes a new evidence package |
| `Prepare-DemoAccess.ps1` | Read-only Azure/app checks using your interactive identity; no secret retrieval |
| `Prepare-DemoAccess.ps1 -Operation Capture` | **Separately approved paid operation**: reads the existing API secret privately and sends one inventory question, without retrying |
| `python -m sample_workload.demo show` | Local integrity/freshness checks, verified links, and scene pauses; no Azure commands, credentials, or model requests |
| `show --open-links` | Also opens the actual app documentation, workbook, source comparison, and local evidence in your browser |
| Existing deployment/experiment/cleanup workflows | Separate approved operations; never called by the presentation |

`prepare` exits **0** only when recording inputs are ready. Exit **2** means
not ready: inspect its reasons and repair the missing prerequisite. A valid
historical comparison can still produce a **not recording-ready** package
when its prices are stale, viewer access is missing, or materials are absent.
The original decision is preserved, not reinterpreted as a current saving.
Malformed or inconsistent primary evidence stops export altogether.

The negative case removes the output meter from an **in-memory copy**, then
calls the unchanged evaluator at the original workflow completion time.
It is a labeled synthetic replay, not a live failure, price refresh, or new
optimization experiment. The real inputs and original price dates stay unchanged.

The local manifest establishes file integrity, **not a digital signature or
independent GitHub attestation**. Obtain originals directly from the exact
successful fork runs. Never assemble unrelated artifacts or claim that a
local receipt proves access by a different identity.

## Runtime and identity prerequisites

Run the following PowerShell blocks from the repository root, off camera.
Use PowerShell 7.2 or later, GitHub CLI, Azure CLI, and Python 3.12 or later.
The sample's existing editable environment must include its runtime/dev
dependencies; follow the [sample setup](../sample-multi-agent-workload/README.md)
if it is missing. Linux/macOS paths are shown.

```powershell
$ErrorActionPreference = 'Stop'
pwsh --version
gh --version
az version
$Python = (Resolve-Path ./hack/sample-multi-agent-workload/.venv/bin/python).Path
& $Python --version
gh auth status
az account show --query '{subscription:id,tenant:tenantId,type:user.type}' -o json
git status --short
git log -1 --format='%H %s'
foreach ($number in 9, 12, 13) {
    gh issue view $number --repo bobjac/finops-toolkit --json number,state,stateReason,url
    if ($LASTEXITCODE) { throw 'Prerequisite lookup failed.' }
}
```

All three issues must remain closed as completed. Use the existing `sandbox`
OIDC identity and protected reviewers for workflows. Your **interactive user**
must separately have management read access to the retained sample, Log
Analytics read/query access to its Application Insights workspace, and query
access to the foundation's **Ingestion** database. Capture also requires read
access to the existing sample API secret. Resolve denied permissions through
the approved access path; do not grant roles to make recording succeed.

The only Azure subscription is `6e87e78d-fe02-4f01-bd7b-4f2157eabd5a`, in tenant
`3670e846-58dd-4658-86fb-00e4029045d6`. Retained groups are
`ftk-dto-hack-s-ae46` and `ftk-dto-hack-foundation`, in `eastus2`.
Historical June 2024 resource IDs are sample context, never mutation targets.

## 1. Archive, clean, and rebuild off camera

**Approval required before any dispatch below.** Archive the existing genuine
experiment, proposal/context, deployment, and cleanup artifacts before deleting
anything. Experiment/context artifacts expire after seven days; combined
deployment and cleanup artifacts retain for 30 days. Keep a private durable
copy outside Actions and the Git checkout, with a second approved backup.
Do not commit evidence, credentials, or video files.

The last accepted historical experiment is **43351201733**, attempt **1**:
baseline `c9df575ea8fa90cfec45072085d9919e21a12068`, candidate
`79a087dce14212ac6f47d090860001dbfa0fb47b`. Its original pricing date is
**November 6, 2026, 04:34:37 UTC**, expiring seven days later. Its accepted
6.0996776593% model-only unit-cost improvement is **historical**, not a
promise for the next run. Do not select reruns to obtain favorable savings.
The associated context run is **43346115712**, attempt **1**. The second
accepted retained deployment is **43458199549**, attempt **1**. These IDs
are archive references, not defaults claiming a fresh clean rehearsal.

Use the [cleanup guide](../cleanup/README.md) to review exact ownership plans.
Do not run teardown commands until each exact group has been approved.
Finish and inspect each run before starting the next one.

```powershell
# Read-only ownership plans, still protected by the sandbox environment.
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev -f operation=Plan -f component=Sample
# After inspecting that plan and receiving exact Sample teardown approval:
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev -f operation=Teardown -f component=Sample -f confirmation=ftk-dto-hack-s-ae46

# Only after Sample teardown succeeds, inspect the separate Foundation plan:
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev -f operation=Plan -f component=Foundation
# After separate exact Foundation teardown approval:
gh workflow run sandbox-cleanup.yml --repo bobjac/finops-toolkit --ref dev -f operation=Teardown -f component=Foundation -f confirmation=ftk-dto-hack-foundation

# After separate clean deployment and paid validation approval:
gh workflow run sandbox-deploy.yml --repo bobjac/finops-toolkit --ref dev -f confirmation=deploy-retained-hack-sandbox
gh run list --repo bobjac/finops-toolkit --branch dev --limit 10
```

Approve intended actual GitHub environment gates yourself. The combined
deployment sends seven evaluated requests/up to 22 model calls. Neither a chat
approval nor a pending gate is successful execution. Keep `dev` stable across
its protected stages. Concurrent scheduled cleanup can hold lifecycle locks;
cancel only an exact separately approved redundant run.

Verify complete deletion from each cleanup receipt and absent resource group
before claiming a clean rebuild. Retained telemetry is deleted with the sample:
**do not replay old spans into the rebuilt workbook**. Soft-delete recovery
state, registry artifacts, and external shared endpoints follow the cleanup
guide's exclusions. If name recovery or permissions block rebuilding, stop and
record the cause; do not purge soft-deleted resources or change scopes without
new approval. Preserve receipts even on failure.

The [deployment guide](../deployment/README.md) lists identity prerequisites,
stage recovery, and `SAMPLE_PRICE_EVIDENCE` requirements. Refresh prices only
through the separately approved retrieval/configuration path. Keep actual
retrieval timestamps: changing an old date is not a refresh. Fresh Hub prices
must match the configured sample/workbook rates.

## 2. Capture the proposal, then run one approved experiment

Set the actual successful clean deployment run ID when prompted. These are
runtime inputs, not filenames or revision placeholders.

```powershell
$DeploymentRun = Read-Host 'Successful complete clean deployment run ID'
if ($DeploymentRun -notmatch '^[0-9]+$') { throw 'A real run ID is required.' }
# Separately approved read-only protected context retrieval:
gh workflow run sandbox-context.yml --repo bobjac/finops-toolkit --ref dev -f "seed_run_id=$DeploymentRun"
```

Save all four original context envelopes and use the read-only proposal prompt
in the [optimizer guide](../sample-multi-agent-workload/experiments/optimizer.md).
The candidate already exists. Request a proposal to **evaluate that exact
published bounded change**, not another code change or a claim that the new
conversation created the earlier candidate. Save its actual JSON/Markdown and
approval record before starting measurement. The JSON must include:

- `repository`, `revisions.baseline`, `revisions.candidate`, and
  `candidateBoundary.soleRuntimePath`, as in the optimizer guide.
- `contextRetrieval.workflow.runId` and `contextRetrieval.responses`: exactly four
  objects containing `tool` and the SHA-256 of that original tool JSON file.
- The objective, hypothesis, original context scope/freshness, risks,
  unchanged conditions/guardrails, and pending approvals.

Use a new genuine proposal/context for the fresh experiment. Do not silently
attach new context to an old proposal or change its original hashes.

After separate approval for two images, temporary apps, **at most 24 workload
requests/96 model calls**, and exact temporary-app cleanup:

```powershell
$Baseline = 'c9df575ea8fa90cfec45072085d9919e21a12068'
$Candidate = '79a087dce14212ac6f47d090860001dbfa0fb47b'
& $Python -m sample_workload.experiment_sources --baseline $Baseline --candidate $Candidate
if ($LASTEXITCODE) { throw 'The exact source boundary failed.' }
gh workflow run sample-experiment.yml --repo bobjac/finops-toolkit --ref dev -f operation=run -f "baseline_revision=$Baseline" -f "candidate_revision=$Candidate" -f "seed_run_id=$DeploymentRun" -f "sample_run_id=$DeploymentRun"
```

Wait for both baseline passes, the candidate, stable telemetry, the evaluator,
and verified temporary-app cleanup. Accept, reject, and repeat are valid
demo outcomes; missing evidence is a blocker. A fresh experiment is necessary
after cleanup removes the workbook's old telemetry.

## 3. Download exact evidence and run local preparation

Keep the same PowerShell session. Choose actual completed context and
experiment IDs, and a private retention directory outside the repository.
This block downloads originals only; it does not dispatch anything.

```powershell
$ContextRun = Read-Host 'Successful proposal context run ID'
$ExperimentRun = Read-Host 'Completed successful experiment run ID'
foreach ($id in $ContextRun, $ExperimentRun) {
    if ($id -notmatch '^[0-9]+$') { throw 'A real run ID is required.' }
}
$EvidenceHome = Read-Host 'Approved private evidence directory outside the Git checkout'
$Session = Join-Path $EvidenceHome ("rehearsal-" + (Get-Date -Format yyyyMMdd-HHmmss))
$Inputs = Join-Path $Session originals
$null = New-Item -ItemType Directory -Path $Inputs
foreach ($item in @(
    @{Name='deployment'; Id=$DeploymentRun},
    @{Name='experiment'; Id=$ExperimentRun},
    @{Name='context'; Id=$ContextRun}
)) {
    gh api "repos/bobjac/finops-toolkit/actions/runs/$($item.Id)" --jq '{id,run_attempt,head_sha,path,status,conclusion,created_at,updated_at,event,head_branch,repository:{full_name:.repository.full_name}}' |
        Set-Content (Join-Path $Inputs "$($item.Name)-run.json") -Encoding utf8
    if ($LASTEXITCODE) { throw 'Producer metadata retrieval failed.' }
}
$DeployAttempt = (Get-Content "$Inputs/deployment-run.json" -Raw | ConvertFrom-Json).run_attempt
$ExperimentAttempt = (Get-Content "$Inputs/experiment-run.json" -Raw | ConvertFrom-Json).run_attempt
$ContextAttempt = (Get-Content "$Inputs/context-run.json" -Raw | ConvertFrom-Json).run_attempt
gh run download $DeploymentRun --repo bobjac/finops-toolkit -n "hack-readiness-$DeploymentRun-$DeployAttempt" -D "$Inputs/deployment"
if ($LASTEXITCODE) { throw 'Readiness artifact unavailable.' }
gh run download $DeploymentRun --repo bobjac/finops-toolkit -n "sample-validation-$DeploymentRun-$DeployAttempt" -D "$Inputs/sample"
if ($LASTEXITCODE) { throw 'Sample artifact unavailable.' }
gh run download $DeploymentRun --repo bobjac/finops-toolkit -n "sandbox-seed-$DeploymentRun-$DeployAttempt" -D "$Inputs/seed"
if ($LASTEXITCODE) { throw 'Seed artifact unavailable.' }
gh run download $ExperimentRun --repo bobjac/finops-toolkit -n "sample-experiment-$ExperimentRun-$ExperimentAttempt" -D "$Inputs/experiment"
if ($LASTEXITCODE) { throw 'Experiment artifact unavailable.' }
gh run download $ContextRun --repo bobjac/finops-toolkit -n "sandbox-context-$ContextRun-$ContextAttempt" -D "$Inputs/context"
if ($LASTEXITCODE) { throw 'Context artifact unavailable.' }
$Proposal = Read-Host 'Path to the genuine saved proposal JSON for this experiment'
Copy-Item -LiteralPath $Proposal -Destination "$Inputs/proposal.json"
$Preflight = Join-Path $Session preflight
& $Python -m sample_workload.demo prepare --input $Inputs --output $Preflight
if ($LASTEXITCODE -notin 0, 2) { throw 'Unexpected preparation failure.' }
```

The initial **not-ready** result is expected: viewer access, retention approval,
screenshots, and the opening answer have not been supplied. It must still say
`historicalEvidenceVerified: true` before continuing. Missing/inconsistent
primary files instead stop export. Do not edit generated readiness or manifests
to bypass a failure.

Download and retain actual teardown plans/results and clean rebuild receipts
alongside `$Inputs`. Preserve complete original proposal Markdown and approval
evidence privately. Metadata/provenance checks are not a substitute for inspecting
actual workflow/environment approvals.

## 4. Verify the viewer and capture the opening answer off camera

Read `preflight/preparation.json` for real app/workbook links, experiment hash,
and absolute UTC measurement window. Open the workbook **AI Agent Tokenomics
(live hub prices)**, select that exact hash, and set a time range containing
all three passes. Confirm the summary, token chart, baseline/candidate rows,
and price evidence render with no permission/query errors and no unpriced calls.
Do not infer interactive access from the workflow identity.

Only after that visual check:

```powershell
pwsh -NoProfile -File ./hack/sample-multi-agent-workload/eng/Prepare-DemoAccess.ps1 -InputDirectory $Inputs -PreparationFile "$Preflight/preparation.json" -OutputFile "$Inputs/viewer.json" -WorkbookRendered
if ($LASTEXITCODE) { throw 'Interactive access checks failed.' }
```

The checker verifies the currently ready retained image, app documentation,
the exact three measurement windows via the existing stable telemetry collector,
and real Ingestion price-table query access. It does not grant anything.
Its receipt expires after one hour. Recheck rather than editing its date;
archive a previous receipt before replacing it.

The experiment intentionally did not retain full answer bodies. After **separate
approval for one question/up to four model calls and private secret read**:

```powershell
pwsh -NoProfile -File ./hack/sample-multi-agent-workload/eng/Prepare-DemoAccess.ps1 -InputDirectory $Inputs -PreparationFile "$Preflight/preparation.json" -OutputFile "$Inputs/opening.json" -Operation Capture -Confirmation capture-one-inventory-question
if ($LASTEXITCODE) { throw 'The single capture failed. Do not automatically retry.' }
```

This validates the real inventory answer and retains its rows, usage, and trace
ID. It is separate from the experiment and cannot establish optimization savings.
Do not run Capture on camera, under a transcript, or with debug logging.
No token appears in its output file. A missing secret fails; it is never created.

## 5. Finish the evidence package

Capture sanitized PNG screenshots named `application.png`, `workbook.png`, and
`proposal.png` under `$Inputs/screenshots`. The application image should show
the retained real answer and trace/call breakdown, not a synthetic test fixture.
Hide account menus, customer tabs, identifiers unrelated to the demo, credential
history, and notifications. Review images and exported text privately.

After agreeing actual retention location and resource lifetime:

```powershell
$RetainUntil = [DateTimeOffset](Read-Host 'Approved evidence/resource retention end in UTC, ISO 8601')
@{
    approved = $true
    retainUntilUtc = $RetainUntil.ToUniversalTime().ToString('o')
    materialsReviewed = $true
} | ConvertTo-Json | Set-Content "$Inputs/retention.json" -Encoding utf8
$Presentation = Join-Path $Session ("presentation-" + (Get-Date -Format yyyyMMdd-HHmmss))
& $Python -m sample_workload.demo prepare --input $Inputs --output $Presentation
if ($LASTEXITCODE) { throw 'Not recording-ready; inspect preparation.json and stop.' }
& $Python -m sample_workload.demo verify --directory $Presentation
if ($LASTEXITCODE) { throw 'Evidence integrity failed.' }
```

The output includes the original reproduced comparison, quality/performance and
tokens, pricing provenance with original dates, curated proposal/context,
the opening answer, screenshots, workflow/revision links, the labeled negative
case, SHA-256 manifest, and an offline `index.html` evidence view. Account names
and raw telemetry spans are not exported. Review remains necessary; filtering
cannot certify screenshot privacy. Back up the package **and** private originals
to the approved retention location and verify both copies can be opened.

Retained resources remain billable. Record their owners privately, exact scopes,
expiry, and approved teardown plan. Tags, budgets, and queued cleanup approvals
are not shutdown. Package readiness does not mean issue #14 is complete.

## 6. Rehearse and record

Close personal/customer windows, enable Do Not Disturb, enlarge text, and test
audio/screen capture. Keep narration outside the captured area. Open `index.html`
to show the recorded answer without sending another request. Also open the real
app `/docs`, live workbook, recorded proposal, and narrow source diff beforehand.
The app's root is an API base, not a frontend landing page.

```powershell
# Read-only, local by default. Press Enter between scenes.
& $Python -m sample_workload.demo show --directory $Presentation
# Optional browser navigation; still no workload invocation:
& $Python -m sample_workload.demo show --directory $Presentation --open-links
```

Do not run both during a single recording. The guided entry point rejects
tampered files, expired preparation/viewer checks, expired prices, or expired
retention. If preparation ages out, recheck access and export a new package;
never alter its generated dates/hashes. Browser access failures remain blockers.

### 0:00-0:35 - Problem and partner value

**Show:** the previously captured real inventory answer, two products, four
cooperating agent calls, trace ID, and capture date.

**Say:** "An AI assistant can give the right answer and still use more context
than it needs. In this synthetic retail example, several agents cooperate to
answer which products are below their reorder point. Each specialist can receive
unnecessary schema information on every request. This is a previously captured
real Azure OpenAI response, not a new experiment running during this video."

### 0:35-1:15 - Microsoft technology and the baseline

**Show:** the live workbook's selected experiment, absolute time window, token
chart, model identity, and original price evidence.

**Say:** "The sample runs on Azure Container Apps with Azure OpenAI. Application
Insights captures correlated model usage, and the FinOps hub in Azure Data
Explorer supplies public-retail pricing. The workbook connects those views.
Historical sample cost data helps identify opportunities; it is not current
sandbox spend. Our experiment fixes the data, model, seven questions, pacing,
and evaluation rules, then measures the baseline twice before the candidate."

### 1:15-2:05 - A bounded proposal with human approval

**Show:** the actual recorded proposal, four context sources/dates, narrow
`agents.py` diff, full baseline/candidate SHAs, and original approval evidence.

**Say:** "The design-time optimizer uses four bounded, read-only context tools:
cost summary, resource costs, cached recommendations, and current pricing.
Its hypothesis is to send each specialist only the complete table definitions
approved for that question. Both schema arguments change; the model, data,
agent call topology, measurement, and guardrails do not. This proposal predates
the selected measurement. A person approves publication, deployment, paid
traffic, and cleanup separately. The agent does not autonomously change production."

If you open a fresh coding-agent session, use the read-only prompt in issue #14.
Label it a **new review/proposal**, never the origin of the completed experiment.
It cannot edit files, dispatch workflows, or invoke the workload.

### 2:05-3:10 - Use only the actual decision branch

**Show:** the comparison table, answer counts, quality, errors, p95, token totals,
price coverage, baseline variation, and unchanged guardrails.

**Say:** "The denominator is successful evaluated answers, not model calls.
Every measured call's consumption stays in the numerator, including nonanswers
or failures. We require 100 percent answer quality, zero HTTP errors, complete
applicable prices, and no more than 20 percent p95 latency regression. An accepted
cost improvement must exceed both five percent and the observed baseline spread."

Read **one** branch, using the numbers on screen:

| Actual result | Narration |
|---|---|
| Accept | "This candidate passed those checks. Its measured public-retail model-only cost per 1,000 successful evaluated answers is lower by the displayed percentage. This small sequential PoC is not an invoice saving or a statistically powered benchmark." |
| Reject | "This candidate was rejected for the displayed result or guardrail. Finding an unsafe or more expensive change before adoption is useful; I am not claiming savings." |
| Repeat | "The measured difference did not clear the variation threshold, or a further controlled measurement is needed. The result is repeat, not accepted savings." |
| Incomplete evidence | **Stop preparation.** Do not narrate a missing row or unknown cost as zero or savings. |

### 3:10-3:45 - Show the synthetic negative case

**Show:** `negative.json` or its labeled section in `index.html`.

**Say:** "This is a synthetic negative test using an isolated copy of the
retained measurement. We remove the output-token meter and run the unchanged
evaluator at the original evaluation time, without changing price dates.
The result becomes repeat with incomplete evidence. Unknown cost does not
become zero. No live price, deployed app, or original decision was changed."

### 3:45-4:30 - Reuse and limits

**Show:** the original decision, evidence manifest, workflow links, and architecture:
Container Apps -> Azure OpenAI -> Application Insights; FinOps hub/ADX ->
workbook and bounded context -> human-approved experiment -> evaluator/cleanup.

**Say:** "A partner can reuse the standalone sample, bounded context adapters,
protected experiment, evaluator, and evidence handoff with another approved
workload. The value is a traceable design-time decision, including reasons to
reject or repeat. These are model-only estimates; infrastructure, telemetry,
builds, and warm-up are excluded. Show the linked off-camera cleanup receipts.
Resources retained for recording remain billable until their separately approved
teardown. This demonstrates the idea, not a production-ready autonomous optimizer."

Do not claim successful clean rebuild or cleanup unless actual receipts verify it.

## 7. Save the rehearsal record and submit

Record the exact Git revision, full commands/results, cleanup and clean rebuild
run links, context/proposal/experiment IDs, original pricing date, viewer check,
selected workbook window, package hash, actual elapsed duration, audio/readability
result, limitations, retention location, and final teardown approvals. Preserve
failure/recovery attempts, not just the successful outcome. Store that record
privately beside the package; it is evidence, not a checked-in planning document.

Play the exported video from beginning to end. Verify **3-5 minutes**, readable
figures, audible narration, no credentials/personal/customer content, honest
labels, and an outcome matching the package. A script or screenshot is not
evidence that a playable video exists.

Confirm the actual year, AM/PM, timezone, required files, size limits, and sharing
permissions in the **Microsoft PSA HTB Portal**. The organizer's email says
**November 27, 11:59 PT** but omits AM/PM. Aim to upload a day early. Submit the
video and requested materials, verify the portal confirmation, and retain that
confirmation privately. Optional slides should use the same verified evidence.
Do not publish submission receipts or personal details in GitHub.

Only then request explicit acceptance and closure of #14. Run final exact
Sample and Foundation teardown operations only under their separate approvals;
verify receipts and preserve the evidence even after Azure resources are gone.

## Local validation

From `hack/sample-multi-agent-workload`, using its existing dev environment:

```bash
.venv/bin/python -m pytest -q tests/test_demo.py tests/test_experiment.py tests/test_experiment_load.py
.venv/bin/python -m ruff format --check .
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src tests
```

From the repository root with PowerShell 7.5, Pester, and PSScriptAnalyzer:

```powershell
Invoke-Pester -Path ./hack/sample-multi-agent-workload/tests/DemoAccess.Tests.ps1 -Output Detailed
Invoke-ScriptAnalyzer ./hack/sample-multi-agent-workload/eng/Prepare-DemoAccess.ps1 -Severity Warning,Error
```

These are offline tests, including synthetic fixtures. They do not prove a
clean Azure rebuild, real viewer access, a recorded video, or submission.

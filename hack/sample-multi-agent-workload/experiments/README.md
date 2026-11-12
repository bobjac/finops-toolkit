# Controlled sample experiments

The **Sample experiment** workflow compares exact fork `dev` revisions without
updating the retained demo app. It implements issue #11's experiment adapter,
not issue #12's optimizer or issue #13's scheduled expiration backstop.

## What runs

The controller builds digest-pinned images from exact Git archives. It creates
one temporary baseline app, measures it twice, deletes it, then creates and
measures one candidate app. Both use the existing sandbox environment, registry,
identity, Key Vault, model deployment, and Application Insights resource.
Each app has one replica, 0.25 CPU, and 0.5 GiB of memory. The image builds the
same seed-42 SQLite database.

Each pass uses one inventory warm-up request and the same seven golden cases,
at concurrency one, with request starts at least 60 seconds apart. Warm-up
lasts at least one minute and is excluded from measured experiment selection.
The measured window is bounded to ten minutes. There are no retries: at most
24 workload HTTP requests and 96 model calls. Health probes do not invoke the
model. Three complete normal passes use 66 measured and 12 warm-up model calls.

The definition fixes 100% evaluated quality, zero HTTP errors, candidate p95
latency no more than 20% above the pooled baseline p95, and cost improvement
strictly greater than both 5% and observed baseline variation. With seven cases
per pass, nearest-rank p95 is the slowest request; pooled baseline p95 is the
larger of the two baseline p95 values.

## Source and measurement boundaries

Use two different full commit SHAs that are ancestors of `origin/dev`. Mutable
branch names and arbitrary candidate scripts are not accepted. The controller,
golden evaluator, infrastructure, and telemetry query always come from the
approved current workflow revision.

Data generation, dependencies, Dockerfile, golden questions, model settings,
runtime, API, and telemetry code must match between variants. Agent code is
also immutable except for the following bounded schema-context expression in
the existing `"schema"` arguments:

```python
(
    ";".join(
        statement
        for statement in SCHEMA.split(";")
        if any(statement.lstrip().startswith(f"CREATE TABLE {table}(") for table in SCOPES[pattern])
    )
    + ";"
)
```

The source verifier normalizes only that expression to `SCHEMA` and compares
the complete agent syntax tree. It rejects changes to call budgets, timeouts,
correlation, accounting, imports, and other agent behavior. This describes the
allowed candidate boundary; the adapter does not apply the optimization.
Protected file hashes and controller hashes are retained in the conditions
manifest. Both variants receive its exact same hash.

Two revisions with unchanged agent logic can exercise the runner. Such a run
is explicitly a **smoke test** and cannot receive an optimization acceptance,
even if cache effects make the candidate cheaper.

## Run an approved experiment

Before dispatching, verify that the retained sample has successful live
acceptance, the seed artifact is available, all three actual model meters remain
within their seven-day freshness window for the entire 90-minute lifetime, and
no sample deployment or cleanup is running. Existing
sample CI can queue a separate **Sample workload CD** run after publication.
Do not approve that retained-app deployment as part of this experiment; cancel
it if it is occupying the shared lifecycle concurrency group.

Obtain approval for the temporary apps, two image builds, bounded paid model
traffic, and scoped app cleanup. Then run this command with the actual approved
values:

```bash
gh workflow run sample-experiment.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=run \
  -f baseline_revision="$BASELINE_REVISION" \
  -f candidate_revision="$CANDIDATE_REVISION" \
  -f seed_run_id="$SEED_RUN_ID" \
  -f sample_run_id="$SAMPLE_RUN_ID"
```

Approve **Sample experiment**, not the retained sample deployment, in GitHub's
`sandbox` environment. Chat approval does not release that protection.
The workflow verifies the current `dev` tip, actual recorded approval, and
trusted predecessor run metadata before Azure login. API tokens come privately
from the existing Key Vault; do not enter them in commands or artifact files.
Source builds and telemetry collection can make a run take 30–60 minutes.

Download the exact completed attempt's artifact:

```bash
gh run download "$EXPERIMENT_RUN_ID" --repo bobjac/finops-toolkit \
  --name "sample-experiment-$EXPERIMENT_RUN_ID-$RUN_ATTEMPT" --dir .tmp/experiment
```

Inspect `definition.json`, `source-verification.json`, `conditions.json`,
`conditions.sha256`, the two `image-*.json` files, `pricing.json`, three
`run-*.json` files, `runs.json`, `cleanup.json`, and `decision.json`/`decision.md`.
Artifacts are retained for seven days. Preserve nonsecret presentation evidence
before expiration.

## Interpret the result

The report includes quality, HTTP errors, client p95, successful-answer
throughput, actual input/cached-input/output tokens, price coverage, model cost,
cost per successful answer, and normalized cost per 1,000 successful answers.
Only correct evaluated `answered` outcomes enter the denominator. The two
expected nonanswers and all consumed calls from failed requests remain in the
numerator.

Cached input is included in provider input tokens. Estimated cost is:

```text
((input - cachedInput) * inputRate
 + cachedInput * cachedInputRate
 + output * outputRate) / 1,000,000
```

The baseline reference is the mean of the two measured unit costs. Variation
is their full range divided by that mean. This small, sequential PoC is not a
statistically powered benchmark. A passing workflow means the experiment
completed, not that the candidate was accepted.

**Accept** requires complete evidence, verified app cleanup, a real eligible
agent change, all guardrails, and improvement above both thresholds.
**Reject** records a complete but non-improving or guardrail-failing comparison.
**Repeat** means incomplete evidence or insufficient improvement beyond
variation. Missing prices, usage, cached-token counts, span attribution, or
zero successful answers are unknown, never free. Unknown token totals are null;
known token subtotals are recorded separately. An unchanged-agent smoke
cannot support an optimization or savings claim.

Prices are the original public-retail USD meters from the verified Hub context,
not negotiated rates or billed costs. The estimate excludes warm-up,
infrastructure, builds, telemetry, retention, and shared charges. Retained
pricing evidence preserves its original retrieval timestamp and units.

## Cleanup and failure recovery

The controller writes its ownership plan before mutations, attempts app cleanup
in `finally`, and the workflow retries cleanup after failures. Deletion requires
the exact temporary app name, subscription/group, repository, experiment/run,
variant, source revision tag, and expiration tag. The retained app and shared
resources are never deletion targets. Cleanup receipts preserve removed IDs and
surface failures; the controller also verifies the retained app image did not
change.

After a failed or canceled run, inspect its cleanup receipt and Azure before
retrying. To retry cleanup for an original completed run:

```bash
gh workflow run sample-experiment.yml --repo bobjac/finops-toolkit --ref dev \
  -f operation=cleanup -f cleanup_run_id="$EXPERIMENT_RUN_ID"
```

This requires a separate actual `sandbox` approval, verifies the original run
belongs to this workflow in the fork, and can delete only its two named apps.
Cleanup does not send model requests.

The 90-minute expiration tag is a recovery identifier, **not an automatic
shutdown**. A hard cancellation or runner loss can interrupt cleanup; scheduled
expiration enforcement remains issue #13. Existing shared resources remain
billable. Image digests and deployment records remain as provenance artifacts
in the existing registry/resource group; app cleanup does not claim their
removal or zero residual charges.

## Local checks and offline reevaluation

From `hack/sample-multi-agent-workload`:

```bash
python -m pytest -q
python -m ruff format --check .
python -m ruff check .
python -m mypy src tests
```

From the repository root, with the supported PowerShell/Pester/analyzer tools:

```powershell
Invoke-Pester -Path ./hack/sample-multi-agent-workload/tests/Experiment.Tests.ps1,./src/powershell/Tests/Unit/DesignTimeOptimizer.Tests.ps1 -Output Detailed
Invoke-ScriptAnalyzer -Path ./hack/sample-multi-agent-workload/eng -Recurse -Severity Warning,Error
az bicep build --file hack/sample-multi-agent-workload/infra/experiment.bicep --stdout
```

Reevaluate retained evidence without Azure or model calls, from the sample:

```bash
python -m sample_workload.experiment \
  --definition ../../.tmp/experiment/definition.json \
  --runs ../../.tmp/experiment/runs.json \
  --questions tests/evaluation/questions.json \
  --pricing ../../.tmp/experiment/pricing.json \
  --conditions-hash "$(cat ../../.tmp/experiment/conditions.sha256)" \
  --cleanup ../../.tmp/experiment/cleanup.json \
  --source-verification ../../.tmp/experiment/source-verification.json \
  --output ../../.tmp/experiment/rechecked.json
```

Reevaluation uses current time for price freshness and exits nonzero for
incomplete evidence. An old artifact does not become fresh because it was
downloaded or reevaluated.

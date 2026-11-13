# Agent-led schema-context optimization

Use the existing `ftk-design-time-optimizer` agent and `/ftk/optimize` command
with `hack/sample-multi-agent-workload/experiments/schema-context.experiment.json`.
This is the fork's bounded issue #12 scenario, not an autonomous optimization
service. Read the experiment operator instructions before proceeding.

## Start with a proposal

Give a new agent session this prompt, replacing the artifact and revision inputs
with verified values:

```text
Use the FinOps Toolkit design-time optimizer instructions.
Work in bobjac/finops-toolkit on dev and propose the sample schema-context
optimization. Use the existing schema-context.experiment.json profile.
Baseline: <full unchanged baseline SHA>.
Seed artifact: <verified Sandbox seed data artifact directory>.
Scope: /subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46.
Retrieve all four bounded context tools. Propose narrowing the schema-agent
and SQL-agent prompts to SCOPES[pattern]. Do not alter any other runtime code,
data, model settings, measurement logic, or guardrails.
Stop after writing a JSON and Markdown proposal. Do not commit, push, dispatch,
deploy, invoke the workload, or delete resources without separate approval.
```

In the source checkout, read
`src/templates/agent-plugin/agents/ftk-design-time-optimizer.md`,
`src/templates/agent-plugin/skills/design-time-optimizer/SKILL.md`, and
`src/design-time-optimizer/context/README.md`. In the packaged plugin, this
guide is `skills/design-time-optimizer/references/sample-optimization.md`.
The sample source and runner still require the fork checkout; the plugin does
not contain or deploy a second copy of the workload.

Verify the seed run's fork, `dev` branch, successful conclusion, workflow path,
revision, and artifact binding. Use the existing context adapter to retrieve
`get_cost_summary`, `get_cost_by_resource`,
`get_optimization_recommendations`, and `get_current_pricing`. Preserve the four
response envelopes in the noncommitted proposal evidence directory. Stop on a
provider failure, invalid scope, or required-price failure.

If the local identity lacks Hub query access, stop and request the existing
protected **Sandbox context** workflow with the verified `seed_run_id`.
Do not grant roles or silently substitute old context. After explicit workflow
and actual `sandbox` approval, verify its successful fork/`dev` run, workflow
path, revision, seed binding, and downloaded response envelopes. Record this as
GitHub-identity retrieval, not successful local access. A failed protected
retrieval remains a blocker.

Historical June 2024 costs identify sample cost drivers, not current sandbox
spend or mutation targets. Empty Advisor recommendations are not proof that the
workload is optimized. Preserve pricing's original retrieval time; it must
remain fresh for the runner's full 90-minute lifetime.

## Form and implement one hypothesis

The hypothesis is that passing only the approved tables to **both** specialist
prompts reduces measured input consumption and estimated model cost per
successful evaluated answer without changing answers or call topology.
The schema agent's output must still equal the existing approved table set.
Prompt caching, output lengths, and model variability can offset input savings.
No percentage improvement is promised.

Capture the exact unchanged baseline SHA before edits. If the checkout already
contains the optimization, request the actual prior baseline; do not invent one
or use the candidate as its own baseline. Follow repository Git approvals and
branch policy. This fork uses approved direct-`dev` publication, not an automatic
candidate branch, pull request, or merge.

The only candidate runtime file is
`hack/sample-multi-agent-workload/src/sample_workload/agents.py`. Replace the
two existing `"schema": SCHEMA` argument values with the bounded expression
already allowed by the source verifier:

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

Do not refactor the expression into another helper, change `SCOPES`, or alter
timeouts, retries, model settings, evaluation, telemetry, prices, load, or
cleanup. Run the sample tests, formatting, lint, and strict type checks.
After approved publication, record the candidate's full commit SHA and run:

```bash
python -m sample_workload.experiment_sources \
  --baseline "$BASELINE_REVISION" --candidate "$CANDIDATE_REVISION"
```

This must report an eligible agent change and equivalent protected inputs.
Character-count reduction and deterministic tests are not measured token or
savings evidence.

## Request an experiment, not permission to deploy automatically

The proposal JSON and Markdown must record the objective, hypothesis, exact
baseline, candidate SHA when available, sole runtime path, four context response
references, original pricing freshness, expected input-meter change, risks,
tests, fixed guardrails, cleanup exclusions, and pending approvals. An
unpublished candidate or unrun experiment must remain explicitly pending.

Use the existing **Sample experiment** workflow and operator instructions.
Request separate approval for two image builds, temporary apps, at most
24 workload requests / 96 model calls, and exact app cleanup. Request permission
to cancel a redundant waiting **Sample workload CD** if it blocks the shared
concurrency group; do not approve a retained-app redeployment instead.
Actual GitHub `sandbox` approval is still required.

Keep the fixed two baselines, one candidate, seven cases per pass, 100% quality,
zero HTTP errors, 20% p95 regression limit, and improvement strictly above both
5% and observed baseline spread. Use exact published revisions and the verified
seed/sample predecessor runs. Do not change the runner to make a candidate pass.

## Record the decision

Download the exact completed attempt's artifact and preserve the original
`decision.json`, `decision.md`, definitions, source/condition hashes, image
digests, prices, measurements, and cleanup receipt. Associate these with the
proposal and the actual workflow run URL. Inspect the JSON per-pass evidence,
not just the workflow badge.

Report **accept**, **reject**, or **repeat** using the runner's result, including
quality, errors, p95, throughput, input/cached/output usage, price coverage,
model-only unit cost, baseline variation, limitations, and cleanup status.
Missing or conflicting evidence must stay incomplete, with no savings claim.
An unchanged-agent smoke is not an optimization. Never silently replace a
failed run with offline or synthetic evidence; label any reevaluation and its
evaluator revision separately.

The retained demo, shared services, registry images, and deployment records are
not removed by app cleanup. Scheduled expiration enforcement remains issue #13.
Publishing a decision is not permission to merge, close an issue, or start
another paid experiment.

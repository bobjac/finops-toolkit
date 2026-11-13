---
description: Prepare and run a bounded FinOps design-time optimization experiment.
disable-model-invocation: true
---

# Run a FinOps design-time optimization

Use the `ftk-design-time-optimizer` agent and follow `skills/design-time-optimizer/SKILL.md`.

## Inputs

Identify:

- Experiment specification path.
- Optimization objective.
- Allowed code and infrastructure paths.
- Required functional and nonfunctional tests.
- FinOps hub environment or approved alternative pricing source.
- Whether the user wants planning only, a candidate change, or a complete approved experiment.

If the experiment path is missing, search for `*.experiment.json`. If there is no specification or more than one plausible specification, ask the user to select or create one.

For the fork's `sample-multi-agent` adapter, read the packaged
`skills/design-time-optimizer/references/sample-optimization.md`, or
`hack/sample-multi-agent-workload/experiments/optimizer.md` in a source
checkout. That guide connects the four bounded context tools to the existing
protected **Sample experiment** workflow. Keep its fixed policy and use
proposal-only mode unless the user approves further work. Preserve the
unchanged baseline SHA before edits and the exact published candidate SHA.

## 1. Validate the experiment

Run:

```powershell
./skills/design-time-optimizer/scripts/Test-DesignTimeOptimizerExperiment.ps1 -Path <path>
```

When working from the FinOps Toolkit source repository before packaging, run:

```powershell
./src/scripts/Test-DesignTimeOptimizerExperiment.ps1 -Path <path>
```

Stop when validation fails. Do not infer missing required values.

## 2. Confirm execution boundaries

Summarize:

- Baseline and candidate refs.
- Workload unit and quantity.
- Region and Azure scope.
- Load duration and virtual users.
- Performance guardrails.
- Required meters, currency, and pricing source.
- Cleanup lifetime.
- Allowed file paths and required approvals.

Do not deploy or perform Git writes until required approvals are satisfied.

## 3. Retrieve FinOps context

Use the configured FinOps Toolkit environment and approved read-only KQL. Retrieve:

- Material historical cost drivers.
- Resource-level costs for the bounded scope.
- Applicable recommendations.
- Pricing inputs for required meters.
- Data and pricing freshness.

Do not execute arbitrary queries when a curated query exists. Preserve source, scope, currency, effective date, and warnings.

## 4. Propose one bounded hypothesis

State:

- The proposed change.
- Why it targets a material cost driver.
- Expected consumption or meter change.
- Possible functional and nonfunctional impact.
- Tests and evidence required to accept the change.

Do not combine unrelated changes.

## 5. Implement and validate

If the user requested implementation and policy allows it:

1. Follow repository Git policy and obtain approval; create a candidate branch only when allowed. The hack fork uses approved direct-`dev` publication.
2. Make the bounded change.
3. Add or update directly related tests.
4. Run the repository's required validation.
5. Start the approved baseline-versus-candidate workflow when available.
6. Collect exact measurement-window telemetry.
7. Clean up temporary resources after success or failure.

If the repository does not yet provide the experiment runner, stop after producing the validated hypothesis and implementation plan. Report the missing component instead of simulating an experiment result.

## 6. Report the decision

Recommend:

- **Accept** only when every required test and guardrail passes and required pricing is complete.
- **Reject** when behavior or a guardrail regresses, cleanup fails, or the cost hypothesis is disproven.
- **Repeat** when evidence is incomplete, noisy, stale, or not equivalent.

Include assumptions, exclusions, confidence, evidence references, and cleanup status.

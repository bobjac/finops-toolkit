---
name: design-time-optimizer
description: Use this skill to define, validate, implement, or evaluate a baseline-versus-candidate FinOps optimization experiment before a repository change is merged.
license: MIT
compatibility: Requires PowerShell 7 for experiment validation. Live cost analysis requires the FinOps Toolkit skill and a configured read-only FinOps provider.
metadata:
  author: microsoft
  version: "1.0"
---

# FinOps design-time optimizer

The design-time optimizer tests whether a bounded code or infrastructure change reduces estimated cost per successful workload unit while preserving functional and nonfunctional requirements.

## Task routing

| Task | Required action |
| --- | --- |
| Create an experiment | Start from `references/sample-api-rightsize.experiment.json` and validate against `references/experiment.schema.json` |
| Validate an experiment | Run `scripts/Test-DesignTimeOptimizerExperiment.ps1` |
| Retrieve FinOps context | Load the `finops-toolkit` skill and use approved read-only queries |
| Propose a change | Select one material, measurable, reversible hypothesis |
| Evaluate a result | Enforce all guardrails and required-price coverage |
| Publish a recommendation | Report accept, reject, or repeat with evidence and cleanup status |

## Experiment contract

An experiment defines:

- Version and stable name.
- Workload unit and quantity.
- Azure subscription and region.
- Baseline and candidate refs.
- Load-test file, warm-up, duration, and virtual users.
- Performance guardrails.
- Currency, pricing source, and required meters.
- Maximum resource lifetime.

Validate before using the specification:

```powershell
./skills/design-time-optimizer/scripts/Test-DesignTimeOptimizerExperiment.ps1 -Path <path>
```

The validator rejects:

- Invalid JSON or schema violations.
- Identical baseline and candidate refs.
- Cleanup lifetimes that cannot cover the configured load stages.
- Missing referenced load-test files when `-CheckReferencedFiles` is used.

## Evidence requirements

Every valid comparison needs:

- Exact baseline and candidate revisions.
- Equivalent deployment configuration.
- Exact measurement windows.
- Completed successful workload units.
- Performance metrics.
- Cost-relevant consumption quantities and units.
- Applicable prices with currency and effective date.
- Required-meter price coverage.
- Cleanup status.

Historical billed cost can prioritize opportunities, but a short experiment normally estimates cost from measured consumption and applicable prices.

## Decision rules

Recommend **accept** only when:

- Functional and security tests pass.
- Every configured guardrail passes.
- Required price coverage is complete.
- Baseline and candidate conditions are equivalent.
- Successful workload units are greater than zero.
- Cleanup succeeds.

Recommend **reject** when any requirement fails or the candidate does not improve the intended cost measure.

Recommend **repeat** when variance, sampling, stale data, missing telemetry, or environmental differences prevent a reliable decision.

## Cost rules

- Preserve full precision and round only display values.
- Keep measured, allocated, extrapolated, excluded, and unpriced amounts separate.
- Never replace a missing price with zero.
- Never mix currencies silently.
- Use successful completed workload units as the denominator.
- Record the price source and effective time.

## Safety rules

- Keep FinOps access read-only.
- Use approved query templates.
- Use isolated experiment environments.
- Do not modify production resources.
- Do not merge automatically.
- Do not weaken tests or guardrails.
- Limit each candidate to one hypothesis.
- Run cleanup after success and failure.
- Follow repository and host approval requirements for Git and deployment operations.

## Packaged references

| File | Purpose |
| --- | --- |
| `references/experiment.schema.json` | Version 1 JSON Schema |
| `references/sample-api-rightsize.experiment.json` | Example experiment |
| `scripts/Test-DesignTimeOptimizerExperiment.ps1` | Repository-native validator |

# Sandbox seed data

H03 ([#5](https://github.com/bobjac/finops-toolkit/issues/5)) prepares a small, labeled historical workload and applicable prices for the [sandbox foundation](./foundation.md). It does not deploy the sample application, a model, or a workbook.

**Status:** Local preparation tests pass. Publication, the 36-month retention deployment, PowerShell tests and lint in GitHub Actions, and both live ingestion passes are pending. Package generation alone does not establish sandbox readiness.

## Data and provenance

The seed selects positive, standard, USD VM usage from `src/open-data/dataset-examples/EA-Cost-FOCUS_1.0.csv`. It uses that FOCUS file only, not overlapping actual or amortized exports.

Each selected charge must have exactly one applicable consumption price in `EA-Prices.csv`, matching its meter, offer, original billing profile, currency, region, effective dates, and compatible normalized unit. Missing or ambiguous candidates are excluded explicitly in `historicalCoverage`; an empty selection fails. Selected monthly meter/offer groups cannot require multiple price variants. Downstream verification fails on any missing required price.

The current repository samples produce:

| Dataset | Rows | Treatment |
| --- | ---: | --- |
| Historical VM usage | 1,878 | Selected from 1,900 candidates; 22 lack unambiguous applicable coverage |
| Historical prices | 13 | Only prices required by the selected VM usage |
| Current GPT-5 mini prices | 3 | Uncached input, cached input, and output for GlobalStandard in `eastus2` |

Original June 2024 charge dates, quantities, units, and billed costs remain unchanged. The historical scoped totals are USD **2,219.31596583689** billed cost and **17,310.263304988297** pricing quantity. These are sample totals, not sandbox charges or measured savings. Source quantities can reflect historical fixture imperfections; they are not reconstructed from costs.

Billing identity is isolated as `dto-history-v1`, account-owner email is cleared, and cost tags include `ftk-dataset=sample-history-v1`. Original sample resource and subscription identifiers are historical context, never deployment or mutation targets. Timezone-free EA price timestamps are interpreted as UTC to match the FOCUS usage dates.

Current model prices come from the authoritative [Azure Retail Prices API](https://prices.azure.com/api/retail/prices). Preparation requires the exact GlobalStandard SKUs, USD, consumption pricing, a zero minimum tier, the primary regional meter, an already-effective rate, and original `1M` units. Batch and data zone prices are not interchangeable. Missing, ambiguous, zero, nonfinite, future-dated, or more-than-seven-day-old required pricing fails.

The adapter preserves meter identifiers, effective start dates, source unit descriptions, and retrieval time. It uses `dto-retail-public-v1` and `PUBLIC-RETAIL` as synthetic normalization identifiers, not a negotiated billing account or offer. Unknown effective end dates stay null. The toolkit normalizes `1M` to a block of 1,000,000 units; the seed metadata states explicitly that these model meters bill tokens. Cached input is a separate rate, not a second subtraction from uncached input.

The retail snapshot fetched during local validation on November 6, 2026 returned USD 0.25, 0.025, and 2.00 per million tokens for input, cached input, and output. Live runs fetch and validate their own snapshot; these documented rates are not fallback prices.

## Normalization and replacement

`src/design-time-optimizer/seed/prepare.py` uses the repository's `focuscost_1.0.json` and `pricesheet_2023-05-01_ea.json` translators to generate explicitly typed Parquet. Each package includes a fresh UUID-prefixed `__seed.parquet` file, a nonempty manifest, and source/schema checksums and expected counts in `seed.json`.

Packages use three stable logical folders in the `ingestion` container:

```text
Prices/2024/06/providers/microsoft.billing/billingaccounts/dto-history-v1
Prices/2024/06/providers/microsoft.billing/billingaccounts/dto-retail-public-v1
Costs/2024/06/providers/microsoft.billing/billingaccounts/dto-history-v1
```

June 2024 is the stable replacement partition, including for current model prices. It is not the model price effective period; original effective dates remain in the price rows. A stable partition prevents reruns in later months from leaving duplicate model-price history.

`Import-DesignTimeOptimizerSeed.ps1` verifies the owned foundation and actual data-plane access before any writes. It requires the exact group confirmation and at least 36 months of configured final retention. The hack wrapper requests 36 months because the toolkit's default 13-month cleanup would immediately remove these original historical fixtures. This change must be deployed before ingestion.

Within each exact seed folder, the importer waits for preceding ingestion to finish, refuses unrecognized blobs, removes only recognized previous seed files, uploads Parquet, and uploads the manifest **last**. The normal `ingestion_ExecuteETL` event trigger performs ingestion, transforms, update policies, and extent replacement. The seed does not write core hub tables or start a duplicate manual pipeline run.

The importer waits for a new matching Data Factory run, excluding runs known before upload. Failed, cancelled, timed-out, or incomplete results fail the pass. It then verifies actual `Hub.Costs()` and `Hub.Prices()` counts, historical tags/dates and scoped totals, and every required price's meter, offer, region, effective start, currency, rate, original unit, and normalized block size.

The workflow prepares two sets of fresh package UUIDs from the **same frozen retail snapshot**, imports both, and compares logical counts and scoped totals. Readiness requires both reports to succeed and the replacement baseline to match.

## Run from the fork

Publish these changes to `bobjac/finops-toolkit:dev` first. Use the existing GitHub `sandbox` environment secrets; do not put credentials in the packages or workflow.

1. Run **Sandbox foundation** on `dev`, operation `Deploy`, confirmation `ftk-dto-hack-foundation`, to apply the approved retention change and verify the retained resources.
2. After that workflow succeeds, run **Sandbox seed data** on `dev`, confirmation `ftk-dto-hack-foundation`.
3. Check both ingestion reports, the baseline comparison, and the final readiness summary. Keep the workflow URL and source revision as issue evidence.

The workflows share the `sandbox-foundation` concurrency group, so seeding cannot run concurrently with a foundation lifecycle operation. Each seed pass has a 30-minute bound; Azure sign-in is refreshed between passes.

For local preparation with the pinned dependency installed:

```bash
python3 -m pip install -r src/design-time-optimizer/seed/requirements.txt
python3 -m unittest discover -s src/design-time-optimizer/seed -p 'test_*.py' -v
python3 src/design-time-optimizer/seed/prepare.py \
  --output .tmp/seed-first --source-revision "$(git rev-parse HEAD)"
python3 src/design-time-optimizer/seed/prepare.py \
  --output .tmp/seed-second --source-revision "$(git rev-parse HEAD)" \
  --retail-snapshot .tmp/seed-first/retail-source.json
```

Use empty output directories. Local preparation needs no Azure sign-in. Live imports require the configured workflow service principal, not an interactive administrator account. `-WhatIf` is offline and proves neither ownership nor access.

## Evidence and failure recovery

The seven-day workflow artifact contains source checksums and revision, the public catalog snapshot and provenance, manifests, foundation verification, actual pipeline run identifiers, and actual hub counts and totals. Credentials and Parquet payloads are not uploaded as evidence.

Once package validation starts, failures persist `ReadyForSeededHistory=false` and never delete the retained foundation. Invalid confirmation and offline plans can stop before evidence is created. A failed replacement can leave partial seed state or staging files; it is not transactional across the three packages. Correct the failure, then rerun the confirmed workflow. Do not remove unknown blobs or append records directly to core tables to make counts match.

Local validation completed:

- Five Python test methods covering canonical types, invalid values, applicable price selection, missing/stale/ambiguous model pricing, preserved provenance/dates, and repeat-package equivalence.
- Real package generation using the repository samples and the public API, with the counts and totals above.
- PowerShell syntax parsing and offline `-WhatIf`.
- Six isolated PowerShell helper smoke checks for ADX frame parsing, partial-result rejection, failed ingestion, exclusion of preceding runs, manifest-last staging, and nonfinite totals; a real invalid-package invocation also persisted false readiness.

Pester and PSScriptAnalyzer are not installed locally; their tests and lint are required steps before live ingestion in the new workflow. The 36-month wrapper compilation and live replacement evidence remain pending publication. Do not close H03 until those checks and both live passes succeed.

The foundation remains billable. Its declared budget and expiration tag are not a spending cap or automatic shutdown. Use the existing confirmed foundation removal workflow when the demonstration is finished.

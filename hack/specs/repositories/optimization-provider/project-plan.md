# Optimization provider project plan

## Purpose

This plan delivers the [optimization provider architecture](./architecture.md) for one external source platform.

## Delivery principles

- Implement only declared capabilities.
- Normalize at the provider boundary.
- Build fixtures before live access.
- Validate scope before every source operation.
- Preserve limitations instead of manufacturing complete data.
- Keep generic agent behavior out of the provider.
- Release independently from the harness.

## Phase 0: Select capabilities and source boundaries

**Objectives**

- Define exactly what the source can provide.
- Establish ownership and security constraints.

**Tasks**

- Identify the source platform, environments, and owners.
- Select initial capabilities.
- Document source APIs, tables, query languages, and rate limits.
- Define allowed scopes and maximum time ranges.
- Classify returned data.
- Select the primary transport.
- Select the implementation language.
- Map source identity to approved authentication.

**Exit criteria**

- Initial capabilities and non-capabilities are explicit.
- Source access and data handling are approved.
- The transport and runtime are selected.

## Phase 1: Bootstrap the repository

**Objectives**

- Create a tested, packageable provider skeleton.

**Tasks**

- Initialize the language toolchain.
- Add formatting, linting, unit tests, and continuous integration.
- Add `provider.yaml`.
- Add configuration and response schema directories.
- Add fixture and contract-test directories.
- Add container packaging when required.
- Add structured logging and request IDs.

**Exit criteria**

- The provider starts locally.
- The manifest and empty configuration validate.
- Continuous integration runs without live credentials.

## Phase 2: Implement public contracts

**Objectives**

- Validate requests and produce deterministic normalized responses.

**Tasks**

- Import or vendor the released provider schemas according to policy.
- Implement request-envelope validation.
- Implement capability routing.
- Implement scope and time-range validation.
- Implement the response envelope.
- Implement structured errors.
- Add deterministic fixtures for every planned capability.
- Run shared provider contract tests.

**Exit criteria**

- Fixture-backed capabilities pass success and failure contracts.
- Unsupported capabilities and versions fail explicitly.
- No source authentication is required for contract tests.

## Phase 3: Implement source access

**Objectives**

- Connect to the source safely.

**Tasks**

- Implement approved authentication.
- Implement the source client.
- Add curated queries or bounded API calls.
- Add pagination and throttling.
- Add retries only for retryable failures.
- Add source response validation.
- Add source schema-change detection.
- Add test-environment integration tests.

**Exit criteria**

- The provider retrieves representative source data.
- Scope and authorization failures are distinguishable.
- Throttling and partial responses are handled explicitly.

## Phase 4: Implement normalization and quality

**Objectives**

- Translate source data without losing material meaning.

**Tasks**

- Map source identifiers and units.
- Preserve source and query-template versions.
- Calculate freshness.
- Calculate completeness and coverage.
- Preserve unknown, missing, excluded, and unpriced values.
- Add currency and effective-date handling for FinOps providers.
- Add sanitization and protected references for conversation providers.
- Add ownership, classification, and lineage for schema providers.

**Exit criteria**

- Representative source fixtures produce expected normalized fixtures.
- Missing data cannot appear as zero or complete.
- Quality warnings are deterministic and tested.

## Phase 5: Harden security and operations

**Objectives**

- Enforce least privilege and safe diagnostics.

**Tasks**

- Add field allowlists and redaction.
- Add network and filesystem restrictions.
- Add audit events and OpenTelemetry.
- Add timeout, cancellation, and resource limits.
- Add secret scanning.
- Add dependency and container scanning.
- Test cross-scope and cross-tenant denial.
- Document least-privilege roles.

**Exit criteria**

- Unauthorized scopes are denied before source queries.
- Logs and errors contain no secrets or protected content.
- Operational telemetry supports diagnosis without source payloads.

## Phase 6: Package and release

**Objectives**

- Produce an independently installable artifact.

**Tasks**

- Build the runtime package or image.
- Generate checksums and a software bill of materials.
- Sign artifacts when supported.
- Publish schemas and fixtures.
- Publish compatibility metadata.
- Write setup, configuration, troubleshooting, and upgrade guidance.
- Add a changelog and semantic-versioning policy.

**Exit criteria**

- A clean environment can install and start the provider.
- The harness discovers the provider through its manifest.
- Release artifacts are immutable and verifiable.

## Phase 7: Validate replacement and compatibility

**Objectives**

- Prove that the provider can replace a mock without changing agents.

**Tasks**

- Run the harness integration suite.
- Compare mock and live normalized behavior.
- Test supported harness versions.
- Test a source schema or API change.
- Test stale, empty, partial, throttled, and unavailable source states.
- Establish a cross-repository compatibility workflow.

**Exit criteria**

- The generic agent requires no source-specific changes.
- Contract-breaking changes are detected before release.
- Supported version combinations are documented.

## Backlog

| ID | Work item | Phase | Depends on | Acceptance criteria |
| --- | --- | --- | --- | --- |
| PRV-001 | Select source platform | 0 | None | Source, owners, environments, and limits are documented |
| PRV-002 | Select capabilities | 0 | PRV-001 | Initial capability list and exclusions are approved |
| PRV-003 | Select transport and runtime | 0 | PRV-001 | Packaging and hosting model are recorded |
| PRV-004 | Bootstrap repository | 1 | PRV-003 | Formatting, linting, tests, and CI run |
| PRV-005 | Add provider manifest | 1 | PRV-002, PRV-003 | Manifest validates |
| PRV-006 | Add configuration schema | 1 | PRV-001 | Invalid scope and identity settings fail |
| PRV-007 | Implement request validation | 2 | PRV-005, PRV-006 | Invalid requests never reach source code |
| PRV-008 | Implement response envelope | 2 | PRV-005 | Fixtures validate against public schemas |
| PRV-009 | Implement structured errors | 2 | PRV-007 | Error categories and retryability are deterministic |
| PRV-010 | Create capability fixtures | 2 | PRV-002, PRV-008 | Every capability has success and failure fixtures |
| PRV-011 | Pass shared contract tests | 2 | PRV-007 through PRV-010 | Offline suite passes |
| PRV-012 | Implement authentication | 3 | PRV-006 | Approved short-lived identity works |
| PRV-013 | Implement source client | 3 | PRV-012 | Representative source call succeeds |
| PRV-014 | Add bounded queries or API calls | 3 | PRV-013 | Scope, time, field, and row limits are enforced |
| PRV-015 | Add pagination and throttling | 3 | PRV-013 | Large and throttled responses behave predictably |
| PRV-016 | Map source identifiers and units | 4 | PRV-014 | Normalized identifiers and units match fixtures |
| PRV-017 | Add quality evaluation | 4 | PRV-016 | Freshness and completeness are reported |
| PRV-018 | Preserve missing values | 4 | PRV-016 | Missing, unknown, and unpriced data are not converted to zero |
| PRV-019 | Add redaction and allowlists | 5 | PRV-014 | Unapproved fields never leave the provider |
| PRV-020 | Add OpenTelemetry and audit | 5 | PRV-013 | Operations are diagnosable without payload logging |
| PRV-021 | Test scope isolation | 5 | PRV-012, PRV-014 | Cross-scope requests are denied |
| PRV-022 | Build release artifact | 6 | PRV-011, PRV-019 through PRV-021 | Clean install succeeds |
| PRV-023 | Publish schemas and SBOM | 6 | PRV-022 | Release is verifiable |
| PRV-024 | Run harness integration tests | 7 | PRV-022 | Provider replaces mock without agent changes |
| PRV-025 | Add compatibility workflow | 7 | PRV-024 | Breaking contract drift blocks release |

## Test matrix

| Scenario | Required result |
| --- | --- |
| Valid bounded request | Normalized success response |
| Unsupported capability | `unsupported-capability` |
| Disallowed scope | `scope-denied` before source access |
| Expired identity | `authentication-failed` |
| Missing role | `authorization-failed` |
| Source timeout | Retryable `source-unavailable` |
| Throttling | Retryable `source-throttled` with backoff metadata |
| Empty valid result | Successful empty data with quality context |
| Partial result | Warning or incomplete status |
| Stale result | Freshness warning or `stale-data` according to contract |
| Source schema drift | `source-schema-changed` |
| Mapping failure | `normalization-failed` |
| Missing price | Unpriced quantity, never zero |
| Protected conversation content | Protected reference, not raw content |

## Security checklist

- [ ] Configuration contains no credentials.
- [ ] Source scopes are allowlisted.
- [ ] Queries and API calls are bounded.
- [ ] Arbitrary query execution is disabled by default.
- [ ] Authentication uses short-lived identity.
- [ ] Returned fields are allowlisted.
- [ ] Sensitive data is redacted or protected by reference.
- [ ] Logs contain no source payloads or credentials.
- [ ] Runtime network and filesystem access are declared.
- [ ] Dependencies and images are scanned.
- [ ] Artifacts include checksums and a software bill of materials.
- [ ] Cross-scope and cross-tenant denial is tested.

## Definition of done

- The provider is independently buildable and releasable.
- The provider repository is not needed at runtime.
- Every declared capability passes offline contract tests.
- Live integration tests cover representative source behavior.
- Scope, time, field, and row limits are enforced.
- Source limitations survive normalization.
- Missing evidence cannot produce a complete success result.
- Authentication, redaction, telemetry, and audit meet policy.
- A harness can replace its mock provider with the release artifact without changing a generic agent.

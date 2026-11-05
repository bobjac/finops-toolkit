# Customer optimization integration project plan

## Purpose

This plan implements the [customer optimization integration architecture](./architecture.md) in an existing application repository.

## Delivery principles

- Wrap existing tools instead of replacing them.
- Establish local validation before cloud execution.
- Instrument one workload before adding more.
- Use synthetic or approved test data.
- Separate application telemetry from protected conversation evidence.
- Keep code-producing and document-producing autonomy distinct.
- Make cleanup a required product capability.

## Phase 0: Assess the repository

**Objectives**

- Understand the current application and delivery process.
- Select one workload and one conversational scenario.

**Tasks**

- Inventory languages, frameworks, package managers, and infrastructure tools.
- Identify existing build, test, deploy, and cleanup commands.
- Identify current load testing and observability.
- Select the first workload unit and nonfunctional requirements.
- Identify cloud scopes and experiment isolation.
- Identify the AI application's unable-to-answer signal.
- Classify data, logs, prompts, queries, and test fixtures.
- Identify required reviewers and prohibited changes.

**Exit criteria**

- Existing commands and owners are documented.
- The first workload and answerability scenario are approved.
- Privacy and production boundaries are known.

## Phase 1: Add configuration and policy

**Objectives**

- Create the `.optimization-harness/` integration surface.
- Fail early on invalid or unsafe configuration.

**Tasks**

- Add `harness.yaml`, `policy.yaml`, and `providers.yaml`.
- Add the first workload specification.
- Define allowed and excluded paths.
- Define Git and cloud autonomy.
- Define artifact classification and retention.
- Add environment-specific settings through ignored local files or secret references.
- Add configuration validation to continuous integration.

**Exit criteria**

- Configuration validates locally and in continuous integration.
- No credentials are committed.
- Automatic merge and production changes are disabled.

## Phase 2: Implement local adapters

**Objectives**

- Prove build and test operations without cloud access.

**Tasks**

- Implement `build`.
- Implement `unit-test`.
- Implement `integration-test`.
- Add request and response validation.
- Add deterministic exit codes.
- Add log redaction.
- Add local fixtures.
- Add adapter conformance tests.

**Exit criteria**

- Local adapters invoke the repository's existing commands.
- Failures produce structured responses.
- The repository still builds and tests normally without the harness.

## Phase 3: Implement experiment deployment

**Objectives**

- Deploy isolated baseline and candidate environments.
- Guarantee cleanup.

**Tasks**

- Implement `deploy` and `wait-ready`.
- Add run, experiment, and variant tags.
- Return an authoritative resource inventory.
- Implement idempotent `cleanup`.
- Add expiration controls.
- Add a scheduled cleanup backstop.
- Test partial deployment and cancellation.

**Exit criteria**

- Both variants deploy from the same source templates.
- Readiness is machine-verifiable.
- Cleanup succeeds after success and simulated failure.

## Phase 4: Add load and telemetry

**Objectives**

- Produce equivalent demand and correlated evidence.

**Tasks**

- Define warm-up and measured phases.
- Implement `load-test`.
- Add OpenTelemetry correlation attributes.
- Implement `collect-telemetry`.
- Implement `collect-consumption`.
- Validate exact measurement windows.
- Add telemetry completeness checks.

**Exit criteria**

- Both variants receive the same load profile.
- Performance and consumption can be filtered by experiment and variant.
- Missing evidence is reported explicitly.

## Phase 5: Enable FinOps optimization

**Objectives**

- Allow bounded code candidates and controlled experiments.

**Tasks**

- Configure the selected FinOps provider.
- Validate scope, currency, pricing, and freshness.
- Confirm allowed optimization paths.
- Run a dry-run recommendation.
- Enable isolated branch creation.
- Run one known baseline-versus-candidate scenario.
- Review the pull-request evidence and cleanup result.

**Exit criteria**

- The known scenario produces the expected directional signal.
- Failed guardrails reject the candidate.
- No production resources are modified.

## Phase 6: Enable answerability analysis

**Objectives**

- Capture sanitized failed-answer evidence.
- Provide safe schema and domain context.

**Tasks**

- Implement the failed-answer event.
- Add protected references for question and query content.
- Export schema and semantic metadata.
- Add freshness, retention, ownership, and classification.
- Configure clustering thresholds.
- Create labeled examples for failure classification.
- Run the answerability agent in document-only mode.

**Exit criteria**

- Known failures classify correctly.
- Query-generation and access failures are not labeled as missing data.
- A verified gap produces a decision record.
- No schema or service code is changed.

## Phase 7: Operationalize

**Objectives**

- Make scheduled execution safe and supportable.

**Tasks**

- Add the scheduler workflow.
- Add workload identity federation.
- Add artifact retention and deletion.
- Add notifications and escalation.
- Add runbooks for provider failure, cleanup failure, and protected-evidence review.
- Add cost and runtime budgets.
- Review permissions and audit events.

**Exit criteria**

- Scheduled runs need no interactive input.
- Failures are visible and actionable.
- Evidence expires according to policy.

## Backlog

| ID | Work item | Phase | Depends on | Acceptance criteria |
| --- | --- | --- | --- | --- |
| CIN-001 | Inventory native commands | 0 | None | Build, test, deploy, load, telemetry, and cleanup owners are documented |
| CIN-002 | Define workload unit | 0 | None | Unit and success denominator are measurable |
| CIN-003 | Define nonfunctional guardrails | 0 | CIN-002 | Latency, errors, throughput, and reliability thresholds are approved |
| CIN-004 | Classify evidence | 0 | None | Telemetry and conversation evidence have handling rules |
| CIN-005 | Add harness configuration | 1 | CIN-001 through CIN-004 | Configuration validates |
| CIN-006 | Add autonomy policy | 1 | CIN-004 | Production and automatic merge are denied |
| CIN-007 | Implement build adapter | 2 | CIN-005 | Existing build runs through the adapter |
| CIN-008 | Implement test adapters | 2 | CIN-005 | Required tests return structured results |
| CIN-009 | Add adapter conformance tests | 2 | CIN-007, CIN-008 | Invalid and failed operations are covered |
| CIN-010 | Implement deployment adapter | 3 | CIN-005 | Isolated variants deploy with correlation tags |
| CIN-011 | Implement readiness adapter | 3 | CIN-010 | Health and telemetry readiness are verified |
| CIN-012 | Implement cleanup adapter | 3 | CIN-010 | Partial and complete resources are removable |
| CIN-013 | Add cleanup backstop | 3 | CIN-012 | Expired experiments are discovered and removed |
| CIN-014 | Implement load adapter | 4 | CIN-010, CIN-011 | Equivalent measured load reaches both variants |
| CIN-015 | Add OpenTelemetry correlation | 4 | CIN-002 | Run, experiment, and variant are queryable |
| CIN-016 | Implement telemetry collection | 4 | CIN-014, CIN-015 | Guardrail evidence is complete or explicitly missing |
| CIN-017 | Implement consumption collection | 4 | CIN-014, CIN-015 | Cost-relevant quantities are returned with units |
| CIN-018 | Configure FinOps provider | 5 | CIN-005 | Provider scope and freshness validate |
| CIN-019 | Run known optimization | 5 | CIN-016 through CIN-018 | Directional result and guardrails match expectations |
| CIN-020 | Emit failed-answer events | 6 | CIN-004 | Events validate and contain no raw protected content |
| CIN-021 | Export schema context | 6 | CIN-004 | Approved metadata is available without production row access |
| CIN-022 | Create classifier fixtures | 6 | CIN-020, CIN-021 | Known failure categories are represented |
| CIN-023 | Run answerability analysis | 6 | CIN-022 | Verified gap produces a traceable decision record |
| CIN-024 | Add scheduled workflow | 7 | CIN-019, CIN-023 | Noninteractive run publishes artifacts |
| CIN-025 | Add operational runbooks | 7 | CIN-024 | Provider, evidence, and cleanup failures are actionable |

## Test strategy

### Static tests

- Configuration schema validation.
- Policy validation.
- Secret and protected-content scanning.
- Adapter executable and permission checks.

### Adapter tests

- Valid request.
- Missing required field.
- Native command failure.
- Timeout and cancellation.
- Partial deployment.
- Repeated cleanup.

### Integration tests

- Workload identity.
- Baseline and candidate deployment.
- Equivalent load.
- OpenTelemetry correlation.
- Provider scope.
- Artifact publishing.

### End-to-end tests

- A known cost candidate passes.
- A performance regression fails.
- Missing price or consumption evidence blocks approval.
- A known data gap creates a decision record.
- A query-generation failure does not create a schema recommendation.
- All experiment resources are removed.

## Definition of done

- The integration uses the repository's native toolchain.
- Local validation needs no cloud credentials.
- Required adapters pass conformance tests.
- Experiments are isolated, correlated, and removable.
- FinOps evidence can support cost-per-workload-unit comparison.
- Failed-answer events are sanitized.
- Schema and domain context are approved and bounded.
- Agent Git writes use isolated branches and approved paths.
- Existing continuous integration remains authoritative.
- The application can build, test, and deploy without the harness.

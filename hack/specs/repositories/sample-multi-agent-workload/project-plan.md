# FinOps multi-agent sample workload project plan

For the current sandbox hack, follow the [hack delivery plan](../../../project-plan.md). It selects schema-context reduction as the first demonstration scenario. The phases and `SMP-*` backlog below retain the broader workload roadmap.

## Purpose

This plan delivers the [FinOps multi-agent sample workload architecture](./architecture.md) as an independently deployable repository.

## Delivery principles

- Build local deterministic behavior before Azure integration.
- Use synthetic data only.
- Instrument before optimizing.
- Keep FinOps Toolkit optional at application runtime.
- Use the same infrastructure modules for baseline and candidate.
- Start with infrastructure rightsizing.
- Require answer-quality evaluation for agent changes.
- Preserve the intentional answerability gap until a separate approved enhancement implements it.

## Phase 0: Bootstrap the repository

**Objectives**

- Create the application, automation, and test structure.

**Tasks**

- Initialize Python 3.12 and `pyproject.toml`.
- Add FastAPI, SQLAlchemy, Azure OpenAI, OpenTelemetry, and test dependencies.
- Add formatting, linting, type checking, pytest, and continuous integration.
- Add Docker packaging.
- Add PowerShell entry scripts.
- Add local environment templates and `.gitignore`.
- Add architecture decision records.

**Exit criteria**

- The application starts locally.
- Formatting, linting, type checking, and unit tests run in continuous integration.
- No Azure access is required.

## Phase 1: Build the synthetic data workload

**Objectives**

- Create deterministic retail data and safe read-only query execution.

**Tasks**

- Create the SQLite schema.
- Create deterministic seed generation.
- Add supported analytical queries.
- Add the intentional shipment-history gap.
- Implement the read-only SQL validator.
- Add row limits and query timeouts.
- Add database unit and integration tests.

**Exit criteria**

- Rebuilding from the same seed produces the same database.
- Supported queries return expected results.
- Write and multi-statement SQL are rejected.
- The schema cannot answer the intentional gap question.

## Phase 2: Implement the multi-agent application

**Objectives**

- Answer supported questions through separate agent roles.

**Tasks**

- Define the common agent interface.
- Implement the coordinator agent.
- Implement the schema agent.
- Implement the SQL generation agent.
- Implement the analysis and response agent.
- Add structured answer statuses.
- Add model-client abstraction and managed-identity authentication.
- Add timeouts, call limits, and error mapping.
- Add API, health, and readiness endpoints.

**Exit criteria**

- At least three agents participate in representative questions.
- Supported questions return structured answers.
- Unsupported questions return explicit statuses.
- Model failures are not mislabeled as data gaps.

## Phase 3: Add evaluation and answerability evidence

**Objectives**

- Prove functional answer quality and capture genuine gaps.

**Tasks**

- Create the golden question set.
- Add expected statuses, tables, results, and call limits.
- Implement deterministic result evaluation.
- Add the intentional unable-to-answer case.
- Emit sanitized failed-answer events.
- Protect raw question and SQL fixtures.
- Add evaluation summaries in JSON and Markdown.

**Exit criteria**

- The evaluation suite detects incorrect data, invented explanations, and excess calls.
- The shipment-delay-cause question returns `unable-to-answer`.
- Failed-answer events contain no raw protected content.

## Phase 4: Add OpenTelemetry

**Objectives**

- Attribute latency, dependencies, models, and tokens to each agent.

**Tasks**

- Add request and coordinator parent spans.
- Add child spans for every agent.
- Add generative AI semantic attributes.
- Add database spans.
- Add experiment, variant, session, and question-pattern attributes.
- Add token-usage validation.
- Add local console export and Azure Monitor export.
- Add telemetry tests with an in-memory exporter.

**Exit criteria**

- Parent and child spans reconcile.
- Input, output, and cached tokens are attributable by agent.
- Protected content does not appear in ordinary spans.

## Phase 5: Build Azure infrastructure

**Objectives**

- Deploy the sample independently to Azure Container Apps.

**Tasks**

- Create modular Bicep.
- Deploy managed identity, monitoring, registry, Container Apps, and Azure Load Testing.
- Configure model endpoint parameters.
- Assign least-privilege model access.
- Add resource tags and expiration.
- Implement build, deploy, readiness, and cleanup scripts.
- Add a manually started deployment workflow.

**Exit criteria**

- A clean subscription can deploy the sample with an existing model endpoint.
- The app uses managed identity.
- Health, readiness, and telemetry work.
- Cleanup removes every resource created by the deployment.

## Phase 6: Add load testing

**Objectives**

- Produce repeatable baseline and candidate performance evidence.

**Tasks**

- Create the JMeter test plan.
- Add warm-up and measured phases.
- Use a fixed question mix.
- Define successful workload units.
- Add P50, P95, error-rate, and throughput guardrails.
- Correlate load-test requests with experiment and variant.
- Add load-test result collection.

**Exit criteria**

- Repeated baseline runs remain within the agreed variance.
- Failed answers and dependency failures are counted separately.
- Measurement windows are exact and queryable.

## Phase 7: Connect FinOps Toolkit

**Objectives**

- Make sample cost and token evidence available to a separately deployed FinOps hub.

**Tasks**

- Deploy FinOps Toolkit from the selected branch.
- Configure Cost Management exports for the sample scope.
- Confirm sample resource tags appear in ingested cost data.
- Parameterize FinOps Toolkit token queries with the sample Application Insights resource.
- Validate model-name and price mapping.
- Preserve unpriced usage instead of returning zero.
- Add evidence collection scripts for cost, prices, and tokens.
- Document expected ingestion delay.

**Exit criteria**

- `Costs()` can isolate the sample workload after ingestion.
- `Prices()` supplies applicable pricing or reports missing coverage.
- Agent token telemetry is queryable by experiment and variant.
- The sample contains no direct write to core hub tables.

## Phase 8: Run the first optimization

**Objectives**

- Validate Container Apps rightsizing end to end.

**Tasks**

- Create the experiment specification.
- Deploy baseline at 1 vCPU and 2 GiB.
- Deploy candidate at 0.5 vCPU and 1 GiB.
- Run functional and answer-quality evaluation.
- Run equivalent load.
- Collect performance, allocation, and token evidence.
- Estimate cost per 1,000 successful questions.
- Enforce every guardrail.
- Publish JSON and Markdown results.
- Remove both variants.

**Exit criteria**

- The experiment returns accept, reject, or repeat.
- Cost cannot override a failed requirement.
- Required meter coverage is explicit.
- Cleanup succeeds.

## Phase 9: Add agent optimization scenarios

**Objectives**

- Enable realistic code and configuration refactors.

**Tasks**

- Add model-routing parameters.
- Add compact schema-context generation.
- Add schema-context caching.
- Add maximum agent-call policy.
- Add token budgets to evaluation cases.
- Add model-routing and context-reduction experiment specifications.
- Compare answer quality, latency, tokens, and estimated cost.

**Exit criteria**

- Agent changes cannot pass without the golden evaluation suite.
- Token reductions are attributable to a specific change.
- Model and prompt changes preserve supported answer behavior.

## Backlog

| ID | Work item | Phase | Depends on | Acceptance criteria |
| --- | --- | --- | --- | --- |
| SMP-001 | Bootstrap Python project | 0 | None | Local API and CI start successfully |
| SMP-002 | Add container packaging | 0 | SMP-001 | Image builds and starts locally |
| SMP-003 | Add PowerShell entry scripts | 0 | SMP-001 | Scripts support noninteractive execution |
| SMP-004 | Define SQLite schema | 1 | SMP-001 | Schema includes required tables and intentional gap |
| SMP-005 | Generate deterministic data | 1 | SMP-004 | Fixed seed produces stable records |
| SMP-006 | Implement SQL safety | 1 | SMP-004 | Writes, multiple statements, and disallowed tables are rejected |
| SMP-007 | Define agent interface | 2 | SMP-001 | Agents share typed request and response contracts |
| SMP-008 | Implement coordinator | 2 | SMP-007 | Coordinator routes supported and unsupported questions |
| SMP-009 | Implement schema agent | 2 | SMP-004, SMP-007 | Minimum approved schema context is returned |
| SMP-010 | Implement SQL agent | 2 | SMP-006, SMP-007 | Read-only SQL is generated and validated |
| SMP-011 | Implement analysis agent | 2 | SMP-007, SMP-010 | Answers use only query results and approved definitions |
| SMP-012 | Add question API | 2 | SMP-008 through SMP-011 | Structured answer statuses are returned |
| SMP-013 | Create golden evaluation set | 3 | SMP-005, SMP-012 | Supported and unsupported cases are represented |
| SMP-014 | Implement deterministic evaluator | 3 | SMP-013 | Wrong results and invented causes fail |
| SMP-015 | Emit failed-answer events | 3 | SMP-012 | Events validate and omit raw protected content |
| SMP-016 | Add trace hierarchy | 4 | SMP-012 | Request and agent parent-child relationships reconcile |
| SMP-017 | Add token telemetry | 4 | SMP-016 | Token usage is attributable by agent and model |
| SMP-018 | Add telemetry privacy tests | 4 | SMP-016 | Prompts, credentials, and rows are absent from ordinary spans |
| SMP-019 | Create modular Bicep | 5 | SMP-002 | Azure resources deploy from one entry point |
| SMP-020 | Add managed identity model access | 5 | SMP-019 | App calls the model without stored credentials |
| SMP-021 | Implement deployment scripts | 5 | SMP-019 | Deploy, readiness, and cleanup are noninteractive |
| SMP-022 | Add expiration and cleanup | 5 | SMP-021 | Failed deployments leave no resources |
| SMP-023 | Create JMeter load test | 6 | SMP-012, SMP-019 | Fixed question mix runs against Azure endpoint |
| SMP-024 | Add load guardrails | 6 | SMP-023 | Latency, errors, and throughput are evaluated |
| SMP-025 | Correlate load and telemetry | 6 | SMP-016, SMP-023 | Exact experiment windows are queryable |
| SMP-026 | Configure hub export scope | 7 | SMP-019 | Sample resource costs reach the hub |
| SMP-027 | Connect token queries | 7 | SMP-017 | Toolkit queries use the sample Application Insights resource |
| SMP-028 | Validate pricing coverage | 7 | SMP-026, SMP-027 | Unpriced usage remains visible |
| SMP-029 | Add FinOps evidence collection | 7 | SMP-026 through SMP-028 | Cost, prices, tokens, and freshness are exported |
| SMP-030 | Define rightsizing experiment | 8 | SMP-024, SMP-029 | Baseline and candidate parameters validate |
| SMP-031 | Run rightsizing comparison | 8 | SMP-030 | Result enforces quality and performance guardrails |
| SMP-032 | Add model routing | 9 | SMP-014, SMP-017 | Routing model is configurable by variant |
| SMP-033 | Add compact schema context | 9 | SMP-009, SMP-014 | Context reduction preserves evaluation results |
| SMP-034 | Add schema-context caching | 9 | SMP-033 | Cached-token or prompt-token change is measurable |
| SMP-035 | Add agent optimization experiments | 9 | SMP-032 through SMP-034 | Each experiment isolates one hypothesis |

## Test strategy

### Unit tests

- Agent contracts and routing.
- SQL validation.
- Schema-context selection.
- Answer statuses.
- Token extraction.
- Tag and configuration generation.

### Integration tests

- SQLite queries.
- Model-client test double.
- OpenTelemetry in-memory exporter.
- API and database behavior.
- Container startup.
- Bicep validation.

### Evaluation tests

- Correct answers.
- Correct unable-to-answer behavior.
- SQL table allowlists.
- Maximum agent calls.
- Token budgets.
- No invented shipment-delay cause.

### Azure tests

- Managed identity.
- Container deployment.
- Readiness.
- Application Insights telemetry.
- Azure Load Testing.
- Cleanup.
- FinOps hub cost and price queries after ingestion.

### End-to-end tests

- Local supported question.
- Local intentional gap.
- Azure baseline deployment.
- Equivalent baseline and candidate load.
- Rightsizing accept or reject decision.
- Token optimization with preserved answer quality.
- Failed run cleanup.

## Security checklist

- [ ] Data is synthetic.
- [ ] SQL is read-only and bounded.
- [ ] Model access uses managed identity.
- [ ] No credentials are committed.
- [ ] Raw prompts and rows are excluded from ordinary telemetry.
- [ ] Protected evidence has explicit retention.
- [ ] Experiment scope is isolated from production.
- [ ] Resource tags include expiration.
- [ ] Git and deployment writes require repository-approved permissions.
- [ ] Automatic merge is disabled.
- [ ] Cleanup runs after success and failure.

## Definition of done

- The repository deploys independently.
- FinOps Toolkit is an optional external integration.
- The sample contains at least three observable agents.
- Supported questions pass deterministic evaluation.
- The intentional gap returns `unable-to-answer`.
- OpenTelemetry supports agent and token attribution.
- Azure resources are tagged for FinOps analysis.
- Cost reaches FinOps hubs through supported Cost Management exports.
- Token telemetry is consumable by FinOps Toolkit queries.
- The first rightsizing experiment is repeatable.
- All resources can be removed automatically.
- Developers can create and test optimizations entirely in the sample repository.

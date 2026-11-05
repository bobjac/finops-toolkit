# FinOps design-time optimizer project plan

For the current sandbox hack, follow the [hack delivery plan](../../../project-plan.md). It moves token measurement earlier, selects schema-context reduction as the first scenario, and defines the issue-ready `H*` backlog. This document retains the broader reference phases and `DTO-*` backlog.

## Purpose

This plan delivers the [FinOps design-time optimizer architecture](./architecture.md) in stages. It starts with a controlled hack demonstration and then hardens the result into a reusable reference implementation.

## Standalone delivery boundary

All design-time optimizer implementation work is completed in the FinOps Toolkit repository. The project must not require the autonomous optimization harness, a sibling repository, or an external orchestration SDK.

The implementation includes its own:

- Agent and skill packaging.
- MCP server or bounded MCP tools.
- FinOps data providers.
- Experiment runner and schemas.
- GitHub Actions workflow.
- Cost and performance evaluator.
- Pull-request reporting.
- Samples, tests, and cleanup.

An optional future adapter can expose the optimizer to an external harness. That adapter must depend on the standalone optimizer rather than move core behavior out of this repository.

## Target outcome

A developer can ask an MCP-enabled coding agent to reduce the cost of a sample workload while preserving defined service-level objectives. The agent retrieves scoped FinOps context, creates one bounded candidate change, starts a repeatable baseline-versus-candidate experiment, and receives a pull-request report that compares estimated unit cost, performance, confidence, assumptions, and tradeoffs.

## Delivery principles

- Complete one end-to-end scenario before expanding provider or workload coverage.
- Treat the workflow contract and evidence model as the product boundary.
- Keep provider-specific logic behind adapters.
- Automate deployment, measurement, reporting, and cleanup.
- Add tests at each boundary instead of relying only on a successful demo.
- Record important design changes as architecture decision records.

## Scope

### Hack MVP

- One sample workload.
- One bounded optimization scenario.
- Four core read-only MCP tools.
- One Azure subscription and region.
- One pricing source.
- Baseline and candidate deployment through Bicep.
- One repeatable Azure Load Testing profile.
- Performance and consumption collection.
- Estimated cost per workload unit.
- Pull-request decision record.
- Automated resource cleanup.

### Target enhancements

- Utilization and estimation MCP tools.
- Repeated experiments and confidence evaluation.
- Additional pricing and telemetry providers.
- AI agent token-cost measurement.
- Reusable workload adapters.
- Durable experiment history and workbook views.

### Deferred

- Autonomous production changes.
- Invoice reconciliation.
- Cross-cloud support.
- Broad service recommendation coverage.
- Automated merge or optimization approval.
- Long-term experiment analytics until the core workflow is stable.

## Working assumptions

- The project remains in the `bobjac/finops-toolkit` fork during the hack.
- The design-time optimizer runs without the autonomous optimization harness.
- GitHub Actions can use workload identity federation to access an Azure sandbox.
- Experiments run in isolated, temporary resource groups.
- The sample workload is small enough to deploy and test within the hack budget.
- FinOps hubs or toolkit-aligned data is available for historical context.
- Public pricing is acceptable for the first demo if negotiated pricing is unavailable and the report states the limitation.
- The coding agent can call MCP tools and start or request a GitHub Actions workflow.

## Workstreams

| Workstream | Outcome |
| --- | --- |
| Product and scenario | A measurable optimization hypothesis, workload unit, SLOs, and demo narrative |
| MCP and cost intelligence | Safe, scoped access to historical cost, prices, recommendations, and selected utilization |
| Sample workload and infrastructure | Reproducible baseline and candidate deployments |
| Experiment orchestration | Automated deploy, test, collect, compare, report, and cleanup workflow |
| Estimation and evidence | Transparent unit-cost model and confidence factors |
| Agent experience | Repository guidance and prompts that produce a bounded, explainable change |
| Security and operations | Federated identity, least privilege, budgets, expiration, auditing, and failure handling |
| Quality and documentation | Automated tests, architecture decisions, setup guide, and demonstration runbook |

## Delivery phases

The schedule is relative so it can fit a short hack or a longer engineering sprint. For a two-day hack, treat each week below as a focused half-day block and reduce hardening scope.

### Phase 0: Confirm the scenario

**Suggested duration:** 1 to 2 days

**Objectives**

- Select the sample workload and one optimization lever.
- Define the workload unit and performance guardrails.
- Confirm Azure, GitHub, FinOps, and coding-agent access.
- Establish the cost and time budget.

**Tasks**

- Inventory available sandbox subscriptions, regions, quotas, and identities.
- Confirm access to FinOps hubs, Cost Management data, pricing, Advisor, Azure Monitor, and Application Insights.
- Evaluate candidate workloads against deployment time, load-test support, telemetry quality, and optimization potential.
- Select one optimization such as rightsizing, scaling configuration, caching, logging volume, or service selection.
- Record the decision in an architecture decision record.
- Define the expected demo sequence and fallback plan.

**Deliverables**

- Scenario brief.
- Workload unit and SLO definition.
- Access and dependency checklist.
- Initial architecture decision record.
- Cost and resource limits.

**Exit criteria**

- The workload can be deployed in the sandbox.
- The optimization is measurable within the available test window.
- Required owners approve the scope and access model.

### Phase 1: Build the experiment foundation

**Suggested duration:** 3 to 5 days

**Objectives**

- Deploy the sample workload reproducibly.
- Establish equivalent baseline and candidate variants.
- Prove load generation, telemetry, and cleanup.

**Tasks**

- Create the sample application and Bicep modules.
- Add baseline and candidate parameters without duplicating infrastructure.
- Add experiment tags and deterministic resource naming.
- Create the Azure Load Testing configuration.
- Instrument application and resource telemetry.
- Add health checks and telemetry-readiness checks.
- Implement automated teardown and a scheduled cleanup backstop.
- Add an experiment specification and schema validation.

**Deliverables**

- Sample workload.
- Versioned Bicep deployment.
- Load-test definition.
- Experiment specification.
- Deployment and cleanup scripts.

**Exit criteria**

- A local or manually started workflow deploys both variants.
- The same load profile runs against both variants.
- Required performance and consumption telemetry is queryable.
- Cleanup removes all experiment resources.

### Phase 2: Implement core FinOps MCP tools

**Suggested duration:** 3 to 5 days

**Objectives**

- Give the coding agent bounded, attributable FinOps context.
- Establish stable schemas and provider boundaries.

**Tasks**

- Select the MCP implementation language and hosting model.
- Implement configuration validation and explicit scope allowlists.
- Implement the common response envelope.
- Add provider adapters for FinOps hubs, pricing, and Advisor.
- Implement:
  - `get_cost_summary`
  - `get_cost_by_resource`
  - `get_optimization_recommendations`
  - `get_current_pricing`
- Add authentication through managed identity or workload identity federation.
- Add audit telemetry and structured errors.
- Add unit tests for input validation, scope enforcement, provider failures, and stale data.
- Add contract tests with representative provider responses.

**Deliverables**

- Read-only MCP server.
- Four core tools.
- Schemas and provider adapters.
- Automated unit and contract tests.
- Setup and configuration documentation.

**Exit criteria**

- The coding agent can call all four tools.
- Requests outside the configured scope are denied.
- Provider failures are explicit and do not activate fixture data.
- Responses include source, freshness, warnings, and evidence.

### Phase 3: Build estimation and comparison

**Suggested duration:** 3 to 5 days

**Objectives**

- Convert measured consumption into transparent unit-cost results.
- Enforce performance and evidence requirements.

**Tasks**

- Define meter adapters for the selected workload.
- Normalize measurement units and price units.
- Implement required-price validation.
- Calculate baseline and candidate experiment cost.
- Calculate cost per successful workload unit.
- Compare cost, latency, throughput, and error rate.
- Classify price coverage and telemetry completeness.
- Add confidence factors and result validity rules.
- Add tests for rounding, missing prices, zero workload units, failed requests, mixed currencies, and guardrail failures.

**Deliverables**

- Unit-cost estimator.
- Comparison model.
- Confidence evaluation.
- Machine-readable experiment result.

**Exit criteria**

- Known input fixtures produce deterministic cost results.
- Missing prices cannot appear as zero cost.
- A failed performance guardrail produces a reject recommendation.
- The result preserves assumptions and excluded charges.

### Phase 4: Automate the end-to-end workflow

**Suggested duration:** 3 to 5 days

**Objectives**

- Connect repository changes, experiments, and pull-request reporting.

**Tasks**

- Add a manually approved GitHub Actions workflow.
- Validate the experiment specification before deployment.
- Build and test both revisions.
- Deploy baseline and candidate environments.
- Run warm-up and measured load stages.
- Query telemetry using exact experiment measurement windows.
- Call the estimator.
- Update one pull-request decision comment.
- Upload machine-readable evidence as a workflow artifact.
- Run cleanup in an unconditional final stage.
- Create a visible failure when cleanup is incomplete.

**Deliverables**

- End-to-end workflow.
- Pull-request report template.
- Evidence artifact schema.
- Workflow and cleanup runbooks.

**Exit criteria**

- A pull request can start a complete experiment with approval.
- The report links to the workflow, load test, telemetry, and artifacts.
- Failed experiments do not publish a valid savings recommendation.
- Cleanup runs after both success and failure.

### Phase 5: Integrate the coding-agent experience

**Suggested duration:** 2 to 3 days

**Objectives**

- Make the workflow usable through a clear agent interaction.
- Keep recommendations bounded, explainable, and reviewable.

**Tasks**

- Add repository instructions for optimization tasks.
- Define how the agent discovers workload units, SLOs, and experiment files.
- Add guidance for choosing one optimization lever.
- Require the agent to state assumptions and expected tradeoffs.
- Add a command or tool for starting the approved workflow.
- Validate the experience from a clean session.
- Create a demonstration script and fallback path.

**Deliverables**

- Agent instructions.
- Example optimization prompt.
- Demonstration runbook.
- Recorded happy-path evidence.

**Exit criteria**

- A developer can complete the scenario without undocumented manual steps.
- The agent retrieves FinOps context before proposing a change.
- The candidate change is limited to the selected scenario.
- The final response directs the reviewer to the decision record.

### Phase 6: Add AI token-cost measurement

**Suggested duration:** 2 to 4 days

**Objectives**

- Use the current branch prototype as an optional AI workload adapter.
- Make token-cost evidence portable and safe.

**Tasks**

- Parameterize Application Insights and FinOps hub endpoints.
- Normalize model and meter identifiers.
- Select price rows by date, currency, region, and offer.
- Preserve unmatched quantities as unpriced.
- Validate cached, input, and output token calculations.
- Validate parent and subagent attribution.
- Add Foundry-native and OpenTelemetry fixtures.
- Integrate token measurements into the experiment result.
- Package the workbook through the repository workbook build path or keep it as an explicitly labeled hack artifact.

**Deliverables**

- AI token meter adapter.
- Tested price enrichment.
- Agent-level evidence view.
- Updated workbook deployment.

**Exit criteria**

- Representative traces produce expected attribution and cost.
- Unmatched models are visible and block authoritative totals.
- The workbook deploys without environment-specific resource IDs.
- Automated lint and query tests cover the new KQL surfaces.

### Phase 7: Harden and package

**Suggested duration:** 1 to 2 weeks

**Objectives**

- Turn the successful hack into a reusable reference implementation.

**Tasks**

- Separate sample configuration from shared components.
- Add deployment and configuration templates.
- Add integration tests for MCP providers and the experiment workflow.
- Add fault-injection tests for provider, deployment, telemetry, and cleanup failures.
- Establish supported versions and compatibility expectations.
- Review threat model and least-privilege roles.
- Add telemetry retention and privacy guidance.
- Add architecture decision records.
- Validate a second workload or optimization lever.
- Document known limitations and support boundaries.

**Deliverables**

- Reusable reference package.
- Automated test suite.
- Security and operations guide.
- Second-scenario validation report.
- Release and contribution guidance.

**Exit criteria**

- A new repository can adopt the pattern from documented inputs.
- Security-critical and cost-calculation paths have automated coverage.
- Cleanup and failure behavior have been tested.
- The architecture and implementation agree.

## MVP backlog

| ID | Work item | Phase | Priority | Depends on | Acceptance criteria |
| --- | --- | --- | --- | --- | --- |
| DTO-001 | Select workload and optimization | 0 | Must | None | Decision record names the workload, lever, unit, SLOs, and expected signal |
| DTO-002 | Confirm sandbox access and quotas | 0 | Must | None | Required identities, regions, providers, and limits are documented |
| DTO-003 | Define experiment schema | 1 | Must | DTO-001 | Invalid or incomplete specifications fail validation |
| DTO-004 | Create reusable Bicep deployment | 1 | Must | DTO-001 | Both variants deploy from the same modules and parameters |
| DTO-005 | Create equivalent load test | 1 | Must | DTO-004 | Baseline and candidate run the same profile and data set |
| DTO-006 | Add telemetry correlation | 1 | Must | DTO-004 | Metrics can be filtered by experiment and variant |
| DTO-007 | Automate cleanup | 1 | Must | DTO-004 | Success and failure paths remove temporary resources |
| DTO-008 | Define MCP response schemas | 2 | Must | DTO-002 | Schemas include source, scope, freshness, warnings, and evidence |
| DTO-009 | Implement cost summary tool | 2 | Must | DTO-008 | Bounded historical summary is returned for an allowed scope |
| DTO-010 | Implement resource cost tool | 2 | Must | DTO-008 | Material cost drivers are returned without raw export data |
| DTO-011 | Implement recommendation tool | 2 | Must | DTO-008 | Recommendations include source and retrieval time |
| DTO-012 | Implement pricing tool | 2 | Must | DTO-008 | Prices include currency, region, effective time, and source |
| DTO-013 | Implement unit-cost estimator | 3 | Must | DTO-003, DTO-005, DTO-012 | Fixture calculations are deterministic and fully explained |
| DTO-014 | Implement guardrail comparison | 3 | Must | DTO-005, DTO-013 | Cost savings cannot override a failed SLO |
| DTO-015 | Add confidence evaluation | 3 | Should | DTO-013 | Report shows price, telemetry, and sample limitations |
| DTO-016 | Build experiment workflow | 4 | Must | DTO-004, DTO-005, DTO-013 | Approved workflow deploys, tests, reports, and cleans up |
| DTO-017 | Publish PR decision record | 4 | Must | DTO-016 | One report comment contains cost, SLOs, assumptions, and links |
| DTO-018 | Add agent instructions | 5 | Must | DTO-009 through DTO-012, DTO-016 | Agent retrieves context and creates one bounded candidate |
| DTO-019 | Create demo runbook | 5 | Must | DTO-018 | Another team member can run the demo without undocumented steps |
| DTO-020 | Harden AI token pricing | 6 | Should | DTO-012, DTO-013 | Missing or mismatched model prices remain visible and block totals |
| DTO-021 | Validate subagent attribution | 6 | Should | DTO-006 | Representative traces prove the documented attribution behavior |
| DTO-022 | Add end-to-end integration test | 7 | Should | DTO-016 | Test validates the workflow against an ephemeral environment |

## Milestones

| Milestone | Demonstrated capability | Required work |
| --- | --- | --- |
| M1: Experiment ready | Baseline and candidate deploy, receive equal load, emit telemetry, and clean up | Phase 0 and Phase 1 |
| M2: Agent grounded | The coding agent retrieves scoped cost, pricing, and recommendation context | Phase 2 |
| M3: Comparison valid | The estimator calculates unit cost and enforces performance guardrails | Phase 3 |
| M4: End-to-end demo | A pull request produces a complete decision record | Phase 4 and Phase 5 |
| M5: AI scenario ready | Agent token consumption is priced and attributed with documented limits | Phase 6 |
| M6: Reference pattern | A second team can adopt the workflow from documentation | Phase 7 |

## Roles

One person can hold multiple roles during the hack.

| Role | Responsibilities |
| --- | --- |
| Product and demo lead | Scenario, success criteria, narrative, scope, and stakeholder decisions |
| Agent and MCP engineer | Tool contracts, providers, schemas, authentication, and agent instructions |
| Workload engineer | Sample application, infrastructure, optimization change, and telemetry |
| Experiment engineer | GitHub Actions, load testing, evidence collection, and cleanup |
| FinOps engineer | Cost model, pricing basis, allocation, confidence, and result interpretation |
| Security reviewer | Identity, authorization, data exposure, resource governance, and threat review |
| Documentation owner | Architecture decisions, setup, demonstration, and known limitations |

## Quality strategy

### Unit tests

- MCP input validation and scope enforcement.
- Provider response normalization.
- Meter quantity conversion.
- Cost calculations and rounding.
- Missing-price and mixed-currency behavior.
- Guardrail and confidence rules.
- Pull-request report rendering.

### Contract tests

- MCP response envelopes.
- FinOps hub query outputs.
- Pricing provider fields and effective dates.
- Azure Monitor telemetry mappings.
- Experiment artifact schema.

### Integration tests

- Federated GitHub-to-Azure authentication.
- Bicep deployment and cleanup.
- Azure Load Testing execution.
- Telemetry retrieval by experiment ID.
- Pull-request comment update.

### End-to-end tests

- A known candidate produces an expected directional cost change.
- A performance regression produces a reject recommendation.
- Missing pricing prevents a valid final comparison.
- A failed workflow leaves no experiment resources.

## Security checklist

- [ ] GitHub Actions uses workload identity federation.
- [ ] MCP runtime uses managed identity where applicable.
- [ ] Cost-intelligence permissions are read-only.
- [ ] Experiment deployment permissions are limited to the sandbox scope.
- [ ] MCP requests cannot select an arbitrary subscription or workspace.
- [ ] Arbitrary KQL, SQL, and Resource Graph execution is not exposed to the agent.
- [ ] Pull-request reports contain no credentials or sensitive billing data.
- [ ] Experiment resource groups have budgets, tags, and expiration.
- [ ] Cleanup failure is visible and actionable.
- [ ] Human approval is required before deployment and merge.

## Key risks

| Risk | Impact | Mitigation | Trigger |
| --- | --- | --- | --- |
| Cost data is too stale for the scenario | Recommendation lacks useful context | Use cost data for prioritization and measured consumption for the experiment | Data freshness exceeds the documented limit |
| Public pricing differs from enterprise rates | Savings estimate is misleading | Label the pricing basis and support a FinOps hub provider | Negotiated pricing is unavailable |
| Short tests produce noisy results | Candidate decision is unstable | Warm up, repeat runs, and report variance | Repeated results differ beyond tolerance |
| Services do not expose useful consumption metrics | Unit cost cannot be calculated | Choose a workload with measurable meters or instrument application-level units | Required meters are absent after Phase 1 |
| Agent proposes a broad change | Review and attribution become difficult | Limit each experiment to one lever and validate changed paths | Candidate spans unrelated components |
| Experiment resources remain deployed | Unexpected cost | Unconditional cleanup, expiration tags, and scheduled backstop | Cleanup workflow reports remaining resources |
| MCP exposes excessive billing context | Data governance concern | Aggregate at the provider and enforce field allowlists | Raw export fields appear in tool responses |
| AI token prices do not match model names | Costs appear as zero or null | Normalize identifiers and block totals with unpriced usage | Price coverage is below 100 percent |
| Subagent attribution is incorrect | Optimization targets the wrong agent | Validate span-tree behavior with fixtures and captured traces | Parent and subagent totals do not reconcile |

## Decision gates

### Gate 1: Scenario commitment

Proceed when the workload, optimization lever, SLOs, access, and budget are confirmed.

### Gate 2: Measurement viability

Proceed when both variants can run equivalent load and produce the required telemetry.

### Gate 3: Estimation validity

Proceed when required quantities map to prices and the unit-cost calculation passes fixtures.

### Gate 4: Demo readiness

Proceed when the complete workflow succeeds twice and the failure path cleans up correctly.

### Gate 5: Reference implementation

Proceed after the architecture, security model, tests, and setup documentation support adoption by another team.

## Definition of done for the hack

- The optimizer can be installed or invoked from the FinOps Toolkit repository without another source repository.
- The coding agent retrieves grounded context through the core MCP tools.
- The agent produces one explainable repository change or actionable patch.
- GitHub Actions deploys equivalent baseline and candidate environments.
- The same load profile runs against both variants.
- The report compares estimated cost per workload unit.
- All defined performance guardrails are evaluated.
- The report includes pricing basis, assumptions, limitations, and confidence factors.
- Evidence links are traceable to a commit and workflow run.
- A person reviews the result before merge.
- Experiment resources are removed.
- The demonstration can be repeated from the runbook.
- No command, package, workflow, or test requires the autonomous optimization harness.

## Immediate next actions

1. Select the sample workload and optimization lever.
2. Confirm the Azure sandbox, FinOps hub, region, quotas, and GitHub identity.
3. Create the first architecture decision record.
4. Define `experiment.yaml` and its schema.
5. Build the baseline deployment and load test before expanding the MCP surface.

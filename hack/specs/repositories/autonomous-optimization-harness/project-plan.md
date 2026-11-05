# Autonomous optimization harness project plan

## Purpose

This plan delivers the [autonomous optimization harness architecture](./architecture.md). It creates a portable command-line product, a provider contract, two isolated specialist agents, and the first FinOps Toolkit provider integration.

The plan is a greenfield-repository handoff. Copy this file and the architecture document into the new harness repository. No implementation task in Phases 0 through 3 requires access to FinOps Toolkit or to the repository where these documents were drafted.

## Target outcome

A customer can add a small configuration directory to a repository and run:

```text
harness run --all --non-interactive
```

The command can run locally or through GitHub Actions, Azure DevOps, cron, or another scheduler. It performs the enabled analysis workflows, enforces policy, preserves evidence, and produces one or more of these outputs:

- A tested FinOps optimization pull request.
- A rejected candidate with evidence explaining why it failed.
- An answerability decision record.
- GitHub issues or user stories derived from an approved record.
- A proposal package for a solution integrator.

## Instructions for the implementing coding agent

Execute the plan in dependency order. Do not start with live cloud integrations.

### Fixed implementation decisions

- Create a standalone repository for the harness.
- Use TypeScript on the current Node.js long-term support release.
- Build a noninteractive CLI and a container image.
- Keep GitHub Actions and other schedulers thin.
- Keep customer toolchains behind executable adapter contracts.
- Keep generic agents in the harness.
- Keep provider-specific source knowledge outside the harness.
- Use versioned JSON Schema for public records.
- Use structured JSON or YAML as the system of record and Markdown as a rendering.
- Disable automatic merge and production changes.

### Initial implementation sequence

1. Create the repository skeleton, package manager configuration, formatting, linting, tests, and continuous integration.
2. Implement schemas and generated or hand-written TypeScript types.
3. Implement `harness validate` against static configuration.
4. Implement run IDs, artifacts, checkpoints, structured logs, and exit codes.
5. Implement mock providers and local adapters.
6. Implement one synthetic agent run without a coding model.
7. Implement policy checks and capability isolation.
8. Add the FinOps agent against deterministic fixtures.
9. Add the answerability agent against sanitized file fixtures.
10. Add Git and GitHub integrations.
11. Integrate external providers only after contract tests are stable.

### Required repository bootstrap

```text
optimization-harness/
  specs/
    architecture.md
    project-plan.md
  src/
    cli/
    control-plane/
    agents/
    contracts/
    providers/
    adapters/
    evaluators/
    policy/
    publishers/
    git/
  schemas/
  templates/
  tests/
    unit/
    contract/
    integration/
    end-to-end/
  samples/
  package.json
  tsconfig.json
  Dockerfile
  README.md
```

The coding agent should maintain a dependency-aware task list using the backlog IDs in this plan. Each completed public contract must include tests and an example fixture before dependent integration work starts.

## Delivery principles

- Build the portable contracts before provider-specific implementations.
- Keep scheduler workflows thin.
- Keep customer build and deployment logic behind adapters.
- Keep generic agents in the harness and source-specific logic in providers.
- Start answerability analysis as a read-only advisory workflow.
- Prove one complete scenario for each agent before adding breadth.
- Make every run resumable, auditable, and safe to clean up.
- Treat machine-readable records as canonical and documents as renderings.

## Scope

### MVP

- A standalone TypeScript and Node.js command-line application.
- Local process and container execution.
- Versioned configuration, provider, adapter, evidence, opportunity, experiment, and decision-record schemas.
- GitHub repository integration.
- One FinOps provider contract.
- One FinOps Toolkit provider package.
- One customer workload adapter example.
- One cost optimization scenario.
- One failed-answer event collector.
- One schema or catalog provider.
- Answerability classification and clustering.
- One decision-record renderer.
- GitHub pull-request and issue publishers.
- Durable artifacts and resumable checkpoints.

### Target enhancements

- Additional FinOps providers.
- Azure DevOps repository and work-item integration.
- Additional application telemetry and data catalog providers.
- Approved-decision implementation agent.
- Proposal templates for solution integrators.
- A provider marketplace or registry.
- Multi-repository and portfolio-level analysis.
- Hosted control-plane option.

### Deferred

- Automatic merge.
- Autonomous production deployment.
- Autonomous production schema changes.
- A graphical management portal.
- Cross-customer shared evidence storage.
- Invoice reconciliation.
- General-purpose autonomous software development outside approved decisions and experiments.

## Workstreams

| Workstream | Outcome |
| --- | --- |
| Product contracts | Stable configuration, provider, adapter, evidence, opportunity, and decision schemas |
| CLI and control plane | Portable, resumable, scheduler-neutral execution |
| Provider ecosystem | Replaceable FinOps, conversation, schema, catalog, and telemetry providers |
| Customer adapters | Stack-native build, test, deploy, load, collect, and cleanup operations |
| FinOps agent | Evidence-backed code and infrastructure optimization |
| Answerability agent | Verified capability-gap decision records |
| Evaluation | Cost, performance, answerability, confidence, and policy decisions |
| Delivery integrations | Branches, pull requests, issues, artifacts, and documents |
| Security and operations | Identity, isolation, privacy, retention, audit, and cleanup |
| FinOps Toolkit integration | An optional released provider package owned by the external FinOps Toolkit repository |

## Repository plan

### Harness repository

Create a new repository for:

- CLI and control-plane code.
- Generic agents.
- Public contracts and schemas.
- Evaluators and policy engine.
- GitHub integration.
- Publisher framework.
- Container image.
- Samples and scheduler templates.

### External FinOps Toolkit repository

Add only the FinOps Toolkit integration:

- Provider manifest.
- Curated and tested KQL.
- Response mappings.
- FinOps Toolkit grounding.
- Contract fixtures.
- Packaging and release changes.
- Compatibility tests.

### Customer repository

Add:

- `.optimization-harness/harness.yaml`
- `.optimization-harness/policy.yaml`
- Workload definitions.
- Adapter commands.
- Requirements and architecture context.
- Optional domain glossary and semantic metadata.

## Delivery phases

### Phase 0: Confirm contracts and ownership

**Suggested duration:** 3 to 5 days

**Objectives**

- Agree on repository boundaries.
- Define the first end-to-end FinOps and answerability scenarios.
- Establish naming, ownership, and autonomy boundaries.

**Tasks**

- Select the first customer-style sample repository.
- Select one measurable FinOps optimization.
- Select one representative unanswered-question cluster.
- Define the normalized FinOps capabilities.
- Define the customer adapter operations.
- Define the answerability event and decision-record minimum fields.
- Decide the coding-agent runtime for unattended execution.
- Record the initial architecture decisions.

**Deliverables**

- Responsibility matrix.
- Scenario briefs.
- Initial schemas.
- Threat-model outline.
- Architecture decision records.

**Exit criteria**

- Each component has one clear owning repository.
- Both scenarios have measurable acceptance criteria.
- The harness can remain independent of FinOps hub and customer schema details.

### Phase 1: Bootstrap the harness CLI

**Suggested duration:** 1 week

**Objectives**

- Create a portable, noninteractive command.
- Validate configuration and persist run state.

**Tasks**

- Create the TypeScript and Node.js project.
- Implement `init`, `validate`, `run`, `resume`, `render`, and `cleanup`.
- Add structured logging and deterministic exit codes.
- Define the artifact directory.
- Add run IDs and correlation.
- Add JSON Schema validation.
- Add local checkpoint persistence.
- Package a container image.
- Add unit tests and a sample GitHub Actions workflow.

**Deliverables**

- Installable CLI.
- Container image.
- Configuration schemas.
- Run-state and artifact model.
- Scheduler example.

**Exit criteria**

- The same command runs locally and in GitHub Actions.
- Invalid configuration fails before any agent or provider starts.
- An interrupted synthetic run can resume.

### Phase 2: Implement extensions and policy

**Suggested duration:** 1 to 2 weeks

**Objectives**

- Load providers, agents, adapters, evaluators, and publishers through stable contracts.
- Enforce least privilege before execution.

**Tasks**

- Implement manifest discovery.
- Implement compatibility checks.
- Define capability resolution.
- Add MCP, executable, and container provider transports as needed.
- Implement the agent manifest and tool allowlist.
- Add policy checks for repository paths, Git writes, deployments, runtime, and candidate count.
- Add provider and adapter contract test kits.
- Add signed-package and checksum hooks.

**Deliverables**

- Extension runtime.
- Provider and adapter SDK contracts.
- Policy engine.
- Contract test kit.

**Exit criteria**

- The harness can replace one mock provider with another without changing an agent.
- An undeclared capability or denied operation cannot run.
- Incompatible provider versions fail with a clear error.

### Phase 3: Implement customer stack adapters

**Suggested duration:** 1 week

**Objectives**

- Prove that the harness can execute a workload without owning its toolchain.

**Tasks**

- Define request and response envelopes for each adapter operation.
- Implement build, test, deploy, readiness, load, collect, and cleanup stubs.
- Create one complete sample adapter set.
- Add resource tracking and idempotent cleanup.
- Add adapter timeouts and log redaction.
- Test success, failure, cancellation, and cleanup paths.

**Deliverables**

- Adapter specification.
- Sample customer repository.
- Adapter conformance tests.

**Exit criteria**

- The harness runs the sample application's native commands.
- The adapter reports all created resources.
- Cleanup runs after success, failure, and cancellation.

### Phase 4: Prove the FinOps provider contract

**Suggested duration:** 1 to 2 weeks

**Objectives**

- Complete the normalized FinOps contract in the standalone harness.
- Prove provider replacement with deterministic mocks.
- Integrate FinOps Toolkit only through an independently released package.

**External tasks in the FinOps Toolkit repository**

- Add the provider manifest and compatibility metadata.
- Reuse the existing Azure MCP read-only Kusto configuration.
- Select or add curated KQL for cost summary, resource cost, recommendations, and pricing.
- Define response mappings and warning behavior.
- Preserve currency, effective date, scope, freshness, and source.
- Reject missing required pricing instead of returning zero.
- Add provider contract fixtures.
- Add Pester tests for packaging, KQL conventions, manifests, and mappings.
- Update the existing agent-plugin build and release process.

**Tasks in the harness repository**

- Implement the normalized FinOps contract.
- Add provider installation and configuration.
- Add mock FinOps fixtures.
- Add contract tests shared with provider owners.
- Add a file-based reference provider that does not require cloud access.
- Ensure the generic FinOps agent can run before the FinOps Toolkit provider exists.

**Deliverables**

- Normalized FinOps schemas.
- Mock and file-based reference providers.
- Provider documentation.
- Automated contract tests.
- Optional FinOps Toolkit provider package when the external integration is available.

**Exit criteria**

- The harness retrieves FinOps data without knowing FinOps hub table names.
- Provider replacement does not change the generic agent.
- Responses expose missing, stale, or unpriced data explicitly.
- The harness test suite and sample run succeed without the FinOps Toolkit provider.

### Phase 5: Deliver the FinOps refactoring loop

**Suggested duration:** 2 weeks

**Objectives**

- Produce and validate one autonomous candidate change.

**Tasks**

- Implement the generic FinOps refactoring agent.
- Add repository and requirement context assembly.
- Add bounded hypothesis selection.
- Add isolated branch creation.
- Limit changed paths and candidate size.
- Run baseline and candidate experiments.
- Calculate cost per successful workload unit.
- Enforce functional and nonfunctional gates.
- Add confidence and evidence-completeness evaluation.
- Publish a pull request only when policy and gates pass.
- Preserve rejected candidates as run artifacts.

**Deliverables**

- FinOps refactoring agent.
- Experiment evaluator.
- Pull-request renderer.
- End-to-end demonstration.

**Exit criteria**

- A known optimization produces the expected directional cost result.
- A performance regression is rejected.
- Missing required prices prevent a savings recommendation.
- The harness creates no production changes or automatic merges.

### Phase 6: Build answerability evidence collection

**Suggested duration:** 1 to 2 weeks

**Objectives**

- Capture and classify failed-answer evidence safely.
- Verify whether failures represent data capability gaps.

**Tasks**

- Define the failed-answer event schema.
- Add a collector for the sample AI application's logs or traces.
- Add sanitization and protected-content references.
- Implement the failure taxonomy.
- Cluster semantically related questions.
- Add frequency, distinct-user, confidence, and business-impact thresholds.
- Add schema, semantic-model, and catalog provider contracts.
- Verify current capability before recommending new data.
- Create a labeled evaluation set for classification tests.

**Deliverables**

- Failed-answer collector.
- Classification and clustering pipeline.
- Schema and catalog provider contracts.
- Evaluation data set.

**Exit criteria**

- Protected question content does not appear in ordinary logs or documents.
- Known failure examples are classified at the agreed accuracy threshold.
- Query-generation and access failures are not mislabeled as missing schema.

### Phase 7: Deliver decision records

**Suggested duration:** 1 week

**Objectives**

- Turn verified answerability gaps into reusable architecture artifacts.

**Tasks**

- Implement the answerability analysis agent.
- Define option-analysis guidance.
- Include security, privacy, reliability, ownership, cost, and operational impacts.
- Add acceptance criteria tied to representative questions.
- Generate the canonical decision-record YAML or JSON.
- Render Markdown architecture decision records.
- Add GitHub issue and user-story rendering.
- Add a solution-integrator proposal template.
- Require approval before any implementation workflow.

**Deliverables**

- Answerability analysis agent.
- Decision-record schema.
- Markdown, issue, and proposal renderers.
- End-to-end demonstration.

**Exit criteria**

- A verified question cluster produces a complete decision record.
- The record distinguishes schema, pipeline, semantic, API, and service options.
- Every recommendation links to sanitized evidence.
- No code or schema is changed by default.

### Phase 8: Harden and pilot

**Suggested duration:** 2 to 4 weeks

**Objectives**

- Validate portability, safety, and supportability with representative engagements.

**Tasks**

- Pilot with a second application stack.
- Pilot with a second FinOps provider or mock alternative.
- Add cancellation, timeout, provider outage, and cleanup fault tests.
- Add artifact signing and software bills of materials.
- Add OpenTelemetry instrumentation for the harness.
- Add retention, deletion, and evidence-classification controls.
- Add upgrade and compatibility testing.
- Document incident response and recovery.
- Review the threat model.
- Measure false-positive rates for both agents.

**Deliverables**

- Pilot reports.
- Security and operations guide.
- Compatibility matrix.
- Release process.
- Support boundaries and known limitations.

**Exit criteria**

- A second stack adopts the harness without changing the core.
- A second FinOps provider passes the public contract.
- Security-critical failures and cleanup paths have automated coverage.
- Agent recommendations meet the agreed precision threshold.

## MVP backlog

| ID | Work item | Phase | Owner repository | Priority | Acceptance criteria |
| --- | --- | --- | --- | --- | --- |
| HNS-001 | Define repository responsibilities | 0 | Harness | Must | Ownership matrix has no overlapping control-plane responsibility |
| HNS-002 | Select FinOps scenario | 0 | Harness | Must | Scenario defines workload unit, change, tests, and expected signal |
| HNS-003 | Select answerability scenario | 0 | Harness | Must | Scenario includes representative failures and current schema |
| HNS-004 | Define configuration schema | 1 | Harness | Must | Invalid configuration fails with actionable errors |
| HNS-005 | Implement CLI lifecycle | 1 | Harness | Must | CLI supports validate, run, resume, render, and cleanup |
| HNS-006 | Add durable checkpoints | 1 | Harness | Must | Interrupted synthetic runs resume without repeating completed stages |
| HNS-007 | Package container image | 1 | Harness | Must | The same image runs locally and in GitHub Actions |
| HNS-008 | Define provider manifest | 2 | Harness | Must | Manifest declares capabilities, runtime, schemas, and compatibility |
| HNS-009 | Implement capability resolution | 2 | Harness | Must | Agents receive only configured and allowed capabilities |
| HNS-010 | Implement policy engine | 2 | Harness | Must | Denied Git, deployment, path, and query operations cannot execute |
| HNS-011 | Publish provider contract kit | 2 | Harness | Must | Mock providers can prove contract conformance |
| HNS-012 | Define adapter contracts | 3 | Harness | Must | Every operation has versioned request, response, and exit behavior |
| HNS-013 | Create sample stack adapters | 3 | Sample customer | Must | Sample builds, tests, deploys, loads, collects, and cleans up |
| HNS-014 | Track experiment resources | 3 | Harness | Must | Cleanup receives an authoritative resource list |
| HNS-015 | Define normalized FinOps contract | 4 | Harness | Must | Contract covers cost, pricing, recommendations, scope, and freshness |
| HNS-016 | Package FinOps Toolkit provider | 4 | FinOps Toolkit | Must | Harness installs and discovers the released provider |
| HNS-017 | Add FinOps Toolkit response mappings | 4 | FinOps Toolkit | Must | Hub results validate against normalized schemas |
| HNS-018 | Add FinOps Toolkit contract tests | 4 | FinOps Toolkit | Must | Representative current and error responses pass shared tests |
| HNS-019 | Implement FinOps refactoring agent | 5 | Harness | Must | Agent produces one bounded hypothesis per candidate |
| HNS-020 | Implement experiment comparison | 5 | Harness | Must | Cost improvement cannot override failed requirements |
| HNS-021 | Add isolated branch workflow | 5 | Harness | Must | Candidate writes occur only on a unique branch |
| HNS-022 | Publish optimization pull request | 5 | Harness | Must | PR includes hypothesis, evidence, cost, tests, and limitations |
| HNS-023 | Define failed-answer event | 6 | Harness | Must | Schema supports protected content references and classification inputs |
| HNS-024 | Implement event sanitization | 6 | Customer integration | Must | Protected content does not enter standard logs or reports |
| HNS-025 | Implement failure classifier | 6 | Harness | Must | Evaluation set meets the agreed precision threshold |
| HNS-026 | Implement clustering and thresholds | 6 | Harness | Must | Isolated events do not create architecture recommendations |
| HNS-027 | Define schema and catalog contracts | 6 | Harness | Must | Agent can verify current capability without provider-specific logic |
| HNS-028 | Implement answerability agent | 7 | Harness | Must | Verified gaps produce structured option analysis |
| HNS-029 | Implement decision-record renderer | 7 | Harness | Must | Canonical record renders as valid Markdown |
| HNS-030 | Implement issue and story renderer | 7 | Harness | Should | Approved record creates traceable backlog items |
| HNS-031 | Add proposal-package renderer | 7 | Integration package | Should | Integrator template includes evidence, scope, options, and assumptions |
| HNS-032 | Add harness OpenTelemetry | 8 | Harness | Should | Runs expose duration, failures, provider calls, and cleanup status |
| HNS-033 | Validate second application stack | 8 | Harness | Should | No core changes are needed to adopt the stack |
| HNS-034 | Validate alternative FinOps provider | 8 | Provider owner | Should | Provider passes the public FinOps contract |
| HNS-035 | Complete security review | 8 | Harness | Must | Threats, controls, residual risks, and operating requirements are documented |

## Milestones

| Milestone | Demonstrated capability | Required phases |
| --- | --- | --- |
| M1: Portable runner | One command runs locally and in GitHub Actions | 0 and 1 |
| M2: Extension platform | Providers and adapters load through enforced contracts | 2 and 3 |
| M3: FinOps Toolkit connected | Harness consumes normalized FinOps hub evidence | 4 |
| M4: Closed-loop optimization | Agent creates and validates a bounded cost candidate | 5 |
| M5: Answerability analysis | Failed-answer clusters produce verified gap analysis | 6 |
| M6: Decision delivery | Gap analysis renders as records, issues, and proposal inputs | 7 |
| M7: Pilot ready | Second stack and provider validate portability | 8 |

## Responsibility matrix

| Responsibility | Harness | FinOps Toolkit | Customer repository | Integration package |
| --- | :---: | :---: | :---: | :---: |
| CLI and run lifecycle | Owns |  |  |  |
| Generic agents | Owns |  |  | May extend |
| Public capability contracts | Owns | Implements | Implements | Implements |
| FinOps hub KQL and mappings |  | Owns |  |  |
| Customer build and test commands | Invokes |  | Owns | May supply templates |
| Customer deployment and cleanup | Coordinates |  | Owns | May supply templates |
| Functional and nonfunctional requirements | Enforces |  | Owns | May advise |
| Provider-specific grounding | Loads | Owns its grounding | Owns private context | Owns its grounding |
| Conversation sanitization | Enforces contract |  | Owns source controls | May implement |
| Evidence and decision schemas | Owns | Conforms | Conforms | Conforms |
| Pull-request and issue publishing | Owns adapters |  | Configures | May add publishers |
| Proposal templates | Supports |  | May customize | Owns specialized templates |
| Merge approval | Never owns |  | Owns |  |
| Production change approval | Never owns |  | Owns |  |

## Test strategy

### Unit tests

- Configuration and schema validation.
- Capability resolution.
- Policy decisions.
- Checkpoint transitions.
- FinOps calculations.
- Answerability classification.
- Decision-record rendering.
- Log redaction.

### Contract tests

- Provider manifests.
- FinOps capability responses.
- Customer adapter operations.
- Evidence and opportunity records.
- Failed-answer events.
- Schema and catalog provider responses.
- Publisher outputs.

### Integration tests

- GitHub authentication and isolated branches.
- Workload identity federation.
- FinOps Toolkit provider startup and queries.
- Sample workload deployment and cleanup.
- OpenTelemetry collection.
- Pull-request and issue creation.

### End-to-end tests

- A valid cost optimization creates a pull request.
- A regression is rejected.
- Missing pricing prevents an approval result.
- A known data gap creates a decision record.
- A query-generation failure does not create a schema proposal.
- An interrupted run resumes.
- Every experiment removes its resources.

## Security checklist

- [ ] Providers and adapters declare required capabilities.
- [ ] Agents receive separate tool allowlists.
- [ ] Provider and deployment identities are separate.
- [ ] Git writes are limited to isolated branches.
- [ ] Automatic merge is disabled.
- [ ] Production changes are disabled.
- [ ] Arbitrary SQL, KQL, cloud, and shell access is denied by default.
- [ ] Conversation evidence is sanitized before analysis.
- [ ] Protected content uses references instead of ordinary artifacts.
- [ ] Evidence has classification and retention metadata.
- [ ] Provider packages are pinned and integrity checked.
- [ ] Cleanup failure returns a failing status.
- [ ] Every sensitive operation has an audit event.

## Key risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Generic agent leaks provider assumptions | Provider replacement requires agent changes | Enforce normalized capability contracts and provider contract tests |
| Customer adapters become a second build system | Adoption becomes expensive | Keep adapters as thin wrappers around existing commands |
| Unattended coding agent makes broad changes | Review and attribution become unsafe | Limit paths, files, candidates, runtime, and one hypothesis per experiment |
| Short tests misrepresent cost | Incorrect optimization recommendation | Use normalized consumption, repeated runs, confidence, and later billed validation |
| Failed answers contain sensitive data | Privacy or confidentiality breach | Sanitize at source, use protected references, and enforce retention |
| Agent assumes every failure is missing data | Unnecessary schema and service proposals | Classify, cluster, verify current capability, and apply evidence thresholds |
| Decision records become sales claims | Partners overstate certainty or scope | Include assumptions, confidence, alternatives, exclusions, and validation criteria |
| FinOps Toolkit provider and harness drift | Integration breaks after upgrades | Declare compatibility, publish fixtures, and run cross-repository contract tests |
| Scheduler contains orchestration logic | Behavior differs across platforms | Keep schedulers thin and invoke one CLI |
| Cleanup fails after interruption | Unexpected cloud cost | Persist resource inventory, support resume, and add cleanup backstops |

## Definition of done

The standalone harness MVP is complete when:

- One command runs both agents noninteractively.
- GitHub Actions contains no material orchestration logic beyond invoking the harness.
- The harness runs against a customer-style repository through documented adapters.
- Mock and file-based FinOps providers pass the public contract.
- The generic FinOps agent works through the normalized contract.
- A bounded optimization candidate is tested against baseline cost and performance.
- A representative answerability gap produces a verified decision record.
- Decision records render as Markdown and GitHub backlog items.
- Agents have separate permissions and autonomy policies.
- Missing evidence and failed requirements cannot produce success.
- Interrupted runs can resume or clean up safely.
- No workflow can merge or modify production automatically.

The optional FinOps Toolkit integration is complete when its independently released provider package passes the same public contract and can replace the mock provider without changing the harness or generic FinOps agent.

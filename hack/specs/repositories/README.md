# Optimization repository blueprints

## Hack scope

Follow the [hack delivery plan](../../project-plan.md) for the current `H01` through `H12` backlog, deployment order, and acceptance criteria.

The design-time optimizer and sample workload packages are in scope. The autonomous harness, customer integration, and standalone optimization-provider packages are retained as deferred references, not hack dependencies.

## Purpose

This directory contains independent repository specification packages. Copy the contents of each package into the target repository before starting a coding-agent implementation session.

| Package | Target repository | Primary responsibility |
| --- | --- | --- |
| `finops-toolkit-design-time-optimizer` | Microsoft FinOps Toolkit | Standalone FinOps optimization agent, MCP tools, experiments, cost evaluation, and reporting |
| `autonomous-optimization-harness` | New harness repository | Portable CLI, generic agents, orchestration, policy, evidence, Git integration, and publishers |
| `customer-optimization-integration` | Customer application repository | Workload requirements, native adapters, telemetry, test data, guardrails, and approvals |
| `optimization-provider` | Provider-specific repository | Replaceable implementation of FinOps, conversation, schema, catalog, or telemetry capabilities |
| `sample-multi-agent-workload` | New sample application repository | Independently deployable multi-agent NL2SQL workload for FinOps and answerability experiments |

## Repository independence

Each package includes:

- `README.md` with coding-agent startup instructions.
- `architecture.md` with required boundaries, contracts, security, and structure.
- `project-plan.md` with phases, backlog, dependencies, tests, and definition of done.

The packages can reference public contracts owned by another repository, but no repository requires a sibling source checkout. Integrations use released packages, containers, executables, MCP servers, or HTTPS endpoints.

## Reference build order

For the hack, the delivery plan takes precedence: first produce a seeded sandbox and working tokenomics workbook, then run the schema-context optimization experiment. The broader order below applies to future work.

1. Build the standalone FinOps Toolkit design-time optimizer in the existing FinOps Toolkit repository.
2. Build and independently deploy the multi-agent sample workload.
3. Connect the sample's cost scope and Application Insights telemetry to FinOps Toolkit.
4. Bootstrap the autonomous harness with mock and file-based providers.
5. Add the customer integration package to another application repository.
6. Build a provider repository against the harness contract.
7. Replace harness mocks with the released provider.
8. Validate end-to-end runs without introducing source-code dependencies between repositories.

## Shared boundaries

- The FinOps Toolkit optimizer runs without the harness.
- The harness runs without FinOps Toolkit by using mock or alternative providers.
- The customer repository keeps its existing toolchain and exposes thin adapters.
- A provider repository owns source-specific access and normalization.
- Generic agents belong in the harness.
- Provider-specific queries and mappings belong with the provider.
- Production changes and automatic merges remain disabled.

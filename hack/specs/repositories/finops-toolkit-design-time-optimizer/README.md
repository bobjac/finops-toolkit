# FinOps Toolkit design-time optimizer repository handoff

For this hack, start with the [hack delivery plan](../../../project-plan.md). Its `H*` backlog controls scope and sequencing; the `DTO-*` backlog below is a detailed reference. Keep implementation and pull requests in the fork, not upstream.

## Target repository

Copy this specification package into the existing Microsoft FinOps Toolkit repository. The implementation is a self-contained FinOps Toolkit capability and must not depend on the autonomous optimization harness.

## Documents

- [Architecture](./architecture.md)
- [Project plan](./project-plan.md)

## Coding-agent startup instructions

1. Read both documents before editing code.
2. Inspect current FinOps Toolkit agent-plugin, PowerShell, Bicep, KQL, workbook, build, and test conventions.
3. Create dependency-aware tasks from the `DTO-*` backlog.
4. Implement the smallest end-to-end scenario before expanding providers or optimization coverage.
5. Keep the optimizer independently executable through FinOps Toolkit commands, MCP tools, scripts, and GitHub Actions.
6. Add tests with every public contract and cost calculation.
7. Treat missing prices, stale data, failed tests, and incomplete cleanup as failures.

## Required outcome

The repository provides:

- A FinOps optimization agent.
- Bounded read-only MCP tools.
- FinOps hub and Azure data providers.
- A reproducible baseline-versus-candidate experiment.
- Cost-per-workload-unit evaluation.
- Performance and reliability guardrails.
- Pull-request reporting.
- Automated cleanup.
- Packaging and documentation consistent with FinOps Toolkit conventions.

## Prohibited dependency

Do not import, install, or require the autonomous optimization harness to build, test, package, or run the optimizer. A future provider adapter can expose the optimizer to the harness, but that adapter remains optional.

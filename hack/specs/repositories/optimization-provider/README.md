# Optimization provider repository handoff

## Target repository

Create a standalone repository for one provider product or one closely related provider family. A provider translates a source-specific platform into the normalized capabilities consumed by the autonomous optimization harness.

Examples:

- FinOps Toolkit and FinOps hubs.
- Another FinOps platform.
- A FOCUS warehouse.
- Application Insights conversation evidence.
- A database schema or data catalog.
- An OpenTelemetry or cloud-monitoring source.

## Documents

- [Architecture](./architecture.md)
- [Project plan](./project-plan.md)

## Coding-agent startup instructions

1. Read both documents before selecting an implementation transport.
2. Obtain the released harness provider contract or use checked-in contract fixtures.
3. Select the smallest capability set required by the target source.
4. Create dependency-aware tasks from the `PRV-*` backlog.
5. Implement deterministic fixtures and normalization before live authentication.
6. Keep generic optimization and answerability reasoning out of the provider.
7. Fail explicitly on stale, missing, ambiguous, or unauthorized source data.

## Required outcome

The repository produces a versioned, independently released provider package that:

- Declares capabilities and compatibility.
- Validates its configuration.
- Authenticates through approved identity mechanisms.
- Executes bounded source operations.
- Normalizes responses into harness contracts.
- Preserves source, scope, freshness, units, and warnings.
- Passes shared provider contract tests.
- Can run as an MCP server, executable, container, or HTTPS service.

The harness consumes the release artifact. It does not require this repository's source code.

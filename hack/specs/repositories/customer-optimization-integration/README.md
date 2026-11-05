# Customer optimization integration repository handoff

## Target repository

Copy this package into an application or solution repository that will be analyzed by the autonomous optimization harness. This is not a replacement application template. It adds a thin, stack-native integration layer to an existing customer codebase.

## Documents

- [Architecture](./architecture.md)
- [Project plan](./project-plan.md)

## Coding-agent startup instructions

1. Read both documents before modifying the customer application.
2. Identify the repository's existing build, test, deployment, load-test, and telemetry mechanisms.
3. Wrap existing commands instead of creating a second build system.
4. Create dependency-aware tasks from the `CIN-*` backlog.
5. Implement validation and local dry runs before granting cloud or Git write permissions.
6. Preserve the customer's language, framework, infrastructure-as-code, testing, and security conventions.
7. Stop when required business, privacy, performance, or deployment decisions are unknown.

## Required outcome

The customer repository contains a `.optimization-harness/` directory that defines:

- Enabled agents and providers.
- Approved repository paths and operations.
- Workload units and nonfunctional requirements.
- Build, test, deploy, load, telemetry, and cleanup adapters.
- OpenTelemetry and experiment correlation.
- Sanitized failed-answer events for AI applications.
- Evidence classification and retention.
- Reviewers and approval gates.

The integration must remain useful when the harness is not installed. Existing developer, test, and deployment workflows continue to run normally.

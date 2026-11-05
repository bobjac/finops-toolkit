# Autonomous optimization harness repository handoff

## Target repository

Create a new standalone repository for the autonomous optimization harness. Copy this package into `specs/` in that repository.

## Documents

- [Architecture](./architecture.md)
- [Project plan](./project-plan.md)

## Coding-agent startup instructions

1. Read both documents in full.
2. Create dependency-aware tasks from the `HNS-*` backlog.
3. Bootstrap a TypeScript and Node.js command-line project.
4. Implement schemas, validation, run state, mock providers, and local adapters before connecting to cloud services.
5. Keep schedulers thin and keep customer toolchains outside the harness.
6. Keep the FinOps and answerability agents isolated by tools, prompts, permissions, and evaluation.
7. Use released provider packages instead of source-code dependencies.

## First executable milestone

The first vertical slice must run without Azure, GitHub write access, or FinOps Toolkit:

```text
harness validate
harness run --all --non-interactive
harness render --run <run-id> --format markdown
```

Use deterministic fixtures, a local sample repository, mock Git operations, and file-based publishers. Add external integrations only after the public contracts and failure behavior are tested.

## Required outcome

The repository produces a portable CLI and container that can:

- Run generic specialist agents.
- Load replaceable providers and customer adapters.
- Enforce policy.
- Persist evidence and checkpoints.
- Create isolated code candidates when allowed.
- Produce decision records and delivery artifacts.
- Resume or clean up interrupted runs.

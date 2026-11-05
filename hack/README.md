# FinOps design-time optimizer hack

This directory contains the specifications and plans for the sandbox hack in `bobjac/finops-toolkit`.

Start with the [hack delivery plan](./project-plan.md). It defines the demonstration, GitHub Actions deployment, sample data, issue backlog, dependencies, validation, and cleanup.

## Documents

| Document | Purpose |
| --- | --- |
| [Hack delivery plan](./project-plan.md) | Current hack scope and linked `H01` through `H12` delivery backlog |
| [GitHub tracking issue #2](https://github.com/bobjac/finops-toolkit/issues/2) | Ordered checklist, native sub-issue progress, and dependency graph |
| [Hack milestone](https://github.com/bobjac/finops-toolkit/milestone/1) | Open and completed delivery issues in the fork |
| [Design-time optimizer architecture](./specs/repositories/finops-toolkit-design-time-optimizer/architecture.md) | Standalone optimizer boundaries, contracts, and target implementation |
| [Design-time optimizer reference plan](./specs/repositories/finops-toolkit-design-time-optimizer/project-plan.md) | Broader `DTO-*` backlog and post-hack hardening |
| [Sample workload architecture](./specs/repositories/sample-multi-agent-workload/architecture.md) | Independently deployable retail assistant, synthetic data, and telemetry |
| [Sample workload reference plan](./specs/repositories/sample-multi-agent-workload/project-plan.md) | Detailed `SMP-*` workload implementation backlog |
| [Repository blueprint index](./specs/repositories/README.md) | All five retained specification packages, including deferred work |
| [Original baseline architecture](./specs/FinOps_Design_Time_Optimizer_Baseline_Architecture.pdf) | Original PDF reference |

The hack delivery plan controls delivery order and the first demonstration scenario. The reference specifications retain their broader designs; they do not make every future feature a hack requirement.

## Working boundaries

- Keep hack issues, workflow runs, and pull requests in the fork. Do not open upstream pull requests for this work.
- Deploy the fork's `dev` branch through the GitHub `sandbox` environment. Resolve source revisions before building or experimenting.
- Keep the optimizer independently executable from the FinOps Toolkit repository.
- Keep the sample independently deployable; coordinate deployments through explicit configuration and pinned artifacts or revisions.
- Defer the autonomous harness, customer integration, and standalone optimization-provider packages.
- Keep credentials outside this directory and source control. Use OIDC for workflows; `.tmp/` remains ignored.

## Tracking delivery

The 12 `H*` work items are created as issues #3 through #14 under tracking issue #2, with the `hack` label and native blocked-by dependencies. Each includes scope, prerequisites, acceptance criteria, and required validation evidence. The `H*` IDs remain planning identifiers, not GitHub issue numbers.

Use the linked backlog and execution waves in the delivery plan to select ready work. Use the detailed `DTO-*` and `SMP-*` reference backlogs to refine scope, not to create a second competing hack backlog. Record exact validation results and implementation evidence before closing an issue.

## Implementing an issue

Say `build issue 3` to use the repository-local [build-issue skill](../.github/skills/build-issue/SKILL.md). It checks prerequisites, creates `bobjac/issue-<number>-<slug>` from the fork's `origin/dev`, implements and validates the issue, and opens a PR to `bobjac/finops-toolkit:dev`.

The skill requests the repository-required Git approval before branch/publish operations and preserves unrelated work. It leaves the issue open until the PR is merged; it does not merge or open upstream PRs. Commit and publish the skill and required hack specifications before starting work from a clean issue branch.

These documents are intended for source control in the fork. The previous root `specs/` directory was ignored; its contents are now under `hack/specs/`.

---
name: build-issue
description: Implement one issue in bobjac/finops-toolkit when the user says "build issue N", "implement issue N", or "build the next issue". Verify dependencies, implement and validate directly on dev, then commit and push to the fork after explicit approval.
license: MIT
compatibility: Requires Git, authenticated GitHub CLI, repository-specific build tools, and permission for Git writes.
---

# Build an issue in the fork

Take one issue from the hack backlog to a validated revision on `bobjac/finops-toolkit:dev`. Do not create a feature branch or PR unless explicitly requested. Close the issue only after all required evidence is verified and the user explicitly approves closure.

This is the repository-specific direct-dev workflow. It applies only to this fork and takes precedence over personal issue-workflow defaults.

## Fixed boundaries

- Issue repository and publication destination: `bobjac/finops-toolkit`.
- Working branch and push remote: `dev` and `origin`.
- No feature branches or PRs by default. If explicitly requested, use `bobjac/issue-<number>-<short-slug>` and target the fork's `dev`.
- Upstream repository: never create issues, branches, pushes, or PRs in `microsoft/finops-toolkit`.
- Keep the optimizer standalone. Do not introduce an autonomous harness dependency.
- Keep credentials and `.tmp/` out of commits, issue comments, logs, and PR bodies.
- Follow repository instructions, approval requirements, content standards, and testing conventions.
- Never rebase, amend, force-push, reset away work, or squash published history.
- Never deploy, weaken guardrails, merge a PR, or bypass open prerequisites automatically.

Run `gh` inline through the host's shell tool. Do not invoke it from a child script or Node/Python subprocess. Specify the fork explicitly on every GitHub operation instead of relying on the default repository of a fork.

## 1. Identify the issue and verify the repository

Accept a positive integer issue number, a fork issue URL, or an `H*` identifier resolved through `hack/project-plan.md`. Reject an upstream or unrelated issue URL.

For "build the next issue", choose the earliest open delivery issue in the plan whose actual prerequisites are complete. Do not choose the tracking issue, a PR, or an issue already under active implementation.

Read repository instructions and inspect:

```bash
git remote -v
git branch --show-current
git status --short
gh repo view bobjac/finops-toolkit --json nameWithOwner,isFork,defaultBranchRef
gh issue view <N> --repo bobjac/finops-toolkit --json number,title,body,state,labels,milestone,url
```

Verify that `origin` points to `bobjac/finops-toolkit`, publication will target `dev`, and the selected item is an open implementation issue. Stop if the repository, branch configuration, or selected issue is inconsistent; do not silently retarget.

If there are staged, modified, or untracked files, agree how to preserve them before switching branches or syncing. Do not automatically stash, discard, stage, or commit unrelated work. An approved isolated worktree is an alternative, but it must have the required committed specifications.

## 2. Read the acceptance criteria and prerequisites

Read `hack/project-plan.md`, the matching issue section, and every relevant specification or linked requirement before editing code.

Inspect native dependencies:

```bash
gh api repos/bobjac/finops-toolkit/issues/<N>/dependencies/blocked_by
```

Check prerequisites stated in the issue body and plan as well. Every actual prerequisite must be satisfied; an API failure is not an empty dependency list. A prerequisite closed as not planned or without required delivery evidence needs clarification.

If a blocker is open, report its issue number and stop unless the user explicitly approves a dependency/scope change. Record an approved change in the issue and plan rather than silently implementing out of order.

If the specifications are only present as uncommitted files in another branch or worktree, stop and have them published to `dev` first. Do not copy unrelated work into the issue implementation.

## 3. Obtain approval and prepare dev

Before Git writes, request explicit approval through the host's question tool. One approval can cover the current issue's switch to `dev`, history-preserving sync, implementation commit, standard push to `origin/dev`, and evidence comment. State the exact issue and destination. Approval to work on `dev` is not blanket approval for future Git writes or Azure deployment.

If the user declines, do not perform the unapproved operations. Existing session opt-outs and stricter approval requirements still apply. Do not interpret the skill's existence as blanket permission to commit or push.

Check for existing implementation work or a PR for the same issue before starting. Do not duplicate, discard, delete, or merge it automatically. If work is already on a feature branch, obtain approval to integrate it into `dev` while preserving history.

After approval and with a clean worktree:

```bash
git fetch origin
git switch dev
git merge --ff-only origin/dev
```

If fast-forwarding fails because histories diverge, inspect the commits and obtain approval for `git merge origin/dev`; preserve both histories and rerun affected validation. Never rebase or reset away commits. If branch protection rejects direct publication, stop and ask rather than bypassing it or silently creating a PR.

Start from the latest fork `origin/dev`, not stale local `dev` or `upstream/dev`. Do not switch the developer's branch when using an approved separate worktree.

## 4. Implement one bounded issue

Map each acceptance criterion to implementation and validation work. Inspect existing code, contracts, helpers, and tests before adding logic.

- Make surgical changes that fully address this issue.
- Reuse repository-native PowerShell, Bicep, KQL, workbook, and build patterns.
- Add focused tests for behavior introduced or fixed.
- Update directly related docs, configuration, and call sites.
- Preserve type safety, approved scopes, and explicit error reporting.
- Preserve sample provenance, price coverage, evaluated answer quality, and cleanup boundaries.
- Never fabricate test results, resource readiness, telemetry, pricing, or savings.
- Implement sample work under `hack/sample-multi-agent-workload/` in this fork, with GitHub Actions workflows in the repository-root `.github/workflows/`. Preserve independent sample build and deployment entry points; a placeholder is not completion of the sample.

If a new design decision or blocker changes scope materially, ask before proceeding. Do not expand the issue to unrelated work.

## 5. Validate against the acceptance criteria

Read the documented validation commands and run the smallest set that covers the change. Typical entry points include:

```bash
pwsh -Command Invoke-Pester -Output Detailed -Path <relevant-test-paths>
pwsh -Command ./src/scripts/Test-PowerShell -Lint
bicep build <changed-template> --stdout
git diff --check
```

Select actual commands based on the changed component and existing CI; these examples are not a requirement to run every suite. Documentation-only changes need no build unless documentation checks exist.

Record each exact command and outcome. Fix failures caused by the change and rerun affected checks. Missing tools or packages are blockers, not passing tests; follow repository dependency-installation rules.

When acceptance requires a live deployment, obtain separate approval to use the sandbox. Publish and dispatch the approved workflow only when its branch/environment policy permits it, and verify its actual result. Do not bypass a `dev`-only deployment restriction or infer end-to-end success from the resource-group smoke test.

Do not present the implementation as complete when required evidence is missing. When a live check requires code on `dev`, obtain explicit approval to publish the locally validated revision with live validation pending. Record the blockers and leave the issue open. Publication is not acceptance, deployment approval, or permission to weaken environment protection.

## 6. Commit and push only the issue changes

Review the complete diff and staged content. Confirm every changed file belongs to the issue and that no credentials, unrelated files, generated release artifacts, or baseline branch changes are included.

Stage explicit file paths; never use `git add .`, `git add -A`, or `git commit -a`.

```bash
git add -- <issue-file-paths>
git diff --cached --check
git diff --cached
```

Commit only within the approved scope, using a conventional commit message with a `Refs bobjac/finops-toolkit#<N>` reference. Do not use automatic closing keywords while required validation or closure approval is pending. Include the repository/host's configured trailers, including Copilot attribution and the current session ID when required. Resolve the session ID from the active host instructions; never reuse the skill-authoring session's ID.

Verify the working branch is `dev`, then push normally to the fork:

```bash
git branch --show-current
git push origin dev
```

If remote `dev` has moved, fetch and obtain approval for `git merge origin/dev`, preserve both sides' valid changes, and rerun relevant validation. Never use rebase or force-push as a shortcut.

## 7. Verify publication and record delivery evidence

Verify the pushed revision is reachable from the fork's remote `dev`, not just that the push exited successfully:

```bash
git fetch origin
git merge-base --is-ancestor <implementation-commit> origin/dev
gh run list --repo bobjac/finops-toolkit --branch dev --commit <implementation-commit>
```

Inspect relevant workflow runs and report pending, failed, disabled, or absent CI honestly. Do not claim hosted validation from local tests or a successful push.

Add one concise issue comment linking the implementation commit and listing acceptance/validation evidence and known limitations. Do not claim dependent issues are unblocked before their prerequisites are delivered. Close the issue only after required evidence is verified and the user explicitly approves.

If the user explicitly requests a PR workflow instead, obtain approval for the feature branch and publication destination, inspect and preserve the repository's PR template, and target `bobjac/finops-toolkit:dev`. Do not create an empty PR from `dev` to itself or enable auto-merge.

## 8. Hand off

Return:

- Issue and implementation commit links.
- Working branch `dev` and explicit destination `bobjac/finops-toolkit:dev`.
- What changed and why.
- Exact validation commands/results, pending CI, and deployment/cleanup status when applicable.
- Any remaining blockers.

Stop after handoff. Do not merge, deploy further resources, start another issue, or open an upstream PR automatically.

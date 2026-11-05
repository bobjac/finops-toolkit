---
name: build-issue
description: Implement one issue in bobjac/finops-toolkit when the user says "build issue N", "implement issue N", or "build the next issue". Verify dependencies, create an issue feature branch from the fork's dev, implement and validate, then commit, push, and open a fork-local PR after explicit approval.
license: MIT
compatibility: Requires Git, authenticated GitHub CLI, repository-specific build tools, and permission for Git writes.
---

# Build an issue in the fork

Take one issue from the hack backlog to a validated feature branch and a pull request targeting `bobjac/finops-toolkit:dev`. Do not merge the PR or close the issue yourself.

This is the repository-specific issue workflow. Do not combine it with another issue skill that prohibits publishing or closes issues before merge.

## Fixed boundaries

- Issue repository and PR base repository: `bobjac/finops-toolkit`.
- Base branch and push remote: `dev` and `origin`.
- Branch pattern: `bobjac/issue-<number>-<short-slug>`.
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

Verify that `origin` points to `bobjac/finops-toolkit`, the PR base will be `dev`, and the selected item is an open implementation issue. Stop if the repository, branch configuration, or selected issue is inconsistent; do not silently retarget.

If there are staged, modified, or untracked files, stop before switching branches and use the host's question tool to agree how to preserve them. Do not automatically stash, discard, stage, commit, or carry unrelated work into the issue branch. An approved isolated worktree is an alternative, but it must have the required committed specifications.

## 2. Read the acceptance criteria and prerequisites

Read `hack/project-plan.md`, the matching issue section, and every relevant specification or linked requirement before editing code.

Inspect native dependencies:

```bash
gh api repos/bobjac/finops-toolkit/issues/<N>/dependencies/blocked_by
```

Check prerequisites stated in the issue body and plan as well. Every actual prerequisite must be satisfied; an API failure is not an empty dependency list. A prerequisite closed as not planned or without required delivery evidence needs clarification.

If a blocker is open, report its issue number and stop unless the user explicitly approves a dependency/scope change. Record an approved change in the issue and plan rather than silently implementing out of order.

If the specifications are only present as uncommitted files in another branch or worktree, stop and have them published to the agreed base first. Do not copy unrelated work into the new feature branch.

## 3. Obtain approval and create the feature branch

Before Git writes, request explicit approval through the host's question tool. One approval can cover the current issue's fetch/branch creation, implementation commit, standard push to `origin`, PR creation in the fork, and evidence comment. State the exact issue, base repository, base branch, and planned branch name.

If the user declines, do not perform the unapproved operations. Existing session opt-outs and stricter approval requirements still apply. Do not interpret the skill's existence as blanket permission to commit or push.

Choose a short lowercase slug containing only letters, digits, and hyphens. Check for an existing local branch, remote branch, or PR for the same issue before creating one. Do not overwrite an existing branch or create a duplicate PR; resume only after confirming its issue, base, ownership, and scope.

After approval and with a clean worktree:

```bash
git fetch origin
git switch -c bobjac/issue-<N>-<slug> origin/dev
```

Start from the latest fork `origin/dev`, not from the current hack branch, local stale `dev`, or `upstream/dev`. Do not switch the developer's branch when using an approved separate worktree.

## 4. Implement one bounded issue

Map each acceptance criterion to implementation and validation work. Inspect existing code, contracts, helpers, and tests before adding logic.

- Make surgical changes that fully address this issue.
- Reuse repository-native PowerShell, Bicep, KQL, workbook, and build patterns.
- Add focused tests for behavior introduced or fixed.
- Update directly related docs, configuration, and call sites.
- Preserve type safety, approved scopes, and explicit error reporting.
- Preserve sample provenance, price coverage, evaluated answer quality, and cleanup boundaries.
- Never fabricate test results, resource readiness, telemetry, pricing, or savings.
- For sample-repository work, agree its repository and delivery boundary first. A fork-local PR containing only a placeholder is not completion of an independently deployed sample.

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

Do not present the implementation as complete when required evidence is missing. If the user explicitly wants review of incomplete work, publish a clearly labeled draft PR with the blockers and remaining validation; otherwise stop at the blocker.

## 6. Commit and push only the issue changes

Review the complete diff and staged content. Confirm every changed file belongs to the issue and that no credentials, unrelated files, generated release artifacts, or baseline branch changes are included.

Stage explicit file paths; never use `git add .`, `git add -A`, or `git commit -a`.

```bash
git add -- <issue-file-paths>
git diff --cached --check
git diff --cached
```

Commit only within the approved scope, using a conventional commit message tied to the issue. Include the repository/host's configured trailers, including Copilot attribution and the current session ID when required. Resolve the session ID from the active host instructions; never reuse the skill-authoring session's ID.

Push the exact feature branch with a normal push:

```bash
git push --set-upstream origin bobjac/issue-<N>-<slug>
```

If the fork's base has moved and conflicts need resolution, obtain approval for `git merge origin/dev`, preserve both sides' valid changes, and rerun relevant validation. Never use rebase or force-push as a shortcut.

## 7. Open the PR explicitly against the fork's dev

Inspect the repository's current PR template before drafting:

- `.github/pull_request_template.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/PULL_REQUEST_TEMPLATE/`

Use the applicable template and preserve its headings, comments, checklist items, and order. Replace placeholders with accurate content. Mark screenshots as not applicable when appropriate without substituting a generic body. Check only tests actually run; include exact commands and results or explicit reasons they were not run.

Do not include Copilot co-author attribution or session trailers in the PR title or body. Any required `Co-authored-by` and `Copilot-Session` trailers belong only in Git commit messages; do not copy them into the PR description.

Use `Fixes bobjac/finops-toolkit#<N>` so merging into the fork's default `dev` closes the intended issue. Do not call `gh issue close` before merge.

Leave deployment checklist options unchecked unless the user has explicitly approved their associated workflows. A request to implement an issue is not approval for automatic Azure deployment.

Store the prepared PR body in an appropriate temporary/session artifact without credentials. Create the PR with explicit repository, base, and head:

```bash
gh pr create --repo bobjac/finops-toolkit \
  --base dev \
  --head bobjac/issue-<N>-<slug> \
  --title "<conventional, descriptive title>" \
  --body-file <prepared-body-path>
```

Use `--draft` only for explicitly approved incomplete work. Do not enable auto-merge.

Verify the created PR, not just the command's exit status:

```bash
gh pr view <PR> --repo bobjac/finops-toolkit \
  --json url,baseRefName,headRefName,headRepositoryOwner,isCrossRepository,isDraft,closingIssuesReferences
gh pr checks <PR> --repo bobjac/finops-toolkit
```

Confirm the URL is in `bobjac/finops-toolkit`, the base is `dev`, the head is the intended branch, and the closing reference is the selected issue. Report pending or failed CI honestly; do not claim all checks passed while they are still running.

## 8. Record delivery evidence and hand off

Add one concise issue comment linking the fork-local PR and listing acceptance/validation evidence and known limitations. Leave the issue open pending merge; do not mark the parent checklist complete or claim dependent issues are unblocked before their prerequisites are delivered.

Return:

- Issue and PR links.
- Feature branch and explicit destination `bobjac/finops-toolkit:dev`.
- What changed and why.
- Exact validation commands/results, pending CI, and deployment/cleanup status when applicable.
- Any remaining blockers.

Stop after handoff. Do not merge, deploy further resources, start another issue, or open an upstream PR automatically.

// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import { pathToFileURL } from 'node:url';

export function verifySource(run, revision, tip) {
  if (!/^[a-f0-9]{40}$/.test(revision) || tip !== revision ||
      run.conclusion !== 'success' || run.event !== 'push' ||
      run.head_branch !== 'dev' || run.head_sha !== revision ||
      run.head_repository?.full_name !== 'bobjac/finops-toolkit' ||
      run.path !== '.github/workflows/sample-workload-ci.yml') {
    throw new Error('Deployment requires successful trusted CI for the current dev revision.');
  }
}

export function verifyProtection(environment, approvals, requireApproval) {
  if (!environment.protection_rules?.some(rule =>
    rule.type === 'required_reviewers' && rule.reviewers?.length > 0)) {
    throw new Error('Sandbox required-reviewer protection is missing; deployment is blocked.');
  }
  if (requireApproval && !approvals.some(approval =>
    approval.state === 'approved' &&
    approval.environments?.some(item => item.name === 'sandbox'))) {
    throw new Error('This workflow has no recorded sandbox deployment approval.');
  }
}

export function verifyLifecycle(revision, tip, ref) {
  if (!/^[a-f0-9]{40}$/.test(revision ?? '') ||
      tip !== revision || ref !== 'refs/heads/dev') {
    throw new Error('Sample lifecycle requires the current fork dev revision.');
  }
}

async function main() {
  const repository = process.env.GITHUB_REPOSITORY;
  if (repository !== 'bobjac/finops-toolkit') {
    throw new Error('Deployment is restricted to the fork.');
  }
  const sourceRun = process.env.SOURCE_RUN_ID;
  const lifecycle = process.argv.includes('--lifecycle');
  if (!lifecycle && !/^\d+$/.test(sourceRun ?? '')) throw new Error('The source CI run is missing.');
  async function get(path) {
    const response = await fetch(`https://api.github.com/repos/${repository}/${path}`, {
      headers: {
        Authorization: `Bearer ${process.env.GH_TOKEN}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    });
    if (!response.ok) throw new Error(`GitHub deployment preflight failed (HTTP ${response.status}).`);
    return response.json();
  }
  const [branch, environment] = await Promise.all([
    get('branches/dev'), get('environments/sandbox'),
  ]);
  if (lifecycle) {
    verifyLifecycle(process.env.SOURCE_REVISION, branch.commit.sha, process.env.GITHUB_REF);
  } else {
    verifySource(await get(`actions/runs/${sourceRun}`),
      process.env.SOURCE_REVISION ?? '', branch.commit.sha);
  }
  const requireApproval = process.argv.includes('--require-approval');
  const approvals = requireApproval ? await get(`actions/runs/${process.env.GITHUB_RUN_ID}/approvals`) : [];
  verifyProtection(environment, approvals, requireApproval);
  console.log('Trusted revision and deployment protection verified.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}

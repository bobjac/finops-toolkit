// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import assert from 'node:assert/strict';
import test from 'node:test';
import { verifyLifecycle, verifyProtection, verifySource } from '../eng/check-deployment.mjs';

const revision = 'a'.repeat(40);
const trusted = {
  conclusion: 'success', event: 'push', head_branch: 'dev', head_sha: revision,
  head_repository: { full_name: 'bobjac/finops-toolkit' },
  path: '.github/workflows/sample-workload-ci.yml',
};
test('only successful current fork dev push CI is eligible', () => {
  verifySource(trusted, revision, revision);
  assert.throws(() => verifySource(trusted, revision, 'b'.repeat(40)));
  for (const invalid of [
    { event: 'pull_request' }, { conclusion: 'failure' }, { head_branch: 'feature' },
    { head_repository: { full_name: 'other/fork' } }, { path: 'other.yml' },
  ]) assert.throws(() => verifySource({ ...trusted, ...invalid }, revision, revision));
});
test('missing protection or actual run approval fails closed', () => {
  const environment = { protection_rules: [{ type: 'required_reviewers', reviewers: [{}] }] };
  assert.throws(() => verifyProtection({ protection_rules: [] }, [], false));
  assert.throws(() => verifyProtection(environment, [], true));
  assert.throws(() => verifyProtection(environment, [
    { state: 'approved', environments: [{ name: 'other' }] },
  ], true));
  verifyProtection(environment, [
    { state: 'approved', environments: [{ name: 'sandbox' }] },
  ], true);
});
test('manual cleanup requires the current dev revision without a CI dependency', () => {
  verifyLifecycle(revision, revision, 'refs/heads/dev');
  assert.throws(() => verifyLifecycle(revision, 'b'.repeat(40), 'refs/heads/dev'));
  assert.throws(() => verifyLifecycle(revision, revision, 'refs/heads/feature'));
  assert.throws(() => verifyLifecycle(undefined, undefined, 'refs/heads/dev'));
});

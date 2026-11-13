// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import assert from 'node:assert/strict';
import test from 'node:test';
import { verifyPredecessor } from '../check-predecessor.mjs';

function run(role = 'seed', orchestrated = false) {
  return {
    id: 123, run_attempt: 2, status: 'completed', conclusion: 'success',
    head_branch: 'dev', head_sha: 'a'.repeat(40),
    head_repository: { full_name: 'bobjac/finops-toolkit' },
    path: orchestrated ? '.github/workflows/sandbox-deploy.yml'
      : `.github/workflows/${role === 'seed' ? 'sandbox-seed' : 'sample-workload-cd'}.yml`,
    event: orchestrated || role === 'seed' ? 'workflow_dispatch' : 'workflow_run',
  };
}

test('preserves standalone artifacts and resolves attempt-specific complete deployment evidence', () => {
  assert.equal(verifyPredecessor('seed', run()), 'sandbox-seed-123');
  assert.equal(verifyPredecessor('seed', run('seed', true)), 'sandbox-seed-123-2');
  assert.equal(verifyPredecessor('sample', run('sample')), 'sample-validation-123-2');
  assert.equal(verifyPredecessor('sample', run('sample', true)), 'sample-validation-123-2');
});

test('rejects failed, partial, foreign, wrong-role, and untrusted producers', () => {
  for (const change of [
    { conclusion: 'failure' }, { status: 'in_progress' }, { head_branch: 'feature' },
    { head_repository: { full_name: 'another/repository' } }, { path: '.github/workflows/sandbox-cleanup.yml' },
    { path: '.github/workflows/sample-workload-cd.yml' }, { head_sha: 'bad' },
    { id: '../123' }, { run_attempt: 0 }, { event: 'pull_request' },
  ]) {
    assert.throws(() => verifyPredecessor('seed', { ...run(), ...change }));
  }
});

test('requires successful replacement and exact seed provenance', () => {
  const checkpoint = {
    RunId: '123', SourceRevision: 'a'.repeat(40), Status: 'VerifiedAndRetained',
    ReadyForSeededHistory: true, BaselineMatch: true,
  };
  assert.equal(verifyPredecessor('seed', run('seed', true), checkpoint), 'sandbox-seed-123-2');
  for (const change of [{ RunId: 'other' }, { SourceRevision: 'b'.repeat(40) }, { BaselineMatch: false }]) {
    assert.throws(() => verifyPredecessor('seed', run('seed', true), { ...checkpoint, ...change }));
  }
});

test('allows earlier successful stage attempts only inside a verified complete deployment run', () => {
  const checkpoint = {
    runId: '123', runAttempt: '1', revision: 'a'.repeat(40),
    status: 'Completed', stage: 'Validation', liveVerified: true,
  };
  assert.equal(verifyPredecessor('sample', run('sample', true), checkpoint), 'sample-validation-123-2');
  assert.throws(() => verifyPredecessor('sample', run('sample'), checkpoint));
  for (const change of [
    { liveVerified: false }, { runAttempt: '3' }, { runAttempt: '' },
    { revision: 'b'.repeat(40) }, { runId: '124' },
  ]) {
    assert.throws(() => verifyPredecessor('sample', run('sample', true), { ...checkpoint, ...change }));
  }
});

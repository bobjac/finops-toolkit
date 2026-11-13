// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function verifyPredecessor(role, run, checkpoint) {
  const orchestration = run.path === '.github/workflows/sandbox-deploy.yml';
  const standalone = {
    seed: '.github/workflows/sandbox-seed.yml',
    sample: '.github/workflows/sample-workload-cd.yml',
  };
  if (!Object.hasOwn(standalone, role) || run.status !== 'completed' ||
      run.conclusion !== 'success' || run.head_branch !== 'dev' ||
      run.head_repository?.full_name !== 'bobjac/finops-toolkit' ||
      !/^[a-f0-9]{40}$/.test(run.head_sha ?? '') ||
      !/^[0-9]{1,12}$/.test(String(run.id)) || !/^[1-9][0-9]*$/.test(String(run.run_attempt)) ||
      (!orchestration && run.path !== standalone[role]) ||
      run.event !== (orchestration || role === 'seed' ? 'workflow_dispatch' : 'workflow_run')) {
    throw new Error('Predecessor must be a successful trusted fork dev producer for this role.');
  }
  if (checkpoint !== undefined) {
    if (role === 'seed') {
      if (checkpoint.RunId !== String(run.id) || checkpoint.SourceRevision !== run.head_sha ||
          checkpoint.Status !== 'VerifiedAndRetained' || checkpoint.ReadyForSeededHistory !== true ||
          checkpoint.BaselineMatch !== true) {
        throw new Error('Seed checkpoint must verify replacement in the exact producer run.');
      }
    } else {
      const attempt = String(checkpoint.runAttempt);
      if (checkpoint.runId !== String(run.id) || checkpoint.revision !== run.head_sha ||
          checkpoint.status !== 'Completed' || checkpoint.stage !== 'Validation' || checkpoint.liveVerified !== true ||
          !/^[1-9][0-9]*$/.test(attempt) || Number(attempt) > run.run_attempt ||
          (!orchestration && Number(attempt) !== run.run_attempt)) {
        throw new Error('Sample checkpoint must verify live behavior in the exact producer run and a valid attempt.');
      }
    }
  }
  return role === 'seed'
    ? `sandbox-seed-${run.id}${orchestration ? `-${run.run_attempt}` : ''}`
    : `sample-validation-${run.id}-${run.run_attempt}`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [role, runFile, checkpointFile] = process.argv.slice(2);
    const run = JSON.parse(readFileSync(runFile, 'utf8'));
    const checkpoint = checkpointFile ? JSON.parse(readFileSync(checkpointFile, 'utf8')) : undefined;
    console.log(verifyPredecessor(role, run, checkpoint));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

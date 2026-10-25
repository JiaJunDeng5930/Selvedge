import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access, lstat, open, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { boundary } from './public/model-boundary.mjs';
import { naturalKey } from './codec.mjs';
import { readControlRecord, writeControlRecord as saveReceipt, durableDirectory } from './control-records.mjs';
import { createManagedWorktree, archiveManagedWorktree, reconcileManagedWorktree } from './worktrees.mjs';
import { cloudEnvironmentBackend, cloudExecutionEnvironment, shellQuote } from './cloud-environments.mjs';

const execute = promisify(execFile);
const receiptFormat = 'selvedge-cloud-workspace-2';

async function git(primary, arguments_, { signal } = {}) {
  // DEFENSE: A host GIT_DIR/GIT_WORK_TREE selector must not redirect the project's observed repository.
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const result = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
    '-C', primary, ...arguments_], { signal, env, timeout: 30_000, maxBuffer: 1024 * 1024 });
  return result.stdout.trim();
}

/** Observe a GitHub source without copying local files, credentials or Git configuration. */
export async function observeCloudRepository(primary, { signal } = {}) {
  try {
    const repository = await realpath(await git(primary, ['rev-parse', '--show-toplevel'], { signal }));
    const observedNames = (await git(repository, ['remote'], { signal })).split('\n').filter(Boolean).sort((a, b) => a.localeCompare(b));
    const names = boundary('effect.cloud_remote_names', { names: observedNames });
    for (const name of names) {
      const remote = await git(repository, ['remote', 'get-url', name], { signal });
      const url = boundary('effect.cloud_repository', { remote });
      if (url === null) continue;
      const commit = await git(repository, ['rev-parse', '--verify', 'HEAD^{commit}'], { signal });
      return { url, commit, repository,
        relative_primary: path.relative(repository, await realpath(primary)) };
    }
    return null;
  } catch (error) {
    signal?.throwIfAborted();
    // DEFENSE: Selected project roots can disappear or have no committed Git repository.
    if (error.code === 128 || ['ENOENT', 'ENOTDIR'].includes(error.code)) return null;
    throw error;
  }
}

function tokenFor(namespace, taskId) {
  return createHash('sha256').update(`selvedge-cloud\0${namespace}\0${naturalKey(taskId)}`).digest('hex');
}

async function locations({ home, namespace }, taskId) {
  const identity = naturalKey(taskId);
  const canonicalHome = await realpath(home);
  const storage = path.join(canonicalHome, 'cloud-workspaces', namespace);
  for (const directory of [path.dirname(storage), storage]) {
    await durableDirectory(directory);
    // DEFENSE: Replaced service storage must not redirect cloud receipts, logs or SSH host-key writes through a symlink.
    if ((await lstat(directory)).isSymbolicLink() || await realpath(directory) !== directory) {
      throw new Error('Cloud workspace storage must not contain symbolic links');
    }
  }
  return { receipt: path.join(storage, `task-${identity}.json`), log: path.join(storage, `task-${identity}.log`),
    knownHosts: path.join(storage, `task-${identity}.known_hosts`), token: tokenFor(namespace, taskId),
    root: `/workspace/selvedge/${identity}/repository`, namespace };
}

async function readReceipt(files, entry) {
  const receipt = await readControlRecord(files.receipt, { maximumBytes: 1024 * 1024, label: 'cloud workspace receipt' });
  boundary('effect.cloud_receipt', { value: receipt, bound_root: entry.root ?? null, expected: { format: receiptFormat, namespace: files.namespace,
    task_id: entry.task_id, source_root: entry.source_root, root: files.root, token: files.token, backend: entry.backend } });
  return receipt;
}

async function log(files, message) {
  const file = await open(files.log, constants.O_WRONLY | constants.O_APPEND | constants.O_CREAT | constants.O_NOFOLLOW, 0o600);
  try { await file.writeFile(`${new Date().toISOString()} ${message}\n`); await file.sync(); }
  finally { await file.close(); }
}

const completion = (effect, result) => boundary('effect.completion', { effect, result });

function failed(effect, error, root, files) {
  return completion(effect, { ok: false, root,
    message: `Cloud workspace startup${effect.kind === 'worktree_archive' ? '/recycle' : ''} failed: ${String(error.message).toWellFormed()}` +
      (files ? `; log: ${files.log}` : '') });
}

async function recordCleanupOperation(errors, description, operation) {
  try { await operation(); }
  // DEFENSE: ENOSPC or changed service-directory permissions can break recording after allocation; reclamation must still run.
  catch (error) { errors.push(`${description}: ${error.message}`); }
}

const resource = (operation, source) => boundary(`control.resource.${operation}`, source);

/** Interpret only physical operations; the extracted resource step chooses their order and outcome. */
async function runResource(plan, { files, backend, signal, prepare, errors = [] }) {
  let cleanupSignal;
  while (true) {
    const state = plan.state;
    let observation;
    switch (plan.effects[0]) {
      case 'finish': return { receipt: state, errors };
      case 'persist':
        try {
          const { guidance, recording_failed, ...durable } = state;
          await saveReceipt(files.receipt, durable);
          observation = { kind: 'persisted' };
        } catch (error) {
          // DEFENSE: Disk exhaustion after allocation must not prevent exact-ID reclamation.
          errors.push(`Could not persist cloud resource: ${error.message}`);
          observation = { kind: 'persistence_failed' };
        }
        break;
      case 'allocate':
        try { observation = { kind: 'allocated', ...await backend.create(state.request, { signal }) }; }
        catch (error) {
          errors.push(`Allocation outcome unknown: ${error.message}`);
          observation = { kind: 'allocation_failed' };
        }
        break;
      case 'prepare':
        try { observation = { kind: 'prepared', ...await prepare(state) }; }
        catch (error) {
          errors.push(`Cloud preparation failed: ${error.message}`);
          observation = { kind: 'preparation_failed' };
        }
        break;
      case 'credentials':
        cleanupSignal = AbortSignal.timeout(120_000);
        try {
          backend = recoveredBackend(state);
          observation = { kind: 'credentials', scope: await backend.scope({ signal: cleanupSignal }) };
        }
        catch (error) {
          errors.push(`Cloud recovery needs credentials: ${error.message}`);
          observation = { kind: 'credentials_failed' };
        }
        break;
      case 'scan':
        try { observation = { kind: 'scan_page', ...await backend.scan(state.token, state.scan_offset, { signal: cleanupSignal }) }; }
        catch (error) {
          errors.push(`Cloud allocation reconciliation incomplete: ${error.message}`);
          observation = { kind: 'scan_failed' };
        }
        break;
      case 'terminate': {
        const id = state.instance_ids[0];
        try {
          await backend.destroy(id, { signal: cleanupSignal });
          observation = { kind: 'terminated', id };
        } catch (error) {
          errors.push(`Cloud destruction failed (${id}): ${error.message}`);
          observation = { kind: 'termination_failed', id };
        }
        break;
      }
      default: throw new Error(`Unknown resource primitive: ${plan.effects[0]}`);
    }
    plan = resource('step', { state, observation });
  }
}

function recoveredBackend(receipt) {
  return cloudEnvironmentBackend({ backend: receipt.backend, [receipt.backend]: receipt.settings });
}

async function destroyReceipt(receipt, files, errors = []) {
  const result = await runResource(resource('recover', receipt), { files, errors });
  if (result.receipt.status !== 'destroyed') {
    result.errors.push(`Cloud resource retained for ${result.receipt.status}; no allocation request was repeated`);
  }
  if (result.receipt.recording_failed && !result.errors.length) result.errors.push('Cloud cleanup completion was not durably recorded');
  return result;
}

async function reportFailure(effect, result, files, message) {
  const failures = [...(message ? [message] : []), ...result.errors];
  if (result.receipt.status !== 'destroyed' && result.receipt.status !== 'no_attempt') {
    failures.push(`Cloud resource retained for ${result.receipt.status}`);
  }
  await recordCleanupOperation(failures, 'Could not write failure log', () => log(files, failures.join('; ')));
  const retained = result.receipt.status === 'no_attempt' ||
    (result.receipt.status === 'destroyed' && !result.receipt.recording_failed) ? null : result.receipt.root;
  return failed(effect, new Error(failures.join('; ')), retained, files);
}

function cloudWorkspace(effect, source, root) {
  return boundary('effect.cloud_workspace', { workspace: effect.workspace, repository: source.repository, root });
}

function initializationScript(source, root) {
  const token = Boolean(process.env.GITHUB_TOKEN);
  const askpass = `#!/bin/sh\ncase "$1" in *Username*) printf '%s\\n' x-access-token;; *) printf '%s\\n' "$SELVEDGE_CLONE_TOKEN";; esac\n`;
  return `set -eu\n` +
    (token ? `IFS= read -r SELVEDGE_CLONE_TOKEN\nexport SELVEDGE_CLONE_TOKEN\n` +
      `credential_dir=$(mktemp -d)\ntrap 'rm -rf -- "$credential_dir"' EXIT\nprintf '%s' ${shellQuote(askpass)} > "$credential_dir/askpass"\nchmod 700 "$credential_dir/askpass"\n` : '') +
    `mkdir -p -- ${shellQuote(path.posix.dirname(root))}\n` +
    `${token ? 'GIT_ASKPASS="$credential_dir/askpass" ' : ''}GIT_TERMINAL_PROMPT=0 git clone --no-checkout -- ${shellQuote(source.url)} ${shellQuote(root)}\n` +
    `cd ${shellQuote(root)}\ngit checkout --detach ${shellQuote(source.commit)}\n` +
    (token ? `unset SELVEDGE_CLONE_TOKEN\nrm -rf -- "$credential_dir"\ntrap - EXIT\n` : '') +
    `test -f .selvedge/env.sh\nbash .selvedge/env.sh\ncommand -v python3 >/dev/null\n`;
}

export async function createTaskWorkspace(effect, options = {}) {
  if (effect.backend === 'local') return createManagedWorktree(effect, options);
  let files, environment;
  try {
    files = await locations(options, effect.task_id);
    const backend = cloudEnvironmentBackend(options.cloud);
    const settings = backend.settings;
    await access(settings.ssh_private_key, constants.R_OK);
    const source = await observeCloudRepository(effect.source_root, options);
    if (!source) throw new Error('Cloud workspace requires a GitHub remote on the project primary workspace');
    const workspace = cloudWorkspace(effect, source, files.root);
    const scope = await backend.scope({ signal: options.signal });
    const receipt = { format: receiptFormat, namespace: options.namespace, task_id: effect.task_id, backend: effect.backend,
      source_root: effect.source_root, root: files.root, workspace, token: files.token, settings, scope,
      request: backend.request(files.token, effect.task_id) };
    await log(files, `Requesting cloud environment (${effect.backend})`);
    const result = await runResource(resource('start', receipt), {
      files, backend, signal: options.signal,
      async prepare(state) {
        const deadline = Date.now() + (settings.startup_timeout_ms ?? 600_000);
        const connection = await backend.ready(state.instance_id, { signal: options.signal, deadline });
        environment = cloudExecutionEnvironment({ ...state, ...connection }, { ...files, signal: options.signal });
        await environment.ready({ signal: options.signal, deadline });
        await log(files, 'Cloning GitHub repository and running .selvedge/env.sh');
        const setup = await environment.execute(`bash -c ${shellQuote(initializationScript(source, files.root))}`, {
          cwd: '/', signal: options.signal, timeout: Math.max(1, deadline - Date.now()),
          input: process.env.GITHUB_TOKEN ? `${process.env.GITHUB_TOKEN}\n` : undefined,
        });
        await log(files, setup.stdout + setup.stderr);
        if (setup.exit_code !== 0) throw new Error(`Project environment initialization exited with code ${setup.exit_code}`);
        return { host: connection.host, guidance: await environment.snapshotProject(options.limits, { signal: options.signal }) };
      },
    });
    if (result.receipt.status !== 'ready' || result.errors.length) return reportFailure(effect, result, files);
    await recordCleanupOperation([], 'Could not write readiness log', () => log(files, 'Cloud workspace ready'));
    return completion(effect, { ok: true, root: files.root, workspace, guidance: result.receipt.guidance });
  } catch (error) {
    return failed(effect, error, null, files);
  } finally { environment?.filesystem.close(); }
}

/** Roll back a physical checkout whose successful completion could not be committed. */
export async function rollbackTaskWorkspaceCreation(effect, options = {}) {
  let files, receipt;
  try {
    files = await locations(options, effect.task_id);
    receipt = await readReceipt(files, effect);
  } catch (error) {
    const failures = [options.message, `Could not recover cloud allocation for rollback: ${error.message}`];
    if (files) await recordCleanupOperation(failures, 'Could not write rollback failure log', () => log(files, failures.join('; ')));
    return failed(effect, new Error(failures.join('; ')), files?.root ?? null, files);
  }
  const result = await destroyReceipt(receipt, files);
  return reportFailure(effect, result, files, options.message);
}

export async function archiveTaskWorkspace(effect, options = {}) {
  if (effect.backend === 'local') return archiveManagedWorktree(effect, options);
  let files;
  try {
    files = await locations(options, effect.task_id);
    const receipt = await readReceipt(files, effect);
    const result = await destroyReceipt(receipt, files);
    if (result.errors.length) return reportFailure(effect, result, files);
    return completion(effect, { ok: true, root: effect.root });
  } catch (error) {
    const failures = [error.message];
    if (files) await recordCleanupOperation(failures, 'Could not write recycle failure log', () => log(files, `Recycle failed: ${error.message}`));
    return failed(effect, new Error(failures.join('; ')), effect.root, files);
  }
}

export async function reconcileTaskWorkspace(entry, options = {}) {
  if (entry.backend === 'local') return reconcileManagedWorktree(entry, options);
  const effect = { kind: entry.status === 'archiving' ? 'worktree_archive' : 'worktree_create', ...entry };
  let files, receipt, environment;
  try {
    files = await locations(options, entry.task_id);
    try { receipt = await readReceipt(files, entry); }
    catch (error) {
      // DEFENSE: A service can stop before persisting a request; no receipt means no allocation was attempted.
      if (error.code === 'ENOENT' && effect.kind === 'worktree_create') {
        return failed(effect, new Error('Cloud workspace preparation interrupted before allocation'), null, files);
      }
      throw error;
    }
    if (effect.kind === 'worktree_create' && entry.status !== 'creating_archived' && receipt.status === 'ready') {
      const result = await runResource(resource('step', { state: receipt, observation: { kind: 'resume' } }), {
        files,
        async prepare(state) {
          environment = cloudExecutionEnvironment(state, files);
          return { host: state.host, guidance: await environment.snapshotProject(options.limits) };
        },
      });
      if (result.receipt.status === 'ready' && !result.errors.length) {
        return completion(effect, { ok: true, root: receipt.root, workspace: receipt.workspace, guidance: result.receipt.guidance });
      }
      return reportFailure(effect, result, files);
    }
    const result = await destroyReceipt(receipt, files);
    if (result.errors.length) return reportFailure(effect, result, files);
    if (effect.kind === 'worktree_archive') return completion(effect, { ok: true, root: receipt.root });
    return reportFailure(effect, result, files, 'Cloud workspace preparation interrupted; environment destroyed');
  } catch (error) {
    const failures = [error.message];
    if (files) await recordCleanupOperation(failures, 'Could not write recovery failure log', () => log(files, `Recovery failed: ${error.message}`));
    return failed(effect, new Error(failures.join('; ')), receipt?.root ?? entry.root ?? files?.root ?? null, files);
  } finally { environment?.filesystem.close(); }
}

/** Resolve a committed association; local paths must never masquerade as a cloud binding. */
export async function taskWorkspaceEnvironment(entry, options = {}) {
  if (entry.backend === 'local') return undefined;
  const files = await locations(options, entry.task_id);
  const receipt = await readReceipt(files, entry);
  if (receipt.status !== 'ready' || !receipt.host || !receipt.instance_id) throw new Error('Cloud workspace is not ready');
  return cloudExecutionEnvironment(receipt, { ...files, signal: options.signal });
}

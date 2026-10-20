import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access, lstat, mkdir, open, realpath, rename, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';
import { boundary } from './public/model-boundary.mjs';
import { createManagedWorktree, archiveManagedWorktree, reconcileManagedWorktree } from './worktrees.mjs';
import { cloudEnvironmentBackend, cloudExecutionEnvironment, shellQuote } from './cloud-environments.mjs';

const execute = promisify(execFile);
const receiptFormat = 'selvedge-cloud-workspace-1';

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
    const names = (await git(repository, ['remote'], { signal })).split('\n').filter(Boolean);
    names.sort((a, b) => a === 'origin' ? -1 : b === 'origin' ? 1 : a.localeCompare(b));
    for (const name of names) {
      const remote = await git(repository, ['remote', 'get-url', name], { signal });
      const match = /^(?:https:\/\/github\.com\/|git@github\.com:|ssh:\/\/git@github\.com\/)([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?\/?$/.exec(remote);
      if (!match) continue;
      const commit = await git(repository, ['rev-parse', '--verify', 'HEAD^{commit}'], { signal });
      return { url: `https://github.com/${match[1]}/${match[2]}.git`, commit, repository,
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
  return createHash('sha256').update(`selvedge-cloud\0${namespace}\0${taskId}`).digest('hex');
}

async function locations({ home, namespace }, taskId) {
  if (!/^[0-9a-f]{32}$/.test(namespace) || !Number.isSafeInteger(taskId) || taskId < 0) {
    throw new Error('Cloud workspace requires a journal namespace and task identity');
  }
  const canonicalHome = await realpath(home);
  const storage = path.join(canonicalHome, 'cloud-workspaces', namespace);
  for (const directory of [path.dirname(storage), storage]) {
    await mkdir(directory, { recursive: true, mode: 0o700 });
    // DEFENSE: Replaced service storage must not redirect cloud receipts, logs or SSH host-key writes through a symlink.
    if ((await lstat(directory)).isSymbolicLink() || await realpath(directory) !== directory) {
      throw new Error('Cloud workspace storage must not contain symbolic links');
    }
  }
  return { receipt: path.join(storage, `task-${taskId}.json`), log: path.join(storage, `task-${taskId}.log`),
    knownHosts: path.join(storage, `task-${taskId}.known_hosts`), token: tokenFor(namespace, taskId),
    root: `/workspace/selvedge/${taskId}/repository`, namespace };
}

async function saveReceipt(filename, receipt) {
  const temporary = `${filename}.${randomUUID()}.tmp`;
  const file = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try { await file.writeFile(JSON.stringify(receipt)); await file.sync(); }
  finally { await file.close(); }
  try { await rename(temporary, filename); }
  finally { await rm(temporary, { force: true }); }
}

async function readReceipt(files, entry) {
  const file = await open(files.receipt, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  let receipt;
  try {
    const facts = await file.stat();
    // DEFENSE: Externally replaced receipt paths can be special files or exceed the bounded control record.
    if (!facts.isFile() || facts.size > 1024 * 1024) throw new Error('Invalid cloud workspace receipt');
    receipt = JSON.parse(await file.readFile('utf8'));
  } finally { await file.close(); }
  if (receipt.format !== receiptFormat || receipt.namespace !== files.namespace || receipt.task_id !== entry.task_id ||
      receipt.source_root !== entry.source_root || receipt.root !== files.root || receipt.token !== files.token ||
      receipt.backend !== entry.backend) {
    throw new Error('Cloud workspace receipt does not match its task');
  }
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

async function destroyReceipt(receipt, files) {
  const backend = cloudEnvironmentBackend({ backend: receipt.backend, [receipt.backend]: receipt.settings });
  const signal = AbortSignal.timeout(120_000);
  const recordingErrors = [];
  // DEFENSE: Allocation can commit while its response or the service is lost; its persisted request recovers the same environment.
  if (!receipt.instance_id && receipt.allocation_unknown) {
    receipt.instance_id = await backend.create(receipt.request, { signal });
    await recordCleanupOperation(recordingErrors, 'Could not record recovered instance', () => saveReceipt(files.receipt, receipt));
  }
  try { if (receipt.instance_id) await backend.destroy(receipt.instance_id, { signal }); }
  catch (error) { throw new Error([error.message, ...recordingErrors].join('; ')); }
  receipt.status = 'destroyed'; receipt.allocation_unknown = false;
  await recordCleanupOperation(recordingErrors, 'Could not record destroyed environment', () => saveReceipt(files.receipt, receipt));
  await recordCleanupOperation(recordingErrors, 'Could not write destruction log', () => log(files, 'Cloud environment destroyed'));
  return recordingErrors;
}

async function failCloudCreation(effect, error, { files, receipt, allocationAttempted }) {
  let retained = null;
  const failures = [error.message];
  if (files) await recordCleanupOperation(failures, 'Could not write startup failure log', () => log(files, `Startup failed: ${error.message}`));
  // DEFENSE: Allocation or setup can fail after creating a billable instance; cleanup is independent of the cancelled startup signal.
  if (allocationAttempted) {
    try { failures.push(...await destroyReceipt(receipt, files)); }
    catch (cleanupError) {
      retained = receipt.root;
      failures.push(`Cloud destruction failed: ${cleanupError.message}`);
      receipt.status = 'destroy_failed';
      await recordCleanupOperation(failures, 'Could not record destruction failure', () => saveReceipt(files.receipt, receipt));
      await recordCleanupOperation(failures, 'Could not write destruction failure log', () => log(files, `Destruction failed: ${cleanupError.message}`));
    }
  }
  return failed(effect, new Error(failures.join('; ')), retained, files);
}

function cloudWorkspace(effect, source, root) {
  const roots = effect.workspace.roots.map(directory => {
    const relative = path.relative(source.repository, directory);
    if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      throw new Error('Cloud workspace roots must belong to the project GitHub repository');
    }
    return path.posix.join(root, ...relative.split(path.sep));
  });
  return { roots, primary_root: path.posix.join(root, ...source.relative_primary.split(path.sep)) };
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
  let files, receipt, environment, allocationAttempted = false;
  try {
    files = await locations(options, effect.task_id);
    const backend = cloudEnvironmentBackend(options.cloud);
    const settings = backend.settings;
    await access(settings.ssh_private_key, constants.R_OK);
    const source = await observeCloudRepository(effect.source_root, options);
    if (!source) throw new Error('Cloud workspace requires a GitHub remote on the project primary workspace');
    const workspace = cloudWorkspace(effect, source, files.root);
    receipt = { format: receiptFormat, namespace: options.namespace, task_id: effect.task_id, backend: effect.backend,
      source_root: effect.source_root, root: files.root, workspace, token: files.token, settings,
      request: backend.request(files.token, effect.task_id), status: 'requested', allocation_unknown: true };
    await log(files, `Requesting cloud environment (${effect.backend})`);
    // Persist authority to recover an allocation before the first billable API call.
    await saveReceipt(files.receipt, receipt);
    allocationAttempted = true;
    try { receipt.instance_id = await backend.create(receipt.request, { signal: options.signal }); }
    catch (error) {
      // DEFENSE: The backend can establish a rejected allocation; transport failure leaves its outcome unknown.
      if (error.allocationRejected) { receipt.allocation_unknown = false; await saveReceipt(files.receipt, receipt); }
      throw error;
    }
    receipt.status = 'allocated'; await saveReceipt(files.receipt, receipt);
    const deadline = Date.now() + (settings.startup_timeout_ms ?? 600_000);
    Object.assign(receipt, await backend.ready(receipt.instance_id, { signal: options.signal, deadline }));
    await saveReceipt(files.receipt, receipt);
    environment = cloudExecutionEnvironment(receipt, { ...files, signal: options.signal });
    await environment.ready({ signal: options.signal, deadline });
    await log(files, 'Cloning GitHub repository and running .selvedge/env.sh');
    const result = await environment.execute(`bash -c ${shellQuote(initializationScript(source, files.root))}`, {
      signal: options.signal, timeout: Math.max(1, deadline - Date.now()),
      input: process.env.GITHUB_TOKEN ? `${process.env.GITHUB_TOKEN}\n` : undefined,
    });
    await log(files, result.stdout + result.stderr);
    if (result.exit_code !== 0) throw new Error(`Project environment initialization exited with code ${result.exit_code}`);
    const guidance = await environment.snapshotProject(options.limits, { signal: options.signal });
    receipt.status = 'ready'; await saveReceipt(files.receipt, receipt);
    await log(files, 'Cloud workspace ready');
    return completion(effect, { ok: true, root: files.root, workspace, guidance });
  } catch (error) {
    return failCloudCreation(effect, error, { files, receipt, allocationAttempted });
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
  return failCloudCreation(effect, new Error(options.message), { files, receipt, allocationAttempted: true });
}

export async function archiveTaskWorkspace(effect, options = {}) {
  if (effect.backend === 'local') return archiveManagedWorktree(effect, options);
  let files;
  try {
    files = await locations(options, effect.task_id);
    const receipt = await readReceipt(files, effect);
    if (effect.root !== receipt.root) throw new Error('Cloud workspace recycle root does not match its task');
    const recordingErrors = await destroyReceipt(receipt, files);
    if (recordingErrors.length) throw new Error(`Cloud environment was destroyed; ${recordingErrors.join('; ')}`);
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
      environment = cloudExecutionEnvironment(receipt, files);
      const guidance = await environment.snapshotProject(options.limits);
      return completion(effect, { ok: true, root: receipt.root, workspace: receipt.workspace, guidance });
    }
    const recordingErrors = await destroyReceipt(receipt, files);
    if (recordingErrors.length) {
      return failed(effect, new Error(`Cloud environment was destroyed; ${recordingErrors.join('; ')}`), null, files);
    }
    if (effect.kind === 'worktree_archive') return completion(effect, { ok: true, root: receipt.root });
    return failed(effect, new Error('Cloud workspace preparation interrupted; environment destroyed'), null, files);
  } catch (error) {
    const failures = [error.message];
    if (files) await recordCleanupOperation(failures, 'Could not write recovery failure log', () => log(files, `Recovery failed: ${error.message}`));
    return failed(effect, new Error(failures.join('; ')), receipt?.root ?? entry.root ?? null, files);
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

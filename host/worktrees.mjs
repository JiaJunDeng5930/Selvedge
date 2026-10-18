import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { cp, lstat, mkdir, open, readFile, realpath, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { canonicalWorkspace } from './sandbox.mjs';
import { snapshotProject } from './project.mjs';
import { boundary } from './public/model-boundary.mjs';

const execute = promisify(execFile);
const maximumGitOutput = 64 * 1024 * 1024;
// NOTE: Allow all 32 bounded Workspace roots and their JSON escaping to round-trip.
const maximumReceiptBytes = 1024 * 1024;

async function git(cwd, arguments_, { signal, encoding = 'utf8' } = {}) {
  // NOTE: Do not let process-level Git selectors redirect an observed repository.
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
    '-C', cwd, ...arguments_], { env, signal, encoding, maxBuffer: maximumGitOutput, timeout: 120_000 });
  return stdout;
}

async function worktreeGitConfiguration(repository, signal) {
  let names;
  try { names = await git(repository, ['config', '--null', '--name-only', '--get-regexp', '^filter\\..*\\.(clean|smudge|process|required)$'], { signal }); }
  catch (error) { if (error.code === 1) return ['-c', 'submodule.recurse=false']; throw error; }
  // NOTE: Checkout and diff must not execute project filter programs outside the task sandbox.
  const drivers = new Set(names.split('\0').filter(Boolean).map(name => name.slice(0, name.lastIndexOf('.'))));
  return ['-c', 'submodule.recurse=false', ...[...drivers].flatMap(driver =>
    ['-c', `${driver}.clean=`, '-c', `${driver}.smudge=`, '-c', `${driver}.process=`, '-c', `${driver}.required=false`])];
}

/** Observe the primary directory, including primaries below a repository root. */
export async function observeWorkspaceGit(primary, { signal } = {}) {
  signal?.throwIfAborted();
  try {
    boundary('effect.root_admit', { root: primary, absolute: typeof primary === 'string' && path.isAbsolute(primary) });
    const root = await realpath(primary);
    if ((await git(root, ['rev-parse', '--is-inside-work-tree'], { signal })).trim() !== 'true') return false;
    await git(root, ['rev-parse', '--verify', 'HEAD^{commit}'], { signal });
    return true;
  } catch (error) {
    signal?.throwIfAborted();
    if (error instanceof TypeError || ['ENOENT', 'ENOTDIR'].includes(error.code) || typeof error.code === 'number') return false;
    throw error;
  }
}

async function locations(home, taskId) {
  const files = boundary('effect.worktree_locations', { home: await realpath(home), task_id: taskId });
  for (const directory of [files.storage, path.dirname(files.archived), path.dirname(files.receipt)]) {
    await mkdir(directory, { recursive: true, mode: 0o700 });
    if ((await lstat(directory)).isSymbolicLink() || await realpath(directory) !== directory) {
      throw new Error('Managed worktree storage must not contain symbolic links');
    }
  }
  return files;
}

async function readReceipt(files, taskId, sourceRoot) {
  const file = await open(files.receipt, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    const facts = await file.stat();
    if (!facts.isFile() || facts.size > maximumReceiptBytes) throw new Error('Invalid managed worktree receipt');
    const buffer = Buffer.alloc(facts.size + 1);
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await file.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    if (length !== facts.size || after.size !== facts.size || after.mtimeMs !== facts.mtimeMs || after.ctimeMs !== facts.ctimeMs) {
      throw new Error('Managed worktree receipt changed while being read');
    }
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, length)));
    return boundary('effect.worktree_receipt', { files, value, task_id: taskId, source_root: sourceRoot });
  } finally { await file.close(); }
}

async function saveReceipt(filename, value) {
  const temporary = `${filename}.${randomUUID()}.tmp`;
  const file = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try { await file.writeFile(JSON.stringify(value)); await file.sync(); }
  finally { await file.close(); }
  try { await rename(temporary, filename); }
  finally { await rm(temporary, { force: true }); }
}

async function verifyTree(root) {
  if ((await lstat(root)).isSymbolicLink() || await realpath(root) !== root ||
      (await realpath((await git(root, ['rev-parse', '--show-toplevel'])).trim())) !== root) {
    throw new Error('Managed worktree root does not match its Git checkout');
  }
  if (!(await lstat(path.join(root, '.git'))).isFile()) throw new Error('Managed worktree Git link is missing');
  const administration = (await git(root, ['rev-parse', '--absolute-git-dir'])).trim();
  if ((await readFile(path.join(administration, 'gitdir'), 'utf8')).trim() !== path.join(root, '.git')) {
    throw new Error('Managed worktree Git registration does not point back to its checkout');
  }
}

function completion(effect, result) {
  return boundary('effect.completion', { effect, result });
}

function failure(effect, error, root) {
  return completion(effect, { ok: false, root: root ?? null,
    message: `Managed worktree operation failed: ${String(error.message).toWellFormed()}` });
}

/** Interpret only an earlier committed worktree_create effect. */
export async function createManagedWorktree(effect, { home, limits, signal } = {}) {
  let root;
  let repository;
  let created = false;
  try {
    const files = await locations(home, effect.task_id);
    root = files.active;
    const primary = await realpath(effect.source_root);
    if (!await observeWorkspaceGit(primary, { signal })) throw new Error('The primary workspace must have a Git commit');
    repository = await realpath((await git(primary, ['rev-parse', '--show-toplevel'], { signal })).trim());
    boundary('effect.worktree_path', { operation: 'source', home: files.home, primary, repository });
    const commit = (await git(repository, ['rev-parse', '--verify', 'HEAD^{commit}'], { signal })).trim();
    const configuration = await worktreeGitConfiguration(repository, signal);
    // Snapshot tracked edits before checkout; ignored files stay in the source workspace.
    const patch = await git(repository, [...configuration, 'diff', '--binary', '--no-ext-diff', '--no-textconv', commit, '--'], { signal, encoding: 'buffer' });
    const untracked = (await git(repository, ['ls-files', '--others', '--exclude-standard', '-z'], { signal })).split('\0').filter(Boolean);
    // Reserve ownership before Git can partially register or populate this path.
    // A pre-existing path is never ours to remove on failure.
    await mkdir(root, { mode: 0o700 });
    created = true;
    await git(repository, [...configuration, 'worktree', 'add', '--detach', '--', root, commit], { signal });
    if (patch.length) {
      const patchFile = path.join(files.storage, `.task-${effect.task_id}.patch`);
      await writeFile(patchFile, patch, { mode: 0o600, flag: 'wx' });
      try { await git(root, [...configuration, 'apply', '--binary', '--', patchFile], { signal }); }
      finally { await rm(patchFile, { force: true }); }
    }
    for (const name of untracked) {
      signal?.throwIfAborted();
      const source = path.resolve(repository, name);
      const destination = path.resolve(root, name);
      boundary('effect.worktree_path', { operation: 'copy', repository, root, source, destination });
      await mkdir(path.dirname(destination), { recursive: true });
      await cp(source, destination, { recursive: true, dereference: false, verbatimSymlinks: true, force: false, errorOnExist: true });
    }
    const nextPrimary = path.join(root, path.relative(repository, primary));
    // NOTE: Git does not track empty directories or directories containing only ignored files.
    await mkdir(nextPrimary, { recursive: true });
    const previous = effect.workspace ?? { roots: [primary], primary_root: primary };
    const workspace = await canonicalWorkspace(boundary('effect.worktree_workspace', {
      workspace: previous, previous: primary, next: nextPrimary, descendants: false,
    }));
    const guidance = await snapshotProject(workspace.primary_root, limits, { signal });
    await saveReceipt(files.receipt, { task_id: effect.task_id, source_root: effect.source_root, root, workspace, status: 'ready' });
    return completion(effect, { ok: true, root, workspace, guidance });
  } catch (error) {
    // NOTE: Source files still own every copied edit; removing a failed new copy loses no source data.
    if (created) {
      try { await git(repository, ['worktree', 'remove', '--force', '--', root]); root = null; }
      catch {
        // Git may already have removed its partial checkout while unwinding.
        // Every other failure retains the reserved path and original diagnostic.
        try { await lstat(root); }
        catch (error) { if (error.code === 'ENOENT') root = null; }
      }
    } else root = null;
    return failure(effect, error, root);
  }
}

/** Archive by moving the checkout, preserving tracked and untracked changes. */
export async function archiveManagedWorktree(effect, { home, signal } = {}) {
  try {
    const files = await locations(home, effect.task_id);
    boundary('effect.worktree_path', { operation: 'archive', files, root: effect.root });
    let receipt;
    try { receipt = await readReceipt(files, effect.task_id, effect.source_root); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      // NOTE: A failed checkout can retain a registered tree before its ready receipt exists.
      receipt = { task_id: effect.task_id, source_root: effect.source_root, root: effect.root, status: 'ready',
        workspace: { roots: [effect.root], primary_root: effect.root } };
    }
    let currentRoot = effect.root;
    try { await lstat(currentRoot); }
    catch (error) {
      if (error.code !== 'ENOENT' || currentRoot !== files.active) throw error;
      currentRoot = files.archived;
    }
    await verifyTree(currentRoot);
    if (currentRoot !== files.archived) await git(currentRoot, ['worktree', 'move', '--', currentRoot, files.archived], { signal });
    const workspace = boundary('effect.worktree_workspace', {
      workspace: receipt.workspace, previous: effect.root, next: files.archived, descendants: true,
    });
    await saveReceipt(files.receipt, { ...receipt, root: files.archived, workspace, status: 'archived' });
    return completion(effect, { ok: true, root: files.archived });
  } catch (error) { return failure(effect, error); }
}

/** Recovery observes receipts and Git links; it never repeats a checkout or move. */
export async function reconcileManagedWorktree(entry, { home, limits } = {}) {
  const effect = boundary('effect.worktree_recovery_effect', { entry });
  const creating = effect.kind === 'worktree_create';
  let root;
  try {
    const files = await locations(home, entry.task_id);
    root = creating ? files.active : entry.root;
    const receipt = await readReceipt(files, entry.task_id, entry.source_root);
    let observedRoot = receipt.root;
    // A move may have completed just before the receipt was persisted.
    if (!creating && receipt.root === files.active) {
      try { await lstat(files.active); }
      catch (error) { if (error.code !== 'ENOENT') throw error; observedRoot = files.archived; }
    }
    await verifyTree(observedRoot);
    if (!creating) {
      if (observedRoot !== files.archived) throw new Error('Worktree archive did not complete before restart; retry archiving');
      return completion(effect, { ok: true, root: observedRoot });
    }
    const workspace = await canonicalWorkspace(receipt.workspace);
    const guidance = await snapshotProject(workspace.primary_root, limits);
    return completion(effect, { ok: true, root: receipt.root, workspace, guidance });
  } catch (error) {
    if (root) { try { await lstat(root); } catch { root = null; } }
    return failure(effect, error, root);
  }
}

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, lstat, mkdir, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { shellQuote } from './cloud-environments.mjs';
import { readControlRecord, writeControlRecord as saveReceipt, durableDirectory } from './control-records.mjs';
import { canonicalWorkspace } from './sandbox.mjs';
import { snapshotProject } from './project.mjs';
import { boundary } from './public/model-boundary.mjs';
import { naturalKey } from './codec.mjs';

const execute = promisify(execFile);
const maximumGitOutput = 64 * 1024 * 1024;
// NOTE: Allow all 32 bounded Workspace roots and their JSON escaping to round-trip.
const maximumReceiptBytes = 1024 * 1024;

async function git(cwd, arguments_, { signal, encoding = 'utf8', environment } = {}) {
  if (environment) {
    const script = 'for name in "${!GIT_@}"; do unset "$name"; done; exec "$@"';
    const command = ['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-C', cwd, ...arguments_];
    const observed = await environment.execute(`bash --noprofile --norc -c ${shellQuote(script)} selvedge-git ${command.map(shellQuote).join(' ')}`,
      { signal, maxBuffer: maximumGitOutput, timeout: 120_000 });
    // DEFENSE: Git reports nonrepository and unborn-HEAD observations through its nonzero exit status.
    if (observed.exit_code !== 0) throw Object.assign(new Error(observed.stderr), { code: observed.exit_code });
    return observed.stdout;
  }
  // DEFENSE: Inherited GIT_DIR/GIT_WORK_TREE and related selectors must not redirect the selected repository.
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
    '-C', cwd, ...arguments_], { env, signal, encoding, maxBuffer: maximumGitOutput, timeout: 120_000 });
  return stdout;
}

async function worktreeGitConfiguration(repository, signal) {
  let names;
  try { names = await git(repository, ['config', '--null', '--name-only', '--get-regexp', '^filter\\..*\\.(clean|smudge|process|required)$'], { signal }); }
  // DEFENSE: git config exits 1 when the selected repository declares no matching filter driver.
  catch (error) { if (error.code === 1) return ['-c', 'submodule.recurse=false']; throw error; }
  // DEFENSE: Repository-configured filters can execute project programs during checkout/diff outside the task sandbox.
  const drivers = new Set(names.split('\0').filter(Boolean).map(name => name.slice(0, name.lastIndexOf('.'))));
  return ['-c', 'submodule.recurse=false', ...[...drivers].flatMap(driver =>
    ['-c', `${driver}.clean=`, '-c', `${driver}.smudge=`, '-c', `${driver}.process=`, '-c', `${driver}.required=false`])];
}

/** Observe the primary directory, including primaries below a repository root. */
export async function observeWorkspaceGit(primary, { signal, environment } = {}) {
  signal?.throwIfAborted();
  try {
    boundary('effect.root_admit', { root: primary, absolute: typeof primary === 'string' && path.isAbsolute(primary) });
  } catch (error) {
    // DEFENSE: Browser-selected primary paths are not yet admitted; invalid root syntax is ineligible for worktrees.
    if (error instanceof TypeError) return false;
    throw error;
  }
  try {
    const root = await (environment?.filesystem.realpath ?? realpath)(primary);
    if ((await git(root, ['rev-parse', '--is-inside-work-tree'], { signal, environment })).trim() !== 'true') return false;
    await git(root, ['rev-parse', '--verify', 'HEAD^{commit}'], { signal, environment });
    return true;
  } catch (error) {
    signal?.throwIfAborted();
    // DEFENSE: A selected path may disappear, Git may be absent, or Git may reject a nonrepository/unborn HEAD;
    // these observations cannot establish an available committed checkout. Transport and programming errors propagate.
    if (['ENOENT', 'ENOTDIR'].includes(error.code) || error.code === 128) return false;
    throw error;
  }
}

async function locations(home, taskId) {
  const files = boundary('effect.worktree_locations', { home: await realpath(home), task_id: taskId });
  for (const directory of [files.storage, path.dirname(files.archived), path.dirname(files.receipt)]) {
    await durableDirectory(directory);
    // DEFENSE: Replaced storage directories must not redirect managed worktree writes through symbolic links.
    if ((await lstat(directory)).isSymbolicLink() || await realpath(directory) !== directory) {
      throw new Error('Managed worktree storage must not contain symbolic links');
    }
  }
  return files;
}

async function readReceipt(files, taskId, sourceRoot) {
  const value = await readControlRecord(files.receipt, { maximumBytes: maximumReceiptBytes, label: 'managed worktree receipt' });
  return boundary('effect.worktree_receipt', { files, value, task_id: taskId, source_root: sourceRoot });
}

async function verifyTree(root) {
  // DEFENSE: Externally moved/replaced checkouts must still match their managed canonical root and Git registration.
  if ((await lstat(root)).isSymbolicLink() || await realpath(root) !== root ||
      (await realpath((await git(root, ['rev-parse', '--show-toplevel'])).trim())) !== root) {
    throw new Error('Managed worktree root does not match its Git checkout');
  }
  // DEFENSE: Managed linked worktrees require a Git link file rather than a substituted repository directory.
  if (!(await lstat(path.join(root, '.git'))).isFile()) throw new Error('Managed worktree Git link is missing');
  const administration = (await git(root, ['rev-parse', '--absolute-git-dir'])).trim();
  // DEFENSE: Git administration may be changed independently; it must point back to this checkout before a move.
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

const control = (operation, source) => boundary(`control.resource.${operation}`, source);

async function runLocalResource(plan, files, operations) {
  const errors = [];
  while (true) {
    const state = plan.state;
    let observation;
    const action = plan.effects[0];
    if (action === 'finish') return { receipt: state, errors };
    if (action === 'persist') {
      try {
        const { task_id, source_root, root, workspace, status } = state;
        await saveReceipt(files.receipt, { task_id, source_root, root, workspace, status });
        observation = { kind: 'persisted' };
      } catch (error) {
        // DEFENSE: A failed durable intent must prevent a new Git mutation; known reserved paths remain removable.
        errors.push(error);
        observation = { kind: 'persistence_failed' };
      }
    } else {
      try { observation = await operations[action](state); }
      catch (error) {
        errors.push(error);
        observation = { kind: action === 'local_remove' ? 'local_remove_failed' : 'local_failed',
          reserved: action === 'local_create' && operations.reserved() };
      }
    }
    plan = control('step', { state, observation });
  }
}

/** The durable resource step grants the one physical checkout attempt. */
export async function createManagedWorktree(effect, { home, limits, signal } = {}) {
  let root, repository, files;
  let reserved = false;
  try {
    files = await locations(home, effect.task_id);
    root = files.active;
    const primary = await realpath(effect.source_root);
    // DEFENSE: The source repository or HEAD can disappear after the command's eligibility observation.
    if (!await observeWorkspaceGit(primary, { signal })) throw new Error('The primary workspace must have a Git commit');
    repository = await realpath((await git(primary, ['rev-parse', '--show-toplevel'], { signal })).trim());
    boundary('effect.worktree_path', { operation: 'source', home: files.home, primary, repository });
    const commit = (await git(repository, ['rev-parse', '--verify', 'HEAD^{commit}'], { signal })).trim();
    const configuration = await worktreeGitConfiguration(repository, signal);
    const patch = await git(repository, [...configuration, 'diff', '--binary', '--no-ext-diff', '--no-textconv', commit, '--'], { signal, encoding: 'buffer' });
    const untracked = (await git(repository, ['ls-files', '--others', '--exclude-standard', '-z'], { signal })).split('\0').filter(Boolean);
    const receipt = { task_id: effect.task_id, source_root: effect.source_root, root,
      workspace: { roots: [root], primary_root: root } };
    const result = await runLocalResource(control('local', { operation: 'create', receipt }), files, {
      reserved: () => reserved,
      async local_create() {
        // Exclusive reservation establishes the only path this operation may remove on failure.
        await mkdir(root, { mode: 0o700 });
        reserved = true;
        await git(repository, [...configuration, 'worktree', 'add', '--detach', '--', root, commit], { signal });
        if (patch.length) {
          const patchFile = path.join(files.storage, `.task-${naturalKey(effect.task_id)}.patch`);
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
        await mkdir(nextPrimary, { recursive: true });
        const workspace = await canonicalWorkspace(boundary('effect.worktree_workspace', {
          workspace: effect.workspace, previous: primary, next: nextPrimary, descendants: false,
        }));
        const guidance = await snapshotProject(workspace.primary_root, limits, { signal });
        return { kind: 'local_created', root, workspace, guidance, status: 'ready' };
      },
      async local_remove() {
        try { await git(repository, ['worktree', 'remove', '--force', '--', root]); root = null; }
        catch (error) {
          // DEFENSE: Git can remove a partial checkout while unwinding; only absence proves it gone.
          try { await lstat(root); } catch (observed) { if (observed.code === 'ENOENT') root = null; else throw observed; }
          if (root) throw error;
        }
        return { kind: 'local_removed' };
      },
    });
    if (result.errors.length || result.receipt.status !== 'ready') {
      return failure(effect, result.errors[0] ?? new Error('Worktree preparation interrupted'), reserved ? root : null);
    }
    return completion(effect, { ok: true, root, workspace: result.receipt.workspace, guidance: result.receipt.guidance });
  } catch (error) { return failure(effect, error, reserved ? root : null); }
}

/** Archive by moving the checkout, preserving tracked and untracked changes. */
export async function archiveManagedWorktree(effect, { home, signal } = {}) {
  try {
    const files = await locations(home, effect.task_id);
    boundary('effect.worktree_path', { operation: 'archive', files, root: effect.root });
    let receipt;
    try { receipt = await readReceipt(files, effect.task_id, effect.source_root); }
    catch (error) {
      // DEFENSE: A failed checkout may retain its reserved root before its first receipt is written.
      if (error.code !== 'ENOENT') throw error;
      receipt = { task_id: effect.task_id, source_root: effect.source_root, root: effect.root,
        workspace: { roots: [effect.root], primary_root: effect.root } };
    }
    const result = await runLocalResource(control('local', { operation: 'archive', receipt }), files, {
      async local_archive(state) {
        let currentRoot = effect.root;
        try { await lstat(currentRoot); }
        catch (error) {
          // DEFENSE: A completed move can precede its receipt write; inspect the owned archive.
          if (error.code !== 'ENOENT' || currentRoot !== files.active) throw error;
          currentRoot = files.archived;
        }
        await verifyTree(currentRoot);
        if (currentRoot !== files.archived) await git(currentRoot, ['worktree', 'move', '--', currentRoot, files.archived], { signal });
        const workspace = boundary('effect.worktree_workspace', {
          workspace: state.workspace, previous: effect.root, next: files.archived, descendants: true,
        });
        return { kind: 'local_archived', root: files.archived, workspace, status: 'archived' };
      },
    });
    if (result.errors.length) throw result.errors[0];
    return completion(effect, { ok: true, root: result.receipt.root });
  } catch (error) { return failure(effect, error); }
}

/** Recovery observes receipts and Git links; it never repeats checkout or move. */
export async function reconcileManagedWorktree(entry, { home, limits } = {}) {
  const effect = boundary('effect.worktree_recovery_effect', { entry });
  const creating = effect.kind === 'worktree_create';
  let root;
  try {
    const files = await locations(home, entry.task_id);
    root = creating ? files.active : entry.root;
    const receipt = await readReceipt(files, entry.task_id, entry.source_root);
    const result = await runLocalResource(control('local', { operation: 'recover', receipt, creating }), files, {
      async local_observe(state) {
        let observedRoot = state.root;
        // DEFENSE: A move can complete immediately before the archived receipt reaches disk.
        if (!creating && state.root === files.active) {
          try { await lstat(files.active); }
          catch (error) { if (error.code !== 'ENOENT') throw error; observedRoot = files.archived; }
        }
        await verifyTree(observedRoot);
        if (!creating) {
          if (observedRoot !== files.archived) throw new Error('Worktree archive did not complete before restart; retry archiving');
          const workspace = boundary('effect.worktree_workspace', {
            workspace: state.workspace, previous: state.root, next: observedRoot, descendants: true,
          });
          return { kind: 'local_observed', root: observedRoot, workspace, status: 'archived' };
        }
        const workspace = await canonicalWorkspace(state.workspace);
        return { kind: 'local_observed', root: state.root, workspace,
          guidance: await snapshotProject(workspace.primary_root, limits), status: 'ready' };
      },
    });
    if (result.errors.length) throw result.errors[0];
    if (result.receipt.recovery_failed) throw new Error('Worktree preparation did not complete before restart');
    return completion(effect, { ok: true, root: result.receipt.root,
      ...(creating ? { workspace: result.receipt.workspace, guidance: result.receipt.guidance } : {}) });
  } catch (error) {
    // DEFENSE: Recovery retains existing owned paths; only ENOENT establishes absence.
    if (root) {
      try { await lstat(root); }
      catch (observationError) {
        if (observationError.code !== 'ENOENT') return failure(effect, observationError, root);
        root = null;
      }
    }
    return failure(effect, error, root);
  }
}

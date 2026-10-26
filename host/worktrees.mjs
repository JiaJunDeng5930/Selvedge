import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, lstat, mkdir, open, readFile, readdir, realpath, rmdir, rm, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { shellQuote } from './cloud-environments.mjs';
import { readControlRecord, writeControlRecord as saveReceipt, durableDirectory, syncDirectory } from './control-records.mjs';
import { canonicalWorkspace } from './sandbox.mjs';
import { snapshotProject } from './project.mjs';
import { boundary } from './public/model-boundary.mjs';
import { naturalKey } from './codec.mjs';
import { runLocalResourceController } from './resource-runtime.ts';

const execute = promisify(execFile);
const maximumGitOutput = 64 * 1024 * 1024;
// NOTE: Allow all 32 bounded Workspace roots and their JSON escaping to round-trip.
const maximumReceiptBytes = 1024 * 1024;

async function git(cwd, arguments_, { signal, encoding = 'utf8', environment } = {}) {
  if (environment) {
    const script = 'for name in "${!GIT_@}"; do unset "$name"; done; exec "$@"';
    const command = ['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
      '-c', 'worktree.useRelativePaths=false', '-C', cwd, ...arguments_];
    const observed = await environment.execute(`bash --noprofile --norc -c ${shellQuote(script)} selvedge-git ${command.map(shellQuote).join(' ')}`,
      { signal, maxBuffer: maximumGitOutput, timeout: 120_000 });
    // DEFENSE: Git reports nonrepository and unborn-HEAD observations through its nonzero exit status.
    if (observed.exit_code !== 0) throw Object.assign(new Error(observed.stderr), { code: observed.exit_code });
    return observed.stdout;
  }
  // DEFENSE: Inherited GIT_DIR/GIT_WORK_TREE and related selectors must not redirect the selected repository.
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-c', 'worktree.useRelativePaths=false',
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

async function commonDirectory(root) {
  return realpath(path.resolve(root, (await git(root, ['rev-parse', '--git-common-dir'])).trim()));
}

/** Git permits relative backlinks, resolved from the linked administration directory. */
async function verifyTree(root, reservation) {
  const entry = await lstat(root, { bigint: true });
  const link = await lstat(path.join(root, '.git'));
  const administration = await realpath((await git(root, ['rev-parse', '--absolute-git-dir'])).trim());
  const backlink = (await readFile(path.join(administration, 'gitdir'), 'utf8')).trim();
  const repositoryCommon = await commonDirectory(reservation.repository);
  const checkoutCommon = await commonDirectory(root);
  control('git_admit', { root, root_symlink: entry.isSymbolicLink(), canonical_root: await realpath(root),
    git_top_level: await realpath((await git(root, ['rev-parse', '--show-toplevel'])).trim()),
    git_link_file: link.isFile(), backlink: await realpath(path.resolve(administration, backlink)),
    dev: String(entry.dev), ino: String(entry.ino), reservation,
    repository_common_dir: repositoryCommon, checkout_common_dir: checkoutCommon });
  return { administration, repositoryCommon, checkoutCommon };
}

async function syncRegular(filename, expected) {
  const file = await open(filename, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    const observed = await file.stat({ bigint: true });
    // DEFENSE: A concurrent external writer can replace a staged file before its barrier.
    if (!observed.isFile() || (expected && (observed.dev !== expected.dev || observed.ino !== expected.ino))) {
      throw new Error('Managed Git storage changed before synchronization');
    }
    await file.sync();
  } finally { await file.close(); }
}

/** Sync an owned initialization tree without following its symbolic links. */
async function syncTree(directory) {
  const before = await lstat(directory, { bigint: true });
  // DEFENSE: An externally replaced staging directory must not redirect a recursive barrier.
  if (!before.isDirectory() || await realpath(directory) !== directory) throw new Error('Managed Git storage is not a canonical directory');
  for (const name of await readdir(directory)) {
    const filename = path.join(directory, name);
    const entry = await lstat(filename, { bigint: true });
    if (entry.isDirectory()) await syncTree(filename);
    else if (entry.isFile()) await syncRegular(filename, entry);
    // Symlink contents and entries are published by their containing directory;
    // their targets are outside this initialization write set.
    else if (!entry.isSymbolicLink()) throw new Error('Managed Git storage contains an unsupported special file');
  }
  const after = await lstat(directory, { bigint: true });
  // DEFENSE: An external rename during traversal invalidates the captured directory identity.
  if (after.dev !== before.dev || after.ino !== before.ino) throw new Error('Managed Git directory changed during synchronization');
  await syncDirectory(directory);
}

async function syncAdministrationParent(repositoryCommon) {
  const directory = path.join(repositoryCommon, 'worktrees');
  try { await syncDirectory(directory); }
  catch (error) {
    // DEFENSE: Removing the final linked checkout can remove the worktrees directory itself.
    if (error.code !== 'ENOENT') throw error;
  }
  await syncDirectory(repositoryCommon);
}

/** The model selects a write set; only this interpreter establishes its physical barrier. */
function gitDurability(files) {
  async function registered(state) {
    const observed = await verifyTree(state.root, state.reservation);
    await syncRegular(path.join(state.root, '.git'));
    await syncTree(observed.administration);
    await syncDirectory(state.root);
    await syncAdministrationParent(observed.repositoryCommon);
    return observed;
  }
  return {
    async local_sync_registration(state) { await registered(state); },
    async local_sync_ready(state) {
      await registered(state);
      await syncTree(state.root);
      await syncDirectory(path.dirname(state.root));
    },
    async local_sync_archive(state) {
      await registered(state);
      await syncDirectory(path.dirname(files.active));
      await syncDirectory(path.dirname(files.archived));
    },
    async local_sync_release(state) {
      await syncDirectory(path.dirname(files.active));
      await syncDirectory(path.dirname(files.archived));
      await syncAdministrationParent(await commonDirectory(state.reservation.repository));
    },
  };
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
  return runLocalResourceController(plan, (state, observation) => control('step', { state, observation }), {
    ...operations,
    async persist(state) {
      const receipt = boundary('effect.worktree_receipt_encode', { state });
      await saveReceipt(files.receipt, receipt);
    },
  });
}

function archiveOutcome(receipt) {
  return { ok: true, outcome: receipt.status === 'released'
    ? { kind: 'reservation_released', previous_root: receipt.reservation.canonical_root, reservation_id: receipt.reservation.id }
    : { kind: 'archived_at', root: receipt.root } };
}

/** Report physical facts separately from the controller's cleanup/archive intent. */
function localOwnership(files, released = () => {}) {
  async function classify(state) {
    const reservation = state.reservation;
    const entries = [];
    const registrations = reservation
      ? (await git(reservation.repository, ['worktree', 'list', '--porcelain', '-z'])).split('\0') : [];
    for (const candidate of [files.active, files.archived]) {
      let entry;
      try { entry = await lstat(candidate, { bigint: true }); }
      catch (error) {
        // DEFENSE: A prior release or move can complete before its receipt write.
        if (error.code !== 'ENOENT') throw error;
        entries.push({ root: candidate, present: false, registrations });
        continue;
      }
      const observed = { root: candidate, present: true, registrations, directory: entry.isDirectory(),
        dev: String(entry.dev), ino: String(entry.ino), canonical_root: await realpath(candidate) };
      entries.push(observed);
      if (!entry.isDirectory() || !reservation) continue;
      let linked;
      try { linked = await lstat(path.join(candidate, '.git')); }
      catch (error) {
        // DEFENSE: Cancellation can interrupt creation after mkdir but before Git registration.
        if (error.code !== 'ENOENT') throw error;
      }
      observed.git_link = Boolean(linked);
      if (linked) {
        const registration = await verifyTree(candidate, reservation);
        observed.repository_common_dir = registration.repositoryCommon;
        observed.checkout_common_dir = registration.checkoutCommon;
      } else {
        observed.empty = (await readdir(candidate)).length === 0;
      }
    }
    return control('classify', { reservation, entries });
  }
  return {
    async local_classify(state) {
      const classification = await classify(state);
      return { kind: 'local_classified', classification };
    },
    async local_release(state) {
      // DEFENSE: An external writer can replace or populate a reservation after the first observation.
      if (await classify(state) !== 'owned_empty') throw new Error('Managed reservation ownership changed before release');
      await rmdir(files.active);
      released();
      return { kind: 'local_removed' };
    },
    async local_remove(state) {
      // DEFENSE: Failure rollback may remove only a registered checkout with the captured reservation identity.
      if (await classify(state) !== 'registered') throw new Error('Managed checkout ownership changed before rollback');
      await git(state.reservation.repository, ['worktree', 'remove', '--force', '--', files.active]);
      released();
      return { kind: 'local_removed' };
    },
  };
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
      ...localOwnership(files, () => { root = null; }),
      ...gitDurability(files),
      async local_reserve() {
        await mkdir(root, { mode: 0o700 });
        reserved = true;
        const entry = await lstat(root, { bigint: true });
        await syncDirectory(path.dirname(root));
        return { kind: 'local_reserved', reservation: { id: randomUUID(), canonical_root: await realpath(root),
          dev: String(entry.dev), ino: String(entry.ino), repository } };
      },
      async local_create(state) {
        await git(repository, [...configuration, 'worktree', 'add', '--detach', '--', root, commit], { signal });
        await verifyTree(root, state.reservation);
        return { kind: 'local_registered' };
      },
      async local_prepare() {
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

    });
    if (result.errors.length || result.receipt.status !== 'ready') {
      const retainedRoot = reserved && result.receipt.status !== 'released' ? root ?? files.active : null;
      return failure(effect, result.errors[0] ?? new Error(`Worktree preparation interrupted; ownership requires resolution at ${root}`), retainedRoot);
    }
    return completion(effect, { ok: true, root, workspace: result.receipt.workspace, guidance: result.receipt.guidance });
  } catch (error) { return failure(effect, error, reserved ? root : null); }
}

/** Archive by moving the checkout, preserving tracked and untracked changes. */
export async function archiveManagedWorktree(effect, { home, signal } = {}) {
  try {
    const files = await locations(home, effect.task_id);
    boundary('effect.worktree_path', { operation: 'archive', files, root: effect.root });
    const receipt = await readReceipt(files, effect.task_id, effect.source_root);
    const result = await runLocalResource(control('local', { operation: 'archive', receipt }), files, {
      ...localOwnership(files),
      ...gitDurability(files),
      async local_archive(state) {
        let currentRoot = effect.root;
        try { await lstat(currentRoot); }
        catch (error) {
          // DEFENSE: A completed move can precede its receipt write; inspect the owned archive.
          if (error.code !== 'ENOENT' || currentRoot !== files.active) throw error;
          currentRoot = files.archived;
        }
        await verifyTree(currentRoot, state.reservation);
        if (currentRoot !== files.archived) await git(currentRoot, ['worktree', 'move', '--', currentRoot, files.archived], { signal });
        const workspace = boundary('effect.worktree_workspace', {
          workspace: state.workspace, previous: effect.root, next: files.archived, descendants: true,
        });
        return { kind: 'local_archived', root: files.archived, workspace, status: 'archived' };
      },
    });
    if (result.errors.length) throw result.errors[0];
    if (!['archived', 'released'].includes(result.receipt.status)) throw new Error(`Managed reservation requires ownership resolution at ${result.receipt.root} (reservation ${result.receipt.reservation?.id ?? 'unrecorded'})`);
    return completion(effect, archiveOutcome(result.receipt));
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
      ...localOwnership(files),
      ...gitDurability(files),
      async local_observe(state) {
        let observedRoot = state.root;
        // DEFENSE: A move can complete immediately before the archived receipt reaches disk.
        if (!creating && state.root === files.active) {
          try { await lstat(files.active); }
          catch (error) { if (error.code !== 'ENOENT') throw error; observedRoot = files.archived; }
        }
        await verifyTree(observedRoot, state.reservation);
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
    if (creating && result.receipt.status !== 'ready') throw new Error('Worktree preparation did not complete before restart');
    if (!creating) {
      if (!['archived', 'released'].includes(result.receipt.status)) throw new Error(`Managed reservation requires ownership resolution at ${result.receipt.root} (reservation ${result.receipt.reservation?.id ?? 'unrecorded'})`);
      return completion(effect, archiveOutcome(result.receipt));
    }
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

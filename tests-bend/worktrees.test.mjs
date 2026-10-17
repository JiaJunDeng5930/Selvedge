import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { watch } from 'node:fs';
import { access, chmod, lstat, mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import path from 'node:path';
import { archiveManagedWorktree, createManagedWorktree, reconcileManagedWorktree } from '../host/worktrees.mjs';
import { home, shellQuote } from './support.mjs';

const execute = promisify(execFile);
const limits = { project_context_bytes: 32768 };
async function git(cwd, ...arguments_) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Worktree fixture', '-c', 'user.email=worktree@example.test',
    '-c', 'filter.fixture.clean=', '-c', 'filter.fixture.smudge=', '-c', 'filter.fixture.required=false',
    '-C', cwd, ...arguments_], { env });
  return stdout.trim();
}

test('real Git preserves dirty source data, suppresses project programs and reconciles interrupted owned worktrees', async t => {
  const base = await realpath(await home(t));
  const repository = path.join(base, 'source repository');
  const primary = path.join(repository, 'packages', 'app');
  const state = path.join(base, 'state');
  await Promise.all([mkdir(primary, { recursive: true }), mkdir(state)]);
  await git(repository, 'init', '--initial-branch=main');
  await writeFile(path.join(repository, '.gitignore'), 'ignored.local\n');
  await writeFile(path.join(repository, '.gitattributes'), 'filtered.txt filter=fixture\n');
  await writeFile(path.join(repository, 'filtered.txt'), 'committed raw text\n');
  await writeFile(path.join(primary, 'AGENTS.md'), 'Keep this task guidance.');
  await writeFile(path.join(primary, 'tracked.txt'), 'committed');
  await writeFile(path.join(primary, 'staged.txt'), 'committed');
  await git(repository, 'add', '.');
  await git(repository, 'commit', '-m', 'Initial worktree');
  await writeFile(path.join(primary, 'tracked.txt'), 'dirty tracked 世界');
  await writeFile(path.join(primary, 'staged.txt'), 'staged');
  await git(repository, 'add', 'packages/app/staged.txt');
  await writeFile(path.join(primary, 'untracked.txt'), 'untracked');
  await writeFile(path.join(primary, 'ignored.local'), 'source-only');
  await writeFile(path.join(repository, 'filtered.txt'), 'dirty raw 世界\n');
  const programMarker = path.join(base, 'project-program-ran');
  const filter = `printf filter >> ${shellQuote(programMarker)}; cat`;
  for (const name of ['clean', 'smudge']) await git(repository, 'config', `filter.fixture.${name}`, filter);
  await git(repository, 'config', 'filter.fixture.required', 'true');
  const hook = path.join(repository, '.git', 'hooks', 'post-checkout');
  await writeFile(hook, `#!/bin/sh\nprintf hook >> ${shellQuote(programMarker)}\n`);
  await chmod(hook, 0o700);
  const sourceStatus = await git(repository, 'status', '--porcelain');
  const effect = { kind: 'worktree_create', task_id: 42, source_root: primary,
    workspace: { roots: [primary], primary_root: primary } };
  const created = await createManagedWorktree(effect, { home: state, limits });
  assert.equal(created.ok, true, JSON.stringify(created));
  const selected = created.workspace.primary_root;
  for (const [name, content] of [['tracked.txt', 'dirty tracked 世界'], ['staged.txt', 'staged'], ['untracked.txt', 'untracked']]) {
    assert.equal(await readFile(path.join(selected, name), 'utf8'), content);
  }
  assert.equal(await readFile(path.join(created.root, 'filtered.txt'), 'utf8'), 'dirty raw 世界\n');
  await assert.rejects(access(path.join(selected, 'ignored.local')), { code: 'ENOENT' });
  await assert.rejects(access(programMarker), { code: 'ENOENT' });
  const receipt = path.join(state, 'worktrees', 'receipts', 'task-42.json');
  const readyReceipt = await readFile(receipt);
  await writeFile(path.join(selected, 'tracked.txt'), 'worktree-only dirty data');
  await writeFile(path.join(selected, 'ignored.local'), 'retained generated data');
  const archived = await archiveManagedWorktree({ kind: 'worktree_archive', task_id: 42,
    source_root: primary, root: created.root }, { home: state });
  assert.equal(archived.ok, true, JSON.stringify(archived));
  const archivedPrimary = path.join(archived.root, 'packages', 'app');
  assert.equal(await readFile(path.join(archivedPrimary, 'tracked.txt'), 'utf8'), 'worktree-only dirty data');
  assert.equal(await readFile(path.join(archivedPrimary, 'ignored.local'), 'utf8'), 'retained generated data');
  // An actual Git move can finish before its ready receipt is replaced.
  await writeFile(receipt, readyReceipt);
  const recovered = await reconcileManagedWorktree({ task_id: 42, source_root: primary,
    root: created.root, status: 'archiving' }, { home: state, limits });
  assert.equal(recovered.ok, true, JSON.stringify(recovered));
  assert.equal(recovered.root, archived.root);
  assert.equal(await readFile(path.join(archivedPrimary, 'ignored.local'), 'utf8'), 'retained generated data');

  // Abort on the real directory reservation, possibly before Git finishes its
  // own partial registration cleanup. Report exactly the path still retained.
  const controller = new AbortController();
  const reserved = path.join(state, 'worktrees', 'task-43');
  const observer = watch(path.dirname(reserved), (_event, name) => {
    if (name?.toString() === 'task-43') controller.abort();
  });
  t.after(() => { observer.close(); controller.abort(); });
  const failed = await createManagedWorktree({ ...effect, task_id: 43 }, { home: state, limits, signal: controller.signal });
  observer.close();
  assert.equal(controller.signal.aborted, true);
  assert.equal(failed.ok, false, JSON.stringify(failed));
  let retained = true;
  try { await lstat(reserved); }
  catch (error) { if (error.code !== 'ENOENT') throw error; retained = false; }
  assert.equal(failed.root, retained ? reserved : null);
  assert.equal(await readFile(path.join(primary, 'tracked.txt'), 'utf8'), 'dirty tracked 世界');
  assert.equal(await readFile(path.join(primary, 'ignored.local'), 'utf8'), 'source-only');
  assert.equal(await git(repository, 'status', '--porcelain'), sourceStatus);
  await assert.rejects(access(programMarker), { code: 'ENOENT' });
});

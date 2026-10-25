import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { chmod, lstat, mkdir, readFile, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, shellQuote } from './support.mjs';
import { filesystemChild } from './fixtures/filesystem-boundaries-server.mjs';

async function until(observe, accepts) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const value = await observe();
    if (accepts(value)) return value;
    await delay(20);
  }
  assert.fail('The real Git reservation operation did not settle within ten seconds');
}

test('HTTP cancellation and recovery release an owned empty reservation before Git registration', { timeout: 30_000 }, async t => {
  const directory = await home(t);
  const repository = path.join(directory, 'repository');
  const storage = path.join(directory, 'service');
  const binary = path.join(directory, 'bin');
  const gate = path.join(directory, 'git-add-entered');
  const execute = promisify(execFile);
  await mkdir(repository);
  await mkdir(binary);
  const git = async (...args) => (await execute('git', ['-c', 'commit.gpgsign=false', '-c', 'user.name=Reservation fixture',
    '-c', 'user.email=reservation@example.test', '-C', repository, ...args])).stdout;
  await git('init', '--initial-branch=main');
  await writeFile(path.join(repository, 'tracked.txt'), 'preserve source');
  await git('add', '.');
  await git('commit', '-m', 'Create reservation fixture');
  const realGit = (await execute('sh', ['-c', 'command -v git'])).stdout.trim();
  const wrapper = path.join(binary, 'git');
  await writeFile(wrapper, `#!/bin/sh
is_add=
previous=
root=
for argument do
  if [ "$previous" = worktree ] && [ "$argument" = add ]; then is_add=yes; fi
  if [ "$previous" = -- ]; then root=$argument; fi
  previous=$argument
done
if [ "$is_add" = yes ]; then
  printf '%s' "$root" > ${shellQuote(gate)}
  while [ -d ${shellQuote(directory)} ]; do sleep 0.02; done
fi
exec ${shellQuote(realGit)} "$@"
`);
  await chmod(wrapper, 0o700);
  const options = { home: storage, cwd: repository, config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0 }) };
  const running = await filesystemChild(t, options, { ...process.env, PATH: `${binary}${path.delimiter}${process.env.PATH}` });
  const { work_id } = await running.command({ op: 'create_work', name: 'Reservation recovery' });
  const { task_id } = await running.command({ op: 'create_work_task', work_id, create_worktree: true,
    profile: 'demo', message: 'Create a managed checkout.' });
  const reservedRoot = await until(async () => {
    try { return await readFile(gate, 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; return ''; }
  }, Boolean);
  assert.equal((await git('worktree', 'list', '--porcelain')).includes(`worktree ${reservedRoot}\n`), false);
  await running.close('SIGKILL');
  const recovered = await filesystemChild(t, options);
  const failed = await until(() => recovered.command({ op: 'read_worktree', task_id }), value => value.status === 'create_failed');
  assert.equal(failed.root, reservedRoot);
  assert.equal((await lstat(reservedRoot)).isDirectory(), true);
  await recovered.command({ op: 'archive', task_id });
  const archived = await until(() => recovered.command({ op: 'read_worktree', task_id }), value => value.status === 'archived');
  assert.equal(archived.root, null, 'Reservation release must not invent an archive path');
  await assert.rejects(lstat(reservedRoot), { code: 'ENOENT' });
  assert.equal(await readFile(path.join(repository, 'tracked.txt'), 'utf8'), 'preserve source');

  await recovered.close();
  const interrupted = await filesystemChild(t, options, { ...process.env, PATH: `${binary}${path.delimiter}${process.env.PATH}` });
  const next = await interrupted.command({ op: 'create_work_task', work_id, create_worktree: true,
    profile: 'demo', message: 'Cancel before Git registration.' });
  const cancelledRoot = await until(() => readFile(gate, 'utf8'), value => value !== reservedRoot);
  await interrupted.close();
  await assert.rejects(lstat(cancelledRoot), { code: 'ENOENT' });
  const reopened = await filesystemChild(t, options);
  const cancelled = await until(() => reopened.command({ op: 'read_worktree', task_id: next.task_id }), value => value.status === 'create_failed');
  assert.equal(cancelled.root, null, 'Cancelled reservation cleanup is durably observed after restart');
});

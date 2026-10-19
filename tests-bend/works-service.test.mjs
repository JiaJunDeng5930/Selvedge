import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, realpath, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, taskIdle } from './support.mjs';

const result = decision => {
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
};

async function postCommand(running, command) {
  const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
    headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    body: JSON.stringify(command) });
  assert.equal(response.status, 200);
  return result({ reply: await response.json() });
}

test('HTTP Work creation observes its selected Project workspace before dispatch', async t => {
  const directory = await realpath(await home(t));
  const workspace = path.join(directory, 'project 世界');
  await mkdir(workspace);
  const guidance = path.join(workspace, 'AGENTS.override.md');
  await writeFile(guidance, 'Original Project guidance.');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => running.close());
  const post = command => postCommand(running, command);
  const { project_id } = await post({ op: 'create_project', name: 'Selected Project', workspace: { roots: [workspace] } });
  await writeFile(guidance, 'Observe this Work Task workspace.');
  const { work_id } = await post({ op: 'create_work', name: '登录功能\n"世界" 😀' });
  const { task_id } = await post({ op: 'create_work_task', work_id, profile: 'demo',
    message: 'Discuss the Work 世界', settings: { project_id } });
  const page = await taskIdle(running.service, task_id);
  assert.deepEqual(page.task.settings.workspace, { roots: [workspace], primary_root: workspace });
  assert.ok(page.messages.some(message => message.type === 'context_change' && message.change.type === 'introduce'
    && message.change.snapshot.value.fields.path === guidance
    && message.change.snapshot.value.fields.content === 'Observe this Work Task workspace.'),
  'The dispatched Work Task receives the file changed after its Project was registered');
});

test('HTTP Work worktree creation observes the default cwd before dispatch', async t => {
  const directory = await realpath(await home(t));
  const repository = path.join(directory, 'source checkout');
  await mkdir(repository);
  const execute = promisify(execFile);
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const git = async (...arguments_) => {
    const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
      '-c', 'user.name=Work fixture', '-c', 'user.email=work@example.test', '-C', repository, ...arguments_],
    { env });
    return stdout.trim();
  };
  await git('init', '--initial-branch=main');
  const filename = path.join(repository, 'tracked.txt');
  await writeFile(filename, 'Committed source data.');
  await git('add', 'tracked.txt');
  await git('commit', '-m', 'Initial Work checkout');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const options = { home: path.join(directory, 'state'), cwd: repository, config };
  const running = await startServer(options);
  t.after(() => running.close());
  const post = command => postCommand(running, command);
  const { work_id } = await post({ op: 'create_work', name: 'Managed checkout Work' });
  const { task_id } = await post({ op: 'create_work_task', work_id, create_worktree: true,
    profile: 'demo', message: 'Work in the copied checkout.' });
  let checkout;
  const deadline = Date.now() + 10_000;
  do {
    checkout = await post({ op: 'read_worktree', task_id });
    assert.notEqual(checkout.status, 'create_failed', JSON.stringify(checkout));
    if (checkout.status === 'ready') break;
    await delay(20);
  } while (Date.now() < deadline);
  assert.equal(checkout.status, 'ready', JSON.stringify(checkout));
  assert.equal(checkout.source_root, repository, 'The combined HTTP command observes the default cwd');
  await taskIdle(running.service, task_id);
});

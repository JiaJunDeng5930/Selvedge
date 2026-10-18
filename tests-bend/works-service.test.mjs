import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

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

test('HTTP Work creation observes its selected Project workspace before dispatch and survives reopen', { timeout: 20_000 }, async t => {
  const directory = await realpath(await home(t));
  const workspace = path.join(directory, 'project 世界');
  await mkdir(workspace);
  const guidance = path.join(workspace, 'AGENTS.override.md');
  await writeFile(guidance, 'Original Project guidance.');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  let running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => running.close());
  const post = command => postCommand(running, command);
  const { project_id } = await post({ op: 'create_project', name: 'Selected Project', workspace: { roots: [workspace] } });
  await writeFile(guidance, 'Observe this Work Task workspace.');
  const { work_id } = await post({ op: 'create_work', name: '登录功能\n"世界" 😀' });
  const { task_id } = await post({ op: 'create_work_task', work_id, profile: 'demo',
    message: 'Discuss the Work 世界', settings: { project_id } });
  const page = await taskIdle(running.service, task_id);
  assert.equal(page.task.work_id, work_id);
  assert.equal(page.task.settings.project_id, project_id);
  assert.deepEqual(page.task.settings.workspace, { roots: [workspace], primary_root: workspace });
  assert.ok(page.messages.some(message => message.role === 'assistant' && message.content === '[Offline demo] Discuss the Work 世界'));
  assert.ok(page.messages.some(message => message.type === 'context_change' && message.change.type === 'introduce'
    && message.change.snapshot.value.fields.path === guidance
    && message.change.snapshot.value.fields.content === 'Observe this Work Task workspace.'),
  'The dispatched Work Task receives the file changed after its Project was registered');
  assert.equal((await post({ op: 'read_work', work_id })).name, '登录功能\n"世界" 😀');
  await post({ op: 'rename_work', work_id, name: 'Renamed goal 世界' });
  const saved = await post({ op: 'read_work', work_id });
  await running.close();
  running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  assert.deepEqual(await post({ op: 'read_work', work_id }), saved);
  const reopened = await post({ op: 'read', task_id });
  assert.equal(reopened.task.work_id, work_id);
  assert.deepEqual(reopened.task.settings.workspace, page.task.settings.workspace);
});

test('HTTP Work worktree creation copies dirty Git data from the default cwd and reopens the same checkout', { timeout: 30_000 }, async t => {
  const directory = await realpath(await home(t));
  const repository = path.join(directory, 'source checkout');
  await mkdir(repository);
  const execute = promisify(execFile);
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const git = async (...arguments_) => {
    const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
      '-c', 'user.name=Work fixture', '-c', 'user.email=work@example.test', '-C', repository, ...arguments_],
    { env, timeout: 5000 });
    return stdout.trim();
  };
  await git('init', '--initial-branch=main');
  const filename = path.join(repository, 'tracked.txt');
  await writeFile(filename, 'Committed source data.');
  await git('add', 'tracked.txt');
  await git('commit', '-m', 'Initial Work checkout');
  const dirty = 'Uncommitted Work data 世界';
  await writeFile(filename, dirty);
  const sourceStatus = await git('status', '--porcelain');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const options = { home: path.join(directory, 'state'), cwd: repository, config };
  let running = await startServer(options);
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
  assert.notEqual(checkout.root, repository);
  assert.equal(await readFile(path.join(checkout.root, 'tracked.txt'), 'utf8'), dirty);
  await taskIdle(running.service, task_id);
  const page = await post({ op: 'read', task_id });
  assert.equal(page.task.work_id, work_id);
  assert.deepEqual(page.task.settings.workspace, { roots: [checkout.root], primary_root: checkout.root });
  const registry = await post({ op: 'list_works' });
  await running.close();
  running = await startServer(options);
  assert.deepEqual(await post({ op: 'list_works' }), registry);
  assert.deepEqual(await post({ op: 'read_worktree', task_id }), checkout);
  const reopened = await post({ op: 'read', task_id });
  assert.equal(reopened.task.work_id, work_id);
  assert.deepEqual(reopened.task.settings.workspace, page.task.settings.workspace);
  assert.equal(await readFile(path.join(checkout.root, 'tracked.txt'), 'utf8'), dirty);
  assert.equal(await readFile(filename, 'utf8'), dirty);
  assert.equal(await git('status', '--porcelain'), sourceStatus);
});

test('a native Work tool discovers its caller and transports graph commands without repeating model requests on reopen', { timeout: 20_000 }, async t => {
  const directory = await home(t);
  const credential = `SELVEDGE_WORK_GRAPH_${process.pid}_${Math.random().toString(16).slice(2)}`;
  process.env[credential] = 'local-work-graph-fixture';
  t.after(() => { delete process.env[credential]; });
  let work_id;
  let discoveredWork;
  let controller;
  let graph;
  let additional;
  const toolResult = (body, id) => {
    const output = body.input.find(item => item.type === 'function_call_output' && item.call_id === id);
    assert.ok(output, `Missing Work graph tool result ${id}`);
    const decoded = JSON.parse(output.output);
    assert.equal(decoded.is_error, false, JSON.stringify(decoded));
    return result({ reply: decoded.value });
  };
  const call = (id, name, args) => [{ type: 'function_call', call_id: id, name, arguments: JSON.stringify(args) }];
  const provider = await responsesServer(t, (body, index) => {
    for (const name of ['read_current_task', 'create_work_task', 'create_task_graph', 'read_task_graph', 'update_task_graph']) {
      assert.ok(body.tools.some(tool => tool.name === name), `Missing native ${name}`);
    }
    switch (index) {
      case 0:
        return call('current-task', 'read_current_task', {});
      case 1: {
        const current = toolResult(body, 'current-task').task;
        assert.equal(current.id, controller);
        assert.equal(current.work_id, work_id);
        assert.notEqual(current.id, 0, 'A caller observation must not default to Task zero');
        assert.notEqual(current.work_id, 0, 'A caller observation must not infer the first Work');
        discoveredWork = current.work_id;
        return call('additional-work-task', 'create_work_task', { work_id: discoveredWork,
          profile: 'demo', message: 'Additional Work Task', create_worktree: false });
      }
      case 2:
        additional = toolResult(body, 'additional-work-task').task_id;
        return call('build-work', 'create_task_graph', { work_id: discoveredWork, name: 'Work implementation',
          nodes: [{ key: 'implementation', profile: 'demo', message: 'Implement the feature' }], rules: [] });
      case 3:
        graph = toolResult(body, 'build-work');
        return call('inspect-work', 'read_task_graph', { graph_id: graph.graph_id });
      case 4:
        assert.equal(toolResult(body, 'inspect-work').name, 'Work implementation');
        return call('add-review', 'update_task_graph', { graph_id: graph.graph_id, name: 'Implementation with review',
          nodes: [...graph.nodes, { key: 'review', profile: 'demo', message: 'Review the feature' }], rules: [] });
      case 5:
        graph = toolResult(body, 'add-review');
        return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Added a review Task to this Work.' }] }];
      default:
        assert.fail(`Unexpected Work controller request ${index}`);
    }
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { ...defaultConfig.profiles,
    fixture: { provider: 'responses', model: 'fixture', endpoint: provider.endpoint, api_key_env: credential },
  } });
  const state = path.join(directory, 'state');
  let service = await Service.open({ home: state, cwd: directory, config });
  t.after(() => service.close());
  const decoy = result(await service.command({ op: 'create_work', name: 'Unrelated Work' })).work_id;
  const decoyTask = result(await service.command({ op: 'create_work_task', work_id: decoy,
    profile: 'demo', message: 'Unrelated Task' })).task_id;
  await taskIdle(service, decoyTask);
  work_id = result(await service.command({ op: 'create_work', name: 'Agent-arranged Work' })).work_id;
  controller = result(await service.command({ op: 'create_work_task', work_id,
    profile: 'fixture', message: 'Arrange this Work, then add a review Task.' })).task_id;
  await taskIdle(service, controller);
  assert.deepEqual(provider.failures, []);
  assert.equal(provider.requests.length, 6);
  assert.ok(Number.isSafeInteger(additional), 'The native command result transports the created Task ID');
  const members = [controller, additional, ...graph.nodes.map(node => node.task_id)];
  await Promise.all(members.map(task_id => taskIdle(service, task_id)));
  const saved = result(await service.command({ op: 'read_work', work_id }));
  assert.deepEqual(saved.graph_ids, [graph.graph_id], 'The optional native graph work_id survives argument transport');
  await service.close();
  service = await Service.open({ home: state, cwd: directory, config });
  assert.deepEqual(result(await service.command({ op: 'read_work', work_id })), saved);
  assert.deepEqual(result(await service.command({ op: 'read_task_graph', graph_id: graph.graph_id })), graph);
  assert.equal(provider.requests.length, 6, 'Replaying the Work must not repeat model calls');
});

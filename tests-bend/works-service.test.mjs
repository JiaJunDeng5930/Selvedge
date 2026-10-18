import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { taskId } from './fixtures/task-graph.mjs';

const result = decision => {
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
};

test('HTTP-created Works retain independent per-Task Projects and fork membership after a service restart', { timeout: 20_000 }, async t => {
  const directory = await realpath(await home(t));
  const roots = [path.join(directory, 'frontend'), path.join(directory, 'backend')];
  await Promise.all(roots.map(root => mkdir(root)));
  await Promise.all(roots.map((root, index) => writeFile(path.join(root, 'AGENTS.md'), `Work project guidance ${index}`)));
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  let running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => running.close());
  const post = async command => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(command) });
    assert.equal(response.status, 200);
    return result({ reply: await response.json() });
  };
  const projects = [];
  for (const [index, root] of roots.entries()) {
    projects.push((await post({ op: 'create_project', name: `Project ${index}`, workspace: { roots: [root] } })).project_id);
  }
  const work_id = (await post({ op: 'create_work', name: 'One goal, two Projects' })).work_id;
  const other = (await post({ op: 'create_work', name: 'Separate goal' })).work_id;
  const tasks = [];
  for (const [index, project_id] of projects.entries()) {
    const created = await post({ op: 'create_work_task', work_id, profile: 'demo',
      message: `Work Task ${index}`, settings: { project_id } });
    tasks.push(created.task_id);
    const page = await taskIdle(running.service, created.task_id);
    assert.equal(page.task.work_id, work_id);
    assert.equal(page.task.settings.project_id, project_id);
    assert.deepEqual(page.task.settings.workspace, { roots: [roots[index]], primary_root: roots[index] });
    assert.ok(page.messages.some(message => message.role === 'assistant' && message.content === `[Offline demo] Work Task ${index}`));
    assert.ok(page.messages.some(message => message.type === 'context_change'
      && message.change.type === 'introduce' && message.change.snapshot.value.fields.content === `Work project guidance ${index}`));
  }
  const separate = (await post({ op: 'create_work_task', work_id: other, profile: 'demo', message: 'Other Work' })).task_id;
  await taskIdle(running.service, separate);
  const independent = (await post({ op: 'create', profile: 'demo', message: 'Standalone', settings: { project_id: projects[0] } })).task_id;
  assert.equal((await taskIdle(running.service, independent)).task.work_id, null);
  const children = (await post({ op: 'fork', task_id: tasks[0], child_count: 1, messages: ['Branch within the same Work'] })).children;
  for (const task_id of [...tasks, ...children]) await taskIdle(running.service, task_id);
  const saved = await post({ op: 'read_work', work_id });
  assert.deepEqual(saved.task_ids, [...tasks, ...children]);
  assert.deepEqual((await post({ op: 'read_work', work_id: other })).task_ids, [separate]);
  assert.equal((await post({ op: 'list' })).tasks.length, tasks.length + children.length + 2);
  await post({ op: 'rename_work', work_id, name: 'Renamed goal 世界' });
  const before = await post({ op: 'list_works' });
  const pages = await Promise.all([...tasks, separate, independent, ...children].map(task_id => taskIdle(running.service, task_id)));
  await running.close();
  running = await startServer({ home: path.join(directory, 'state'), cwd: roots[1], config });
  assert.deepEqual(await post({ op: 'list_works' }), before);
  for (const page of pages) assert.deepEqual(await taskIdle(running.service, page.task.id), page);
});

test('a Work conversation can create and edit its graph through native model tools, independently of graph nodes', { timeout: 20_000 }, async t => {
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
          profile: 'demo', message: 'Additional Work Task' });
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
  assert.equal(graph.nodes.some(node => node.task_id === controller), false);
  assert.equal(graph.nodes.some(node => node.task_id === additional), false);
  const members = [controller, additional, taskId(graph, 'implementation'), taskId(graph, 'review')];
  for (const task_id of members) {
    assert.equal((await taskIdle(service, task_id)).task.work_id, work_id);
  }
  const saved = result(await service.command({ op: 'read_work', work_id }));
  assert.deepEqual(saved.task_ids, members);
  assert.deepEqual(saved.graph_ids, [graph.graph_id]);
  assert.deepEqual(result(await service.command({ op: 'read_work', work_id: decoy })).task_ids, [decoyTask]);
  await service.close();
  service = await Service.open({ home: state, cwd: directory, config });
  assert.deepEqual(result(await service.command({ op: 'read_work', work_id })), saved);
  assert.deepEqual(result(await service.command({ op: 'read_task_graph', graph_id: graph.graph_id })), graph);
  assert.equal(provider.requests.length, 6, 'Replaying the Work must not repeat model calls');
  result(await service.command({ op: 'delete_task_graph', graph_id: graph.graph_id }));
  const after = result(await service.command({ op: 'read_work', work_id }));
  assert.deepEqual(after.task_ids, members);
  assert.deepEqual(after.graph_ids, []);
  for (const task_id of members) assert.equal((await taskIdle(service, task_id)).task.work_id, work_id);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, symlink, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { CommandNotSubmitted, Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { action, concat, literal, rule, taskId } from './fixtures/task-graph.mjs';

const call = (id, name, args) => [{ type: 'function_call', call_id: id, name, arguments: JSON.stringify(args) }];
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
function result(body, id) {
  const output = body.input.find(item => item.type === 'function_call_output' && item.call_id === id);
  assert.ok(output, `Missing native tool result ${id}`);
  const delivered = JSON.parse(output.output);
  assert.equal(delivered.is_error, false, JSON.stringify(delivered));
  assert.equal(delivered.value.ok, true, JSON.stringify(delivered));
  return delivered.value.result;
}

test('immediate offline Task replies reach the paired Task through the real service and survive restart', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const config = validateConfig(structuredClone(defaultConfig));
  let service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  const installed = await service.command({ op: 'create_task_graph', name: 'Immediate handoff 世界',
    nodes: [{ key: 'tests', profile: 'demo', message: 'adversarial tests' },
      { key: 'implementation', profile: 'demo', message: 'implementation' }],
    rules: [rule('test result', 'tests', action('implementation', concat(literal('Use these tests:\n'), { kind: 'output' })))],
  });
  assert.equal(installed.reply.ok, true, JSON.stringify(installed.reply));
  const graph = installed.reply.result;
  const source = taskId(graph, 'tests');
  const target = taskId(graph, 'implementation');
  const sourcePage = await taskIdle(service, source);
  const targetPage = await taskIdle(service, target);
  assert.ok(sourcePage.messages.some(message => message.role === 'assistant' && message.content === '[Offline demo] adversarial tests'));
  assert.deepEqual(targetPage.messages.filter(message => message.role === 'user').map(message => message.content),
    ['implementation', 'Use these tests:\n[Offline demo] adversarial tests']);
  const beforeGraph = (await service.command({ op: 'read_task_graph', graph_id: graph.graph_id })).reply;
  assert.equal(beforeGraph.result.receipts.length, 1);
  await service.close();
  service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  assert.deepEqual((await service.command({ op: 'read_task_graph', graph_id: graph.graph_id })).reply, beforeGraph);
  assert.deepEqual(await taskIdle(service, target), targetPage);
});

test('a model can create, inspect, replace and remove graphs through frozen native tool capabilities', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const key = `SELVEDGE_GRAPH_FIXTURE_${process.pid}_${Math.random().toString(16).slice(2)}`;
  process.env[key] = 'local-graph-fixture';
  t.after(() => { delete process.env[key]; });
  const names = ['create_task_graph', 'read_task_graph', 'update_task_graph', 'list_task_graphs', 'delete_task_graph'];
  let graph;
  let child;
  const model = await responsesServer(t, (body, index) => {
    for (const name of names) assert.ok(body.tools.some(tool => tool.name === name), `Missing native ${name}`);
    switch (index) {
      case 0:
        return call('build', 'create_task_graph', { name: 'Agent-authored graph',
          nodes: [{ key: 'worker', profile: 'demo', message: 'independent work' }], rules: [] });
      case 1:
        graph = result(body, 'build');
        child = taskId(graph, 'worker');
        return call('inspect', 'read_task_graph', { graph_id: graph.graph_id });
      case 2:
        assert.equal(result(body, 'inspect').name, 'Agent-authored graph');
        return call('replace', 'update_task_graph', { graph_id: graph.graph_id, name: 'Revised by agent', nodes: graph.nodes, rules: [] });
      case 3:
        assert.equal(result(body, 'replace').name, 'Revised by agent');
        return call('list', 'list_task_graphs', {});
      case 4:
        assert.ok(result(body, 'list').graphs.some(item => item.graph_id === graph.graph_id && item.name === 'Revised by agent'));
        return call('remove', 'delete_task_graph', { graph_id: graph.graph_id });
      case 5:
        result(body, 'remove');
        return answer('Constructed and edited the graph through native tools.');
      default:
        assert.fail(`Unexpected controller request ${index}`);
    }
  });
  const config = validateConfig({ ...defaultConfig, profiles: { ...defaultConfig.profiles, fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: key,
  } } });
  const service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'fixture', message: 'Build and revise a graph.' });
  assert.equal(created.reply.ok, true);
  const controller = created.reply.result.task_id;
  const completed = await taskIdle(service, controller);
  assert.deepEqual(model.failures, []);
  assert.equal(model.requests.length, 6);
  assert.equal(completed.messages.filter(message => message.role === 'function_output').length, 5);
  assert.equal((await service.command({ op: 'read_task_graph', graph_id: graph.graph_id })).reply.ok, false);
  const independent = await taskIdle(service, child);
  assert.equal(independent.task.status, 'active');
  assert.ok(independent.messages.some(message => message.role === 'assistant' && message.content === '[Offline demo] independent work'));
});

test('graph Task creation observes canonical workspace roots and journals the same guidance snapshot as ordinary creation', { timeout: 15_000 }, async t => {
  const base = await realpath(await home(t));
  const root = path.join(base, 'selected project');
  const alias = path.join(base, 'project alias');
  await mkdir(root);
  await writeFile(path.join(root, 'AGENTS.md'), 'Graph task guidance before installation.');
  await symlink(root, alias);
  const config = validateConfig({ ...defaultConfig, chatgpt: false });
  let service = await Service.open({ home: path.join(base, 'state'), cwd: base, config });
  t.after(() => service.close());
  const installed = await service.command({ op: 'create_task_graph', name: 'Workspace-bound work', nodes: [
    { key: 'worker', profile: 'demo', message: 'work in the selected project',
      settings: { workspace: { roots: [alias], primary_root: alias } } },
  ], rules: [] });
  assert.equal(installed.reply.ok, true, JSON.stringify(installed.reply));
  const worker = taskId(installed.reply.result, 'worker');
  const settled = await taskIdle(service, worker);
  assert.deepEqual(settled.task.settings.workspace, { roots: [root], primary_root: root });
  const db = new DatabaseSync(path.join(base, 'state', 'journal.sqlite'), { readOnly: true });
  let observed;
  try {
    observed = db.prepare('SELECT input FROM journal ORDER BY seq').all().map(row => JSON.parse(row.input))
      .find(input => input.command?.op === 'create_task_graph').command.nodes[0].settings;
  } finally { db.close(); }
  assert.deepEqual(observed.workspace, { roots: [root], primary_root: root });
  assert.equal(observed.guidance.workspace, root);
  assert.equal(observed.guidance.instructions, 'Graph task guidance before installation.');
  await writeFile(path.join(root, 'AGENTS.md'), 'Changed after the task was created.');
  await service.close();
  service = await Service.open({ home: path.join(base, 'state'), cwd: base, config });
  assert.deepEqual((await taskIdle(service, worker)).task.settings, settled.task.settings);
});

test('a bad graph workspace observation aborts all node creation and does not accept client-supplied guidance', async t => {
  const base = await realpath(await home(t));
  const service = await Service.open({ home: path.join(base, 'state'), cwd: base,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  const before = service.journal.sequence;
  const first = { key: 'valid first', profile: 'demo', message: 'must not run' };
  await assert.rejects(service.command({ op: 'create_task_graph', name: 'All or nothing', nodes: [first,
    { key: 'bad second', profile: 'demo', message: 'bad root', settings: { workspace: { roots: [path.join(base, 'missing')] } } },
  ], rules: [] }), error => {
    assert.ok(error instanceof CommandNotSubmitted);
    assert.equal(error.cause.code, 'ENOENT');
    return true;
  });
  await assert.rejects(service.command({ op: 'create_task_graph', name: 'No forged guidance', nodes: [first,
    { key: 'forged', profile: 'demo', message: 'forged', settings: {
      guidance: { workspace: base, revision: 'absent', instructions: '' },
    } },
  ], rules: [] }), error => {
    assert.ok(error instanceof CommandNotSubmitted);
    assert.ok(error.cause instanceof TypeError);
    assert.match(error.cause.message, /observed by the service/);
    return true;
  });
  assert.equal(service.journal.sequence, before);
  assert.deepEqual((await service.command({ op: 'list' })).reply.result.tasks, []);
  assert.deepEqual((await service.command({ op: 'list_task_graphs' })).reply.result.graphs, []);
});

test('new graph nodes refresh global and selected-project guidance while referenced Tasks keep their frozen context', { timeout: 15_000 }, async t => {
  const base = await realpath(await home(t));
  const state = path.join(base, 'state');
  const cwd = path.join(base, 'launch workspace');
  const selected = path.join(base, 'selected workspace');
  await Promise.all([state, cwd, selected].map(directory => mkdir(directory)));
  await Promise.all([
    writeFile(path.join(state, 'AGENTS.md'), 'Global graph guidance A'),
    writeFile(path.join(cwd, 'AGENTS.md'), 'Launch graph guidance A'),
    writeFile(path.join(selected, 'AGENTS.md'), 'Selected graph guidance A'),
  ]);
  const config = validateConfig({ ...defaultConfig, chatgpt: false });
  let service = await Service.open({ home: state, cwd, config });
  t.after(() => service.close());
  const project = await service.command({ op: 'create_project', name: 'Selected project', workspace: { roots: [selected] } });
  assert.equal(project.reply.ok, true, JSON.stringify(project.reply));
  const installed = await service.command({ op: 'create_task_graph', name: 'Initial graph', nodes: [
    { key: 'original', profile: 'demo', message: 'keep original context' },
  ], rules: [] });
  assert.equal(installed.reply.ok, true, JSON.stringify(installed.reply));
  const graph = installed.reply.result;
  const original = await taskIdle(service, taskId(graph, 'original'));
  const introduced = (page, kind) => page.messages.find(message => message.type === 'context_change'
    && message.change.type === 'introduce' && message.change.snapshot.key.type === kind).change.snapshot;
  assert.equal(introduced(original, 'global_agents').value.fields.content, 'Global graph guidance A');
  assert.equal(introduced(original, 'project_guidance').value.fields.content, 'Launch graph guidance A');
  await Promise.all([
    writeFile(path.join(state, 'AGENTS.md'), 'Global graph guidance B'),
    writeFile(path.join(cwd, 'AGENTS.md'), 'Launch graph guidance B'),
    writeFile(path.join(selected, 'AGENTS.md'), 'Selected graph guidance B'),
  ]);
  const updated = await service.command({ op: 'update_task_graph', graph_id: graph.graph_id, name: 'Expanded graph', nodes: [
    ...graph.nodes,
    { key: 'fresh', profile: 'demo', message: 'use current launch context' },
    { key: 'selected', profile: 'demo', message: 'use current selected context', settings: { project_id: project.reply.result.project_id } },
  ], rules: [] });
  assert.equal(updated.reply.ok, true, JSON.stringify(updated.reply));
  const fresh = await taskIdle(service, taskId(updated.reply.result, 'fresh'));
  const selectedPage = await taskIdle(service, taskId(updated.reply.result, 'selected'));
  for (const page of [fresh, selectedPage]) {
    assert.equal(introduced(page, 'global_agents').value.fields.content, 'Global graph guidance B');
  }
  assert.equal(introduced(fresh, 'project_guidance').value.fields.content, 'Launch graph guidance B');
  assert.equal(introduced(selectedPage, 'project_guidance').value.fields.content, 'Selected graph guidance B');
  assert.deepEqual(selectedPage.task.settings.workspace, { roots: [selected], primary_root: selected });
  assert.deepEqual(await taskIdle(service, original.task.id), original);
  await Promise.all([
    writeFile(path.join(state, 'AGENTS.md'), 'Global graph guidance C'),
    writeFile(path.join(cwd, 'AGENTS.md'), 'Launch graph guidance C'),
    writeFile(path.join(selected, 'AGENTS.md'), 'Selected graph guidance C'),
  ]);
  await service.close();
  service = await Service.open({ home: state, cwd, config });
  assert.deepEqual(await taskIdle(service, original.task.id), original);
  assert.deepEqual(await taskIdle(service, fresh.task.id), fresh);
  assert.deepEqual(await taskIdle(service, selectedPage.task.id), selectedPage);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

test('graph declarations resolve existing tasks before allocating any spawned tasks', async t => {
  const directory = await home(t);
  const service = await Service.open({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  const command = async request => (await service.command(request)).reply;
  const first = await command({ op: 'create_idle', profile: 'demo' });
  assert.equal(first.ok, true);
  const next = first.result.task_id + 1;
  const spawn = { key: 'new', profile: 'demo', message: 'A fresh graph task' };
  const guessed = { key: 'guessed', task_id: next };
  for (const nodes of [[spawn, guessed], [guessed, spawn]]) {
    const refused = await command({ op: 'create_task_graph', name: 'No guessed identities', nodes, rules: [] });
    assert.equal(refused.error.code, 'task_not_found');
    assert.equal((await command({ op: 'read', task_id: next })).error.code, 'task_not_found');
    assert.deepEqual((await command({ op: 'list_task_graphs' })).result.graphs, []);
  }
  const work = await command({ op: 'create_work', name: 'Original Work membership' });
  assert.equal(work.ok, true);
  for (const nodes of [[spawn, guessed], [guessed, spawn]]) {
    const refused = await command({ op: 'create_task_graph', work_id: work.result.work_id,
      name: 'No provisional Work members', nodes, rules: [] });
    assert.equal(refused.error.code, 'task_not_found');
    const unchanged = await command({ op: 'read_work', work_id: work.result.work_id });
    assert.deepEqual(unchanged.result.task_ids, []);
    assert.deepEqual(unchanged.result.graph_ids, []);
  }
  const secondFailure = await command({ op: 'create_task_graph', name: 'All starts are resolved first',
    nodes: [spawn, { key: 'invalid', profile: 'absent', message: 'Unavailable profile' }], rules: [] });
  assert.equal(secondFailure.error.code, 'unknown_profile');
  assert.equal((await command({ op: 'read', task_id: next })).error.code, 'task_not_found');
  const created = await command({ op: 'create_task_graph', name: 'Shared existing task', nodes: [
    { key: 'left', task_id: first.result.task_id }, { key: 'right', task_id: first.result.task_id }, spawn,
  ], rules: [] });
  assert.equal(created.ok, true, JSON.stringify(created));
  const saved = await command({ op: 'read_task_graph', graph_id: created.result.graph_id });
  assert.equal(saved.result.nodes[0].task_id, first.result.task_id);
  assert.equal(saved.result.nodes[1].task_id, first.result.task_id);
  assert.equal(saved.result.nodes[2].task_id, next);
  const update = await command({ op: 'update_task_graph', graph_id: created.result.graph_id,
    name: 'Still cannot guess', nodes: [spawn, { key: 'future', task_id: next + 1 }], rules: [] });
  assert.equal(update.error.code, 'task_not_found');
  assert.deepEqual((await command({ op: 'read_task_graph', graph_id: created.result.graph_id })).result, saved.result);
});

test('graph domain errors preserve Work, capacity and declaration priority', async t => {
  const directory = await home(t);
  const service = await Service.open({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  const command = async request => (await service.command(request)).reply;
  const invalid = { op: 'create_task_graph', work_id: 42, name: '',
    nodes: [{ key: 'same', task_id: 0 }, { key: 'same', task_id: 0 }], rules: [] };
  assert.equal((await command(invalid)).error.code, 'work_not_found');
  for (let index = 0; index < 32; index++) {
    assert.equal((await command({ op: 'create_task_graph', name: `Graph ${index}`, nodes: [], rules: [] })).ok, true);
  }
  assert.equal((await command(invalid)).error.code, 'work_not_found');
  assert.equal((await command({ op: 'create_task_graph', name: 'Overflow', nodes: [], rules: [] })).error.code,
    'invalid_task_graph');
  assert.equal((await command({ op: 'create_idle', profile: 'absent', work_id: 42 })).error.code, 'unknown_profile');
  assert.equal((await command({ op: 'create_idle', profile: 'demo', work_id: 42 })).error.code, 'invalid_arguments');
});


test('native Work and Graph authority gates defer failed ordinary starts until the domain phase', async t => {
  const calls = [
    ['failed-before-escalation', 'create_task_graph', { name: 'Authority before profile failure', nodes: [
      { key: 'missing-profile', profile: 'absent', message: 'Unknown profile' },
      { key: 'expanded', profile: 'demo', message: 'Forbidden authority', settings: { approval: { mode: 'full-access' } } },
    ], rules: [] }, 'invalid_native_feature'],
    ['missing-work-escalation', 'create_task_graph', { work_id: 42, name: 'Authority before missing Work', nodes: [
      { key: 'expanded', profile: 'demo', message: 'Forbidden authority', settings: { approval: { mode: 'full-access' } } },
    ], rules: [] }, 'invalid_native_feature'],
    ['ordered-node-failures', 'create_task_graph', { name: 'Original node failure order', nodes: [
      { key: 'missing-profile', profile: 'absent', message: 'Unknown profile' }, { key: 'missing-task', task_id: 42 },
    ], rules: [] }, 'unknown_profile'],
    ['work-authority', 'create_work_task', { work_id: 42, profile: 'demo', message: 'Forbidden authority',
      settings: { approval: { mode: 'full-access' } } }, 'invalid_native_feature'],
  ];
  const observed = new Map();
  const upstream = await responsesServer(t, body => {
    const outputs = body.input.filter(item => item.type === 'function_call_output');
    if (outputs.length) {
      for (const output of outputs) observed.set(output.call_id, JSON.parse(output.output));
      return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Finished authority checks.' }] }];
    }
    return calls.map(([id, name, arguments_]) => ({ type: 'function_call', call_id: id, name,
      arguments: JSON.stringify(arguments_) }));
  });
  const directory = await home(t);
  const credential = 'SELVEDGE_GRAPH_AUTHORITY_FIXTURE_KEY';
  const previous = process.env[credential];
  process.env[credential] = 'loopback-fixture';
  t.after(() => {
    if (previous === undefined) delete process.env[credential]; else process.env[credential] = previous;
  });
  const service = await Service.open({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, profiles: { ...defaultConfig.profiles,
      fixture: { provider: 'responses', model: 'graph-authority-fixture', endpoint: upstream.endpoint,
        api_key_env: credential, timeout_ms: 5000 } } }) });
  t.after(() => service.close());
  const created = (await service.command({ op: 'create', profile: 'fixture', message: 'Check native authority.' })).reply;
  assert.equal(created.ok, true);
  const deadline = Date.now() + 10000;
  while (observed.size < calls.length && Date.now() < deadline) await delay(10);
  assert.equal(observed.size, calls.length, JSON.stringify([...observed]));
  for (const [id, , , expected] of calls) assert.equal(observed.get(id)?.value?.error?.code, expected, `${id}: ${JSON.stringify(observed.get(id))}`);
  const tasks = (await service.command({ op: 'list' })).reply.result.tasks;
  assert.equal(tasks.length, 1, 'Every refused native feature keeps its births atomic');
  assert.deepEqual((await service.command({ op: 'list_task_graphs' })).reply.result.graphs, []);
});

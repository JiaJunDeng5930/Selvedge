import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

// Pure graph construction, failure atomicity, original-world references and
// Work/capacity/declaration priority are universally owned by
// theories/Features/GraphConstructionProofs.v at the production handlers.
// The provider/native function-call and output bridge below remains an IO check.

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

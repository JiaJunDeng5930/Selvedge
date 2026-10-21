import test from 'node:test';
import assert from 'node:assert/strict';
import { realpath } from 'node:fs/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const answer = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];

test('Task tools share one Work UI atomically and retain its source across a real journal reopen', async t => {
  const directory = await realpath(await home(t));
  const key = 'SELVEDGE_WORK_UI_FIXTURE';
  const previous = process.env[key];
  process.env[key] = 'local-work-ui-fixture';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });

  let pending;
  const upstream = await responsesServer(t, body => {
    if (!pending) return answer;
    const output = body.input.find(item => item.type === 'function_call_output' && item.call_id === pending.id);
    if (output) {
      pending.output = JSON.parse(output.output).value;
      return answer;
    }
    const definition = body.tools.find(tool => tool.name === pending.name);
    assert.ok(definition, `The actual model request exposes ${pending.name}`);
    assert.equal(Object.hasOwn(definition.parameters.properties, 'work_id'), false,
      'The calling Task supplies Work authority; the model does not select a Work');
    return [{ type: 'function_call', call_id: pending.id, name: pending.name,
      arguments: JSON.stringify(pending.arguments) }];
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    worker: { provider: 'responses', model: 'work-ui-fixture', endpoint: upstream.endpoint, api_key_env: key },
  } });
  const options = { home: path.join(directory, 'state'), cwd: directory, config };
  let running = await startServer(options);
  t.after(() => running.close());
  async function post(command) {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(command) });
    assert.equal(response.status, 200);
    const reply = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  let call = 0;
  async function tool(task_id, name, arguments_ = {}) {
    assert.equal(pending, undefined);
    pending = { id: `work-ui-call-${++call}`, name, arguments: arguments_ };
    await post({ op: 'send', task_id, message: `Perform Work UI fixture step ${call}.` });
    const page = await taskIdle(running.service, task_id);
    assert.ok(Object.hasOwn(pending, 'output'),
      'The provider receives the actual native tool result: ' + JSON.stringify(page.messages.at(-1)));
    const output = pending.output;
    pending = undefined;
    assert.deepEqual(upstream.failures, []);
    assert.equal(typeof output.ok, 'boolean', JSON.stringify(output));
    return output.ok ? output.result : output;
  }
  async function create(work_id) {
    const command = work_id === undefined ? { op: 'create' } : { op: 'create_work_task', work_id };
    const { task_id } = await post({ ...command, profile: 'worker', message: 'Prepare the Work UI fixture.' });
    await taskIdle(running.service, task_id);
    return task_id;
  }
  const snapshot = value => ({ source: value.source, revision: value.revision });
  const { work_id } = await post({ op: 'create_work', name: 'Shared UI Work' });
  const { work_id: otherWork } = await post({ op: 'create_work', name: 'Independent Work' });
  const first = await create(work_id);
  const second = await create(work_id);
  const isolated = await create(otherWork);
  const unowned = await create();

  assert.deepEqual(snapshot(await tool(first, 'read_work_ui')), { source: '', revision: 0 });
  assert.deepEqual(snapshot(await tool(second, 'read_work_ui')), { source: '', revision: 0 });
  const source = '<ui id="work-panel">\n  <metric id="progress" label="共同进度 😀" value={1} />\n</ui>\n';
  const add = '*** Begin Patch\n*** Add File: work-ui.dsl\n'
    + source.split('\n').map(line => `+${line}`).join('\n') + '\n*** End Patch';
  const committed = await tool(first, 'apply_work_ui_patch', { revision: 0, patch: add });
  assert.deepEqual(snapshot(committed), { source, revision: 1 });
  assert.deepEqual(snapshot(await tool(second, 'read_work_ui')), snapshot(committed));

  const update = '*** Begin Patch\n*** Update File: work-ui.dsl\n@@\n'
    + '-  <metric id="progress" label="共同进度 😀" value={1} />\n'
    + '+  <metric id="progress" label="共同进度 😀" value={2} />\n*** End Patch';
  const stale = await tool(second, 'apply_work_ui_patch', { revision: 0, patch: update });
  assert.ok(stale.error, JSON.stringify(stale));
  const mismatch = await tool(second, 'apply_work_ui_patch', { revision: 1,
    patch: update.replace('value={1}', 'value={9}') });
  assert.ok(mismatch.error, JSON.stringify(mismatch));
  assert.deepEqual(snapshot(await tool(first, 'read_work_ui')), snapshot(committed),
    'Rejected writes preserve both the exact stored source and its revision');

  const changed = await tool(second, 'apply_work_ui_patch', { revision: 1, patch: update });
  assert.deepEqual(snapshot(changed), { source: source.replace('value={1}', 'value={2}'), revision: 2 });
  const { children: [child] } = await post({ op: 'fork', task_id: second, child_count: 1,
    messages: ['Inspect the shared Work UI from a derived Task.'] });
  await taskIdle(running.service, second);
  await taskIdle(running.service, child);
  assert.deepEqual(snapshot(await tool(child, 'read_work_ui')), snapshot(changed));
  assert.deepEqual(snapshot(await tool(isolated, 'read_work_ui')), { source: '', revision: 0 });
  const unreadable = await tool(unowned, 'read_work_ui');
  assert.ok(unreadable.error, JSON.stringify(unreadable));
  const denied = await tool(unowned, 'apply_work_ui_patch', { revision: 0, patch: add });
  assert.ok(denied.error, JSON.stringify(denied));

  await running.close();
  running = await startServer(options);
  assert.deepEqual(snapshot(await tool(first, 'read_work_ui')), snapshot(changed));
  assert.deepEqual(snapshot(await tool(child, 'read_work_ui')), snapshot(changed));
  assert.deepEqual(snapshot(await tool(isolated, 'read_work_ui')), { source: '', revision: 0 });

  // NOTE: An ordinary 3000-line replacement overflowed generated SSE CRLF line handling below the public input limit.
  const largeSource = ['<ui id="large-work-panel">',
    '  <text id="marker" label="Large source version one" />',
    ...Array(2997).fill('        '), '</ui>'].join('\n');
  const replacement = (before, after) => '*** Begin Patch\n*** Update File: work-ui.dsl\n@@\n'
    + before.split('\n').map(line => '-' + line).join('\n') + '\n'
    + after.split('\n').map(line => '+' + line).join('\n') + '\n*** End Patch';
  assert.deepEqual(snapshot(await tool(child, 'apply_work_ui_patch', {
    revision: 2, patch: replacement(changed.source, largeSource),
  })), { source: largeSource, revision: 3 });
  const largeRevision = largeSource.replace('version one', 'version two');
  const largePatch = replacement(largeSource, largeRevision);
  assert.ok(largePatch.length < 65536, 'The reproduced 3000-line replacement fits the public patch limit');
  assert.deepEqual(snapshot(await tool(first, 'apply_work_ui_patch', {
    revision: 3, patch: largePatch,
  })), { source: largeRevision, revision: 4 });
  assert.deepEqual(snapshot(await tool(second, 'read_work_ui')), { source: largeRevision, revision: 4 });
  assert.deepEqual(upstream.failures, []);
});

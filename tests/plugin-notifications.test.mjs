import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Observed.' }] }];

test('post-commit plugin events keep their order and replay never redelivers the saved batch', { timeout: 30000 }, async t => {
  const directory = await home(t);
  const log = path.join(directory, 'events.jsonl');
  await writeFile(log, '');
  const apiKey = 'SELVEDGE_NOTIFICATION_FIXTURE_KEY';
  const previous = process.env[apiKey];
  process.env[apiKey] = 'loopback-notification-fixture';
  t.after(() => { if (previous === undefined) delete process.env[apiKey]; else process.env[apiKey] = previous; });
  const upstream = await responsesServer(t, body => body.input.some(item =>
    item.type === 'function_call_output' && item.call_id === 'notification-read') ? done :
    [{ type: 'function_call', call_id: 'notification-read', name: 'read_current_task', arguments: '{}' }]);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider: 'responses', model: 'notification-fixture', endpoint: upstream.endpoint, api_key_env: apiKey } },
    plugins: { observer: { command: process.execPath,
      args: [fileURLToPath(new URL('./fixtures/core-migration-hooks.mjs', import.meta.url)), 'observer', log] } },
  });
  const options = { home: path.join(directory, 'state'), cwd: directory, config };
  let running = await startServer(options);
  t.after(() => running.close());
  const command = async value => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' }, body: JSON.stringify(value) });
    return response.json();
  };
  const events = async () => (await readFile(log, 'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);
  const until = async (observe, complete) => {
    const deadline = Date.now() + 15000;
    let value;
    do { value = await observe(); if (complete(value)) return value; await delay(15); } while (Date.now() < deadline);
    assert.fail(`Notification fixture did not finish: ${JSON.stringify(value)}`);
  };
  const created = await command({ op: 'create', profile: 'fixture', message: 'Read the current task and finish.' });
  assert.equal(created.ok, true, JSON.stringify(created));
  const owner = created.result.task_id;
  await until(() => command({ op: 'read', task_id: owner }), reply =>
    reply.ok && reply.result.task.phase === 'idle' && reply.result.task.operations.length === 0);
  const delivered = await until(events, values => values.some(value =>
    value.type === 'task_changed' && value.task_id === owner && value.payload.phase === 'idle') &&
    values.some(value => value.type === 'tool_completed'));
  assert.deepEqual(upstream.failures, []);
  assert.ok(delivered.some(value => value.type === 'task_created' && value.task_id === owner));
  assert.ok(delivered.some(value => value.type === 'model_started'));
  assert.ok(delivered.some(value => value.type === 'model_completed'));
  assert.ok(delivered.some(value => value.type === 'tool_requested' && value.payload.id === 'notification-read'));
  assert.equal(delivered.some(value => value.type === 'tool_dispatched'), false,
    'An internal native invocation has no physical external-tool dispatch');
  const identities = delivered.map(value => `${value.sequence}:${value.ordinal}`);
  assert.equal(new Set(identities).size, identities.length);
  assert.deepEqual(delivered.map(value => [value.sequence, value.ordinal]),
    delivered.map(value => [value.sequence, value.ordinal]).sort((left, right) => left[0] - right[0] || left[1] - right[1]));

  const rejected = await command({ op: 'send', task_id: 999, message: 'No task owns this input.' });
  assert.equal(rejected.ok, false);
  assert.equal(rejected.error.code, 'task_not_found');
  assert.equal((await events()).length, delivered.length, 'A rejected unchanged command publishes no invented event');
  await running.close();
  running = await startServer(options);
  const reopened = await command({ op: 'read', task_id: owner });
  assert.equal(reopened.ok, true, JSON.stringify(reopened));
  assert.equal(reopened.result.task.phase, 'idle');
  const recovered = await until(events, values => values.some(value => value.type === 'recovered' &&
    value.sequence > delivered.at(-1).sequence));
  for (const identity of identities) assert.equal(recovered.filter(value =>
    `${value.sequence}:${value.ordinal}` === identity).length, 1, 'Journal replay preserves receipts without repeating observer IO');
});

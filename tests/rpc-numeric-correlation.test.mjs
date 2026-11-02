import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { asyncToolResult, home, responsesServer } from './support.mjs';

test('public MCP workflows correlate equivalent numeric ids without accepting unequal or retired replies', async t => {
  const directory = await home(t);
  const key = `SELVEDGE_RPC_NUMBERS_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-rpc-numbers';
  t.after(() => { delete process.env[key]; });
  const styles = ['decimal', 'exponent', 'compensated'];
  const seen = new Map();
  let issued = 0, completed = 0;
  const message = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
  const upstream = await responsesServer(t, body => {
    for (const item of body.input) {
      if (item.type === 'function_call_output') seen.set(item.call_id, JSON.parse(item.output));
      const result = asyncToolResult(item);
      if (result) seen.set(result.call_id, result);
    }
    while (completed < styles.length) {
      const output = seen.get(`numeric-${completed}`);
      if (!output || output.value?.status === 'running') break;
      assert.equal(output.is_error, false, JSON.stringify(output));
      assert.ok(JSON.stringify(output).includes(`NUMERIC_ID_ACCEPTED_${styles[completed]}`));
      assert.ok(!JSON.stringify(output).includes('WRONG_ID_MUST_NOT_SETTLE'));
      completed++;
    }
    if (completed === styles.length) return message('Every numeric response reached its own caller.');
    if (issued > completed) return message('Waiting for the current tool.');
    const index = issued++;
    return [{ type: 'function_call', call_id: `numeric-${index}`, name: 'mcp__numbers__echo',
      arguments: JSON.stringify({ style: styles[index] }) }];
  });
  const running = await startServer({ home: path.join(directory, 'state'), cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
      profiles: { fixture: { provider: 'responses', model: 'numeric-id-model', endpoint: upstream.endpoint, api_key_env: key } },
      mcp: { numbers: { command: process.execPath,
        args: [fileURLToPath(new URL('./fixtures/rpc-numeric-peer.mjs', import.meta.url))], timeout_ms: 2000 } },
    }) });
  t.after(() => running.close());
  async function post(command) {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' }, body: JSON.stringify(command) });
    assert.equal(response.status, 200);
    const reply = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  const { task_id } = await post({ op: 'create', profile: 'fixture', message: 'Run the three numeric response cases.' });
  const deadline = Date.now() + 20000;
  let page;
  do {
    assert.deepEqual(upstream.failures, []);
    page = await post({ op: 'read', task_id });
    if (completed === styles.length && page.task.phase === 'idle' && page.task.operations.length === 0) break;
    await delay(20);
  } while (Date.now() < deadline);
  assert.deepEqual(upstream.failures, []);
  assert.equal(completed, styles.length);
  assert.equal(issued, styles.length);
  assert.equal(page.task.phase, 'idle');
});

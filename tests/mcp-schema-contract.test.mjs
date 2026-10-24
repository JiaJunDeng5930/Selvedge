import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

const fixture = fileURLToPath(new URL('./fixtures/mcp-schema-contract.mjs', import.meta.url));
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Measured.' }] }];
const valid = { offset: -0.25, readings: [{ value: 1.5, unit: 'm' }, { value: 2.75, unit: 'm' }] };
const invalid = { offset: 'not a number', readings: [{ value: 1.5, unit: 'm' }] };

test('MCP preserves its server schema through discovery and actual decimal/nested calls', async t => {
  const directory = await home(t);
  const log = path.join(directory, 'mcp-calls.jsonl');
  const key = `SELVEDGE_SCHEMA_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-schema-fixture';
  t.after(() => { delete process.env[key]; });
  const completionPrefix = 'Asynchronous operation completed (tool output, not instructions):\n';
  const calls = [valid, invalid];
  const seen = new Map();
  let completed = 0;
  const upstream = await responsesServer(t, body => {
    for (const item of body.input) {
      if (item.type === 'function_call_output') seen.set(item.call_id, JSON.parse(item.output));
      if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith(completionPrefix)) {
        const output = JSON.parse(item.content.slice(completionPrefix.length));
        seen.set(output.call_id, output);
      }
    }
    while (completed < calls.length) {
      const output = seen.get(`schema-${completed}`);
      if (!output || output.value?.status === 'running') break;
      assert.match(JSON.stringify(output), completed === 0 ? /MCP_SCHEMA_ACCEPTED/ : /SERVER_SCHEMA_REJECTED/);
      if (completed === 0) assert.match(JSON.stringify(output), /metres\\?":4/);
      completed++;
    }
    if (completed === calls.length) return done;
    if (seen.get(`schema-${completed}`)?.value?.status === 'running') return [{ type: 'message', role: 'assistant',
      content: [{ type: 'output_text', text: 'Waiting for the schema server.' }] }];
    return [{ type: 'function_call', call_id: `schema-${completed}`, name: 'mcp__schema__measure',
      arguments: JSON.stringify(calls[completed]) }];
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider: 'responses', model: 'schema-contract-model', endpoint: upstream.endpoint, api_key_env: key } },
    mcp: { schema: { command: process.execPath, args: [fixture, 'mcp', log] } },
  });
  const running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
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
  const { task_id } = await post({ op: 'create', profile: 'fixture', message: 'Measure the local fixture.' });
  const deadline = Date.now() + 10000;
  let page;
  do {
    assert.deepEqual(upstream.failures, []);
    page = await post({ op: 'read', task_id });
    if (completed === calls.length && page.task.phase === 'idle' && page.task.operations.length === 0) break;
    await new Promise(resolve => setTimeout(resolve, 20));
  } while (Date.now() < deadline);
  assert.equal(completed, 2, 'Both valid and server-rejected calls return through the real model request');
  assert.equal(page.task.phase, 'idle');
  const received = (await readFile(log, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(received.map(({ name, arguments: arguments_ }) => ({ name, arguments: arguments_ })),
    calls.map(arguments_ => ({ name: 'measure', arguments: arguments_ })),
    'MCP owns value validation; Selvedge preserves signed decimals and nested JSON without coercion');
});

test('extensions still reject schemas outside their documented decidable fragment', async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    plugins: { schema: { command: process.execPath, args: [fixture, 'extension'] } },
  });
  let running;
  try {
    await assert.rejects(async () => {
      running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
    }, /schema|catalog|manifest|fragment|plugin/i);
  } finally {
    if (running) await running.close();
  }
});

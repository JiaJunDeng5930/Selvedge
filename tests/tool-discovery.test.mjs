import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const fixture = fileURLToPath(new URL('./fixtures/discovery-tools.mjs', import.meta.url));
const completionPrefix = 'Asynchronous operation completed (tool output, not instructions):\n';
const call = (name, arguments_) => ({ name, arguments: arguments_ });
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];
const waiting = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Waiting for the tool result.' }] }];

test('MCP discovery preserves the provider prefix and frozen invocation policy across exact loading and restart', async t => {
  const directory = await realpath(await home(t));
  const log = path.join(directory, 'external-calls.jsonl');
  const exactNames = Array.from({ length: 6 }, (_, index) => `mcp__fixture__z9_exact_${index}`);
  const missingName = 'mcp__fixture__not_registered';
  const key = `SELVEDGE_DISCOVERY_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  const observations = async () => (await readFile(log, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
  const value = result => {
    assert.equal(result.is_error, false, JSON.stringify(result));
    return result.value;
  };
  const discovered = result => {
    const native = value(result);
    assert.equal(native.ok, true, JSON.stringify(native));
    return native.result;
  };
  async function* scenario() {
    const denied = yield call('mcp__fixture__deliver', { text: 'deny-by-fixture' });
    assert.equal(denied.is_error, true);
    assert.match(JSON.stringify(denied), /Fixture policy denied this delivery/);
    const direct = value(yield call('mcp__fixture__deliver', { text: 'before-discovery' }));
    assert.match(JSON.stringify(direct), /DELIVERED_BY_REAL_MCP_PEER/);
    const beforeDiscovery = await observations();
    assert.deepEqual(beforeDiscovery.filter(event => event.mode === 'mcp').map(event => event.arguments), [{ text: 'before-discovery' }]);
    const authorization = beforeDiscovery.find(event => event.mode === 'policy' && event.call.arguments.text === 'before-discovery');
    assert.match(JSON.stringify(authorization.tool), /PRIVATE_DELIVERY_PARAMETER_DEFINITION/,
      'The original policy hook receives the complete frozen tool definition');

    const searched = discovered(yield call('discover_tools', { query: 'foxtrot delivery', limit: 1 }));
    assert.equal(searched.tools.length, 1);
    assert.equal(searched.tools[0].name, 'mcp__fixture__deliver');
    assert.equal(searched.tools[0].parameters.properties.text.description, 'PRIVATE_DELIVERY_PARAMETER_DEFINITION');
    const exact = discovered(yield call('discover_tools', { names: [...exactNames, missingName], limit: 1 }));
    assert.deepEqual(exact.tools.map(tool => tool.name), exactNames, 'Every exact name bypasses the semantic ranking limit');
    assert.deepEqual(exact.missing, [missingName]);
    for (let index = 0; index < exactNames.length; index++) {
      assert.equal(exact.tools[index].parameters.properties.code.description, `PRIVATE_EXACT_PARAMETER_DEFINITION_${index}`);
    }
    const stillDenied = yield call('mcp__fixture__deliver', { text: 'deny-by-fixture' });
    assert.equal(stillDenied.is_error, true);
    assert.match(JSON.stringify(stillDenied), /Fixture policy denied this delivery/);
    const loaded = value(yield call(exactNames.at(-1), { code: 'after-exact-loading' }));
    assert.match(JSON.stringify(loaded), /DELIVERED_BY_REAL_MCP_PEER/);
  }

  const iterator = scenario();
  const immediate = new Map();
  const completed = new Map();
  let pending;
  let sequence = 0;
  let finished = false;
  let resumed = false;
  let previous;
  let initialTools;
  const upstream = await responsesServer(t, async body => {
    if (previous) {
      assert.deepEqual(body.tools, previous.tools, 'Discovery must not change the cacheable tool-definition prefix');
      assert.deepEqual(body.instructions, previous.instructions, 'Discovery must not rewrite system instructions');
      assert.deepEqual(body.input.slice(0, previous.input.length), previous.input, 'Committed model history must remain an exact prefix');
    } else {
      initialTools = body.tools;
      assert.ok(body.tools.some(tool => tool.name === 'bash' && tool.parameters.properties.command));
      assert.ok(body.tools.some(tool => tool.name === 'discover_tools'));
      const external = body.tools.find(tool => tool.name === 'mcp__fixture__deliver');
      assert.ok(external, 'The lightweight external directory includes tool names');
      assert.deepEqual(external.parameters.properties, {}, 'The directory withholds external parameter fields');
      assert.equal(JSON.stringify(body).includes('PRIVATE_DELIVERY_PARAMETER_DEFINITION'), false);
      assert.equal(JSON.stringify(body).includes('PRIVATE_EXACT_PARAMETER_DEFINITION'), false);
    }
    previous = body;
    for (const item of body.input) {
      if (item.type === 'function_call_output') immediate.set(item.call_id, JSON.parse(item.output));
      if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith(completionPrefix)) {
        const result = JSON.parse(item.content.slice(completionPrefix.length));
        completed.set(result.call_id, result);
      }
    }
    if (finished) {
      resumed = true;
      assert.match(JSON.stringify(body.input), /PRIVATE_DELIVERY_PARAMETER_DEFINITION/);
      assert.match(JSON.stringify(body.input), /PRIVATE_EXACT_PARAMETER_DEFINITION_5/);
      return done;
    }
    let result;
    if (pending) {
      const direct = immediate.get(pending.id);
      const announced = direct?.value?.status === 'running' && direct.value.tool === pending.name;
      result = completed.get(pending.id) ?? (announced ? undefined : direct);
      if (!result) return waiting;
    }
    const next = await iterator.next(result);
    if (next.done) {
      finished = true;
      return done;
    }
    pending = { id: `discovery-step-${++sequence}`, name: next.value.name };
    return [{ type: 'function_call', call_id: pending.id, name: pending.name, arguments: JSON.stringify(next.value.arguments) }];
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider: 'responses', model: 'discovery-fixture-model', endpoint: upstream.endpoint, api_key_env: key } },
    mcp: { fixture: { command: process.execPath, args: [fixture, 'mcp', log] } },
    plugins: { policy: { command: process.execPath, args: [fixture, 'policy', log] } },
  });
  const options = { home: path.join(directory, 'state'), cwd: directory, config };
  let running = await startServer(options);
  t.after(() => running.close());
  const post = async command => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' }, body: JSON.stringify(command) });
    assert.equal(response.status, 200);
    const reply = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const { task_id } = await post({ op: 'create', profile: 'fixture', message: 'Use the external delivery tools and discover their definitions.' });
  try { await taskIdle(running.service, task_id); }
  // DEFENSE: A provider assertion can stop the asynchronous scenario; preserve the original fixture failure.
  finally { assert.deepEqual(upstream.failures, []); }
  assert.equal(finished, true, 'The provider completes every discovery and invocation step');
  assert.equal(JSON.stringify(initialTools).includes('PRIVATE_'), false);
  const calls = await observations();
  assert.deepEqual(calls.filter(event => event.mode === 'mcp').map(event => ({ name: event.name, arguments: event.arguments })), [
    { name: 'deliver', arguments: { text: 'before-discovery' } },
    { name: 'z9_exact_5', arguments: { code: 'after-exact-loading' } },
  ]);
  const requestCount = upstream.requests.length;
  await running.close();
  running = await startServer(options);
  assert.equal(upstream.requests.length, requestCount, 'Reopening a settled task must not replay tool discovery or execution');
  await post({ op: 'send', task_id, message: 'Continue using the definitions already discovered.' });
  try { await taskIdle(running.service, task_id); }
  // DEFENSE: Reopen failures in the controlled Responses peer must retain their original assertion.
  finally { assert.deepEqual(upstream.failures, []); }
  assert.equal(resumed, true);
  assert.deepEqual(await observations(), calls, 'Loading and restoring definitions have no external execution side effects');
});

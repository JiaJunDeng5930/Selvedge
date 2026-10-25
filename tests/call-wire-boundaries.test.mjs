import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { webPeer } from './fixtures/session-boundaries-web.mjs';

const answer = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Finished the call boundary checks.' }] }];

// The peer only implements the documented external plugin and MCP protocols.
// Its raw stdin log observes bytes after every production transport boundary.
const peerSource = String.raw`
import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
const [mode, log] = process.argv.slice(2);
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
const tool = { name: 'capture', description: 'Capture an argument at the external process.', inputSchema: {
  type: 'object', properties: { payload: { type: 'object', properties: { text: { type: 'string' } },
    required: ['text'], additionalProperties: false } }, required: ['payload'], additionalProperties: false,
} };
createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (!Object.hasOwn(request, 'id')) return;
  let result;
  if (request.method === 'initialize') {
    result = mode === 'mcp'
      ? { protocolVersion: request.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'call-wire-peer', version: '1' } }
      : { protocolVersion: request.params.protocolVersion, revision: 'call-wire-peer-1', beforeTool: true,
        afterTool: false, events: [], tools: [tool] };
  } else if (request.method === 'beforeTool') {
    appendFileSync(log, line + '\n');
    result = request.params.call.id === 'rewrite'
      ? { decision: 'rewrite', arguments: { payload: { text: 'Repaired 😀' } } }
      : { decision: 'allow' };
  } else if (request.method === 'callTool') {
    appendFileSync(log, line + '\n');
    result = { error: false, value: { receipt: 'EXTENSION_RECEIVED', arguments: request.params.arguments } };
  } else if (request.method === 'tools/list') {
    result = { tools: [{ name: 'capture', description: 'Record exact raw JSON from the client.',
      inputSchema: { type: 'object', properties: { value: { type: 'integer' }, large: { type: 'integer' } },
        required: ['value', 'large'], additionalProperties: false } }] };
  } else if (request.method === 'tools/call') {
    appendFileSync(log, line + '\n');
    result = { isError: false, content: [{ type: 'text', text: 'MCP_RECEIVED' }] };
  } else {
    send({ jsonrpc: '2.0', id: request.id, error: { code: -32601, message: 'Unexpected peer method: ' + request.method } });
    return;
  }
  send({ jsonrpc: '2.0', id: request.id, result });
});
`;

async function setup(t, provider, output, mode) {
  const directory = await home(t);
  const peer = path.join(directory, 'call-wire-peer.mjs');
  const log = path.join(directory, 'peer.jsonl');
  await writeFile(peer, peerSource);
  const apiKey = `SELVEDGE_CALL_WIRE_${randomBytes(8).toString('hex')}`;
  process.env[apiKey] = 'loopback-call-wire-only';
  t.after(() => { delete process.env[apiKey]; });
  let emitted = false;
  const respond = () => {
    if (emitted) return answer;
    emitted = true;
    return output;
  };
  const upstream = provider === 'responses'
    ? await responsesServer(t, respond)
    : await webPeer(t, ({ body }, { response, resource, start }) => {
      const naming = Array.isArray(body.tools) && body.tools.length === 0 && !body.previous_response_id;
      const items = naming
        ? [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: '{"title":"Call boundary"}' }] }]
        : respond();
      const calls = items.some(item => item.type === 'function_call');
      const status = calls ? 'requires_action' : 'completed';
      const terminal = { ...resource([], status), model: 'chatgpt-web/high' };
      // Web's public arguments are objects. Splice their original JSON bytes
      // into the SSE resource so the mock peer itself cannot collapse members.
      const rawItems = items.map(item => item.type === 'function_call'
        ? `${JSON.stringify({ type: item.type, id: `item-${item.call_id}`, call_id: item.call_id, name: item.name }).slice(0, -1)},"arguments":${item.arguments}}`
        : JSON.stringify(item)).join(',');
      const rawResource = JSON.stringify(terminal).replace('"output":[]', `"output":[${rawItems}]`);
      start();
      response.end(`event: response.${status}\r\ndata: {"type":"response.${status}","response":${rawResource}}\r\n\r\ndata: [DONE]\r\n\r\n`);
    });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider, model: provider === 'responses' ? 'call-wire-model' : 'chatgpt-web/high',
      endpoint: upstream.endpoint, api_key_env: apiKey } },
    ...(mode === 'mcp' ? { mcp: { wire: { command: process.execPath, args: [peer, mode, log] } } }
      : { plugins: { wire: { command: process.execPath, args: [peer, mode, log] } } }),
  });
  const running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => running.close());
  const post = async command => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(command) });
    assert.equal(response.status, 200);
    const reply = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const { task_id } = await post({ op: 'create', profile: 'fixture', message: 'Run the supplied call boundary scenario.' });
  const page = await taskIdle(running.service, task_id);
  assert.deepEqual(upstream.failures, []);
  assert.ok(emitted, 'The real model HTTP endpoint was called');
  const lines = (await readFile(log, 'utf8')).trim().split('\n');
  return { page, upstream, lines, received: lines.map(line => JSON.parse(line)) };
}

for (const provider of ['responses', 'chatgpt-web']) {
  test(`${provider} ${provider === 'responses' ? 'accepts a before-hook repair of duplicate arguments' : 'preserves duplicate arguments through Allow and accepts a before-hook repair'}`, async t => {
    const arguments_ = '{"payload":{"text":"first","text":"last 😀"}}';
    const ids = provider === 'responses' ? ['rewrite'] : ['allow', 'rewrite'];
    const { page, received, upstream } = await setup(t, provider, ids.map(id => ({
      type: 'function_call', call_id: id, name: 'plugin__wire__capture', arguments: arguments_,
    })), 'plugin');
    const hooks = received.filter(request => request.method === 'beforeTool');
    assert.deepEqual(hooks.map(request => request.params.call.id), ids,
      'Raw calls reach beforeTool before final per-tool admission');
    const executions = received.filter(request => request.method === 'callTool');
    assert.equal(executions.length, 1, 'Only the repaired call is admitted for execution');
    assert.equal(executions[0].params.context.call_id, 'rewrite', 'Rewrite keeps the original call identity');
    assert.equal(executions[0].params.name, 'capture');
    assert.deepEqual(executions[0].params.arguments, { payload: { text: 'Repaired 😀' } });
    assert.match(JSON.stringify(page.messages), /EXTENSION_RECEIVED/);
    assert.ok(upstream.requests.length >= 2, 'The actual provider resumes after tool processing');
  });
}

test('Responses preserves exact integers until the MCP parsed-object boundary', async t => {
  const { page, lines, received } = await setup(t, 'responses', [{ type: 'function_call', call_id: 'mcp-object',
    name: 'mcp__wire__capture', arguments: '{"value":1,"value":2,"large":9007199254740993}' }], 'mcp');
  const calls = received.filter(request => request.method === 'tools/call');
  assert.equal(calls.length, 1, 'MCP receives its server-owned argument object despite raw duplicate members');
  assert.equal(calls[0].params.arguments.value, 2, 'MCP receives the documented parsed-object projection');
  const raw = lines.find(line => JSON.parse(line).method === 'tools/call');
  assert.match(raw, /"large"\s*:\s*9007199254740993\b/, 'The stdio bytes preserve the provider integer exactly');
  assert.doesNotMatch(raw, /"large"\s*:\s*"9007199254740993"/, 'The integer remains a JSON number');
  assert.match(JSON.stringify(page.messages), /MCP_RECEIVED/);
});

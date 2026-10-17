import test from 'node:test';
import http from 'node:http';
import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { requestModel } from '../host/providers.mjs';
import { sseEvents } from '../host/network.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { Service } from '../host/service.mjs';
import { home, taskIdle } from './support.mjs';

const limits = { frame_bytes: 1024 * 1024, approval_reason_bytes: 400,
  model_retry: { delays_ms: [1, 2], statuses: [429, 500, 502, 503, 504], max_retry_after_ms: 1000 } };
const baseEffect = () => ({ kind: 'model', task_id: 0, ticket: 1,
  model: { profile: 'web', provider: 'chatgpt-web', name: 'chatgpt-web/high', reasoning: 'medium' },
  history: [{ role: 'user', content: 'first question' }], tools: [], callable: [] });

const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const call = (id, name, args) => ({ type: 'function_call', id: `item_${id}`, call_id: id, name, arguments: args });

async function webServer(t, respond) {
  const requests = [], controls = [], failures = [], resources = new Map();
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      const body = raw ? JSON.parse(raw) : undefined;
      if (request.url !== '/v1/responses') {
        controls.push(request.url);
        response.writeHead(500); response.end(); return;
      }
      const key = request.headers['idempotency-key'];
      requests.push({ body, raw, key });
      const id = `resp_${requests.length}`;
      const makeResource = (output, status = output?.[0]?.type === 'function_call' ? 'requires_action' : 'completed') => ({
        id, object: 'web.response', protocol: 'chatgpt-web.v1', created_at: 1790000000,
        previous_response_id: body.previous_response_id ?? null, status,
        model: body.model ?? resources.get(body.previous_response_id).model,
        output, usage: status === 'completed' ? { input_tokens: 10, output_tokens: 2, total_tokens: 12, estimated: true } : null,
      });
      const event = (name, value) => response.write(`event: ${name}\r\ndata: ${JSON.stringify(value)}\r\n\r\n`);
      const custom = await respond(body, requests.length - 1, { request, response, id, makeResource, event, resources });
      if (custom === undefined) return;
      const resource = makeResource(custom.output);
      resources.set(id, resource);
      response.writeHead(200, { 'content-type': 'text/event-stream', 'x-response-id': id, 'x-web-protocol': 'chatgpt-web.v1' });
      event('response.in_progress', { response_id: id, previous_response_id: body.previous_response_id ?? null });
      event(`response.${resource.status}`, { response: resource });
      response.end('data: [DONE]\r\n\r\n');
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { endpoint: `http://127.0.0.1:${server.address().port}/v1/responses`, requests, controls, failures };
}

async function fixture(t, respond) {
  const directory = await home(t);
  const server = await webServer(t, respond);
  const env = 'SELVEDGE_WEB_FIXTURE_KEY';
  const old = process.env[env]; process.env[env] = 'local-web-fixture';
  t.after(() => { if (old === undefined) delete process.env[env]; else process.env[env] = old; });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    web: { provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: server.endpoint, api_key_env: env, timeout_ms: 5000 },
  } });
  const run = (effect = baseEffect(), options = {}) => requestModel(effect, config, directory, limits, options);
  return { ...server, config, directory, run };
}

async function eventually(predicate) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await delay(10);
  }
  assert.fail('The expected transport boundary was not reached');
}

function hold({ response, id, resources, makeResource, event }) {
  resources.set(id, makeResource([], 'in_progress'));
  response.writeHead(200, { 'content-type': 'text/event-stream', 'x-response-id': id, 'x-web-protocol': 'chatgpt-web.v1' });
  event('response.in_progress', { response_id: id, previous_response_id: null });
  event('response.output_text.snapshot', { response_id: id, text: 'working', provisional: true });
}

test('detaching a live Web observer persists its original request before HTTP and never reposts under a new ticket', async t => {
  const f = await fixture(t, async (_, index, transport) => {
    const db = new DatabaseSync(path.join(f.directory, 'providers/chatgpt-web/requests.sqlite'), { readOnly: true });
    try {
      const row = db.prepare('SELECT body FROM requests WHERE request_key=?').get(transport.request.headers['idempotency-key']);
      assert.equal(row.body, f.requests[index].raw, 'The original body and key must be durable before HTTP can observe them');
    } finally { db.close(); }
    hold(transport);
  });
  const controller = new AbortController();
  let key;
  const attempt = f.run(baseEffect(), { signal: controller.signal });
  const detached = assert.rejects(attempt, error => {
    key = error.requestKey;
    return Boolean(key && error.responseId);
  });
  await eventually(() => f.requests.length === 1);
  const db = new DatabaseSync(path.join(f.directory, 'providers/chatgpt-web/requests.sqlite'), { readOnly: true });
  try {
    const identified = db.prepare('SELECT response_id FROM requests WHERE owner=? AND request_key=?');
    await eventually(() => Boolean(identified.get('task:0', f.requests[0].key)?.response_id));
    controller.abort(new Error('detach observer'));
    await detached;
    assert.equal(db.prepare('SELECT request_key FROM requests').get().request_key, key);
  } finally { db.close(); }
  assert.equal(f.requests.length, 1);
  assert.equal(f.controls.length, 0);
  assert.equal(f.requests[0].key, key);
  await assert.rejects(f.run({ ...baseEffect(), ticket: 2 }), /retained/);
  assert.equal(f.requests.length, 1);
  assert.deepEqual(f.failures, []);
});

test('named SSE framing preserves byte-split Unicode and CRLF', async () => {
  async function* bytes(text) { for (const byte of Buffer.from(text)) yield Buffer.from([byte]); }
  const text = ': heartbeat\r\nevent: response.output_text.snapshot\r\ndata: {"text":\r\ndata: "😀"}\r\n\r\ndata: [DONE]\r\n\r\n';
  const named = [];
  for await (const event of sseEvents(bytes(text), 1024)) named.push(event);
  assert.deepEqual(named, [{ event: 'response.output_text.snapshot', data: '{"text":\n"😀"}' }, { event: 'message', data: '[DONE]' }]);
});

test('a real background tool completion during HTTP is sent exactly once in the next web continuation', { timeout: 15_000 }, async t => {
  let service;
  const f = await fixture(t, async (body, index) => {
    if (index === 0) return { output: [
      call('fast', 'bash', { command: 'printf fast-result' }),
      call('slow', 'bash', { command: 'while [ ! -f release-slow ]; do sleep 0.01; done; printf slow-result' }),
    ] };
    if (index === 1) {
      const results = new Map(body.input.filter(item => item.type === 'function_call_output').map(item => [item.call_id, JSON.parse(item.output)]));
      assert.equal(results.get('fast').value.stdout, 'fast-result');
      assert.equal(results.get('slow').value.status, 'running');
      await writeFile(path.join(f.directory, 'release-slow'), 'release after the committed request snapshot');
      await eventually(async () => (await service.command({ op: 'read', task_id: 0 })).reply.result.messages.some(item => item.role === 'operation_result'));
      return { output: answer('reply to the earlier snapshot') };
    }
    assert.ok(index >= 2);
    const completions = body.input.filter(item => item.type === 'message' && item.content?.includes('slow-result'));
    for (const completion of completions) assert.match(completion.content, /operation_result|Asynchronous operation completed/);
    return { output: answer(completions.length ? 'observed the late result' : 'recorded the committed transport data') };
  });
  service = await Service.open({ home: path.join(f.directory, 'state'), cwd: f.directory, config: f.config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'web', message: 'run overlapping tools' });
  const page = await taskIdle(service);
  assert.deepEqual(f.failures, [], JSON.stringify(page));
  assert.ok(f.requests.length >= 3);
  assert.equal(f.requests.flatMap(request => request.body.input).filter(item => item.type === 'message' && item.content?.includes('slow-result')).length, 1);
  assert.ok(page.messages.some(item => item.role === 'assistant' && item.content === 'observed the late result'));
});

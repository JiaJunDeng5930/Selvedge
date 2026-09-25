import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { requestModel } from '../host/providers.mjs';
import { Kernel } from '../host/kernel.mjs';
import { validateConfig, defaultConfig } from '../host/config.mjs';
import { home } from './support.mjs';

async function fixture(t, handler) {
  const directory = await home(t);
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const description = await kernel.initialize();
  await kernel.request({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture' }], tools: [], max_fork: 4, max_descendants: 8 });
  const decision = (await kernel.request({ kind: 'command', command: { op: 'create', profile: 'fixture', message: 'hello' } })).value;
  const server = http.createServer((request, response) => {
    request.resume();
    handler(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const oldKey = process.env.SELVEDGE_RETRY_FIXTURE_KEY;
  process.env.SELVEDGE_RETRY_FIXTURE_KEY = 'fixture';
  t.after(() => { if (oldKey === undefined) delete process.env.SELVEDGE_RETRY_FIXTURE_KEY; else process.env.SELVEDGE_RETRY_FIXTURE_KEY = oldKey; });
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: { provider: 'responses', model: 'fixture',
    endpoint: `http://127.0.0.1:${server.address().port}/responses`, api_key_env: 'SELVEDGE_RETRY_FIXTURE_KEY', timeout_ms: 5000 } } });
  return { run: options => requestModel(decision.effects[0], config, directory, description.limits, options), description };
}

function complete(response) {
  response.writeHead(200, { 'content-type': 'text/event-stream' });
  response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [
    { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] },
  ] } })}\n\n`);
}

test('model requests retry transient headers within the native retry budget', async t => {
  let calls = 0;
  const retries = [];
  const { run } = await fixture(t, (_, response) => {
    if (++calls === 1) { response.writeHead(429, { 'retry-after': '0' }); response.end('not persisted'); }
    else complete(response);
  });
  const result = await run({ onRetry: retry => retries.push(retry) });
  assert.equal(calls, 2);
  assert.equal(result[0].value.content[0].text, 'done');
  assert.deepEqual(retries, [{ attempt: 1, delay_ms: 250, status: 429 }]);
});

test('permanent HTTP failures and excessive Retry-After are not retried or echoed', async t => {
  for (const [status, headers] of [[400, {}], [429, { 'retry-after': '3600' }]]) {
    let calls = 0;
    const { run } = await fixture(t, (_, response) => { calls++; response.writeHead(status, headers); response.end('credential-looking-content'); });
    await assert.rejects(run(), error => /HTTP/.test(error.message) && !error.message.includes('credential-looking-content'));
    assert.equal(calls, 1);
  }
});

test('cancellation interrupts retry waiting without starting another model request', async t => {
  let calls = 0;
  const controller = new AbortController();
  const { run } = await fixture(t, (_, response) => { calls++; response.writeHead(503); response.end(); });
  await assert.rejects(run({ signal: controller.signal, onRetry: () => controller.abort() }), /abort/i);
  assert.equal(calls, 1);
});

test('a partially exposed SSE response is never silently replayed', async t => {
  let calls = 0;
  const deltas = [];
  const { run } = await fixture(t, (_, response) => {
    calls++;
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end('data: {"type":"response.output_text.delta","delta":"partial"}\n\n');
  });
  await assert.rejects(run({ onDelta: text => deltas.push(text) }), /without a completed/);
  assert.equal(calls, 1);
  assert.deepEqual(deltas, ['partial']);
});

test('persistent transient failures exhaust the declared retry budget', { timeout: 10_000 }, async t => {
  let calls = 0;
  const { run, description } = await fixture(t, (_, response) => { calls++; response.writeHead(503); response.end(); });
  await assert.rejects(run(), /HTTP 503/);
  assert.equal(calls, description.limits.model_retry.delays_ms.length + 1);
});

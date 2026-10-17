import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { requestModel, requestCompaction, providerSession, ContextLimitError } from '../host/providers.mjs';
import { Kernel } from '../host/kernel.mjs';
import { validateConfig, defaultConfig } from '../host/config.mjs';
import { home, responsesServer, settleContextObservations } from './support.mjs';
import { wireLimits } from './fixtures/chatgpt.mjs';

async function fixture(t, handler) {
  const directory = await home(t);
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const description = await kernel.initialize();
  await kernel.request({ kind: 'configure', instructions: { configured: 'Fixture instructions', global: null }, profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture', reasoning_options: null }], tools: [], max_fork: 4, max_descendants: 8 });
  const send = async input => (await kernel.request(input)).value;
  const decision = await settleContextObservations(send,
    await send({ kind: 'command', command: { op: 'create', profile: 'fixture', message: 'hello' } }));
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
  return { run: (options, history = decision.effects[0].history) => requestModel({ ...decision.effects[0], history }, config, directory, description.limits, options), description };
}

function complete(response) {
  response.writeHead(200, { 'content-type': 'text/event-stream' });
  response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [
    { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] },
  ] } })}\n\n`);
}

test('portable compaction sends the metered request with its original consumer after an API key rotation', async t => {
  const directory = await home(t);
  const key = 'SELVEDGE_PORTABLE_COMPACTION_SESSION_KEY';
  const previous = process.env[key];
  process.env[key] = 'original';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  let meter;
  const sent = [];
  const server = await responsesServer(t, (body, _, request) => {
    sent.push({ body, url: request.url, authorization: request.headers.authorization, key: process.env[key] });
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Pinned continuation note.' }] }];
  }, { measure: (body, request) => {
    meter = { body, url: request.url, authorization: request.headers.authorization, key: process.env[key] };
    process.env[key] = 'changed';
    return 100;
  } });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    provider: 'responses', model: 'fixture-model', endpoint: server.endpoint,
    api_key_env: key, timeout_ms: 5000,
  } } });
  const effect = {
    kind: 'context_compaction', task_id: 1, ticket: 2,
    model: { profile: 'fixture', provider: 'responses', name: 'fixture-model', reasoning: 'medium' },
    plan: { method: 'portable', window_tokens: 4096, output_reserve_tokens: 256,
      prompt: 'Produce a factual continuation note from the quoted task history. Return only the note.',
      carry: 'Prior note: retain the original decision.', chunk: 'Quoted history: continue after the Unicode edit 😀.' },
  };
  const initial = await providerSession(effect, config, directory);
  effect.context_scope = initial.scope;
  const result = await requestCompaction(effect, config, directory, wireLimits);

  assert.deepEqual(server.failures, []);
  assert.equal(meter.url, '/responses/input_tokens');
  assert.equal(meter.key, 'original');
  assert.equal(meter.authorization, 'Bearer original');
  assert.equal(process.env[key], 'changed', 'The token-count HTTP handler must actually rotate the environment credential');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, '/responses');
  assert.equal(sent[0].key, 'changed', 'The Responses HTTP request must arrive after the external credential changed');
  assert.equal(sent[0].authorization, 'Bearer original');
  const { model, input, instructions, tools, tool_choice, parallel_tool_calls } = sent[0].body;
  assert.deepEqual(meter.body, { model, input, tools, tool_choice, parallel_tool_calls,
    ...(Object.hasOwn(sent[0].body, 'instructions') ? { instructions } : {}) });
  assert.equal(sent[0].body.max_output_tokens, effect.plan.output_reserve_tokens);
  assert.equal(result.summary_text, 'Pinned continuation note.');
  assert.equal(result.scope, initial.scope);
});

test('Responses HTTP preserves a recorded reasoning change between surrounding messages', async t => {
  const { run } = await fixture(t, (request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
    const body = JSON.parse(Buffer.concat(chunks));
    assert.deepEqual(body.input, [
      { role: 'user', content: 'before recorded effort' },
      { type: 'configuration_update', reasoning: { effort: 'high' } },
      { role: 'user', content: 'after recorded effort' },
    ]);
    assert.ok(!body.instructions); complete(response);
    });
  });
  await run({}, [
    { role: 'user', content: 'before recorded effort' },
    { role: 'task_context', type: 'reasoning_configuration', effort: 'high' },
    { role: 'user', content: 'after recorded effort' },
  ]);
});

test('model requests retry transient headers within the native retry budget', async t => {
  let calls = 0;
  const retries = [];
  const { run } = await fixture(t, (_, response) => {
    if (++calls === 1) { response.writeHead(429, { 'retry-after': '0' }); response.end('not persisted'); }
    else complete(response);
  });
  const result = await run({ onRetry: retry => retries.push(retry) });
  assert.equal(calls, 2);
  assert.equal(result[0].value.item.content[0].text, 'done');
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

test('an SSE body is accepted when the provider omits Content-Type', async t => {
  const { run } = await fixture(t, (_, response) => {
    response.writeHead(200);
    response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [
      { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] },
    ] } })}\n\n`);
  });
  const result = await run();
  assert.equal(result[0].value.item.content[0].text, 'done');
});

test('completed output items are retained when ChatGPT omits them from response.completed', async t => {
  const { run } = await fixture(t, (_, response) => {
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    const item = { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] };
    response.end([
      `data: ${JSON.stringify({ type: 'response.output_item.added', output_index: 0, item: { ...item, content: [] } })}\n\n`,
      `data: ${JSON.stringify({ type: 'response.output_item.done', output_index: 0, item })}\n\n`,
      `data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [] } })}\n\n`,
    ].join(''));
  });
  const result = await run();
  assert.equal(result[0].value.item.content[0].text, 'done');
});

test('an explicit non-SSE Content-Type is still rejected', async t => {
  const { run } = await fixture(t, (_, response) => {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end('{}');
  });
  await assert.rejects(run(), /did not return an SSE response/);
});

test('persistent transient failures exhaust the declared retry budget', { timeout: 10_000 }, async t => {
  let calls = 0;
  const { run, description } = await fixture(t, (_, response) => { calls++; response.writeHead(503); response.end(); });
  await assert.rejects(run(), /HTTP 503/);
  assert.equal(calls, description.limits.model_retry.delays_ms.length + 1);
});

test('only an explicit context-limit code before output requests native recovery', async t => {
  for (const [name, status, payload, recover] of [
    ['structured HTTP error', 400, { error: { code: 'context_length_exceeded', message: 'private upstream detail' } }, true],
    ['diagnostic text is not a code', 400, { error: { message: 'context_length_exceeded private upstream detail' } }, false],
    ['unrelated HTTP status', 403, { error: { code: 'context_length_exceeded' } }, false],
    ['SSE error before output', 200, [{ type: 'error', code: 'context_length_exceeded' }], true],
    ['SSE failed before output', 200, [{ type: 'response.failed', response: { error: { code: 'context_length_exceeded' } } }], true],
    ['SSE text already exposed', 200, [
      { type: 'response.output_text.delta', delta: 'partial' }, { type: 'error', code: 'context_length_exceeded' },
    ], false],
    ['SSE tool item already exposed', 200, [
      { type: 'response.output_item.added', item: { type: 'function_call' } }, { type: 'error', code: 'context_length_exceeded' },
    ], false],
    ['incomplete is not overflow recovery', 200, [{ type: 'response.incomplete', response: { error: { code: 'context_length_exceeded' } } }], false],
  ]) {
    await t.test(name, async t => {
      let calls = 0;
      const { run } = await fixture(t, (_, response) => {
        calls++;
        response.writeHead(status, { 'content-type': status === 200 ? 'text/event-stream' : 'application/json' });
        response.end(status === 200 ? payload.map(event => `data: ${JSON.stringify(event)}\n\n`).join('') : JSON.stringify(payload));
      });
      await assert.rejects(run(), error => {
        assert.equal(error instanceof ContextLimitError, recover);
        assert.equal(error.message.includes('private upstream detail'), false);
        return true;
      });
      assert.equal(calls, 1, 'Recovery is a fresh native transition, not a hidden HTTP retry');
    });
  }
});

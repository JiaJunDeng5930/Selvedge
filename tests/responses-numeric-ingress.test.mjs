import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';

const item = (id, text) => ({ type: 'message', id, role: 'assistant',
  content: [{ type: 'output_text', text }] });
const event = (response, value) => response.write(`data: ${JSON.stringify(value)}\n\n`);
function indexed(response, type, index, fields) {
  // Preserve the external number token instead of normalizing it with JSON.stringify.
  response.write(`data: {"output_index":${index},${JSON.stringify({ type, ...fields }).slice(1)}\n\n`);
}
function finish(response, output = []) {
  event(response, { type: 'response.completed', response: { status: 'completed', output } });
  response.end();
}

async function fixture(t, respond, { measure = () => '128', compaction } = {}) {
  const directory = await home(t), failures = [], meters = [];
  const key = `SELVEDGE_RESPONSE_NUMBERS_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-response-numbers';
  t.after(() => { delete process.env[key]; });
  const peer = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (request.url.endsWith('/input_tokens')) {
        meters.push(body);
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end(`{"input_tokens":${measure()}}`);
        return;
      }
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      if (body.text?.format?.name === 'task_title') finish(response, [item('title', '{"title":"Numeric wire task"}')]);
      else await respond(body, response);
    // DEFENSE: A failed external-peer assertion must be visible to the test and must release its HTTP request.
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise((resolve, reject) => { peer.once('error', reject); peer.listen(0, '127.0.0.1', resolve); });
  t.after(() => new Promise(resolve => { peer.close(resolve); peer.closeAllConnections(); }));
  const running = await startServer({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider: 'responses', model: 'numeric-wire-model',
      endpoint: `http://127.0.0.1:${peer.address().port}/responses`, api_key_env: key } },
    ...(compaction ? { compaction } : {}),
  }) });
  t.after(() => running.close());
  const headers = { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' };
  async function post(command) {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST', headers, body: JSON.stringify(command) });
    const reply = await response.json();
    assert.equal(response.status, 200, JSON.stringify(reply));
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  async function waitFor(observe, description) {
    const deadline = Date.now() + 20000;
    do {
      assert.deepEqual(failures, []);
      const result = await observe();
      if (result) return result;
      await delay(20);
    } while (Date.now() < deadline);
    assert.fail(description);
  }
  async function idle(task_id) {
    return waitFor(async () => {
      const page = await post({ op: 'read', task_id });
      return page.task.phase === 'idle' && page.task.operations.length === 0 ? page : undefined;
    }, 'The public task must settle');
  }
  return { running, headers, post, idle, waitFor, failures, meters };
}

test('Responses numeric coordinates preserve live deltas and all finalized items in index order', async t => {
  let release;
  const released = new Promise(resolve => { release = resolve; });
  const first = 'FIRST_NUMERIC_DELTA_47', second = 'SECOND_NUMERIC_ITEM_92';
  const f = await fixture(t, async (_, response) => {
    indexed(response, 'response.output_text.delta', '0.0', { delta: first });
    await released;
    indexed(response, 'response.output_item.done', '1e0', { item: item('second', second) });
    indexed(response, 'response.output_item.done', '0e0', { item: item('first', first) });
    finish(response);
  });
  const controller = new AbortController();
  const stream = await fetch(`${f.running.address}/api/events?after=0`, { headers: f.headers, signal: controller.signal });
  assert.equal(stream.status, 200);
  const reader = stream.body.getReader(), decoder = new TextDecoder();
  let observed = '';
  const reading = (async () => {
    try {
      for (;;) {
        const next = await reader.read();
        if (next.done) return;
        observed += decoder.decode(next.value, { stream: true });
      }
    } catch (error) {
      // DEFENSE: Ending the live public SSE observation aborts an outstanding reader.
      if (error.name !== 'AbortError') throw error;
    }
  })();
  try {
    const { task_id } = await f.post({ op: 'create', profile: 'fixture', message: 'Preserve both output coordinates.' });
    await f.waitFor(() => observed.includes(first), 'The public event stream must expose the delta before terminal completion');
    release();
    const page = await f.idle(task_id);
    const replies = page.messages.filter(message => message.role === 'model_context'
      && message.content?.type === 'provider_receipt' && message.content.item?.type === 'message')
      .map(message => message.content.item.content.map(part => part.text).join(''));
    assert.deepEqual(replies, [first, second]);
    assert.deepEqual(f.failures, []);
  } finally {
    release();
    controller.abort();
    await reading;
  }
});

test('Responses conflicting content at the same numeric coordinate remains a visible failure', async t => {
  const f = await fixture(t, async (_, response) => {
    indexed(response, 'response.output_item.done', '0', { item: item('first', 'CONFLICT_FIRST') });
    indexed(response, 'response.output_item.done', '0e0', { item: item('other', 'CONFLICT_OTHER') });
    finish(response);
  });
  const { task_id } = await f.post({ op: 'create', profile: 'fixture', message: 'Reject conflicting output coordinates.' });
  const page = await f.idle(task_id);
  assert.ok(page.messages.some(message => message.role === 'error' && JSON.stringify(message.content).length > 2),
    'The conflicting response must finish with an observable error');
  assert.deepEqual(f.failures, []);
});

test('Responses decimal and exponent token counts support actual portable compaction', async t => {
  let spelling = '128.0';
  const summaries = [];
  const f = await fixture(t, async (body, response) => {
    if (body.tools.length === 0) {
      const text = `NUMERIC_COMPACTION_SUMMARY_${summaries.length + 1}`;
      summaries.push({ body, text });
      finish(response, [item(`summary-${summaries.length}`, text)]);
    } else finish(response, [item('original', 'ORIGINAL_COMPACTION_HISTORY')]);
  }, { measure: () => spelling, compaction: {
    enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 60000,
    targets: [{ profile: 'fixture', window_tokens: 8192, output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'summary' }],
  } });
  const { task_id } = await f.post({ op: 'create', profile: 'fixture', message: 'Keep the verified work in the next context.' });
  await f.idle(task_id);
  for (const value of ['128.0', '128e0']) {
    spelling = value;
    const count = summaries.length, meters = f.meters.length;
    await f.post({ op: 'compact', task_id });
    await f.waitFor(() => summaries.length > count, 'The admitted integer token count must allow a real summary request');
    const summary = summaries[count];
    await f.waitFor(async () => {
      const page = await f.post({ op: 'read', task_id });
      return JSON.stringify(page).includes(summary.text);
    }, 'The public context must retain the summary returned by the metered request');
    assert.equal(summary.body.max_output_tokens, 1024);
    assert.ok(f.meters.slice(meters).some(body => body.tools.length === 0), 'The actual summary request must be metered');
  }
  assert.equal(summaries.length, 2);
  assert.deepEqual(f.failures, []);
});

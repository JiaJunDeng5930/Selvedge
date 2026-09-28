import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { boardTextOutcome, requestBoardText } from '../host/board-text.mjs';
import { responseBody } from '../host/providers.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

const output = text => [{ type: 'context', value: {
  type: 'message', role: 'assistant', content: [{ type: 'output_text', text }],
} }];
// Component-test bounds deliberately differ from the native policy. Service
// integration obtains its actual budgets from the executable description.
const limits = { frame_bytes: 64 * 1024, model_retry: { statuses: [], delays_ms: [], max_retry_after_ms: 0 } };
const effect = { kind: 'board_text', card_id: 7, ticket: 13, retitle: false,
  model: { profile: 'draft', provider: 'responses', name: 'draft-model', reasoning: 'default', project: null },
  prompt: '保留原要求，生成一个任务标题和描述。',
};

test('board drafting decodes one bounded JSON message and ignores reasoning content', () => {
  const value = { title: '修复拖动 🧭', description: '第一行\n第二行：保留原来的行为。' };
  assert.deepEqual(boardTextOutcome(output(JSON.stringify(value)), 1024), value);
  assert.deepEqual(boardTextOutcome([{ type: 'context', value: { type: 'reasoning', encrypted_content: 'opaque' } },
    ...output(JSON.stringify(value))], 1024), value);
  assert.deepEqual(boardTextOutcome([{ type: 'text', text: JSON.stringify(value) }], 1024), value);
  const bytes = Buffer.byteLength(JSON.stringify(value));
  assert.deepEqual(boardTextOutcome(output(JSON.stringify(value)), bytes), value);
  assert.throws(() => boardTextOutcome(output(JSON.stringify(value)), bytes - 1), /bounded/);
});

test('drafting rejects tools, duplicate keys, malformed Unicode, ambiguity and extra fields', () => {
  for (const text of [
    '{"title":"one","title":"two"}',
    '{"title":"one","\\u0074itle":"two"}',
    '{"title":"one","description":"text","task_id":"7"}',
    '{"title":"","description":"text"}',
    '{"title":"  ","description":"text"}',
    '{"title":"one","description":null}',
    '{"title":"\\ud800","description":"text"}',
    '{"title":"one","description":"\\u0000"}',
    '```json\n{"title":"one","description":"text"}\n```',
    '{"title":"one","description":"text"}\n{"title":"two","description":"text"}',
  ]) assert.throws(() => boardTextOutcome(output(text), 4096), TypeError, text);
  for (const items of [[], [...output('{"title":"one","description":"text"}'), ...output('{}')],
    [{ type: 'call', id: 'invoke', name: 'bash', arguments: { command: 'echo not-executed' } }],
    [{ type: 'context', value: { type: 'function_call', name: 'bash' } }],
    [{ type: 'context', value: { type: 'message', role: 'user', content: [{ type: 'output_text', text: '{}' }] } }],
  ]) assert.throws(() => boardTextOutcome(items, 4096), TypeError);
  assert.throws(() => boardTextOutcome(output('{}'), 0), /bound/);
});

test('independent board requests have no tools, task history or inherited reasoning level', () => {
  for (const provider of ['responses', 'chatgpt']) {
    const profile = { provider, model_info: { supported_reasoning_levels: [{ effort: 'high' }] } };
    const body = responseBody({ ...effect, model: { ...effect.model, provider },
      tools: [{ name: 'bash', description: 'must not be offered', parameters: {} }], callable: ['bash'],
      history: [{ role: 'user', content: 'unrelated task secret' }],
    }, profile);
    assert.deepEqual(body.input, [{ role: 'user', content: effect.prompt }]);
    assert.deepEqual(body.tools, []);
    assert.equal(body.tool_choice, provider === 'chatgpt' ? 'auto' : 'none');
    assert.equal(Object.hasOwn(body, 'reasoning'), false);
    assert.equal(Object.hasOwn(body, 'instructions'), false);
    assert.equal(body.model, 'draft-model');
  }
});

function configured(t, endpoint) {
  const previous = process.env.SELVEDGE_BOARD_DRAFT_TEST_KEY;
  process.env.SELVEDGE_BOARD_DRAFT_TEST_KEY = 'local-fixture-only';
  t.after(() => {
    if (previous === undefined) delete process.env.SELVEDGE_BOARD_DRAFT_TEST_KEY;
    else process.env.SELVEDGE_BOARD_DRAFT_TEST_KEY = previous;
  });
  return validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    draft: { provider: 'responses', model: 'draft-model', endpoint,
      api_key_env: 'SELVEDGE_BOARD_DRAFT_TEST_KEY', timeout_ms: 5000 },
  } });
}

test('a real SSE drafting request preserves the prompt and decodes its complete response', async t => {
  const expected = { title: '修复任务看板', description: '验证筛选、编辑和拖动操作。' };
  const endpoint = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: JSON.stringify(expected) }] }]);
  const config = configured(t, endpoint.endpoint);
  assert.deepEqual(await requestBoardText(effect, config, await home(t), limits), expected);
  assert.equal(endpoint.requests.length, 1);
  assert.deepEqual(endpoint.requests[0].input, [{ role: 'user', content: effect.prompt }]);
  assert.deepEqual(endpoint.requests[0].tools, []);
  assert.equal(endpoint.requests[0].reasoning, undefined);
  assert.deepEqual(endpoint.failures, []);
});

test('board HTTP cancellation aborts a live request rather than fabricating a draft', async t => {
  const arrived = Promise.withResolvers();
  const disconnected = Promise.withResolvers();
  let requests = 0;
  const server = http.createServer((request, response) => {
    requests++;
    request.resume();
    response.once('close', disconnected.resolve);
    arrived.resolve();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const config = configured(t, `http://127.0.0.1:${server.address().port}/responses`);
  const controller = new AbortController();
  const pending = requestBoardText(effect, config, await home(t), limits, { signal: controller.signal });
  const rejected = assert.rejects(pending, /abort|cancel/i);
  await arrived.promise;
  controller.abort(new Error('draft cancelled'));
  await rejected;
  await disconnected.promise;
  assert.equal(requests, 1);
});

test('board transport refuses an automatic or offline endpoint before making a request', async () => {
  await assert.rejects(requestBoardText({ ...effect, model: { ...effect.model, adaptive_reasoning: {} } }, {}, '', limits), /ordinary/);
  const config = validateConfig({ ...defaultConfig, chatgpt: false });
  await assert.rejects(requestBoardText({ ...effect, model: { profile: 'demo', provider: 'echo', name: 'echo', reasoning: 'default' } },
    config, '', limits), /offline echo/);
});

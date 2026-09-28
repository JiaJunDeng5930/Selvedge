import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { DatabaseSync } from 'node:sqlite';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig, profileCatalog } from '../host/config.mjs';
import { evaluatorConnections, adaptivePolicy, accountAutoPreset, accountConnection } from '../host/reasoning-config.mjs';
import { budgetOutputs, outputTokens, decisionContext, decisionRequest, validateDecision, requestReasoning, evaluatorLimits } from '../host/jev.mjs';
import { home, taskIdle, responsesServer } from './support.mjs';

const automatic = { evaluator: 'jev', efforts: ['low', 'medium', 'high'], baseline: 'medium', transport: 'configuration_update', max_lease: 10 };
const limits = { frame_bytes: 16_777_216 };
const nativeEffect = (history = [{ role: 'user', content: 'Implement the requested change without altering other behavior.' }]) => ({
  kind: 'reasoning', task_id: 0, ticket: 0, model: { profile: 'automatic', provider: 'responses', name: 'worker-model', adaptive_reasoning: automatic }, history,
});
const chosen = (effort = 'low', lease = '2') => ({ model: 'jev-1.13', answers: {
  effort: { type: 'choice', choice: effort }, lease: { type: 'choice', choice: lease },
} });

function key(t, value = 'fixture-evaluator-key') {
  const previous = process.env.SELVEDGE_JEV_TEST_KEY;
  const previousPrimary = process.env.SELVEDGE_PRIMARY_TEST_KEY;
  process.env.SELVEDGE_PRIMARY_TEST_KEY = 'fixture-primary-key';
  if (value === undefined) delete process.env.SELVEDGE_JEV_TEST_KEY; else process.env.SELVEDGE_JEV_TEST_KEY = value;
  t.after(() => {
    if (previous === undefined) delete process.env.SELVEDGE_JEV_TEST_KEY; else process.env.SELVEDGE_JEV_TEST_KEY = previous;
    if (previousPrimary === undefined) delete process.env.SELVEDGE_PRIMARY_TEST_KEY; else process.env.SELVEDGE_PRIMARY_TEST_KEY = previousPrimary;
  });
}

async function evaluator(t, handler = () => chosen()) {
  const requests = [], failures = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const parts = [];
      for await (const part of request) parts.push(part);
      const body = JSON.parse(Buffer.concat(parts));
      requests.push({ body, headers: request.headers });
      const reply = await handler(body, requests.length - 1, response, request);
      if (!response.writableEnded && !response.destroyed && reply !== undefined) {
        response.writeHead(200, { 'content-type': 'application/json' }); response.end(JSON.stringify(reply));
      }
    })().catch(error => { failures.push(error); if (!response.writableEnded) { response.writeHead(500); response.end('fixture failed'); } });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { endpoint: `http://127.0.0.1:${server.address().port}/evaluate`, requests, failures };
}

function configFor(evaluatorURL, providerURL = 'http://127.0.0.1:1/responses', overrides = {}) {
  return validateConfig({ ...defaultConfig, chatgpt: false,
    profiles: { automatic: { provider: 'responses', model: 'worker-model', endpoint: providerURL,
      api_key_env: 'SELVEDGE_PRIMARY_TEST_KEY', adaptive_reasoning: automatic },
      ordinary: { provider: 'responses', model: 'worker-model', endpoint: providerURL, api_key_env: 'SELVEDGE_PRIMARY_TEST_KEY' } },
    reasoning_evaluators: { jev: { provider: 'typesafe', endpoint: evaluatorURL, api_key_env: 'SELVEDGE_JEV_TEST_KEY', ...overrides } },
  });
}

test('evaluator connections, manual policies and the account convenience are independent configurations', () => {
  const evaluators = evaluatorConnections({ jev: {} });
  assert.equal(evaluators.jev.model, 'typesafe-ai/jev');
  const ordinary = validateConfig({ ...defaultConfig, reasoning_evaluators: { jev: {} } });
  assert.equal(ordinary.profiles.demo.adaptive_reasoning, undefined);
  const manual = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    other: { provider: 'responses', model: 'another-model', adaptive_reasoning: automatic },
  } });
  assert.deepEqual(manual.reasoning_evaluators, {});
  assert.deepEqual(profileCatalog(manual)[0].adaptive_reasoning, automatic);
  const account = { provider: 'chatgpt', model: 'gpt-6-astra', endpoint: 'https://example.invalid/responses',
    auth_file: 'account.json', bound_account_id: 'an-account' };
  const descriptor = { slug: 'gpt-6-astra', default_reasoning_level: 'medium',
    supported_reasoning_levels: [{ effort: 'low' }, { effort: 'medium' }, { effort: 'high' }] };
  const preset = accountAutoPreset(account, descriptor);
  assert.deepEqual(preset, { ...account, adaptive_reasoning: automatic });
  assert.equal(accountAutoPreset(account, { ...descriptor, slug: 'different-model' }), undefined);
  assert.equal(accountAutoPreset(account, { ...descriptor, supported_reasoning_levels: [] }), undefined);
  assert.equal(accountConnection({ ...account, adaptive_reasoning: automatic }).adaptive_reasoning, undefined);
  assert.equal(accountConnection(account).model, undefined);
  assert.throws(() => adaptivePolicy({ ...automatic, max_lease: undefined }), /Adaptive reasoning/);
});

test('configuration rejects invalid efforts, ambiguous policies, credential URLs and unbounded evaluators', () => {
  for (const change of [{ efforts: ['auto'] }, { efforts: ['low', 'low'] }, { baseline: 'unavailable' },
    { transport: 'guess' }, { max_lease: 0 }, { max_lease: 11 }, { evaluator: '' }]) {
    assert.throws(() => adaptivePolicy({ ...automatic, ...change }), /Adaptive reasoning/);
  }
  assert.equal(adaptivePolicy(null), null);
  assert.throws(() => evaluatorConnections({ jev: { endpoint: 'http://not-loopback.invalid/evaluate' } }), /HTTPS/);
  assert.throws(() => evaluatorConnections({ jev: { endpoint: 'https://example.invalid/?api_key=secret' } }), /credentials/);
  assert.throws(() => evaluatorConnections({ jev: { api_key: 'not-an-environment-variable' } }), /fields/);
  assert.throws(() => evaluatorConnections({ jev: { timeout_ms: 0 } }), /deadline/);
  assert.throws(() => evaluatorConnections({ jev: { max_attempts: 4 } }), /retry bound/);
  assert.throws(() => validateConfig({ ...defaultConfig, profiles: { bad: { provider: 'echo', model: 'echo', adaptive_reasoning: automatic } } }), /echo/);
});

test('paired tool output budgets include escaped text and preserve Unicode source prefixes and suffixes', () => {
  const originals = [
    { text: 'small complete result', is_error: false },
    { text: '\u0001"\\😀世界'.repeat(5000), is_error: false },
    { text: 'other result\n'.repeat(5000), is_error: true },
  ];
  const outputs = budgetOutputs(originals);
  assert.equal(outputs[0].text, originals[0].text);
  assert.ok(outputs.reduce((sum, output) => sum + outputTokens(output.text), 0) <= 1000);
  for (const [index, output] of outputs.entries()) {
    assert.equal(output.preview.sent_tokens, outputTokens(output.text));
    assert.ok(output.preview.sent_tokens <= output.preview.budget_tokens);
    if (output.preview.truncated && output.text) {
      const [head, tail] = output.text.split('\n[Tool output preview: middle omitted]\n');
      assert.ok(originals[index].text.startsWith(head));
      assert.ok(originals[index].text.endsWith(tail));
      assert.equal(output.text.includes('\uFFFD'), false);
    }
  }
});

test('the evaluator frame retains original/current goals and public notes and pairs only the last six calls', () => {
  const history = [{ role: 'user', content: 'original constraints' }, { role: 'user', content: 'a previous request' },
    { role: 'reasoning_summary', content: [{ text: 'public summary', encrypted_content: 'must not appear' }] },
    ...Array.from({ length: 8 }, (_, i) => ({ role: 'function_call', call_id: `call-${i}`, name: 'bash', arguments: { command: String(i) } })),
    ...Array.from({ length: 8 }, (_, i) => ({ role: 'function_output', call_id: `call-${i}`, content: { stdout: String(i) }, is_error: false })),
    { role: 'user', content: 'the current request' }];
  const context = decisionContext(nativeEffect(history));
  assert.equal(context.original_user_request, 'original constraints');
  assert.equal(context.latest_user_request, 'the current request');
  assert.deepEqual(context.prior_user_requests, ['a previous request']);
  assert.equal(context.recent_tool_calls.length, 6);
  assert.equal(context.omitted_older_tool_calls, 2);
  assert.equal(context.recent_tool_calls[0].call_id, 'call-2');
  assert.equal(context.recent_tool_calls[0].outputs[0].text, '{"stdout":"2"}');
  assert.equal(JSON.stringify(context).includes('must not appear'), false);
  assert.throws(() => decisionContext(nativeEffect([{ role: 'model_context', content: { encrypted_content: 'private' } }])), /unsupported role/);
});

test('all supported Jev APIs use typed choices and prove their configured provider identity', () => {
  const effect = nativeEffect();
  const vercel = evaluatorConnections({ e: { provider: 'vercel' } }).e;
  const openrouter = evaluatorConnections({ e: { provider: 'openrouter' } }).e;
  const typesafe = evaluatorConnections({ e: { provider: 'typesafe' } }).e;
  assert.deepEqual(decisionRequest(effect, vercel).providerOptions, { gateway: { only: ['typesafe-ai'] } });
  assert.deepEqual(decisionRequest(effect, openrouter).provider, { only: ['typesafe'], allow_fallbacks: false });
  assert.equal(decisionRequest(effect, typesafe).providerOptions, undefined);
  assert.deepEqual(validateDecision(chosen(), typesafe, automatic), { effort: 'low', generations: 2 });
  const routed = { ...chosen(), model: vercel.model, providerMetadata: { gateway: { routing: { canonicalSlug: vercel.model, finalProvider: 'typesafe-ai' } } } };
  assert.deepEqual(validateDecision(routed, vercel, automatic), { effort: 'low', generations: 2 });
  assert.throws(() => validateDecision({ ...routed, providerMetadata: {} }, vercel, automatic), /invalid model\/provider/);
  const routedOpen = { ...chosen(), model: 'typesafe/jev-1.13-20260901', provider: 'TypeSafe' };
  assert.deepEqual(validateDecision(routedOpen, openrouter, automatic), { effort: 'low', generations: 2 });
  assert.throws(() => validateDecision({ ...routedOpen, provider: 'other' }, openrouter, automatic), /invalid/);
  assert.throws(() => validateDecision(chosen('unavailable'), typesafe, automatic), /invalid/);
  assert.throws(() => validateDecision(chosen('low', '3'), typesafe, automatic), /invalid/);
  assert.throws(() => validateDecision(chosen('low', '10'), typesafe, { ...automatic, max_lease: 5 }), /invalid/);
});

test('real HTTP evaluation sends only the configured key/model, retries the same request and does not guess on invalid JSON', async t => {
  key(t);
  const upstream = await evaluator(t, (_, index, response) => {
    if (!index) { response.writeHead(503, { 'retry-after': '0' }); response.end('not logged or treated as a decision'); return; }
    return chosen('high', '5');
  });
  const config = configFor(upstream.endpoint);
  assert.deepEqual(await requestReasoning(nativeEffect(), config, limits), { effort: 'high', generations: 5 });
  assert.equal(upstream.requests.length, 2);
  assert.deepEqual(upstream.requests[0].body, upstream.requests[1].body);
  assert.equal(upstream.requests[0].headers.authorization, 'Bearer fixture-evaluator-key');
  assert.equal(upstream.requests[0].body.model, 'jev-latest');
  assert.deepEqual(Object.keys(upstream.requests[0].body.questions.effort.criteria), automatic.efforts);
  assert.equal(JSON.stringify(upstream.requests[0].body).includes('fixture-evaluator-key'), false);
  const invalid = await evaluator(t, (_, __, response) => { response.writeHead(200); response.end('{invalid json'); });
  await assert.rejects(requestReasoning(nativeEffect(), configFor(invalid.endpoint), limits), /invalid or oversized/);
  assert.equal(invalid.requests.length, 1);
});

test('missing evaluator/key and oversized contexts fail before HTTP; cancellation aborts a pending evaluator', async t => {
  key(t);
  const upstream = await evaluator(t, async () => { await delay(500); return chosen(); });
  const config = configFor(upstream.endpoint);
  await assert.rejects(requestReasoning(nativeEffect(), { ...config, reasoning_evaluators: {} }, limits), /Configure reasoning_evaluators.jev/);
  const missing = { ...config, reasoning_evaluators: { jev: { ...config.reasoning_evaluators.jev, api_key_env: 'SELVEDGE_NONEXISTENT_JEV_KEY_TEST' } } };
  await assert.rejects(requestReasoning(nativeEffect(), missing, limits), /Set SELVEDGE_NONEXISTENT/);
  await assert.rejects(requestReasoning(nativeEffect([{ role: 'user', content: 'word '.repeat(40_000) }]), config, limits), /token\/byte budget/);
  assert.equal(upstream.requests.length, 0);
  const controller = new AbortController();
  const pending = requestReasoning(nativeEffect(), config, limits, { signal: controller.signal });
  while (!upstream.requests.length) await delay(5);
  controller.abort(new Error('Test stopped the evaluator'));
  await assert.rejects(pending, /Test stopped/);
  assert.equal(upstream.requests.length, 1);
  assert.equal(evaluatorLimits.request_tokens, 28_000);
});

test('the complete native/service flow commits evaluation first, bypasses it under a lease, and does not replay it after restart', async t => {
  key(t);
  const directory = await home(t);
  const state = path.join(directory, 'state');
  const observedKinds = [];
  const committed = kind => {
    const database = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
    try {
      const rows = database.prepare('SELECT decision FROM journal ORDER BY seq').all();
      const effects = rows.flatMap(row => JSON.parse(row.decision).effects);
      assert.ok(effects.some(effect => effect.kind === kind));
      observedKinds.push(kind);
    } finally { database.close(); }
  };
  const upstream = await evaluator(t, () => { committed('reasoning'); return chosen('low', '2'); });
  const primary = await responsesServer(t, (_, index) => {
    committed('model');
    if (index === 0) return [{ type: 'function_call', call_id: 'read-self', name: 'read_task', arguments: '{"task_id":0,"after":0,"limit":1}' }];
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Completed the native task.' }] }];
  });
  const config = configFor(upstream.endpoint, primary.endpoint);
  let service = await Service.open({ home: state, config, cwd: directory });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'automatic', message: 'Do the task with a bounded follow-up.' });
  assert.equal(created.reply.ok, true, JSON.stringify(created));
  const page = await taskIdle(service);
  assert.equal(page.messages.findLast(message => message.role === 'model_context')?.content?.content?.[0]?.text,
    'Completed the native task.', JSON.stringify(page));
  assert.equal(upstream.requests.length, 1);
  assert.equal(primary.requests.length, 2);
  assert.deepEqual(observedKinds, ['reasoning', 'model', 'model']);
  assert.ok(primary.requests.every(body => body.reasoning.effort === 'medium'));
  assert.deepEqual(primary.requests[1].input.slice(0, primary.requests[0].input.length), primary.requests[0].input);
  await service.close();
  service = await Service.open({ home: state, config, cwd: directory });
  assert.deepEqual((await taskIdle(service)).messages, page.messages);
  await delay(40);
  assert.equal(upstream.requests.length, 1);
  await service.command({ op: 'create', profile: 'ordinary', message: 'An ordinary endpoint never invokes Jev.' });
  await taskIdle(service, 1);
  assert.equal(upstream.requests.length, 1);
  assert.deepEqual(upstream.failures, []);
  assert.deepEqual(primary.failures, []);
});

test('a missing Jev connection or a bad evaluator reply is visible in the task and sends zero main-model requests', async t => {
  key(t);
  const upstream = await evaluator(t, () => chosen('not-allowed', '10'));
  const primary = await responsesServer(t, () => assert.fail('No fallback main-model request is allowed'));
  for (const configured of [false, true]) {
    const directory = await home(t);
    const config = configFor(upstream.endpoint, primary.endpoint);
    const service = await Service.open({ home: path.join(directory, 'state'), cwd: directory,
      config: configured ? config : { ...config, reasoning_evaluators: {} } });
    try {
      await service.command({ op: 'create', profile: 'automatic', message: 'Must not silently use a default model effort.' });
      const page = await taskIdle(service);
      assert.equal(page.messages.at(-1).role, 'error');
      assert.match(page.messages.at(-1).content, configured ? /invalid model\/provider, effort or lease/ : /Configure reasoning_evaluators.jev/);
    } finally { await service.close(); }
  }
  assert.equal(primary.requests.length, 0);
  assert.equal(upstream.requests.length, 1);
});

test('new input during a real evaluator request is reevaluated before any main-model HTTP request', async t => {
  key(t);
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  t.after(() => release());
  const upstream = await evaluator(t, async (_, index) => {
    if (index === 0) { await pending; return chosen('low', '10'); }
    return chosen('high', '1');
  });
  const primary = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: 'Revised task complete.' }] }]);
  const directory = await home(t);
  const service = await Service.open({ home: path.join(directory, 'state'),
    config: configFor(upstream.endpoint, primary.endpoint), cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'automatic', message: 'Initial request.' });
  for (let count = 0; count < 200 && upstream.requests.length === 0; count++) await delay(10);
  assert.equal(upstream.requests.length, 1);
  await service.command({ op: 'send', task_id: 0, message: 'Changed requirement: verify recovery.' });
  release();
  await taskIdle(service);
  assert.equal(upstream.requests.length, 2);
  assert.equal(upstream.requests[1].body.state.latest_user_request, 'Changed requirement: verify recovery.');
  assert.equal(primary.requests.length, 1);
  assert.equal(primary.requests[0].input.at(-1).reasoning.effort, 'high');
  assert.deepEqual(upstream.failures, []);
});

test('interrupt aborts the evaluator HTTP stream and its late response never starts the main model', async t => {
  key(t);
  let response;
  const upstream = await evaluator(t, (_, __, res) => { response = res; return undefined; });
  const primary = await responsesServer(t, () => assert.fail('An interrupted evaluator cannot launch a generation'));
  const directory = await home(t);
  const service = await Service.open({ home: path.join(directory, 'state'),
    config: configFor(upstream.endpoint, primary.endpoint), cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'automatic', message: 'Wait for evaluator.' });
  for (let count = 0; count < 200 && !response; count++) await delay(10);
  assert.ok(response);
  assert.equal((await service.command({ op: 'interrupt', task_id: 0 })).reply.ok, true);
  for (let count = 0; count < 200 && !response.destroyed; count++) await delay(10);
  assert.equal(response.destroyed, true, 'The physical evaluator connection must be cancelled');
  const page = await taskIdle(service);
  assert.equal(page.task.status, 'stopped');
  assert.equal(primary.requests.length, 0);
  assert.equal(upstream.requests.length, 1);
});

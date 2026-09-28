import test from 'node:test';
import assert from 'node:assert/strict';
import { stat, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { requestModel, cancelModelTask, responseBody } from '../host/providers.mjs';
import { requestApproval, approvalOutcome } from '../host/approvals.mjs';
import { requestBoardText } from '../host/board-text.mjs';
import { sseEvents, events } from '../host/network.mjs';
import { chatgptWebRequestAction } from '../host/chatgpt-web.mjs';
import { WebRequestStore } from '../host/chatgpt-web-store.mjs';
import { defaultConfig, validateConfig, profileCatalog } from '../host/config.mjs';
import { Service } from '../host/service.mjs';
import { home, taskIdle } from './support.mjs';
import { webServer, answer, call } from './fixtures/chatgpt-web.mjs';

const limits = { frame_bytes: 1024 * 1024, approval_reason_bytes: 400,
  model_retry: { delays_ms: [1, 2], statuses: [429, 500, 502, 503, 504], max_retry_after_ms: 1000 } };
const tool = { name: 'work', description: 'A fixture function', parameters: { type: 'object', properties: { path: { type: 'string' } } } };
const baseEffect = () => ({ kind: 'model', task_id: 0, ticket: 1, instructions: 'Follow the user.',
  model: { profile: 'web', provider: 'chatgpt-web', name: 'chatgpt-web/high', reasoning: 'medium', project: null },
  history: [{ role: 'user', content: 'first question' }], tools: [tool], callable: ['work'], settings: { workspace: '/fixture' } });

function append(history, items) {
  return [...history, ...items.map(item => item.type === 'text' ? { role: 'assistant', content: item.text } :
    item.type === 'context' ? { role: 'model_context', content: item.value } :
      { role: 'function_call', content: { id: item.id, name: item.name, arguments: item.arguments } })];
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

test('web profiles use their own endpoint, token and fixed effort catalog', () => {
  for (const effort of ['light', 'medium', 'high', 'xhigh', 'pro']) {
    const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { web: { provider: 'chatgpt-web', model: `chatgpt-web/${effort}` } } });
    assert.equal(config.profiles.web.endpoint, 'http://127.0.0.1:8787/v1/responses');
    assert.equal(config.profiles.web.api_key_env, 'CHATGPT_WEB_TOKEN');
    assert.deepEqual(profileCatalog(config), [{ key: 'web', provider: 'chatgpt-web', name: `chatgpt-web/${effort}` }]);
  }
  for (const extra of [{ model: 'gpt-native' }, { endpoint: 'http://127.0.0.1:8787/responses' },
    { endpoint: 'http://127.0.0.1:8787/v1/responses?token=secret' }, { api_key_env: 'bad-name' },
    { adaptive_reasoning: { evaluator: 'fixture', efforts: ['high'], baseline: 'high', transport: 'request_effort' } }]) {
    assert.throws(() => validateConfig({ ...defaultConfig, profiles: { web: { provider: 'chatgpt-web', model: 'chatgpt-web/high', ...extra } } }));
  }
});

test('root requests use named snapshots and retain only authoritative output plus an opaque receipt', async t => {
  const f = await fixture(t, async body => {
    assert.equal(body.model, 'chatgpt-web/high');
    assert.match(body.instructions, /Committed task settings/);
    assert.match(body.input[0].content, /Project context snapshot/);
    assert.equal(body.input[1].content, 'first question');
    assert.deepEqual(body.tools, [{ type: 'function', ...tool }]);
    return { output: answer('final 😀'), snapshots: ['provisional longer text', 'short', 'corrected 😀'] };
  });
  const effect = baseEffect(); effect.model.project = { workspace: '/fixture', instructions: 'project data', revision: 'r1' };
  const snapshots = [];
  const items = await f.run(effect, { onSnapshot: (text, index) => snapshots.push([text, index]), onDelta: () => assert.fail('snapshots are not deltas') });
  assert.deepEqual(snapshots, [['provisional longer text', 0], ['short', 0], ['corrected 😀', 0], ['final 😀', 0]]);
  assert.deepEqual(items[0], { type: 'text', text: 'final 😀' });
  assert.equal(items[1].value.type, 'provider_receipt');
  assert.equal(items[1].value.status, 'completed');
  const file = path.join(f.directory, 'providers/chatgpt-web/requests.sqlite');
  assert.equal((await stat(file)).mode & 0o777, 0o600);
  const store = await WebRequestStore.open(f.directory);
  const stored = store.find(items[1].value.request_key); store.close();
  assert.equal(stored.body, f.requests[0].raw);
  assert.ok(!JSON.stringify(stored).includes('local-web-fixture'));
  assert.ok(!stored.response.includes('provisional longer text'));
  assert.deepEqual(f.failures, []);
});

test('completed continuations send only new messages and inherit all root settings', async t => {
  const f = await fixture(t, async (_, index) => ({ output: answer(`answer ${index}`), json: index === 1 }));
  const root = baseEffect(); const first = await f.run(root);
  const next = { ...root, ticket: 2, history: [...append(root.history, first), { role: 'user', content: 'only this is new' }] };
  await f.run(next);
  assert.deepEqual(f.requests[1].body, { previous_response_id: first[1].value.response_id,
    input: [{ type: 'message', role: 'user', content: 'only this is new' }], stream: true });
  assert.deepEqual(f.failures, []);
});

test('local transport receipts never become another backend\'s wire input', async t => {
  const f = await fixture(t, async () => ({ output: answer('portable answer') }));
  const root = baseEffect(); const output = await f.run(root);
  const history = append(root.history, output);
  for (const provider of ['responses', 'chatgpt']) {
    const body = responseBody({ ...root, history, model: { ...root.model, provider, name: 'fixture-model' } }, { provider });
    assert.deepEqual(body.input, [{ role: 'user', content: 'first question' }, { role: 'assistant', content: 'portable answer' }]);
    assert.ok(!JSON.stringify(body).includes(output.at(-1).value.response_id));
    assert.ok(!JSON.stringify(body).includes(output.at(-1).value.request_key));
  }
});

test('object-argument calls return one exact result batch, then flush deferred messages without mixing them', async t => {
  const f = await fixture(t, async (body, index) => {
    if (index === 0) return { output: [call('a', 'work', { path: 'a' }), call('b', 'work', { path: 'b' })] };
    if (index === 1) {
      assert.deepEqual(body.input.map(item => item.call_id), ['a', 'b']);
      assert.deepEqual(JSON.parse(body.input[1].output), { value: { content: 'opaque JSON, not MCP blocks' }, is_error: true });
      return { output: answer('tool turn completed') };
    }
    assert.equal(body.input[0].content, 'new request during tools');
    return { output: answer('new request answered') };
  });
  const root = baseEffect(); const first = await f.run(root);
  assert.deepEqual(first[0], { type: 'call', id: 'a', name: 'work', arguments: { path: 'a' } });
  const next = { ...root, ticket: 2, history: [...append(root.history, first),
    { role: 'function_output', call_id: 'b', content: { content: 'opaque JSON, not MCP blocks' }, is_error: true },
    { role: 'user', content: 'new request during tools' },
    { role: 'function_output', call_id: 'a', content: 'ok', is_error: false }] };
  const output = await f.run(next);
  assert.deepEqual(output.slice(0, 2), [{ type: 'text', text: 'tool turn completed' }, { type: 'text', text: 'new request answered' }]);
  assert.deepEqual(output.at(-1).value.deferred, []);
  assert.equal(f.requests.length, 3);
  assert.deepEqual(f.failures, []);
});

test('messages deferred over several tool rounds survive in the native context carrier', async t => {
  const f = await fixture(t, async (_, index) => index < 2 ? { output: [call(`c${index}`, 'work')] } : { output: answer(`done ${index}`) });
  const root = baseEffect(); const first = await f.run(root);
  const next = { ...root, ticket: 2, history: [...append(root.history, first),
    { role: 'user', content: 'keep this message' }, { role: 'function_output', call_id: 'c0', content: 'zero', is_error: false }] };
  const second = await f.run(next);
  assert.equal(second.at(-1).value.deferred[0].content, 'keep this message');
  const last = { ...root, ticket: 3, history: [...append(next.history, second), { role: 'function_output', call_id: 'c1', content: 'one', is_error: false }] };
  await f.run(last);
  assert.deepEqual(f.requests[3].body.input, [{ type: 'message', role: 'user', content: 'keep this message' }]);
  assert.deepEqual(f.failures, []);
});

test('missing, repeated and foreign results fail before admitting another request', async t => {
  const f = await fixture(t, async () => ({ output: [call('a', 'work'), call('b', 'work')] }));
  const root = baseEffect(); const first = await f.run(root);
  const result = id => ({ role: 'function_output', call_id: id, content: 'ok', is_error: false });
  for (const results of [[result('a')], [result('a'), result('a')], [result('a'), result('foreign')]]) {
    await assert.rejects(f.run({ ...root, ticket: 2, history: [...append(root.history, first), ...results] }), /batch|results/);
  }
  assert.equal(f.requests.length, 1);
});

test('forks and text checkpoints start explicit roots; summaries never invoke remote compaction', async t => {
  const f = await fixture(t, async () => ({ output: answer('answer'), snapshots: ['preview'] }));
  const root = baseEffect(); const first = await f.run(root);
  const history = append(root.history, first);
  await f.run({ ...root, task_id: 8, ticket: 2, history: [...history, { role: 'user', content: 'child task' }] });
  assert.equal(f.requests[1].body.previous_response_id, undefined);
  assert.ok(f.requests[1].body.input.some(item => item.content === 'first question'));
  const summary = await f.run({ ...root, ticket: 3, kind: 'summary', history, instructions: 'Summarize this task.' },
    { onSnapshot: () => assert.fail('summary previews must not be displayed') });
  assert.deepEqual(summary, [{ type: 'text', text: 'answer' }]);
  assert.deepEqual(f.requests[2].body.tools, []);
  assert.ok(f.requests[2].body.input.every(item => item.type === 'message'));
  await f.run({ ...root, ticket: 4, history: [{ role: 'context_summary', content: 'replacement context' }, { role: 'user', content: 'continue' }] });
  assert.equal(f.requests[3].body.previous_response_id, undefined);
  assert.ok(!JSON.stringify(f.requests[3].body).includes('first question'));
  assert.deepEqual(f.failures, []);
});

test('transient header retries preserve the original body and idempotency key; completed replay is local', async t => {
  const f = await fixture(t, async (_, index, { response }) => {
    if (!index) { response.writeHead(503); response.end('private upstream detail'); return; }
    return { output: answer('recovered') };
  });
  const retries = [];
  const first = await f.run(baseEffect(), { onRetry: value => retries.push(value) });
  assert.equal(f.requests.length, 2);
  assert.equal(f.requests[0].key, f.requests[1].key);
  assert.equal(f.requests[0].raw, f.requests[1].raw);
  assert.equal(retries.length, 1);
  assert.deepEqual(await f.run(), first);
  assert.equal(f.requests.length, 2);
  await assert.rejects(f.run({ ...baseEffect(), history: [{ role: 'user', content: 'changed body' }] }), /cannot change/);
  assert.equal(f.requests.length, 2);
});

test('interrupted observation retains identity, does not resend, and permits same-key observation plus explicit controls', async t => {
  const f = await fixture(t, async (_, index) => ({ output: answer('final'), snapshots: ['provisional'], interrupted: index === 0 }));
  let error;
  await assert.rejects(f.run(), value => { error = value; return Boolean(value.requestKey && value.responseId); });
  assert.equal(f.requests.length, 1);
  await assert.rejects(f.run({ ...baseEffect(), ticket: 2 }), /request retained/);
  assert.equal(f.requests.length, 1, 'an unknown outcome cannot silently start a replacement root');
  const inspected = await chatgptWebRequestAction(error.requestKey, 'inspect', f.config, f.directory, limits);
  assert.equal(inspected.id, error.responseId);
  await chatgptWebRequestAction(error.requestKey, 'resume', f.config, f.directory, limits, { confirm: true });
  const recovered = await f.run();
  assert.equal(recovered[0].text, 'final');
  assert.equal(f.requests[0].key, f.requests[1].key);
  await cancelModelTask(0, f.config, f.directory, limits);
  assert.deepEqual(f.controls.map(value => [value.action, value.method, value.body]), [
    ['inspect', 'GET', undefined], ['resume', 'POST', { confirm: true }], ['cancel', 'POST', {}],
  ]);
  assert.deepEqual(f.failures, []);
});

test('connection and contract changes cannot consume a retained predecessor', async t => {
  const f = await fixture(t, async () => ({ output: answer('done') }));
  const root = baseEffect(); const first = await f.run(root);
  const next = { ...root, ticket: 2, history: [...append(root.history, first), { role: 'user', content: 'next' }] };
  await assert.rejects(f.run({ ...next, instructions: 'different root instructions' }), /contract changed/);
  const alien = structuredClone(next); alien.history[2].content.store_id = 'different-home';
  await assert.rejects(f.run(alien), /connection or contract changed/);
  assert.equal(f.requests.length, 1);
});

test('provider resources are validated before any call can reach native execution', async t => {
  for (const [name, alter] of [
    ['string arguments', r => { r.status = 'requires_action'; r.usage = null; r.output = [{ ...call('x', 'work'), arguments: '{}' }]; }],
    ['custom call never declared', r => { r.status = 'requires_action'; r.usage = null; r.output = [{ type: 'custom_tool_call', id: 'x', call_id: 'x', name: 'work', input: 'raw' }]; }],
    ['duplicate call IDs', r => { r.status = 'requires_action'; r.usage = null; r.output = [call('x', 'work'), call('x', 'work')]; }],
    ['wrong model', r => { r.model = 'chatgpt-web/light'; }],
    ['wrong protocol', r => { r.protocol = 'responses.v1'; }],
    ['wrong predecessor', r => { r.previous_response_id = 'foreign'; }],
    ['wrong identity', r => { r.id = 'foreign'; }],
  ]) await t.test(name, async t => {
    const f = await fixture(t, async (_, __, { makeResource }) => { const resource = makeResource(answer('done')); alter(resource); return { resource }; });
    await assert.rejects(f.run(), error => Boolean(error.requestKey));
    assert.equal(f.requests.length, 1);
  });
});

test('admitted HTTP failures preserve their identity and do not expose upstream diagnostics', async t => {
  const f = await fixture(t, async (_, __, { id, response }) => {
    response.writeHead(409, { 'content-type': 'application/json', 'x-response-id': id });
    response.end(JSON.stringify({ error: { code: 'previous_response_consumed', message: 'secret credential-looking data' } }));
  });
  await assert.rejects(f.run(), error => error.code === 'previous_response_consumed' && error.responseId && !error.message.includes('secret'));
  assert.equal(f.requests.length, 1);
});

test('web transport crosses real native execution, SQLite commit, restart, fork and checkpoint boundaries', { timeout: 20_000 }, async t => {
  const f = await fixture(t, async (body, index, { request }) => {
    const database = new DatabaseSync(path.join(f.directory, 'state', 'journal.sqlite'), { readOnly: true });
    const decisions = database.prepare('SELECT decision FROM journal ORDER BY seq').all().map(row => JSON.parse(row.decision));
    database.close();
    const receipts = new DatabaseSync(path.join(f.directory, 'state/providers/chatgpt-web/requests.sqlite'), { readOnly: true });
    const saved = receipts.prepare('SELECT invocation, body FROM requests WHERE request_key=?').get(request.headers['idempotency-key']);
    receipts.close();
    assert.equal(saved.body, f.requests[index].raw, 'The exact request body/key must be durable before HTTP');
    const [, owner, ticket] = saved.invocation.split(':');
    assert.ok(decisions.some(decision => decision.effects.some(effect =>
      effect.kind === 'model' && effect.task_id === Number(owner) && effect.ticket === Number(ticket))),
    'HTTP requires its own earlier committed model intent');
    if (index === 0) return { output: [call('run', 'bash', { command: "printf 'ran\\n' >> executions; printf 'tool ok'" })] };
    if (index === 1) {
      const result = JSON.parse(body.input[0].output);
      assert.equal(result.is_error, false);
      // OS scheduling may return a running operation before its completion.
      // The final task page below must contain the actual stdout in either case.
      if (result.value.status !== 'running') assert.match(result.value.stdout, /tool ok/);
    }
    return { output: answer(`native answer ${index}`) };
  });
  const state = path.join(f.directory, 'state');
  let service = await Service.open({ home: state, cwd: f.directory, config: f.config });
  t.after(() => service.close());
  const notices = []; service.on('notice', value => notices.push(value));
  const created = await service.command({ op: 'create', profile: 'web', message: 'execute the fixture tool' });
  assert.equal(created.reply.ok, true);
  let page = await taskIdle(service);
  assert.deepEqual(f.failures, [], JSON.stringify(page));
  assert.ok(!page.messages.some(item => item.role === 'error' || (item.role === 'function_output' && item.is_error)), JSON.stringify(page));
  assert.ok(page.messages.some(item => ['function_output', 'operation_result'].includes(item.role) && item.content?.stdout === 'tool ok'), JSON.stringify(page));
  assert.ok(page.messages.some(item => item.role === 'model_context' && item.content.type === 'provider_receipt'));
  assert.equal(await readFile(path.join(f.directory, 'executions'), 'utf8'), 'ran\n');
  const count = f.requests.length;
  await service.close();
  service = await Service.open({ home: state, cwd: f.directory, config: f.config });
  assert.equal(f.requests.length, count, 'journal replay must not resend browser effects');
  await service.command({ op: 'send', task_id: 0, message: 'new message after restart' });
  page = await taskIdle(service);
  assert.equal(f.requests.at(-1).body.input.at(-1).content, 'new message after restart');
  assert.ok(f.requests.at(-1).body.previous_response_id);
  const forked = await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['child request'] });
  assert.equal(forked.reply.ok, true, JSON.stringify(forked.reply));
  await taskIdle(service, 1);
  await taskIdle(service, 0);
  const childRequest = f.requests.find(request => request.body.input.some(item => item.content === 'child request'));
  assert.ok(childRequest);
  assert.equal(childRequest.body.previous_response_id, undefined);
  assert.equal((await service.command({ op: 'compact', task_id: 0, summary: 'explicit replacement context' })).reply.ok, true);
  assert.equal((await service.command({ op: 'send', task_id: 0, message: 'continue with summary' })).reply.ok, true);
  await taskIdle(service);
  assert.equal(f.requests.at(-1).body.previous_response_id, undefined);
  assert.equal(await readFile(path.join(f.directory, 'executions'), 'utf8'), 'ran\n', 'no tool replay after restart or branch');
  assert.ok(notices.some(value => value.type === 'snapshot'));
  assert.deepEqual(f.failures, []);
});

test('independent approval and board callers consume the same normalized text interface', async t => {
  const f = await fixture(t, async (body, index) => {
    assert.deepEqual(body.tools, []);
    assert.equal(body.previous_response_id, undefined);
    assert.ok(!JSON.stringify(body).includes('first question'));
    if (index === 0) {
      assert.equal(JSON.parse(body.input[0].content).command.name, 'bash');
      return { output: answer('{"decision":"deny","reason":"Not authorized by the user."}') };
    }
    assert.equal(body.input[0].content, 'Draft a description.');
    return { output: answer('{"title":"Fixture","description":"A generated description."}') };
  });
  const review = await requestApproval({ ...baseEffect(), kind: 'approval',
    call: { id: 'a', name: 'bash', arguments: { command: 'pwd' } }, user_requests: ['Inspect only.'] }, f.config, f.directory, limits);
  assert.deepEqual(review, { decision: 'deny', reason: 'Not authorized by the user.' });
  const draft = await requestBoardText({ ...baseEffect(), kind: 'board_text', card_id: 3, prompt: 'Draft a description.' }, f.config, f.directory, limits);
  assert.deepEqual(draft, { title: 'Fixture', description: 'A generated description.' });
  for (const items of [[], [{ type: 'text', text: '{}' }, { type: 'text', text: '{}' }],
    [{ type: 'call', id: 'a', name: 'bash', arguments: {} }], [{ type: 'context', value: { type: 'provider_receipt' } }]]) {
    assert.throws(() => approvalOutcome(items, 400));
  }
  assert.deepEqual(f.failures, []);
});

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

test('committed steering cancels the original page and authorizes one explicit replacement root', { timeout: 10_000 }, async t => {
  const f = await fixture(t, async (_, index, transport) => {
    if (index === 0) { hold(transport); return; }
    return { output: answer('followed the new instruction') };
  });
  const state = path.join(f.directory, 'state');
  const service = await Service.open({ home: state, cwd: f.directory, config: f.config });
  t.after(() => service.close());
  const notices = []; service.on('notice', notice => notices.push(notice));
  assert.equal((await service.command({ op: 'create', profile: 'web', message: 'old instruction' })).reply.ok, true);
  await eventually(() => notices.some(notice => notice.type === 'snapshot'));
  assert.equal((await service.command({ op: 'steer', task_id: 0, message: 'replacement instruction' })).reply.ok, true);
  const page = await taskIdle(service);
  assert.ok(page.messages.some(item => item.role === 'assistant' && item.content === 'followed the new instruction'), JSON.stringify(page));
  await eventually(() => f.controls.length === 1);
  assert.equal(f.controls[0].action, 'cancel');
  assert.equal(f.requests.length, 2);
  assert.equal(f.requests[1].body.previous_response_id, undefined);
  assert.equal(f.requests[1].body.input.at(-1).content, 'replacement instruction');
  assert.deepEqual(f.failures, []);
});

test('service shutdown detaches observation without remote Stop or resend; explicit interruption permits replacement', { timeout: 10_000 }, async t => {
  const f = await fixture(t, async (_, index, transport) => {
    if (index === 0) { hold(transport); return; }
    return { output: answer('explicitly resumed task') };
  });
  const state = path.join(f.directory, 'state');
  let service = await Service.open({ home: state, cwd: f.directory, config: f.config });
  t.after(() => service.close());
  const notices = []; service.on('notice', notice => notices.push(notice));
  await service.command({ op: 'create', profile: 'web', message: 'keep original task' });
  await eventually(() => notices.some(notice => notice.type === 'snapshot'));
  await service.close();
  assert.equal(f.controls.length, 0);
  service = await Service.open({ home: state, cwd: f.directory, config: f.config });
  assert.equal(f.requests.length, 1);
  await service.command({ op: 'send', task_id: 0, message: 'ordinary retry must not duplicate unknown work' });
  let page = await taskIdle(service);
  assert.equal(f.requests.length, 1);
  assert.ok(page.messages.some(item => item.role === 'error' && item.content.includes('request retained')));
  await service.command({ op: 'interrupt', task_id: 0 });
  await eventually(() => f.controls.length === 1);
  await service.command({ op: 'send', task_id: 0, message: 'explicit replacement after interruption' });
  page = await taskIdle(service);
  assert.ok(page.messages.some(item => item.role === 'assistant' && item.content === 'explicitly resumed task'), JSON.stringify(page));
  assert.equal(f.requests.length, 2);
  assert.equal(f.requests[1].body.previous_response_id, undefined);
  assert.deepEqual(f.failures, []);
});

test('named SSE framing survives bytewise Unicode/CRLF splits and rejects incomplete or oversized frames', async () => {
  async function* bytes(text) { for (const byte of Buffer.from(text)) yield Buffer.from([byte]); }
  const text = ': heartbeat\r\nevent: response.output_text.snapshot\r\ndata: {"text":\r\ndata: "😀"}\r\n\r\ndata: [DONE]\r\n\r\n';
  const named = [];
  for await (const event of sseEvents(bytes(text), 1024)) named.push(event);
  assert.deepEqual(named, [{ event: 'response.output_text.snapshot', data: '{"text":\n"😀"}' }, { event: 'message', data: '[DONE]' }]);
  const data = [];
  for await (const event of events(bytes(text), 1024)) data.push(event);
  assert.deepEqual(data, named.map(event => event.data));
  for (const text of ['data: unfinished', 'data: no separator\n', 'event: ' + 'x'.repeat(120) + '\n\n']) {
    await assert.rejects(async () => { for await (const _ of sseEvents(bytes(text), 100)) assert.fail('bad frame accepted'); });
  }
});

test('aborting an observer retains its key without issuing remote cancellation or another POST', async t => {
  const f = await fixture(t, async (_, __, transport) => { hold(transport); });
  const controller = new AbortController();
  let key;
  await assert.rejects(f.run(baseEffect(), { signal: controller.signal, onSnapshot: () => controller.abort(new Error('detach observer')) }), error => {
    key = error.requestKey;
    return Boolean(key && error.responseId);
  });
  assert.equal(f.requests.length, 1);
  assert.equal(f.controls.length, 0);
  assert.equal(f.requests[0].key, key);
  await assert.rejects(f.run({ ...baseEffect(), ticket: 2 }), /retained/);
  assert.equal(f.requests.length, 1);
});

test('receipt input coverage preserves arrivals committed before the model reply was appended', async t => {
  const f = await fixture(t, async () => ({ output: answer('answer') }));
  const root = baseEffect();
  const first = await f.run(root);
  const arriving = { role: 'operation_result', operation_id: 7, call_id: 'older', tool: 'work', content: 'arrived during HTTP', is_error: false };
  const next = { ...root, ticket: 2, history: append([...root.history, arriving], first) };
  await f.run(next);
  assert.equal(f.requests[1].body.input.length, 1);
  assert.match(f.requests[1].body.input[0].content, /arrived during HTTP/);
  const changed = structuredClone(next); changed.history[0].content = 'mutated committed history';
  await assert.rejects(f.run(changed), /history no longer matches/);
  assert.equal(f.requests.length, 2);
});

test('a real background tool completion during HTTP is sent exactly once in the next web continuation', { timeout: 15_000 }, async t => {
  let service;
  const f = await fixture(t, async (body, index) => {
    if (index === 0) return { output: [
      call('fast', 'bash', { command: 'printf fast-result' }),
      call('slow', 'bash', { command: 'while [ ! -f release-slow ]; do sleep 0.01; done; printf slow-result' }),
    ] };
    if (index === 1) {
      const results = new Map(body.input.map(item => [item.call_id, JSON.parse(item.output)]));
      assert.equal(results.get('fast').value.stdout, 'fast-result');
      assert.equal(results.get('slow').value.status, 'running');
      await writeFile(path.join(f.directory, 'release-slow'), 'release after the committed request snapshot');
      await eventually(async () => (await service.command({ op: 'read', task_id: 0 })).reply.result.messages.some(item => item.role === 'operation_result'));
      return { output: answer('reply to the earlier snapshot') };
    }
    assert.equal(index, 2);
    assert.equal(body.input.length, 1);
    assert.equal(body.input[0].type, 'message');
    assert.match(body.input[0].content, /Asynchronous operation completed/);
    assert.match(body.input[0].content, /slow-result/);
    return { output: answer('observed the late result') };
  });
  service = await Service.open({ home: path.join(f.directory, 'state'), cwd: f.directory, config: f.config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'web', message: 'run overlapping tools' });
  const page = await taskIdle(service);
  assert.deepEqual(f.failures, [], JSON.stringify(page));
  assert.equal(f.requests.length, 3);
  assert.ok(page.messages.some(item => item.role === 'assistant' && item.content === 'observed the late result'));
});

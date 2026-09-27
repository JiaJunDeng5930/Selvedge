import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { requestModel, responseBody } from '../host/providers.mjs';
import { taskIdle } from './support.mjs';
import { chatgptFixture, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

const checkpoint = { type: 'compaction', id: 'cmp-fixture', encrypted_content: 'opaque-context-fixture',
  internal_chat_message_metadata_passthrough: { fixture: 'preserve exact bytes' } };
const assistant = text => ({ type: 'message', role: 'assistant', phase: 'final_answer', content: [{ type: 'output_text', text }] });
const summaryEffect = () => ({ ...modelEffect(), kind: 'summary', instructions: 'Text-summary instructions must not be used for ChatGPT',
  context_instructions: 'The same native assistant instructions', tools: [], callable: [] });
const isCompact = request => request.body?.input?.at(-1)?.type === 'compaction_trigger';
const catalog = { models: [{ slug: 'fixture-model', display_name: 'Fixture model', visibility: 'list', priority: 0,
  default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium' }] }] };

async function fixtureService(t, handle) {
  const upstream = await chatgptFixture(t, (request, response) => request.method === 'GET'
    ? jsonResponse(response, catalog) : handle(request, response));
  const config = validateConfig({ ...defaultConfig, profiles: {}, chatgpt: upstream.profile });
  let service = await Service.open({ home: upstream.directory, config, cwd: upstream.directory });
  t.after(() => service.close());
  return { ...upstream, get service() { return service; },
    key: Object.keys(service.config.profiles)[0],
    restart: async () => { await service.close(); service = await Service.open({ home: upstream.directory, config, cwd: upstream.directory }); },
  };
}

test('remote compaction v2 uses the Responses route, normal instructions and an opaque result', async t => {
  const upstream = await chatgptFixture(t, (request, response) => {
    assert.equal(request.url, '/backend-api/codex/responses');
    assert.equal(request.body.instructions, 'The same native assistant instructions');
    assert.deepEqual(request.body.input.at(-1), { type: 'compaction_trigger' });
    assert.equal(request.body.stream, true);
    assert.equal(request.body.store, false);
    assert.equal(request.body.tool_choice, 'auto');
    assert.deepEqual(request.body.tools, []);
    modelResponse(response, [{ type: 'reasoning', summary: [] }, checkpoint], [
      { type: 'response.output_text.delta', delta: 'Not a visible assistant response' },
    ]);
  });
  const deltas = [];
  const result = await requestModel(summaryEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits,
    { onDelta: text => deltas.push(text) });
  assert.deepEqual(result, [{ type: 'context', value: checkpoint }]);
  assert.deepEqual(deltas, []);
  const keyRequest = responseBody(summaryEffect(), { provider: 'responses' });
  assert.equal(keyRequest.instructions, summaryEffect().instructions);
  assert.notEqual(keyRequest.input.at(-1).type, 'compaction_trigger');
  assert.deepEqual(upstream.failures, []);
});

test('malformed, ambiguous, oversized or tool-bearing remote checkpoints never become summary text', async t => {
  for (const [name, output] of [
    ['empty', []], ['ordinary text', [assistant('not a native checkpoint')]],
    ['missing cipher', [{ type: 'compaction' }]],
    ['empty cipher', [{ ...checkpoint, encrypted_content: '' }]],
    ['oversized', [{ ...checkpoint, encrypted_content: 'x'.repeat(wireLimits.provider_checkpoint_limit_bytes + 1) }]],
    ['two checkpoints', [checkpoint, { ...checkpoint, id: 'second' }]],
    ['tool invocation', [checkpoint, { type: 'function_call', call_id: 'no', name: 'bash', arguments: '{}' }]],
  ]) await t.test(name, async t => {
    const upstream = await chatgptFixture(t, (_, response) => modelResponse(response, output));
    await assert.rejects(requestModel(summaryEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits), /compaction/i);
    assert.equal(upstream.requests.length, 1);
  });
  await t.test('a truncated compaction stream is not silently retried', async t => {
    const upstream = await chatgptFixture(t, (_, response) => {
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.end(`data: ${JSON.stringify({ type: 'response.output_item.done', output_index: 0, item: checkpoint })}\n\n`);
    });
    await assert.rejects(requestModel(summaryEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits), /without a completed/);
    assert.equal(upstream.requests.length, 1);
  });
});

test('automatic remote compaction crosses native scheduling, HTTP, SQLite, replay and UI projection', { timeout: 20_000 }, async t => {
  const longAnswer = 'Original model work. '.repeat(7500);
  let modelCalls = 0;
  let compactCalls = 0;
  let firstInstructions;
  const running = await fixtureService(t, (request, response) => {
    if (isCompact(request)) {
      compactCalls++;
      assert.equal(request.body.instructions, firstInstructions);
      assert.ok(request.body.input.some(item => item.content?.[0]?.text === longAnswer));
      modelResponse(response, [checkpoint]);
    } else {
      modelCalls++;
      firstInstructions ??= request.body.instructions;
      if (modelCalls > 1) {
        assert.deepEqual(request.body.input.filter(item => item.type === 'compaction'), [checkpoint]);
        assert.equal(request.body.input.some(item => item.content?.[0]?.text === longAnswer), false);
        assert.ok(request.body.input.some(item => item.role === 'user' && item.content === 'Original user request.'));
        assert.ok(request.body.input.some(item => item.role === 'user' && item.content === 'Continue after large output.'));
      }
      modelResponse(response, [assistant(modelCalls === 1 ? longAnswer : 'Continued from the provider checkpoint.')]);
    }
  });
  await running.service.command({ op: 'create', profile: running.key, message: 'Original user request.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after large output.' });
  let page = await taskIdle(running.service);
  assert.equal(compactCalls, 1);
  assert.equal(modelCalls, 2);
  assert.ok(page.messages.some(message => message.role === 'model_context' && message.content.content?.[0]?.text === longAnswer));
  assert.deepEqual(page.messages.filter(message => message.content?.type === 'compaction').map(message => message.content), [checkpoint]);
  const presentation = await running.service.presentation({ event: { type: 'select', task_id: 0 } });
  // The existing native UI already understands opaque provider context; no UI model is extended.
  assert.equal(presentation.reply.ok, true);
  assert.ok(JSON.stringify(presentation.reply).includes('Provider context retained'));
  await running.restart();
  assert.equal(compactCalls, 1);
  assert.equal(modelCalls, 2);
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after restart.' });
  page = await taskIdle(running.service);
  assert.equal(modelCalls, 3);
  assert.equal(compactCalls, 1);
  assert.ok(page.messages.some(message => message.content.content?.[0]?.text === longAnswer));
  assert.deepEqual(running.failures, []);
});

test('an explicit context-limit error gets one remote checkpoint and persistent overflow stops', async t => {
  let compactCalls = 0;
  let models = 0;
  const running = await fixtureService(t, (request, response) => {
    if (isCompact(request)) { compactCalls++; modelResponse(response, [checkpoint]); }
    else { models++; jsonResponse(response, { error: { code: 'context_length_exceeded', message: 'private upstream details' } }, 400); }
  });
  await running.service.command({ op: 'create', profile: running.key, message: 'A small request.' });
  const page = await taskIdle(running.service);
  assert.equal(compactCalls, 1);
  assert.equal(models, 2);
  assert.ok(page.messages.some(message => message.role === 'error' && message.content.includes('persists after compaction')));
  assert.equal(JSON.stringify(page).includes('private upstream details'), false);
  assert.deepEqual(running.failures, []);
});

test('manual compaction does not start a new turn and cancelled compaction cannot install a late checkpoint', async t => {
  let compactCalls = 0;
  let models = 0;
  let pending;
  let started;
  const requested = new Promise(resolve => { started = resolve; });
  const running = await fixtureService(t, (request, response) => {
    if (isCompact(request)) {
      if (++compactCalls === 1) modelResponse(response, [checkpoint]);
      else { pending = response; response.writeHead(200, { 'content-type': 'text/event-stream' }); response.flushHeaders(); started(); }
    } else { models++; modelResponse(response, [assistant('Finished.')]); }
  });
  await running.service.command({ op: 'create', profile: running.key, message: 'A task.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 });
  await taskIdle(running.service);
  assert.equal(models, 1);
  await running.service.command({ op: 'send', task_id: 0, message: 'More work before another checkpoint.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 });
  await requested;
  await running.service.command({ op: 'interrupt', task_id: 0 });
  pending.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [{ ...checkpoint, id: 'late' }] } })}\n\n`);
  await delay(30);
  const page = await taskIdle(running.service);
  assert.equal(page.task.status, 'stopped');
  assert.deepEqual(page.messages.filter(message => message.content?.type === 'compaction').map(message => message.content), [checkpoint]);
  assert.equal(models, 2);
  assert.deepEqual(running.failures, []);
});

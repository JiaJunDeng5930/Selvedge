import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { requestModel, responseBody } from '../host/providers.mjs';
import { taskIdle } from './support.mjs';
import { chatgptFixture, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

const checkpoint = 'Retain the original user request and continue the unfinished work.';
const assistant = text => ({ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] });
const summaryEffect = () => ({ ...modelEffect(), kind: 'summary', instructions: 'Summarize this task for continuation by the same assistant.',
  context_instructions: 'The same native assistant instructions', tools: [], callable: [] });
const isSummary = request => request.body?.instructions?.startsWith('Summarize this task for continuation');
const catalog = { models: [{ slug: 'fixture-model', display_name: 'Fixture model', visibility: 'list' }] };

async function fixtureService(t, handle) {
  const upstream = await chatgptFixture(t, (request, response) => request.method === 'GET'
    ? jsonResponse(response, catalog) : handle(request, response));
  const config = validateConfig({ ...defaultConfig, profiles: {}, chatgpt: {
    ...upstream.profile, auth_file: path.join(upstream.directory, upstream.profile.auth_file),
  } });
  let service = await Service.open({ home: path.join(upstream.directory, 'state'), config, cwd: upstream.directory });
  t.after(() => service.close());
  return { ...upstream, get service() { return service; }, key: Object.keys(service.config.profiles)[0],
    restart: async () => { await service.close(); service = await Service.open({ home: path.join(upstream.directory, 'state'), config, cwd: upstream.directory }); },
  };
}

test('official Responses summary uses bounded text instructions and no tools or preview fields', async t => {
  const upstream = await chatgptFixture(t, (request, response) => {
    assert.equal(request.url, '/v1/responses');
    assert.equal(request.body.instructions, summaryEffect().instructions);
    assert.equal(request.body.tool_choice, 'none'); assert.deepEqual(request.body.tools, []);
    modelResponse(response, [assistant(checkpoint)], [{ type: 'response.output_text.delta', delta: 'hidden summary delta' }]);
  });
  const deltas = [];
  const result = await requestModel(summaryEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits,
    { onDelta: text => deltas.push(text) });
  assert.deepEqual(result, [{ type: 'context', value: assistant(checkpoint) }]); assert.deepEqual(deltas, []);
  const request = responseBody({ ...summaryEffect(), model: { ...summaryEffect().model,
    adaptive_reasoning: { transport: 'configuration_update' } }, sampling: { request_effort: 'medium', effective_effort: 'medium' } }, { provider: 'chatgpt' });
  assert.equal(request.instructions, summaryEffect().instructions);
  assert.equal(request.input.some(item => item.type === 'compaction_trigger'), false);
  assert.deepEqual(upstream.failures, []);
});

test('empty, oversized and tool-bearing summaries are rejected by the native checkpoint boundary', async t => {
  for (const [name, output] of [
    ['empty', []], ['oversized', [assistant('x'.repeat(16385))]],
    ['tool invocation', [assistant(checkpoint), { type: 'function_call', namespace: 'selvedge', call_id: 'no', name: 'bash', arguments: '{}' }]],
  ]) await t.test(name, async t => {
    const running = await fixtureService(t, (request, response) => modelResponse(response, isSummary(request) ? output : [assistant('Finished.')]));
    await running.service.command({ op: 'create', profile: running.key, message: 'An objective.' });
    await taskIdle(running.service);
    await running.service.command({ op: 'compact', task_id: 0 });
    const page = await taskIdle(running.service);
    assert.equal(page.messages.some(message => message.role === 'context_summary'), false);
    assert.ok(page.messages.some(message => message.role === 'error'));
    assert.deepEqual(running.failures, []);
  });
  await t.test('a truncated summary stream is not silently retried', async t => {
    const upstream = await chatgptFixture(t, (_, response) => {
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.end(`data: ${JSON.stringify({ type: 'response.output_item.done', output_index: 0, item: assistant(checkpoint) })}\n\n`);
    });
    await assert.rejects(requestModel(summaryEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits), /without a completed/);
    assert.equal(upstream.requests.length, 1);
  });
});

test('automatic text checkpoint keeps original read_task history and survives native restart and UI rendering', async t => {
  let compactCalls = 0, modelCalls = 0;
  const longAnswer = 'x'.repeat(140000);
  const largeOutputSummary = 'The original request produced a large output. The latest user request is: Continue after large output.';
  const running = await fixtureService(t, (request, response) => {
    if (isSummary(request)) {
      compactCalls++;
      assert.ok(request.body.input.some(item => item.role === 'user' && item.content === 'Continue after large output.'));
      modelResponse(response, [assistant(largeOutputSummary)]);
    }
    else {
      modelCalls++;
      if (modelCalls > 1) {
        assert.ok(request.body.input.some(item => item.role === 'user' && typeof item.content === 'string' && item.content.includes(largeOutputSummary)));
        assert.equal(request.body.input.some(item => item.content?.[0]?.text === longAnswer), false);
      }
      modelResponse(response, [assistant(modelCalls === 1 ? longAnswer : 'Continued from the text summary.')]);
    }
  });
  await running.service.command({ op: 'create', profile: running.key, message: 'Original user request.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after large output.' });
  let page = await taskIdle(running.service);
  assert.deepEqual(running.failures, []);
  assert.equal(compactCalls, 1); assert.equal(modelCalls, 2);
  assert.ok(page.messages.some(message => message.role === 'model_context' && message.content.content?.[0]?.text === longAnswer));
  assert.deepEqual(page.messages.filter(message => message.role === 'context_summary').map(message => message.content), [largeOutputSummary]);
  const presentation = await running.service.presentation({ event: { type: 'select', task_id: 0 } });
  assert.equal(presentation.reply.ok, true); assert.ok(JSON.stringify(presentation.reply).includes(largeOutputSummary));
  await running.restart();
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after restart.' });
  page = await taskIdle(running.service);
  assert.equal(modelCalls, 3); assert.equal(compactCalls, 1);
  assert.ok(page.messages.some(message => message.content.content?.[0]?.text === longAnswer));
  assert.deepEqual(running.failures, []);
});

test('explicit context-limit error gets one text checkpoint and persistent overflow stops', async t => {
  let compactCalls = 0, models = 0;
  const running = await fixtureService(t, (request, response) => {
    if (isSummary(request)) { compactCalls++; modelResponse(response, [assistant(checkpoint)]); }
    else { models++; jsonResponse(response, { error: { code: 'context_length_exceeded', message: 'private upstream details' } }, 400); }
  });
  await running.service.command({ op: 'create', profile: running.key, message: 'A small request.' });
  const page = await taskIdle(running.service);
  assert.equal(compactCalls, 1); assert.equal(models, 2);
  assert.ok(page.messages.some(message => message.role === 'error' && message.content.includes('persists after compaction')));
  assert.equal(JSON.stringify(page).includes('private upstream details'), false);
  assert.deepEqual(running.failures, []);
});

test('manual summary starts no turn and cancelled summary cannot install a late checkpoint', async t => {
  let compactCalls = 0, models = 0, pending, started;
  const requested = new Promise(resolve => { started = resolve; });
  const running = await fixtureService(t, (request, response) => {
    if (isSummary(request)) {
      if (++compactCalls === 1) modelResponse(response, [assistant(checkpoint)]);
      else { pending = response; response.writeHead(200, { 'content-type': 'text/event-stream' }); response.flushHeaders(); started(); }
    } else { models++; modelResponse(response, [assistant('Finished.')]); }
  });
  await running.service.command({ op: 'create', profile: running.key, message: 'A task.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 }); await taskIdle(running.service);
  assert.equal(models, 1);
  await running.service.command({ op: 'send', task_id: 0, message: 'More work before another checkpoint.' }); await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 }); await requested;
  await running.service.command({ op: 'interrupt', task_id: 0 });
  pending.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [assistant('late summary')] } })}\n\n`);
  await delay(30);
  const page = await taskIdle(running.service);
  assert.equal(page.task.status, 'stopped');
  assert.deepEqual(page.messages.filter(message => message.role === 'context_summary').map(message => message.content), [checkpoint]);
  assert.equal(models, 2); assert.deepEqual(running.failures, []);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { interactiveMarkdownFixture } from './fixtures/interactive-markdown.mjs';
import { taskIdle } from './support.mjs';
import { events } from '../host/network.mjs';

async function until(predicate, description) {
  const deadline = Date.now() + 10_000;
  do {
    const value = await predicate();
    if (value) return value;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Timed out: ${description}`);
}
const speech = text => ({ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] });

test('large SSE snapshots and later deltas remain connected through a commit', async t => {
  const fixture = await interactiveMarkdownFixture();
  t.after(() => fixture.close());
  const notices = [];
  fixture.running.service.on('notice', event => notices.push(event));
  const created = await fixture.command({ op: 'create', profile: 'interactive', message: 'Large SSE transport fixture' });
  assert.equal(created.reply.ok, true);
  const task = created.reply.result.task_id;
  await until(() => fixture.requests.length === 1, 'actual model stream');
  const large = 'x'.repeat(128 * 1024);
  assert.ok(Buffer.byteLength(large) < fixture.running.service.limits.frame_bytes);
  fixture.emit(0, large);
  await until(() => notices.some(event => event.type === 'delta' && event.text === large), 'large preview accepted before subscribing');
  let eventWriter;
  fixture.running.server.on('request', (request, writer) => {
    if (request.url === '/api/events') eventWriter = writer;
  });
  const controller = new AbortController();
  const response = await fetch(`${fixture.running.address}/api/events`, {
    headers: { authorization: `Bearer ${fixture.running.token}` },
    signal: controller.signal,
  });
  assert.equal(response.status, 200);
  assert.ok(eventWriter && Buffer.byteLength(large) > eventWriter.writableHighWaterMark,
    'the legal event fixture must exceed the real HTTP writer high-water mark');
  const iterator = events(response.body, fixture.running.service.limits.frame_bytes);
  t.after(async () => { controller.abort(); await iterator.return().catch(() => {}); });
  const next = async () => {
    const result = await iterator.next();
    assert.equal(result.done, false, 'the authenticated event connection ended');
    return JSON.parse(result.value);
  };
  const snapshot = await next();
  assert.equal(snapshot.type, 'stream-state');
  assert.equal(snapshot.namespace, fixture.running.service.journal.namespace);
  assert.equal(snapshot.streams.length, 1);
  assert.equal(snapshot.streams[0].task_id, task);
  const ticket = snapshot.streams[0].ticket;
  assert.deepEqual(snapshot.streams[0].parts, [{ output_index: 0, text: large }]);
  const revision = await next();
  assert.deepEqual(revision, { type: 'commit', namespace: snapshot.namespace, sequence: fixture.running.service.journal.sequence });
  fixture.emit(0, large);
  assert.deepEqual(await next(), { type: 'delta', namespace: snapshot.namespace, task_id: task, ticket, output_index: 0, text: large });
  const suffix = ' followed by another real delta';
  fixture.emit(0, suffix);
  assert.deepEqual(await next(), { type: 'delta', namespace: snapshot.namespace, task_id: task, ticket, output_index: 0, text: suffix });
  fixture.finish(0, { text: 'Completed after the large preview.' });
  let commit;
  do { commit = await next(); } while (commit.type !== 'commit');
  assert.equal(commit.namespace, snapshot.namespace);
  assert.ok(commit.sequence > revision.sequence);
  await taskIdle(fixture.running.service, task);
  assert.deepEqual(fixture.failures, []);
});

test('actual SSE sparse output indices remain the committed speech origins across reasoning and tool slots', async t => {
  const fixture = await interactiveMarkdownFixture();
  t.after(() => fixture.close());
  const notices = [];
  fixture.running.service.on('notice', event => notices.push(event));
  const created = await fixture.command({ op: 'create', profile: 'interactive', message: 'Sparse output identity fixture' });
  assert.equal(created.reply.ok, true);
  const task = created.reply.result.task_id;
  await until(() => fixture.requests.length === 1, 'first actual model request');
  fixture.emit(0, 'First live ', 1);
  fixture.emit(0, 'answer.', 1);
  fixture.emit(0, 'Second live answer.', 4);
  await until(() => notices.filter(event => event.type === 'delta').length === 3, 'SSE deltas at application service');
  const previews = notices.filter(event => event.type === 'delta');
  assert.deepEqual(previews.map(value => value.output_index), [1, 1, 4]);
  assert.ok(previews.every(value => value.namespace === fixture.running.service.journal.namespace));
  assert.ok(previews.every(value => value.task_id === task && value.ticket === previews[0].ticket));
  const authorization = { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' };
  const observed = await fetch(`${fixture.running.address}/api/browser/observation`, {
    method: 'POST', headers: authorization, body: JSON.stringify({ kind: 'streams' }),
  });
  assert.equal(observed.status, 200);
  const streamEnvelope = await observed.json();
  assert.equal(streamEnvelope.namespace, fixture.running.service.journal.namespace);
  assert.equal(streamEnvelope.streams.length, 1);
  assert.equal(streamEnvelope.streams[0].namespace, streamEnvelope.namespace);
  const controller = new AbortController();
  const eventResponse = await fetch(`${fixture.running.address}/api/events`, { headers: authorization, signal: controller.signal });
  const iterator = events(eventResponse.body, fixture.running.service.limits.frame_bytes);
  try {
    const first = JSON.parse((await iterator.next()).value);
    assert.equal(first.type, 'stream-state');
    assert.equal(first.namespace, streamEnvelope.namespace);
    assert.deepEqual(first.streams, streamEnvelope.streams);
  } finally {
    controller.abort();
    await iterator.return().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
  fixture.finish(0, { output: [
    { type: 'reasoning', id: 'reasoning-before', summary: [{ type: 'summary_text', text: 'Reasoning before speech.' }] },
    speech('First live answer.'),
    { type: 'function_call', call_id: 'list-graphs', name: 'list_task_graphs', arguments: '{}' },
    { type: 'reasoning', id: 'reasoning-between', summary: [{ type: 'summary_text', text: 'Reasoning between speech.' }] },
    speech('Second live answer.'),
  ] });
  await until(() => fixture.requests.length === 2, 'actual follow-up after native graph listing');
  fixture.finish(1, { text: 'Finished after the native tool.' });
  const completed = await taskIdle(fixture.running.service, task);
  const contexts = completed.messages.filter(value => value.role === 'model_context');
  assert.ok(contexts.every(value => value.content.type === 'provider_receipt'));
  const messages = contexts.filter(value => value.content.item.type === 'message' && value.content.item.role === 'assistant');
  assert.equal(messages.length, 3);
  assert.deepEqual(messages.map(value => value.content.item), [
    speech('First live answer.'), speech('Second live answer.'), speech('Finished after the native tool.'),
  ]);
  for (const [content, part] of [['First live answer.', 1], ['Second live answer.', 4]]) {
    const message = messages.find(value => value.content.item.content[0].text === content);
    assert.deepEqual(message.origin, { producer_task: task, operation: previews[0].ticket, part, mode: 'interactive-v1' });
  }
  const reasoning = contexts.filter(value => value.content.item.type === 'reasoning');
  assert.deepEqual(reasoning.map(value => value.content.item), [
    { type: 'reasoning', id: 'reasoning-before', summary: [{ type: 'summary_text', text: 'Reasoning before speech.' }] },
    { type: 'reasoning', id: 'reasoning-between', summary: [{ type: 'summary_text', text: 'Reasoning between speech.' }] },
  ]);
  assert.deepEqual(reasoning.map(value => value.origin), [0, 3].map(part => ({
    producer_task: task, operation: previews[0].ticket, part, mode: 'plain',
  })));
  assert.ok(completed.messages.some(value => value.role === 'function_call' && value.content.name === 'list_task_graphs'));
  assert.deepEqual(fixture.failures, []);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';

async function eventually(observe) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const result = await observe();
    if (result) return result;
    await delay(5);
  }
  assert.fail('Audio public behavior did not settle within five seconds');
}

function transport(upgradeStatus = () => undefined) {
  const sockets = [];
  class Socket extends EventTarget {
    readyState = 0;
    sent = [];
    handlers = new Map();
    constructor() {
      super(); sockets.push(this);
      const rejection = upgradeStatus(sockets.length - 1);
      queueMicrotask(() => {
        if (rejection) this.handlers.get('unexpected-response')({}, { statusCode: rejection, destroy() {} });
        else { this.readyState = 1; this.dispatchEvent(new Event('open')); }
      });
    }
    on(name, listener) { this.handlers.set(name, listener); }
    send(value) { this.sent.push(JSON.parse(value)); }
    close() { this.readyState = 3; this.dispatchEvent(Object.assign(new Event('close'), { code: 1000 })); }
    terminate() { this.close(); }
    provider(value) { this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(value) })); }
  }
  return {
    sockets,
    options: {
      WebSocketImpl: Socket,
      authorityFactory: () => ({
        async connections() { return [{ id: 'audio-fixture', source: 'chatgpt_audio', authorized: true }]; },
        async authorize() { return { headers: {}, account_id: 'test-account' }; },
        async close() {},
      }),
      fetchImpl: async () => new Response('v=0\r\n', { status: 201, headers: { location: 'https://api.openai.com/v1/live/rtc_test' } }),
    },
  };
}

async function serviceFixture(t, wire = transport()) {
  const home = await mkdtemp(path.join(os.tmpdir(), 'selvedge-audio-'));
  const service = await Service.open({ home, cwd: home,
    config: validateConfig({ ...defaultConfig, chatgpt: false }), audioOptions: wire.options });
  t.after(async () => { await service.close(); await rm(home, { recursive: true, force: true }); });
  const created = await service.command({ op: 'create_idle', profile: 'demo' });
  assert.equal(created.reply.ok, true);
  const task_id = created.reply.result.task_id;
  const read = async () => (await service.command({ op: 'read', task_id })).reply.result.messages;
  return { service, wire, task_id, read, directory: home };
}

test('voice control resolves referenced turns, commits before publication and flushes tails once', async t => {
  const { service, wire, task_id, read } = await serviceFixture(t);
  const published = [];
  const visibleCommits = [];
  service.on('audio', event => {
    published.push(event);
    if (event.type === 'transcript' && event.final) visibleCommits.push(read().then(messages =>
      assert.ok(messages.some(message => message.item_id === event.item_id), 'A final transcript must already be committed when published')));
  });
  const result = await service.audioCreate({ browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' });
  await eventually(() => published.some(event => event.type === 'ready'));
  const socket = wire.sockets[0];
  socket.provider({ type: 'delegation.created', item: { type: 'delegation', target: 'client', id: 'work', user_bidi_turn_id: 'turn', content: [] } });
  socket.provider({ type: 'delegation.created', item: { type: 'delegation', target: 'client', id: 'next-work', user_bidi_turn_id: 'turn', content: [] } });
  socket.provider({ type: 'turn.created', turn: { role: 'user', id: 'turn', transcript: 'Please explain the answer' } });
  const accepted = await eventually(() => socket.sent.find(event => event.type === 'delegation.context.append' && event.delegation_item_id === 'work'));
  assert.match(accepted.content[0].text, /accepted the requested work/);
  assert.ok((await read()).some(message => message.role === 'speech_delegation_receipt' && message.delegation_id === 'work' && message.content === 'Please explain the answer'));
  await eventually(() => socket.sent.some(event => event.type === 'delegation.context.append' && event.delegation_item_id === 'next-work'));
  assert.deepEqual((await read()).filter(message => message.role === 'speech_delegation_receipt').map(message => message.delegation_id), ['work', 'next-work']);
  socket.provider({ type: 'output_transcript.added', item: { text: 'unfinished answer' } });
  await eventually(() => published.some(event => event.type === 'transcript' && event.text === 'unfinished answer'));
  await Promise.all([service.audioStop(result.id, 'browser'), service.audioDisconnect(result.id, 'browser')]);
  socket.provider({ type: 'turn.done', turn: { role: 'assistant', id: 'late', transcript: 'late callback' } });
  await delay(10);
  const messages = await read();
  assert.equal(messages.filter(message => message.role === 'speech_transcript' && message.content === 'unfinished answer').length, 1);
  assert.equal(messages.some(message => message.item_id === 'late'), false);
  assert.equal(published.filter(event => event.type === 'stopped').length, 1);
  await Promise.all(visibleCommits);
});

test('a stopped voice session cannot close or write to the same browser after reconnect', async t => {
  const { service, wire, task_id, read } = await serviceFixture(t);
  const events = [];
  service.on('audio', event => events.push(event));
  const input = { browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' };
  const first = await service.audioCreate(input);
  await eventually(() => events.some(event => event.type === 'ready' && event.session_id === first.id));
  await service.audioStop(first.id, input.browser_id);
  const second = await service.audioCreate(input);
  assert.notEqual(second.id, first.id);
  await eventually(() => events.some(event => event.type === 'ready' && event.session_id === second.id));
  wire.sockets[0].provider({ type: 'output_transcript.added', item: { text: 'retired data' } });
  wire.sockets[0].close();
  wire.sockets[1].provider({ type: 'turn.done', turn: { role: 'user', id: 'current', transcript: 'current input' } });
  await eventually(async () => (await read()).some(message => message.item_id === 'current' && message.content === 'current input'));
  assert.equal((await read()).some(message => message.content === 'retired data'), false);
  assert.equal(events.some(event => event.text === 'retired data'), false);
  assert.equal(events.some(event => event.session_id === second.id && ['error', 'stopped'].includes(event.type)), false);
  await service.audioStop(second.id, input.browser_id);
});


test('voice activation recovers from an initial 404 and reports a persistent 404 failure', async t => {
  for (const recovers of [true, false]) {
    const { service, wire, task_id } = await serviceFixture(t, transport(attempt => recovers && attempt > 0 ? undefined : 404));
    const events = [];
    service.on('audio', event => events.push(event));
    const session = await service.audioCreate({ browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' });
    await eventually(() => events.some(event => event.type === (recovers ? 'ready' : 'stopped')));
    assert.ok(wire.sockets.length > 1);
    assert.equal(events.filter(event => event.type === 'ready').length, recovers ? 1 : 0);
    assert.equal(events.filter(event => event.type === 'error').length, recovers ? 0 : 1);
    if (recovers) await service.audioStop(session.id, 'browser');
  }
});

test('stopping voice drains received transcripts and its final tail once into Task history', async t => {
  const { service, wire, task_id, read } = await serviceFixture(t);
  const events = [];
  service.on('audio', event => events.push(event));
  const session = await service.audioCreate({ browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' });
  await eventually(() => events.some(event => event.type === 'ready'));
  const socket = wire.sockets[0];
  socket.provider({ type: 'turn.done', turn: { role: 'assistant', id: 'first', transcript: 'first committed answer' } });
  socket.provider({ type: 'turn.done', turn: { role: 'assistant', id: 'second', transcript: 'second received answer' } });
  socket.provider({ type: 'output_transcript.added', item: { text: 'latest unfinished tail' } });
  await service.audioStop(session.id, 'browser');
  const expected = ['first committed answer', 'second received answer', 'latest unfinished tail'];
  assert.deepEqual((await read()).filter(message => message.role === 'speech_transcript').map(message => message.content), expected);
  assert.deepEqual(events.filter(event => event.type === 'transcript' && event.final).map(event => event.text), expected);
  assert.equal(events.filter(event => event.type === 'stopped').length, 1);
});

test('a failed speech journal write publishes no acceptance and reopens with only its committed prefix', async t => {
  const { service, wire, task_id, read, directory } = await serviceFixture(t);
  const events = [];
  service.on('audio', event => events.push(event));
  const session = await service.audioCreate({ browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' });
  await eventually(() => events.some(event => event.type === 'ready'));
  const socket = wire.sockets[0];
  socket.provider({ type: 'turn.done', turn: { role: 'user', id: 'prefix', transcript: 'acknowledged speech' } });
  await eventually(() => events.some(event => event.item_id === 'prefix' && event.final));
  const committed = (await read()).filter(message => message.role === 'speech_transcript');
  assert.deepEqual(committed.map(message => [message.item_id, message.content]), [['prefix', 'acknowledged speech']]);
  const database = new DatabaseSync(path.join(directory, 'journal.sqlite'));
  try {
    database.exec("CREATE TRIGGER reject_speech_write BEFORE INSERT ON journal BEGIN SELECT RAISE(ABORT, 'speech disk write failed'); END");
    socket.provider({ type: 'turn.done', turn: { role: 'user', id: 'rejected', transcript: 'uncommitted request' } });
    socket.provider({ type: 'turn.done', turn: { role: 'user', id: 'suffix', transcript: 'must not commit after failure' } });
    socket.provider({ type: 'delegation.created', item: { type: 'delegation', target: 'client', id: 'unaccepted-work', user_bidi_turn_id: 'rejected', content: [] } });
    socket.provider({ type: 'output_transcript.added', item: { text: 'failed session tail' } });
    await service.audioStop(session.id, 'browser');
    await assert.rejects(service.command({ op: 'read', task_id }), /speech disk write failed/);
    assert.deepEqual(events.filter(event => event.type === 'transcript' && event.final).map(event => event.item_id), ['prefix']);
    assert.equal(socket.sent.some(event => event.type === 'delegation.context.append' && event.delegation_item_id === 'unaccepted-work'), false);
    await service.close();
    database.exec('DROP TRIGGER reject_speech_write');
  } finally { database.close(); }
  const reopened = await Service.open({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }), audioOptions: wire.options });
  try {
    const recovered = await reopened.command({ op: 'read', task_id });
    assert.equal(recovered.reply.ok, true);
    assert.deepEqual(recovered.reply.result.messages.filter(message => message.role === 'speech_transcript'), committed);
    assert.equal(recovered.reply.result.messages.some(message => message.role === 'speech_delegation_receipt'), false);
  } finally { await reopened.close(); }
});

test('accepted Task progress reaches the active voice provider', async t => {
  const { service, wire, task_id, read } = await serviceFixture(t);
  const events = [];
  service.on('audio', event => events.push(event));
  const session = await service.audioCreate({ browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' });
  await eventually(() => events.some(event => event.type === 'ready'));
  const messages = ['first progress delivery', 'second progress delivery'];
  assert.equal((await service.command({ op: 'send', task_id, message: messages[0] })).reply.ok, true);
  await eventually(async () => (await read()).some(message => message.role === 'model_context' && message.content?.item?.role === 'assistant'));
  assert.equal((await service.command({ op: 'send', task_id, message: messages[1] })).reply.ok, true);
  await eventually(async () => (await read()).filter(message => message.role === 'model_context' && message.content?.item?.role === 'assistant').length === 2);
  await eventually(() => {
    const progress = wire.sockets[0].sent.flatMap(event => event.content ?? []).map(part => part.text ?? '')
      .filter(text => text.includes('progress ('));
    return messages.every(message => progress.some(text => text.includes(message)));
  });
  await service.audioStop(session.id, 'browser');
});

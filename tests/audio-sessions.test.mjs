import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { createChatGPTAudio } from '../host/chatgpt-audio.mjs';

async function eventually(observe) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const result = await observe();
    if (result) return result;
    await delay(5);
  }
  assert.fail('Audio public behavior did not settle within five seconds');
}

function transport(upgradeStatuses = []) {
  const sockets = [];
  class Socket extends EventTarget {
    readyState = 0;
    sent = [];
    handlers = new Map();
    constructor() {
      super(); sockets.push(this);
      const rejection = upgradeStatuses[sockets.length - 1];
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

async function serviceFixture(t, options = {}) {
  const home = await mkdtemp(path.join(os.tmpdir(), 'selvedge-audio-'));
  const wire = transport();
  const service = await Service.open({ home, cwd: home,
    config: validateConfig({ ...defaultConfig, chatgpt: false }), audioOptions: wire.options, ...options });
  t.after(async () => { await service.close(); await rm(home, { recursive: true, force: true }); });
  const created = await service.command({ op: 'create_idle', profile: 'demo' });
  assert.equal(created.reply.ok, true);
  const task_id = created.reply.result.task_id;
  const read = async () => (await service.command({ op: 'read', task_id })).reply.result.messages;
  return { service, wire, task_id, read };
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

test('old generations cannot commit to a live browser session', async t => {
  let receive, request;
  const { service, task_id, read } = await serviceFixture(t, {
    audioFactory: options => {
      receive = options.onEvent;
      return {
        async createSession(value) { request = value; return { id: value.id, sdp: 'v=0' }; },
        async appendContext() {}, async stopSession() {}, async close() {},
      };
    },
  });
  const session = await service.audioCreate({ browser_id: 'browser', connection: 'audio-fixture', task_id, sdp: 'v=0' });
  const event = { session_id: session.id, task_id, type: 'transcript', final: true, role: 'user', item_id: 'stale', text: 'stale input' };
  await receive({ ...event, generation: 'retired-generation' });
  assert.equal((await read()).some(message => message.item_id === 'stale'), false);
  await receive({ ...event, generation: request.generation, item_id: 'current', text: 'current input' });
  assert.ok((await read()).some(message => message.item_id === 'current'));
});

test('a released sideband callback cannot close or write to a replacement with the same id', async t => {
  const wire = transport(), events = [];
  const audio = createChatGPTAudio({ home: '/unused-audio-fixture', ...wire.options, onEvent: async event => events.push(event) });
  t.after(() => audio.close());
  const input = { id: 'shared-id', connection: 'audio-fixture', task_id: 0, sdp: 'v=0' };
  await audio.createSession({ ...input, generation: 'first' });
  await eventually(() => events.some(event => event.type === 'ready'));
  await audio.stopSession(input.id);
  await audio.createSession({ ...input, generation: 'second' });
  await eventually(() => events.some(event => event.type === 'ready' && event.generation === 'second'));
  wire.sockets[0].provider({ type: 'output_transcript.added', item: { text: 'retired data' } });
  wire.sockets[0].close();
  await delay(10);
  assert.equal(await audio.appendContext(input.id, { text: 'current context' }), true);
  assert.equal(wire.sockets[1].sent.at(-1).content[0].text, 'current context');
  assert.equal(events.some(event => event.text === 'retired data'), false);
});


test('voice activation retries only its bounded 404 window and reports exhaustion', async t => {
  for (const failures of [3, 4]) {
    const wire = transport(Array(failures).fill(404)), events = [];
    const audio = createChatGPTAudio({ home: '/unused-audio-fixture', ...wire.options, onEvent: async event => events.push(event) });
    t.after(() => audio.close());
    await audio.createSession({ id: `activation-${failures}`, connection: 'audio-fixture', task_id: 0, sdp: 'v=0' });
    await eventually(() => events.some(event => event.type === (failures === 3 ? 'ready' : 'closed')));
    assert.equal(wire.sockets.length, 4);
    assert.equal(events.filter(event => event.type === 'ready').length, failures === 3 ? 1 : 0);
    assert.equal(events.filter(event => event.type === 'error').length, failures === 4 ? 1 : 0);
    await audio.close();
  }
});

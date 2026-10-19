import test from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { authorize } from '../host/chatgpt-account.mjs';
import { createChatGPTAudio } from '../host/chatgpt-audio.mjs';
import { chatgptFixture } from './fixtures/chatgpt.mjs';

async function audioFixture(t) {
  const account = await chatgptFixture(t);
  await account.seedExpiredCredential();
  const requests = [], messages = [], observed = [], controlSockets = [];
  const options = { rejectASR: 0, initialize: true, holdAudio: false, activationFailures: 0, source: 'codex_audio' };
  let control;
  const server = Bun.serve({ hostname: '127.0.0.1', port: 0,
    async fetch(request, server) {
      const url = new URL(request.url);
      const entry = { path: url.pathname, headers: Object.fromEntries(request.headers) };
      requests.push(entry);
      if (url.pathname.startsWith('/v1/live/')) {
        if (options.activationFailures > 0) {
          options.activationFailures -= 1;
          entry.status = 404;
          // NOTE: The real gateway can delay the body after sending 404 headers; keep EOF pending until the client releases it.
          return new Response(new ReadableStream({
            start(controller) { controller.enqueue(new TextEncoder().encode('{"error":{"code":"session_id_not_found"}}')); },
          }), { status: 404, headers: { 'content-type': 'application/json' } });
        }
        if (server.upgrade(request)) return;
        return new Response('', { status: 400 });
      }
      if (url.pathname === '/backend-api/transcribe') {
        const wire = await request.clone().text();
        const form = await request.formData();
        const file = form.get('file');
        entry.audio = [...new Uint8Array(await file.arrayBuffer())];
        entry.filename = file.name;
        entry.mime = /Content-Type: ([^\r\n]+)/i.exec(wire)?.[1];
        entry.language = form.get('language');
        if (options.holdAudio) {
          await new Promise(resolve => request.signal.addEventListener('abort', resolve, { once: true }));
          return new Response('', { status: 499 });
        }
        if (options.rejectASR) {
          const status = options.rejectASR;
          options.rejectASR = 0;
          return Response.json({ error: { code: 'fixture_rejection' } }, { status });
        }
        return Response.json({ text: '测试转录' });
      }
      if (url.pathname === '/backend-api/wham/realtime/calls') {
        entry.body = await request.json();
        entry.search = url.search;
        if (options.holdAudio) {
          await new Promise(resolve => request.signal.addEventListener('abort', resolve, { once: true }));
          return new Response('', { status: 499 });
        }
        return new Response('v=0\r\na=fixture-answer\r\n', { status: 201,
          headers: { location: 'https://api.openai.com/v1/realtime/calls/rtc_fixture' } });
      }
      return new Response('', { status: 404 });
    },
    websocket: {
      open(socket) {
        control = socket;
        if (options.initialize) setTimeout(() => socket.send(JSON.stringify({ type: 'session.started' })), 20);
      },
      message(_socket, raw) { messages.push(JSON.parse(String(raw))); },
    },
  });
  t.after(() => server.stop(true));
  const base = `http://127.0.0.1:${server.port}`;
  class LocalWebSocket extends WebSocket {
    constructor(url, init) {
      assert.equal(url, 'wss://api.openai.com/v1/live/rtc_fixture');
      super(url.replace('wss://api.openai.com', base.replace('http:', 'ws:')), init);
      controlSockets.push(this);
    }
  }
  const manager = createChatGPTAudio({ home: account.directory,
    authorityFactory: ({ onChange }) => ({
      async connections() { return [{ id: 'chatgpt-voice', label: 'ChatGPT', source: options.source, authorized: true }]; },
      authorize(id, options) { assert.equal(id, 'chatgpt-voice'); return authorize(account.profile, account.directory, options); },
      async startLogin() { await onChange(); return { url: 'https://auth.openai.com/oauth/authorize?fixture=1', login_id: 'fixture-login' }; },
      async close() { options.authorityClosed = true; },
    }),
    fetchImpl(url, init) {
      assert.equal(new URL(url).origin, 'https://chatgpt.com');
      return fetch(url.replace('https://chatgpt.com', base), init);
    },
    WebSocketImpl: LocalWebSocket,
    onEvent: async event => { observed.push(event); },
  });
  t.after(() => manager.close());
  return { manager, account, options, requests, messages, observed, controlSockets,
    hasControl() { return Boolean(control); },
    send(event) { control.send(JSON.stringify(event)); } };
}

async function until(predicate) {
  const timeout = AbortSignal.timeout(2000);
  while (!predicate()) {
    timeout.throwIfAborted();
    await new Promise(resolve => setTimeout(resolve, 5));
  }
}

test('audio admits only its official authority, refreshes it and uploads actual recorded bytes and MIME', async t => {
  const fixture = await audioFixture(t);
  fixture.options.source = 'siwc';
  assert.deepEqual((await fixture.manager.capabilities()).connections, []);
  await assert.rejects(fixture.manager.transcribe({ connection: 'chatgpt-voice',
    audio: new Uint8Array([1]), mime: 'audio/webm' }), /Official ChatGPT audio sign-in/);
  assert.equal(fixture.requests.length, 0);
  fixture.options.source = 'codex_audio';
  assert.deepEqual(await fixture.manager.startLogin(), {
    url: 'https://auth.openai.com/oauth/authorize?fixture=1', login_id: 'fixture-login',
  });
  assert.equal(fixture.observed.some(event => event.type === 'account_changed'), true);
  const capability = await fixture.manager.capabilities();
  assert.equal(capability.connections.length, 1);
  assert.deepEqual(capability.unavailable, []);
  assert.equal(JSON.stringify(capability).includes('Bearer'), false);
  const connection = capability.connections[0].id;
  fixture.options.rejectASR = 401;
  assert.deepEqual(await fixture.manager.transcribe({ connection,
    audio: new Uint8Array([1, 2, 3, 4]), mime: 'audio/webm', language: 'zh' }), { text: '测试转录' });
  const uploads = fixture.requests.filter(request => request.path.endsWith('/transcribe'));
  assert.equal(uploads.length, 2);
  assert.deepEqual(uploads.map(request => request.audio), [[1, 2, 3, 4], [1, 2, 3, 4]]);
  assert.deepEqual(uploads.map(request => [request.mime, request.language]), [['audio/webm', 'zh'], ['audio/webm', 'zh']]);
  assert.deepEqual(uploads.map(request => request.filename), ['recording.webm', 'recording.webm']);
  assert.deepEqual(uploads.map(request => request.headers.authorization),
    ['Bearer opaque-access-renewed-1', 'Bearer opaque-access-renewed-2']);
  assert.ok(uploads.every(request => request.headers['chatgpt-account-id']));
  fixture.options.rejectASR = 403;
  await assert.rejects(fixture.manager.transcribe({ connection, audio: new Uint8Array([5]), mime: 'audio/ogg' }), /HTTP 403/);
  assert.equal(fixture.requests.filter(request => request.path.endsWith('/transcribe')).length, 3);
  assert.deepEqual(fixture.account.failures, []);
  await fixture.manager.close();
  assert.equal(fixture.options.authorityClosed, true);
});

test('voice returns SDP before activation, recovers its initial 404 and flushes the interrupted transcript tail', async t => {
  const fixture = await audioFixture(t);
  fixture.options.initialize = false;
  fixture.options.activationFailures = 1;
  const { connections } = await fixture.manager.capabilities();
  const initial_items = [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: 'existing task request' }] },
    { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'existing task response' }] }];
  const session = await fixture.manager.createSession({ connection: connections[0].id, task_id: 0,
    id: 'fixture-voice-session', initial_items, sdp: 'v=0\r\na=fixture-offer\r\n' });
  assert.deepEqual(session, { id: 'fixture-voice-session', call_id: 'rtc_fixture', sdp: 'v=0\r\na=fixture-answer\r\n' });
  assert.equal(fixture.observed.some(event => event.type === 'ready'), false);
  await until(() => fixture.hasControl() && fixture.observed.some(event => event.type === 'ready'));
  const upgrades = fixture.requests.filter(request => request.path.startsWith('/v1/live/'));
  assert.equal(upgrades.length, 2);
  assert.equal(upgrades[0].status, 404);
  assert.equal(fixture.observed.some(event => event.type === 'error' || event.type === 'closed'), false);
  fixture.send({ type: 'session.started' });
  assert.equal(fixture.observed.filter(event => event.type === 'ready').length, 1);
  assert.equal(fixture.observed[0].type, 'ready');
  const call = fixture.requests.find(request => request.path.endsWith('/calls'));
  assert.equal(call.headers['openai-alpha'], 'quicksilver=v2');
  assert.equal(call.headers['thread-id'], '0');
  assert.equal(call.body.session.model, 'gpt-live-1-codex');
  assert.equal(call.body.session.delegation.type, 'client');
  assert.equal(call.body.session.voice_session_id, session.id);
  assert.deepEqual(call.body.session.initial_items, initial_items);
  const sideband = fixture.requests.find(request => request.path.startsWith('/v1/live/'));
  assert.equal(sideband.headers.authorization, call.headers.authorization);
  assert.equal(sideband.headers['chatgpt-account-id'], call.headers['chatgpt-account-id']);
  assert.equal(sideband.headers['openai-alpha'], 'quicksilver=v2');
  assert.equal(sideband.headers['thread-id'], '0');
  assert.equal(sideband.headers['session-id'], session.id);
  assert.equal(sideband.headers['x-session-id'], session.id);
  fixture.send({ type: 'turn.created', turn: { id: 'turn-assistant-1', start_ms: 600, end_ms: 800,
    role: 'assistant', transcript: ' Hi.' } });
  fixture.send({ type: 'turn.done', turn: { role: 'user', transcript: '', id: 'empty-turn' } });
  fixture.send({ type: 'input_transcript.added', item: { text: 'hello' } });
  fixture.send({ type: 'input_transcript.added', item: { text: 'next unfinished utterance' } });
  fixture.send({ type: 'turn.done', turn: { role: 'user', transcript: 'hello', id: 'turn-user-1' } });
  fixture.send({ type: 'delegation.created', item: { id: 'delegation-1', type: 'delegation', target: 'client',
    content: [{ type: 'input_text', text: 'inspect ' }, { type: 'input_text', text: 'the code' }] } });
  fixture.send({ type: 'output_transcript.added', item: { text: 'I am checking' } });
  await until(() => fixture.observed.some(event => event.type === 'error')
    || (fixture.observed.some(event => event.type === 'delegation') && fixture.observed.length >= 5));
  assert.equal(fixture.observed.find(event => event.type === 'error'), undefined);
  assert.equal(fixture.observed.filter(event => event.type === 'ready').length, 1);
  assert.equal(fixture.observed.filter(event => event.type === 'transcript').length, 1);
  assert.deepEqual(fixture.observed.find(event => event.type === 'transcript'), {
    session_id: session.id, task_id: 0, type: 'transcript', role: 'user', text: 'hello',
    item_id: 'turn-user-1', completion: 'completed', final: true, remaining: 'next unfinished utterance',
  });
  await fixture.manager.appendContext(session.id, { delegation_item_id: 'delegation-1', channel: 'commentary', text: 'Task #0 accepted' });
  await until(() => fixture.messages.length === 1);
  assert.deepEqual(fixture.messages[0], { type: 'delegation.context.append', delegation_item_id: 'delegation-1',
    channel: 'commentary', content: [{ type: 'input_text', text: 'Task #0 accepted' }] });
  const longText = '语音🙂'.repeat(110);
  await fixture.manager.appendContext(session.id, { delegation_item_id: 'delegation-1', channel: 'speakable', text: longText });
  await until(() => fixture.messages.length === 4);
  const parts = fixture.messages.slice(1);
  assert.equal(parts.map(part => part.content[0].text).join(''), longText);
  assert.ok(parts.every(part => Buffer.byteLength(part.content[0].text) <= 500 && part.content[0].text.isWellFormed()));
  assert.ok(parts.every(part => part.delegation_item_id === 'delegation-1'));
  assert.equal(await fixture.manager.stopSession(session.id), true);
  assert.ok(fixture.observed.some(event => event.type === 'transcript' && event.completion === 'interrupted'
    && event.role === 'user' && event.text === 'next unfinished utterance' && event.remaining === ''));
  const tail = fixture.observed.at(-2);
  assert.equal(tail.type, 'transcript');
  assert.equal(tail.completion, 'interrupted');
  assert.equal(tail.text, 'I am checking');
  assert.equal(tail.role, 'assistant');
  assert.equal(fixture.observed.at(-1).type, 'closed');
  assert.equal(await fixture.manager.appendContext(session.id, { text: 'work continues' }), false);
});

test('cancelling a pending sideband activation releases the failed socket and prevents a later retry', async t => {
  const fixture = await audioFixture(t);
  fixture.options.initialize = false;
  fixture.options.activationFailures = 1;
  const { connections } = await fixture.manager.capabilities();
  const controller = new AbortController();
  await fixture.manager.createSession({ connection: connections[0].id, task_id: 8,
    sdp: 'v=0\r\n', signal: controller.signal });
  await until(() => fixture.controlSockets.length === 1 && fixture.controlSockets[0].readyState === WebSocket.CLOSED);
  controller.abort(new Error('fixture cancelled'));
  await until(() => fixture.observed.some(event => event.type === 'closed'));
  assert.equal(fixture.observed.some(event => event.type === 'ready'), false);
  assert.ok(fixture.observed.some(event => event.type === 'error' && event.error.includes('fixture cancelled')));
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(fixture.requests.filter(request => request.path.startsWith('/v1/live/')).length, 1);
  assert.equal(fixture.observed.filter(event => event.type === 'closed').length, 1);
  assert.ok(fixture.controlSockets.every(socket => socket.readyState === WebSocket.CLOSED));
});

test('metadata-only delegation waits for its referenced user turn instead of executing the latest transcript', async t => {
  const fixture = await audioFixture(t);
  const { connections } = await fixture.manager.capabilities();
  const session = await fixture.manager.createSession({ connection: connections[0].id, task_id: 9, sdp: 'v=0\r\n' });
  await until(() => fixture.observed.some(event => event.type === 'ready'));
  fixture.send({ type: 'turn.created', turn: { id: 'unrelated-turn', role: 'user', transcript: 'unrelated request' } });
  fixture.send({ type: 'delegation.created', item: { id: 'linked-delegation', type: 'delegation', target: 'client',
    handoff_id: 'handoff-1', user_bidi_turn_id: 'referenced-turn' } });
  fixture.send({ type: 'turn.created', turn: { id: 'referenced-turn', role: 'user', transcript: 'inspect this task' } });
  await until(() => fixture.observed.some(event => event.type === 'delegation'));
  const delegations = fixture.observed.filter(event => event.type === 'delegation');
  assert.equal(delegations.length, 1);
  assert.equal(delegations[0].text, 'inspect this task');
  assert.equal(delegations[0].delegation_id, 'linked-delegation');
  fixture.send({ type: 'conversation.handoff.requested', item_id: 'legacy-handoff', handoff_id: 'handoff-2',
    user_bidi_turn_id: 'referenced-turn' });
  await until(() => fixture.observed.filter(event => event.type === 'delegation').length === 2);
  assert.equal(fixture.observed.filter(event => event.type === 'delegation')[1].text, 'inspect this task');
  await fixture.manager.stopSession(session.id);
});

test('closing the audio host aborts both an upload and call creation before any sideband exists', async t => {
  const fixture = await audioFixture(t);
  const { connections } = await fixture.manager.capabilities();
  fixture.options.holdAudio = true;
  const pendingCall = fixture.manager.createSession({ connection: connections[0].id, task_id: 10, sdp: 'v=0\r\n' });
  const pendingUpload = fixture.manager.transcribe({ connection: connections[0].id, audio: new Uint8Array([1]), mime: 'audio/webm' });
  const callRejected = assert.rejects(pendingCall, /Audio host is closed/);
  const uploadRejected = assert.rejects(pendingUpload, /Audio host is closed/);
  await until(() => fixture.requests.some(request => request.body) && fixture.requests.some(request => request.audio));
  await fixture.manager.close();
  await Promise.all([callRejected, uploadRejected]);
  assert.equal(fixture.requests.some(request => request.path.startsWith('/v1/live/')), false);
});

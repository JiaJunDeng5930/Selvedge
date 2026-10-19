import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, taskIdle, responsesServer } from './support.mjs';
import { events } from '../host/network.mjs';

function audioFixture({ signedIn = true, readyBeforeAnswer = true } = {}) {
  const sessions = new Map();
  const uploads = [];
  const reports = [];
  let emit;
  let beforeReport;
  let logins = 0;
  return {
    checkReports: check => { beforeReport = check; },
    sessions, uploads, reports,
    get logins() { return logins; },
    send: event => emit(event),
    factory({ onEvent }) {
      emit = onEvent;
      return {
        capabilities: async () => ({ connections: signedIn ? [{ id: 'account', label: 'ChatGPT', source: 'codex_audio', asr: true, voice: true }] : [] }),
        startLogin: async () => {
          logins++;
          signedIn = true;
          await emit({ type: 'account_changed' });
          return { url: 'https://auth.openai.com/oauth/authorize?state=fixture', login_id: 'login-1' };
        },
        transcribe: async source => { uploads.push(source); return { text: '听写内容' }; },
        createSession: async source => {
          sessions.set(source.id, source);
          if (readyBeforeAnswer) await emit({ type: 'ready', session_id: source.id, task_id: source.task_id });
          return { id: source.id, call_id: 'upstream-call', sdp: 'answer' };
        },
        appendContext: async (id, source) => { beforeReport?.(source); reports.push({ id, ...source }); },
        stopSession: async id => {
          if (!sessions.has(id)) return;
          sessions.delete(id);
          await emit({ type: 'closed', session_id: id });
        },
        close: async () => { sessions.clear(); },
      };
    },
  };
}

const requireResult = result => {
  assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
  return result.reply.result;
};

test('audio routes retain local authentication and ownership, and commit speech before reporting accepted work', async t => {
  const directory = await home(t);
  const fixture = audioFixture({ signedIn: false });
  let finishModel;
  let markRequested;
  const modelRequested = new Promise(resolve => { markRequested = resolve; });
  const modelReply = new Promise(resolve => { finishModel = resolve; });
  t.after(() => finishModel());
  const upstream = await responsesServer(t, async () => {
    markRequested();
    await modelReply;
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: '完成语音委派' }] }];
  });
  const key = 'SELVEDGE_AUDIO_SERVICE_TEST_KEY';
  process.env[key] = 'fixture';
  t.after(() => { delete process.env[key]; });
  const running = await startServer({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
      demo: { provider: 'responses', model: 'fixture', endpoint: upstream.endpoint, api_key_env: key },
    } }), audioFactory: options => fixture.factory(options) });
  t.after(() => running.close());
  const headers = { authorization: `Bearer ${running.token}` };
  const post = (pathname, body) => fetch(`${running.address}${pathname}`, { method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const read = async id => requireResult(await running.service.command({ op: 'read', task_id: id }));

  const unauthorized = await fetch(`${running.address}/api/audio/capabilities`);
  assert.equal(unauthorized.status, 401);
  const foreign = await fetch(`${running.address}/api/audio/capabilities`, { headers: { ...headers, origin: 'https://foreign.example' } });
  assert.equal(foreign.status, 403);
  assert.deepEqual((await (await fetch(`${running.address}/api/audio/capabilities`, { headers })).json()).connections, []);
  assert.equal(fixture.logins, 0, 'Observing capabilities must not start sign-in');
  const unauthenticatedLogin = await fetch(`${running.address}/api/audio/login`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ browser_id: 'browser' }) });
  assert.equal(unauthenticatedLogin.status, 401);
  const foreignLogin = await fetch(`${running.address}/api/audio/login`, { method: 'POST',
    headers: { ...headers, origin: 'https://foreign.example', 'content-type': 'application/json' }, body: JSON.stringify({ browser_id: 'browser' }) });
  assert.equal(foreignLogin.status, 403);
  assert.equal((await post('/api/audio/login', { browser_id: 'browser', account_changed: true })).status, 400);
  assert.equal(fixture.logins, 0);
  const controller = new AbortController();
  const stream = await fetch(`${running.address}/api/events?after=0`, { headers, signal: controller.signal });
  const iterator = events(stream.body, running.service.limits.frame_bytes);
  try {
    assert.equal(JSON.parse((await iterator.next()).value).type, 'stream-state');
    assert.equal(JSON.parse((await iterator.next()).value).type, 'commit');
    const login = await post('/api/audio/login', { browser_id: 'browser' });
    assert.equal(login.status, 200, await login.clone().text());
    assert.deepEqual(await login.json(), { url: 'https://auth.openai.com/oauth/authorize?state=fixture', login_id: 'login-1' });
    assert.equal(JSON.parse((await iterator.next()).value).type, 'account_changed');
    assert.equal(fixture.logins, 1);
    assert.equal((await (await fetch(`${running.address}/api/audio/capabilities`, { headers })).json()).connections[0].id, 'account');
  } finally {
    controller.abort();
    // DEFENSE: Stopping the authenticated event stream can reject its reader cleanup with AbortError.
    await iterator.return().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
  const uploaded = await fetch(`${running.address}/api/audio/transcribe?connection=account&browser_id=browser`, {
    method: 'POST', headers: { ...headers, 'content-type': 'audio/webm' }, body: Uint8Array.of(1, 2, 3) });
  assert.deepEqual(await uploaded.json(), { text: '听写内容' });
  assert.deepEqual([...fixture.uploads[0].audio], [1, 2, 3]);

  const task = requireResult(await running.service.command({ op: 'create_idle', profile: 'demo' })).task_id;
  const created = await post('/api/audio/sessions', { connection: 'account', browser_id: 'browser', task_id: task, sdp: 'offer' });
  assert.equal(created.status, 200, await created.clone().text());
  const session = await created.json();
  const voiceAbort = new AbortController();
  const voiceEvents = await fetch(`${running.address}/api/audio/sessions/${session.id}/events?browser_id=browser`, {
    headers, signal: voiceAbort.signal });
  const voiceReader = voiceEvents.body.getReader();
  t.after(async () => {
    voiceAbort.abort();
    await voiceReader.cancel().catch(error => { if (error.name !== 'AbortError') throw error; });
  });
  assert.match(new TextDecoder().decode((await voiceReader.read()).value), /"type":"ready"/);
  const forbidden = await post(`/api/audio/sessions/${session.id}/stop?browser_id=other`, {});
  assert.equal(forbidden.status, 400);
  assert.equal(fixture.sessions.size, 1);
  const conflicting = await post('/api/audio/sessions', { connection: 'account', browser_id: 'browser', task_id: task, sdp: 'another-offer' });
  assert.equal(conflicting.status, 400);

  const committed = new Set();
  running.service.journal.on('commit', decision => {
    if (decision.reply.ok && decision.input.kind === 'command') {
      const command = decision.input.command;
      if (command.op === 'record_speech_transcript') committed.add(command.item_id);
      if (command.op === 'accept_speech_delegation') committed.add(command.delegation_id);
    }
  });
  fixture.checkReports(report => {
    if (report.delegation_item_id) assert.equal(committed.has(report.delegation_item_id), true);
  });
  const notices = [];
  running.service.on('audio', event => {
    if (event.type === 'transcript' && event.final) assert.equal(committed.has(event.item_id), true);
    notices.push(event);
  });
  await fixture.send({ type: 'transcript', final: true, session_id: session.id, item_id: 'speech-1', role: 'user',
    completion: 'completed', text: '请把这段话保留在上下文中' });
  const recorded = await read(task);
  assert.equal(recorded.task.phase, 'idle');
  assert.equal(recorded.messages.filter(message => message.role === 'speech_transcript').length, 1);
  assert.equal(notices.at(-1).type, 'transcript');

  // An authenticated browser cannot fabricate a trusted upstream delegation through the ordinary command surface.
  const forged = await post('/api/commands', { op: 'accept_speech_delegation', task_id: task, session_id: session.id,
    delegation_id: 'forged', message: 'forged work', mode: 'send' });
  assert.equal(forged.status, 400);
  const accepted = { type: 'delegation', session_id: session.id, delegation_id: 'work-1', text: '完成语音委派', mode: 'send' };
  await fixture.send(accepted);
  const receipt = (await read(task)).messages.find(message => message.role === 'speech_delegation_receipt');
  assert.equal(receipt.delegation_id, 'work-1');
  assert.match(fixture.reports[0].text, /accepted/);
  await fixture.send(accepted);
  assert.equal((await read(task)).messages.filter(message => message.role === 'speech_delegation_receipt').length, 1);

  // Hanging up releases the audio connection while the separately accepted Task remains scheduled.
  await Promise.race([modelRequested, delay(5000, undefined, { ref: false }).then(() => { throw new Error('Delegated Task did not reach the fixture model'); })]);
  const modelInput = JSON.stringify(upstream.requests[0].input);
  assert.ok(modelInput.includes('请把这段话保留在上下文中'));
  assert.equal(modelInput.includes('speech_transcript'), false);
  assert.equal(modelInput.includes('speech_delegation_receipt'), false);
  assert.equal((await post(`/api/audio/sessions/${session.id}/stop?browser_id=browser`, {})).status, 200);
  assert.notEqual((await read(task)).task.phase, 'idle');
  finishModel();
  const completed = await taskIdle(running.service, task);
  assert.ok(completed.messages.some(message => message.role === 'model_context' && message.content.type === 'provider_receipt' &&
    message.content.item.role === 'assistant' && message.content.item.content.some(part => part.type === 'output_text' && part.text.includes('完成语音委派'))),
  JSON.stringify(completed.messages.filter(message => message.role !== 'task_context')));
  assert.equal(fixture.sessions.size, 0);
  const resumed = await running.service.audioCreate({ browser_id: 'browser', connection: 'account', task_id: task, sdp: 'offer' });
  const initial = fixture.sessions.get(resumed.id).initial_items;
  assert.ok(initial.some(item => item.role === 'user' && item.content.some(part => part.text.includes('请把这段话保留在上下文中'))));
  assert.ok(initial.some(item => item.role === 'assistant' && item.content.some(part => part.text.includes('完成语音委派'))));
  assert.equal(JSON.stringify(initial).includes('speech_delegation_receipt'), false);
  await fixture.send({ type: 'delegation', session_id: resumed.id, delegation_id: 'work-2', text: '继续完成工作', mode: 'send' });
  await taskIdle(running.service, task);
  for (let attempt = 0; !fixture.reports.some(report => report.channel === 'speakable') && attempt < 50; attempt++) await delay(10);
  assert.ok(fixture.reports.some(report => report.channel === 'speakable' && report.text.includes('完成语音委派')));
  await running.service.audioStop(resumed.id, 'browser');
});

test('disconnecting the owner event stream releases its voice connection', async t => {
  const directory = await home(t);
  const fixture = audioFixture({ readyBeforeAnswer: false });
  const running = await startServer({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0 }), audioFactory: options => fixture.factory(options) });
  t.after(() => running.close());
  const task_id = requireResult(await running.service.command({ op: 'create_idle', profile: 'demo' })).task_id;
  const session = await running.service.audioCreate({ browser_id: 'owner', connection: 'account', task_id, sdp: 'offer' });
  const abort = new AbortController();
  const response = await fetch(`${running.address}/api/audio/sessions/${session.id}/events?browser_id=owner`, {
    headers: { authorization: `Bearer ${running.token}` }, signal: abort.signal });
  const reader = response.body.getReader();
  assert.match(new TextDecoder().decode((await reader.read()).value), /"type":"connecting"/);
  await fixture.send({ type: 'ready', session_id: session.id, task_id });
  assert.match(new TextDecoder().decode((await reader.read()).value), /"type":"ready"/);
  abort.abort();
  await reader.cancel().catch(error => { if (error.name !== 'AbortError') throw error; });
  for (let attempt = 0; fixture.sessions.size && attempt < 50; attempt++) await delay(10);
  assert.equal(fixture.sessions.size, 0);
  await running.service.audioCreate({ browser_id: 'owner', connection: 'account', task_id, sdp: 'offer' });
  await running.close();
  assert.equal(fixture.sessions.size, 0);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { AudioRuntime } from '../host/public/audio.mjs';

function deferred() {
  let resolve; let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function microphone() {
  const track = { enabled: true, stopped: false, stop() { this.stopped = true; } };
  return { track, getTracks: () => [track], getAudioTracks: () => [track] };
}
class Recorder {
  constructor(stream) { this.stream = stream; this.mimeType = 'audio/mp4'; this.state = 'inactive'; }
  start() { this.state = 'recording'; }
  stop() {
    this.state = 'inactive';
    this.ondataavailable?.({ data: new Blob(['recorded sound'], { type: this.mimeType }) });
    this.onstop?.();
  }
}
class Peer {
  constructor() {
    this.connectionState = 'new'; this.iceGatheringState = 'complete';
    this.channel = { readyState: 'connecting', close() { this.closed = true; } };
    Peer.latest = this;
  }
  addTrack() {}
  createDataChannel(name) { assert.equal(name, 'oai-events'); return this.channel; }
  async createOffer() { return { type: 'offer', sdp: 'offer bytes' }; }
  async setLocalDescription(value) { this.localDescription = value; }
  async setRemoteDescription(value) { this.remoteDescription = value; }
  close() { this.closed = true; this.connectionState = 'closed'; this.onconnectionstatechange?.(); }
}
class Output {
  async play() { this.playing = true; }
  pause() { this.playing = false; this.paused = true; }
}
class Events {
  constructor(url) { this.url = url; Events.latest = this; }
  close() { this.closed = true; }
}
function runtime(options = {}) {
  const observations = []; const uploads = []; const stops = [];
  const io = new AudioRuntime({
    limits: { asr_max_bytes: 26214400, connect_timeout_ms: 20000, request_timeout_ms: 120000, session_max_ms: 3600000 },
    browserId: 'physical-test', emit: (type, values) => observations.push({ type, ...values }),
    field: () => ({ value: 'a😀b', selectionStart: 1, selectionEnd: 3 }),
    MediaRecorder: Recorder, RTCPeerConnection: Peer, Audio: Output, EventSource: Events,
    fetch: async (url, init) => { stops.push({ url, init }); return { ok: true }; },
    request: async (url, init) => { uploads.push({ url, init }); return { text: 'transcript' }; },
    ...options,
  });
  return { io, observations, uploads, stops };
}

test('dictation uploads the recorder actual MIME and releases microphone before the response', async () => {
  const stream = microphone(); const response = deferred();
  let uploaded;
  const { io, observations } = runtime({ mediaDevices: { getUserMedia: async () => stream },
    request: async (url, init) => { uploaded = { url, init }; return response.promise; } });
  await io.execute('Record', { ticket: 1n, owner: 'task-draft' });
  assert.deepEqual(observations[0], { type: 'Captured', ticket: 1n, start: 1n, end: 2n });
  const finishing = io.execute('Transcribe', { ticket: 1n, connection: 'chatgpt/one' });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(stream.track.stopped, true);
  assert.equal(uploaded.init.headers['content-type'], 'audio/mp4');
  assert.equal(uploaded.init.body.type, 'audio/mp4');
  assert.equal(await uploaded.init.body.text(), 'recorded sound');
  assert.match(uploaded.url, /connection=chatgpt%2Fone&browser_id=physical-test$/);
  io.execute('Release', { ticket: 1n });
  assert.equal(uploaded.init.signal.aborted, true);
  response.resolve({ text: 'late transcript' });
  await finishing;
  assert.equal(observations.some(item => item.type === 'Transcribed'), false);
  io.dispose();
});

test('pending microphone cancellation and explicit account login release their own physical resources', async () => {
  const permission = deferred(); const stream = microphone();
  const { io, observations } = runtime({ mediaDevices: { getUserMedia: () => permission.promise } });
  const recording = io.execute('Record', { ticket: 2n, owner: 'task-draft' });
  io.execute('Release', { ticket: 2n });
  permission.resolve(stream);
  await recording;
  assert.equal(stream.track.stopped, true);
  assert.deepEqual(observations, []);

  const response = deferred(); const order = [];
  const popup = { closed: false, opener: 'parent', location: { replace(url) { order.push(['navigate', url]); } },
    focus() { order.push(['focus']); }, close() { this.closed = true; } };
  const auth = runtime({
    openWindow: (...args) => { order.push(['open', ...args]); return popup; },
    loginTarget: url => { order.push(['validate', url]); return 'validated official target'; },
    request: async (url, init) => { order.push(['request', url, JSON.parse(init.body)]); return response.promise; },
  });
  const login = auth.io.execute('BeginAudioLogin', {});
  assert.deepEqual(order, [['open', 'about:blank', '_blank'], ['request', '/api/audio/login', { browser_id: 'physical-test' }]]);
  assert.equal(popup.opener, null);
  response.resolve({ url: 'official authority URL', login_id: 'login-id' });
  await login;
  assert.deepEqual(order.slice(2), [['validate', 'official authority URL'], ['navigate', 'validated official target']]);
  auth.io.accountChanged();
  assert.equal(popup.closed, false);
  assert.equal(auth.io.loginWindow, null);
  assert.deepEqual(auth.observations, [{ type: 'Refresh' }]);
  auth.io.dispose();

  const blocked = runtime({ openWindow: () => null, request: () => assert.fail('A blocked popup must not begin login') });
  await blocked.io.execute('BeginAudioLogin', {});
  assert.match(blocked.observations[0].reason, /Allow the sign-in popup/);
  blocked.io.dispose();
});

test('voice keeps microphone disabled until media, session and host control are ready; page release closes every resource', async t => {
  const stream = microphone(); const control = deferred();
  const { io, observations, stops } = runtime({ mediaDevices: { getUserMedia: async () => stream },
    request: async () => control.promise });
  t.after(() => io.dispose());
  const connecting = io.execute('ConnectVoice', { ticket: 3n, connection: 'account', task: 7n });
  await new Promise(resolve => setImmediate(resolve));
  const peer = Peer.latest;
  assert.equal(stream.track.enabled, false);
  peer.connectionState = 'connected'; peer.onconnectionstatechange();
  peer.channel.readyState = 'open'; peer.channel.onopen();
  peer.channel.onmessage({ data: JSON.stringify({ type: 'session.started' }) });
  assert.equal(stream.track.enabled, false);
  control.resolve({ id: 'local-call', call_id: 'rtc_real', sdp: 'answer bytes' });
  await connecting;
  assert.equal(stream.track.enabled, false);
  Events.latest.onmessage({ data: JSON.stringify({ type: 'ready' }) });
  assert.equal(stream.track.enabled, true);
  assert.deepEqual(observations.filter(item => item.type === 'VoiceReady'), [{ type: 'VoiceReady', ticket: 3n }]);
  assert.equal(peer.remoteDescription.sdp, 'answer bytes');
  io.execute('SetInputMute', { ticket: 3n, muted: true });
  assert.equal(stream.track.enabled, false);
  io.execute('SetOutputMute', { ticket: 3n, muted: true });
  assert.equal(io.resources.get(3n).output.muted, true);
  Events.latest.onmessage({ data: JSON.stringify({ type: 'transcript', role: 'user', final: false, text: 'hello' }) });
  Events.latest.onmessage({ data: JSON.stringify({ type: 'transcript', role: 'user', final: false, text: ' next' }) });
  Events.latest.onmessage({ data: JSON.stringify({ type: 'transcript', role: 'user', item_id: 'first', final: true, text: 'hello', remaining: ' next' }) });
  Events.latest.onmessage({ data: JSON.stringify({ type: 'transcript', role: 'user', final: false, text: ' unfinished' }) });
  Events.latest.onmessage({ data: JSON.stringify({ type: 'transcript', role: 'user', item_id: 'second', final: true, text: ' next unfinished', remaining: '' }) });
  assert.deepEqual(observations.filter(item => item.type === 'LiveText').map(item => item.text),
    ['hello', 'hello next', ' next', ' next unfinished', '']);
  const entry = io.resources.get(3n);
  io.dispose();
  assert.equal(stream.track.stopped, true);
  assert.equal(peer.closed, true);
  assert.equal(peer.channel.closed, true);
  assert.equal(entry.events.closed, true);
  assert.equal(entry.output.srcObject, null);
  assert.equal(stops[0].init.keepalive, true);
  assert.match(stops[0].url, /local-call\/stop\?browser_id=physical-test$/);
});

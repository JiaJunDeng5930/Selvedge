import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { randomBytes, randomUUID } from 'node:crypto';
import { RemoteConnector } from '../host/remote-connector.mjs';

const controllerId = 'a'.repeat(64);
const grant = { controller_id: controllerId, grant_epoch: 1 };
const tick = () => new Promise(resolve => setTimeout(resolve, 5));

async function until(predicate, description = 'Remote connector condition did not settle') {
  const deadline = Date.now() + 3000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error(description);
    await tick();
  }
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

class TransportService extends EventEmitter {
  sequence = 1;
  program = { $: 'Test.Program', value: 17n };
  streams = [];
  allowed = true;
  checks = 0;
  commands = [];
  closeCalls = 0;
  checkGate;
  commandGate;

  browserSnapshot() { return { sequence: this.sequence, program: this.program }; }
  browserStreams() { return structuredClone(this.streams); }
  async remoteCheck(id, epoch) {
    assert.equal(id, controllerId);
    assert.equal(epoch, 1);
    ++this.checks;
    if (this.checkGate) return this.checkGate();
    return { sequence: this.sequence, reply: { ok: this.allowed } };
  }
  async remoteCommand(id, epoch, params) {
    assert.equal(id, controllerId);
    assert.equal(epoch, 1);
    this.commands.push(params);
    await this.commandGate?.promise;
    return { sequence: ++this.sequence, reply: { ok: true, result: { accepted: true } } };
  }
  close() { ++this.closeCalls; }
}

async function fixture(t, options = {}) {
  const token = randomBytes(32).toString('base64url');
  const hostId = randomUUID();
  const sockets = [];
  const frames = [];
  const requests = [];
  let probeStatus = 426;
  let pong = true;
  const server = Bun.serve({
    hostname: '127.0.0.1', port: 0,
    fetch(request, server) {
      requests.push({ url: request.url, authorization: request.headers.get('authorization') });
      assert.equal(new URL(request.url).pathname, `/v1/hosts/${hostId}/host`);
      if (request.headers.get('authorization') !== `Bearer ${token}`) return new Response(null, { status: 401 });
      if (probeStatus !== 426) return new Response(null, { status: probeStatus });
      if (server.upgrade(request)) return;
      return new Response(null, { status: 426 });
    },
    websocket: {
      open(socket) {
        sockets.push(socket);
        socket.send(JSON.stringify({ type: 'ready', version: 1 }));
      },
      message(socket, data) {
        const frame = JSON.parse(data);
        frames.push({ socket, ...frame });
        if (frame.type === 'ping' && pong) socket.send(JSON.stringify({ type: 'pong' }));
      },
    },
  });
  const service = new TransportService();
  const pairs = [];
  const statuses = [];
  let grants = [grant];
  const connector = new RemoteConnector({
    relayUrl: server.url.origin, hostId, hostToken: token, service, getGrants: async () => grants,
    onPairRequest: frame => pairs.push(frame), onStatus: status => statuses.push(status),
    allowLoopback: true, retryBaseMs: 15, retryMaxMs: 30, heartbeatMs: 50,
    heartbeatTimeoutMs: 150, connectTimeoutMs: 500, ...options,
  });
  t.after(() => { connector.close(); server.stop(true); });
  const send = frame => sockets.at(-1).send(JSON.stringify(frame));
  const openController = () => send({ type: 'controller_open', connection_id: 'controller-1', ...grant });
  const request = (id, method, params = {}) => send({ type: 'request', connection_id: 'controller-1', ...grant, request: { id, method, params } });
  const response = id => frames.find(frame => frame.type === 'response' && frame.response.id === id)?.response;
  return { connector, service, frames, sockets, requests, pairs, statuses, send, request, response, openController,
    setGrants: value => { grants = value; }, setProbeStatus: value => { probeStatus = value; }, setPong: value => { pong = value; } };
}

test('remote connector authenticates outbound, resyncs grants on reconnect and keeps pairing secrets out of status', async t => {
  const f = await fixture(t);
  assert.throws(() => new RemoteConnector({ relayUrl: 'http://127.0.0.1:1234' }), /HTTPS origin/);
  f.connector.start();
  await until(() => f.connector.status().connected
    && f.frames.some(frame => frame.socket === f.sockets[0] && frame.type === 'grants'));
  assert.ok(f.requests.length >= 2);
  assert.deepEqual(f.frames.filter(frame => frame.type !== 'ping').map(({ type }) => type), ['hello', 'grants']);
  f.connector.pair('a-secure-one-time-pairing-code', Date.now() + 1000);
  await until(() => f.frames.some(frame => frame.type === 'pairing'));
  f.send({ type: 'pair_request', request_id: 'pair-request', controller_id: controllerId, label: 'My phone' });
  await until(() => f.pairs.length === 1);
  assert.equal(f.pairs[0].label, 'My phone');
  assert.ok(!JSON.stringify(f.statuses).includes('pairing-code'));
  assert.ok(!JSON.stringify(f.statuses).includes('Bearer'));
  f.connector.pair('another-one-time-pairing-code', Date.now() + 1000);
  await until(() => f.frames.filter(frame => frame.type === 'pairing').length === 2);
  f.sockets[0].close(1012, 'Restart');
  await until(() => f.sockets.length === 2 && f.connector.status().connected
    && f.frames.some(frame => frame.socket === f.sockets[1] && frame.type === 'grants'));
  const second = f.frames.filter(frame => frame.socket === f.sockets[1]);
  assert.deepEqual(second.filter(frame => frame.type !== 'ping').map(frame => frame.type), ['hello', 'grants']);
  assert.deepEqual(second.find(frame => frame.type === 'grants').grants, [grant]);
  assert.equal(f.service.closeCalls, 0);
});

test('remote subscription captures program, stream state and notice cursor together without replaying captured deltas', async t => {
  const f = await fixture(t);
  f.connector.start();
  await until(() => f.connector.status().connected);
  f.openController();
  const gate = deferred();
  f.service.checkGate = async () => { await gate.promise; return { sequence: f.service.sequence, reply: { ok: true } }; };
  f.request('subscribe', 'subscribe');
  await until(() => f.service.checks === 1);
  f.service.streams = [{ text: 'before snapshot' }];
  f.service.emit('notice', { type: 'delta', text: 'before snapshot' });
  gate.resolve();
  await until(() => f.response('subscribe'));
  const snapshot = f.response('subscribe').result;
  assert.deepEqual(snapshot.program.value, { $: '$bigint', value: '17' });
  assert.deepEqual(snapshot.streams, [{ text: 'before snapshot' }]);
  assert.equal(snapshot.notice_sequence, 1);
  assert.equal(f.frames.filter(frame => frame.type === 'event').length, 0);
  f.service.emit('notice', { type: 'delta', text: 'after snapshot' });
  await until(() => f.frames.some(frame => frame.type === 'event'));
  assert.deepEqual(f.frames.find(frame => frame.type === 'event').event, {
    incarnation: snapshot.incarnation, notice_sequence: 2, notice: { type: 'delta', text: 'after snapshot' },
  });
  assert.equal(f.service.checks, 2);
});

test('native authorization is rechecked when a revocation commits while the previous read check returns', async t => {
  const f = await fixture(t);
  f.connector.start();
  await until(() => f.connector.status().connected);
  f.openController();
  f.service.checkGate = async () => {
    if (f.service.checks === 1) {
      ++f.service.sequence;
      return { sequence: f.service.sequence - 1, reply: { ok: true } };
    }
    return { sequence: f.service.sequence, reply: { ok: false } };
  };
  f.request('snapshot', 'snapshot');
  await until(() => f.response('snapshot'));
  assert.equal(f.service.checks, 2);
  assert.equal(f.response('snapshot').error.code, 'remote_access_denied');
  assert.ok(!JSON.stringify(f.response('snapshot')).includes('$bigint'));
});

test('revocation suppresses queued observations and full grant synchronization retires device connections', async t => {
  const f = await fixture(t);
  f.connector.start();
  await until(() => f.connector.status().connected);
  f.openController();
  f.request('subscribe', 'subscribe');
  await until(() => f.response('subscribe'));
  f.service.allowed = false;
  ++f.service.sequence;
  f.service.emit('notice', { type: 'delta', text: 'must stay private' });
  await until(() => f.service.checks === 2);
  assert.equal(f.frames.filter(frame => frame.type === 'event').length, 0);
  f.setGrants([]);
  await f.connector.syncGrants();
  await until(() => f.frames.filter(frame => frame.type === 'grants').length === 2);
  assert.deepEqual(f.frames.filter(frame => frame.type === 'grants').at(-1).grants, []);
  assert.equal(f.connector.status().controller_count, 0);
});

test('disconnecting and reconnecting never cancels or replays an accepted native command', async t => {
  const f = await fixture(t);
  f.connector.start();
  await until(() => f.connector.status().connected);
  f.openController();
  const gate = deferred();
  f.service.commandGate = gate;
  f.request('create', 'command', { request_id: 'stable-create-request', command: { op: 'create', message: 'Continue while offline' } });
  await until(() => f.service.commands.length === 1);
  f.sockets[0].close(1012, 'Network lost');
  await until(() => f.sockets.length === 2 && f.connector.status().connected);
  gate.resolve();
  await tick();
  assert.equal(f.service.commands.length, 1);
  assert.equal(f.service.closeCalls, 0);
  assert.equal(f.response('create'), undefined);
  assert.equal(f.connector.status().controller_count, 0);
});

test('bounded per-device request queue closes the relay transport without closing the task service', async t => {
  const f = await fixture(t);
  f.connector.start();
  await until(() => f.connector.status().connected);
  f.openController();
  const gate = deferred();
  f.service.checkGate = async () => { await gate.promise; return { sequence: f.service.sequence, reply: { ok: true } }; };
  for (let index = 0; index < 33; ++index) f.request(index, 'snapshot');
  await until(() => f.statuses.some(status => status.last_error === 'request_queue_full'));
  gate.resolve();
  assert.equal(f.service.closeCalls, 0);
  assert.ok(f.service.checks <= 1);
});

test('relay credential rejection stops automatic retries until explicit restart', async t => {
  const f = await fixture(t);
  f.setProbeStatus(401);
  f.connector.start();
  await until(() => f.connector.status().state === 'auth_failed');
  assert.equal(f.requests.length, 1);
  await new Promise(resolve => setTimeout(resolve, 80));
  assert.equal(f.requests.length, 1);
  f.setProbeStatus(426);
  f.connector.start();
  await until(() => f.connector.status().connected);
  assert.equal(f.sockets.length, 1);
});

test('application heartbeat detects an unresponsive relay and reconnects with current grants', async t => {
  const f = await fixture(t, { heartbeatMs: 10, heartbeatTimeoutMs: 30 });
  f.setPong(false);
  f.connector.start();
  await until(() => f.sockets.length >= 2);
  f.setPong(true);
  await until(() => f.connector.status().connected);
  assert.ok(f.statuses.some(status => status.last_error === 'heartbeat_timeout'));
  assert.equal(f.service.closeCalls, 0);
});

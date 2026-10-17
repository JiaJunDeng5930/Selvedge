import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { randomBytes, randomUUID } from 'node:crypto';
import { RemoteConnector } from '../host/remote-connector.mjs';

async function until(predicate) {
  const deadline = Date.now() + 3000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error('The WebSocket transport did not reach the expected boundary');
    await new Promise(resolve => setTimeout(resolve, 5));
  }
}

test('a lost relay socket cannot replay an in-flight command or deliver its late response to a new session', async t => {
  const hostId = randomUUID(), token = randomBytes(32).toString('base64url');
  const grant = { controller_id: 'a'.repeat(64), grant_epoch: 1 };
  const sockets = [], frames = [], authorizations = [];
  const server = Bun.serve({
    hostname: '127.0.0.1', port: 0,
    fetch(request, server) {
      authorizations.push(request.headers.get('authorization'));
      if (request.headers.get('authorization') !== `Bearer ${token}`) return new Response(null, { status: 401 });
      assert.equal(new URL(request.url).pathname, `/v1/hosts/${hostId}/host`);
      assert.equal(new URL(request.url).search, '');
      if (server.upgrade(request)) return;
      return new Response(null, { status: 426 });
    },
    websocket: {
      open(socket) { sockets.push(socket); socket.send(JSON.stringify({ type: 'ready', version: 1 })); },
      message(socket, data) {
        const frame = JSON.parse(data);
        frames.push({ socket, frame });
        if (frame.type === 'ping') socket.send(JSON.stringify({ type: 'pong' }));
      },
    },
  });
  const gate = Promise.withResolvers();
  const commands = [];
  let closed = false;
  const service = Object.assign(new EventEmitter(), {
    browserSnapshot: () => ({ sequence: 1, program: { $: 'Transport.Program' } }),
    browserStreams: () => [],
    remoteCheck: async () => ({ sequence: 1, reply: { ok: true } }),
    remoteCommand: async (controller, epoch, params) => {
      commands.push({ controller, epoch, params });
      await gate.promise;
      return { sequence: 1, reply: { ok: true, result: 'Accepted 世界 😀' } };
    },
    close: () => { closed = true; },
  });
  const connector = new RemoteConnector({ relayUrl: server.url.origin, hostId, hostToken: token,
    service, getGrants: async () => [grant], allowLoopback: true, retryBaseMs: 5, retryMaxMs: 10 });
  t.after(() => { gate.resolve(); connector.close(); server.stop(true); });
  const send = (socket, frame) => socket.send(JSON.stringify(frame));
  const open = socket => send(socket, { type: 'controller_open', connection_id: 'reused-connection', ...grant });
  const ready = socket => connector.status().connected && frames.some(item => item.socket === socket && item.frame.type === 'grants');
  connector.start();
  await until(() => sockets[0] && ready(sockets[0]));
  open(sockets[0]);
  const params = { request_id: 'retained-native-request', command: { op: 'create', message: 'Continue 世界 😀 while disconnected' } };
  send(sockets[0], { type: 'request', connection_id: 'reused-connection', ...grant,
    request: { id: 'old-rpc', method: 'command', params } });
  await until(() => commands.length === 1);
  sockets[0].close(1012, 'Connection lost after admission');
  await until(() => sockets[1] && ready(sockets[1]));
  open(sockets[1]);
  gate.resolve();
  send(sockets[1], { type: 'request', connection_id: 'reused-connection', ...grant,
    request: { id: 'new-rpc', method: 'snapshot', params: {} } });
  await until(() => frames.some(item => item.socket === sockets[1] && item.frame.response?.id === 'new-rpc'));
  assert.deepEqual(commands, [{ controller: grant.controller_id, epoch: grant.grant_epoch, params }]);
  assert.equal(frames.some(item => item.frame.response?.id === 'old-rpc'), false);
  assert.equal(closed, false);
  assert.ok(authorizations.length >= 4);
  assert.ok(authorizations.every(value => value === `Bearer ${token}`));
});

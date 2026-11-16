import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { Service } from '../host/service.mjs';
import { provisionRemote } from '../host/remote-control.mjs';
import { home } from './support.mjs';

async function until(condition) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (await condition()) return;
    await delay(5);
  }
  throw new Error('Remote transport did not reach the requested external state');
}

test('remote transport retries an outage, detects missing pongs, and stops after rejected authentication', async t => {
  const directory = await home(t);
  const enrollmentToken = randomBytes(32).toString('base64url');
  let handshakeRequests = 0;
  let plainRequests = 0;
  let connections = 0;
  let pings = 0;
  let rejectAuthentication = false;
  const peer = Bun.serve({ hostname: '127.0.0.1', port: 0,
    async fetch(request, server) {
      if (new URL(request.url).pathname === '/v1/hosts/register') {
        const body = await request.json();
        return Response.json({ host_id: body.host_id });
      }
      if (request.headers.get('upgrade') === 'websocket') {
        handshakeRequests++;
        if (rejectAuthentication) return new Response(null, { status: 401 });
        if (handshakeRequests === 1) return new Response(null, { status: 503 });
        if (server.upgrade(request)) return;
      }
      plainRequests++;
      return new Response(null, { status: 426 });
    },
    websocket: {
      open() { connections++; rejectAuthentication = true; },
      message(socket, text) {
        const frame = JSON.parse(text);
        if (frame.type === 'hello') socket.send(JSON.stringify({ type: 'ready', version: 1 }));
        if (frame.type === 'ping') pings++;
      },
    },
  });
  let service;
  t.after(async () => { await service?.close(); await peer.stop(true); });
  const relayUrl = `http://127.0.0.1:${peer.port}`;
  await provisionRemote({ home: directory, relayUrl, enrollmentToken, allowLoopback: true });
  const config = { ...validateConfig({ ...defaultConfig, chatgpt: false }), remote: { relay_url: relayUrl } };
  service = await Service.open({ home: directory, cwd: directory, config, remoteOptions: {
    allowLoopback: true, retryBaseMs: 20, retryMaxMs: 20, heartbeatMs: 10, heartbeatTimeoutMs: 25,
  } });
  await service.remote.enable();
  await until(async () => (await service.remote.status()).connection.state === 'auth_failed');
  assert.equal(plainRequests, 0, 'Only real WebSocket handshakes reach the host endpoint');
  assert.equal(handshakeRequests, 3, 'Outage, accepted connection and credentials rejected on the next attempt');
  assert.equal(connections, 1);
  assert.ok(pings > 0, 'A real WebSocket carried the heartbeat before its deadline expired');
  await delay(100);
  assert.equal(handshakeRequests, 3, 'Rejected credentials stop further connections');
});

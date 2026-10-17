import assert from 'node:assert/strict';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { after, before, test } from 'node:test';
import WebSocket from 'ws';
import { startRelay } from './runtime.mjs';
import { REMOTE_PROTOCOL_VERSION, parseRemoteFrame, validateControllerRequest,
  validateHostFrame, assertRelayUrl } from '../../remote/protocol.mjs';

const enrollmentToken = randomBytes(32).toString('base64url');
const secret = () => randomBytes(32).toString('base64url');
const identity = value => createHash('sha256').update(value).digest('hex');
let relay;
before(async () => { relay = await startRelay({ enrollmentToken }); });
after(async () => { await relay?.close(); });

async function post(path, credential, body) {
  const response = await fetch(`${relay.url}${path}`, { method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` },
    body: JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}

class Peer {
  constructor(socket) {
    this.socket = socket;
    this.messages = [];
    this.waiters = [];
    this.closed = new Promise(resolve => socket.once('close', (code, reason) => resolve({ code, reason: reason.toString() })));
    socket.on('message', raw => {
      const value = JSON.parse(raw.toString());
      const waiting = this.waiters.findIndex(waiter => waiter.matches(value));
      if (waiting < 0) this.messages.push(value);
      else this.waiters.splice(waiting, 1)[0].resolve(value);
    });
    socket.on('error', () => {});
  }
  send(value) { this.socket.send(JSON.stringify(value)); }
  next(matches = () => true) {
    const index = this.messages.findIndex(matches);
    if (index >= 0) return Promise.resolve(this.messages.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Remote relay message timed out')), 4000);
      this.waiters.push({ matches, resolve: value => { clearTimeout(timeout); resolve(value); } });
    });
  }
  close() { this.socket.close(); }
}

async function connect(path, credential) {
  const socket = new WebSocket(`${relay.url.replace('http:', 'ws:')}${path}`,
    credential ? { headers: { authorization: `Bearer ${credential}` } } : {});
  const peer = new Peer(socket);
  await new Promise((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  return peer;
}

async function fixture() {
  const hostId = randomUUID(), hostToken = secret();
  const registered = await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: hostToken });
  assert.equal(registered.status, 200);
  const host = await connect(`/v1/hosts/${hostId}/host`, hostToken);
  assert.deepEqual(await host.next(), { type: 'ready', version: REMOTE_PROTOCOL_VERSION });
  host.send({ type: 'hello', version: REMOTE_PROTOCOL_VERSION });
  host.send({ type: 'grants', grants: [] });
  await synced(host);
  return { hostId, hostToken, host, path: `/v1/hosts/${hostId}` };
}

async function synced(host) {
  host.send({ type: 'ping' });
  await host.next(value => value.type === 'pong');
}

async function grant(f, controllerToken = secret(), grantEpoch = 1) {
  const controllerId = identity(controllerToken);
  f.host.send({ type: 'grants', grants: [{ controller_id: controllerId, grant_epoch: grantEpoch }] });
  await synced(f.host);
  return { controllerToken, controllerId, grantEpoch };
}

async function controller(f, g) {
  const issued = await post(`${f.path}/tickets`, g.controllerToken, {});
  assert.equal(issued.status, 200);
  const peer = await connect(`${f.path}/control?ticket=${issued.body.ticket}`);
  const ready = await peer.next();
  assert.deepEqual(ready, { type: 'ready', version: 1, controller_id: g.controllerId, grant_epoch: g.grantEpoch });
  const opened = await f.host.next(value => value.type === 'controller_open');
  return { peer, opened, ticket: issued.body.ticket };
}

test('registration requires enrollment authorization and cannot replace an existing host credential', async () => {
  const hostId = randomUUID(), hostToken = secret();
  assert.equal((await post('/v1/hosts/register', 'wrong', { host_id: hostId, host_token: hostToken })).status, 401);
  assert.equal((await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: hostToken, extra: true })).status, 400);
  assert.equal((await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: hostToken })).status, 200);
  assert.equal((await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: hostToken })).status, 200);
  assert.equal((await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: secret() })).status, 409);
  const endpoint = `${relay.url}/v1/hosts/${hostId}/host`;
  assert.equal((await fetch(endpoint, { headers: { authorization: `Bearer ${hostToken}` } })).status, 426);
  assert.equal((await fetch(endpoint, { headers: { authorization: `Bearer ${enrollmentToken}` } })).status, 401);
  assert.equal((await fetch(`${relay.url}/v1/hosts/${hostId}/pair?extra=true`)).status, 400);
});

test('pairing code is spent once and local grant is required before controller ticket issuance', async () => {
  const f = await fixture();
  const code = secret(), controllerToken = secret();
  f.host.send({ type: 'pairing', code, expires_at: Date.now() + 60_000 });
  await synced(f.host);
  const paired = await post(`${f.path}/pair`, code, { controller_token: controllerToken, label: 'Test phone' });
  assert.equal(paired.status, 200);
  assert.equal(paired.body.status, 'pending');
  assert.equal(paired.body.controller_id, identity(controllerToken));
  assert.deepEqual(await f.host.next(value => value.type === 'pair_request'), { type: 'pair_request',
    request_id: paired.body.request_id, controller_id: identity(controllerToken), label: 'Test phone' });
  assert.equal((await post(`${f.path}/pair`, code, { controller_token: controllerToken, label: 'Replay' })).status, 401);
  assert.equal((await post(`${f.path}/tickets`, controllerToken, {})).status, 401);
  const g = await grant(f, controllerToken);
  const c = await controller(f, g);
  await assert.rejects(connect(`${f.path}/control?ticket=${c.ticket}`), /401/);
  c.peer.close(); f.host.close();
});

test('replacing a pairing code invalidates the earlier code before asynchronous hashing completes', async () => {
  const f = await fixture(), first = secret(), replacement = secret();
  f.host.send({ type: 'pairing', code: first, expires_at: Date.now() + 60_000 });
  f.host.send({ type: 'pairing', code: replacement, expires_at: Date.now() + 60_000 });
  await synced(f.host);
  const body = { controller_token: secret(), label: 'Latest pairing code' };
  assert.equal((await post(`${f.path}/pair`, first, body)).status, 401);
  assert.equal((await post(`${f.path}/pair`, replacement, body)).status, 200);
  f.host.close();
});

test('controller forwarding derives identity from its grant and rejects spoofed envelope fields', async () => {
  const f = await fixture(), g = await grant(f);
  const c = await controller(f, g);
  const request = { id: 'read-1', method: 'snapshot', params: {} };
  c.peer.send(request);
  const forwarded = await f.host.next(value => value.type === 'request');
  assert.deepEqual(forwarded, { type: 'request', connection_id: c.opened.connection_id,
    controller_id: g.controllerId, grant_epoch: 1, request });
  f.host.send({ type: 'response', connection_id: c.opened.connection_id, response: { id: request.id, result: { sequence: 12 } } });
  assert.deepEqual(await c.peer.next(), { id: request.id, result: { sequence: 12 } });
  f.host.send({ type: 'event', connection_id: c.opened.connection_id, event: { type: 'commit', sequence: 13 } });
  assert.deepEqual(await c.peer.next(), { type: 'event', event: { type: 'commit', sequence: 13 } });
  c.peer.send({ ...request, controller_id: 'forged' });
  assert.equal((await c.peer.closed).code, 1008);
  f.host.close();
});

test('grant removal closes old controller sockets and invalidates unspent tickets', async () => {
  const f = await fixture(), g = await grant(f), c = await controller(f, g);
  const issued = await post(`${f.path}/tickets`, g.controllerToken, {});
  f.host.send({ type: 'grants', grants: [] });
  await synced(f.host);
  assert.equal((await c.peer.closed).code, 1008);
  assert.equal((await post(`${f.path}/tickets`, g.controllerToken, {})).status, 401);
  await assert.rejects(connect(`${f.path}/control?ticket=${issued.body.ticket}`), /401/);
  f.host.close();
});

test('outstanding ticket bound fits the hibernation attachment and rejects excess before serialization', async () => {
  const f = await fixture(), g = await grant(f);
  f.host.send({ type: 'pairing', code: secret(), expires_at: Date.now() + 60_000 });
  await synced(f.host);
  for (let index = 0; index < 8; index++) {
    assert.equal((await post(`${f.path}/tickets`, g.controllerToken, {})).status, 200);
  }
  assert.equal((await post(`${f.path}/tickets`, g.controllerToken, {})).status, 429);
  await relay.hibernate(f.hostId);
  assert.equal((await post(`${f.path}/tickets`, g.controllerToken, {})).status, 429);
  f.host.close();
});

test('Durable Object hibernation preserves socket identity, grant epoch and one-use tickets', async () => {
  const f = await fixture(), g = await grant(f), c = await controller(f, g);
  const issued = await post(`${f.path}/tickets`, g.controllerToken, {});
  const code = secret();
  f.host.send({ type: 'pairing', code, expires_at: Date.now() + 60_000 });
  await synced(f.host);
  await relay.hibernate(f.hostId);
  c.peer.send({ id: 'after-hibernation', method: 'snapshot', params: {} });
  const request = await f.host.next(value => value.type === 'request');
  assert.equal(request.connection_id, c.opened.connection_id);
  assert.equal(request.controller_id, g.controllerId);
  assert.equal(request.grant_epoch, g.grantEpoch);
  const extra = await connect(`${f.path}/control?ticket=${issued.body.ticket}`);
  assert.equal((await extra.next()).controller_id, g.controllerId);
  assert.equal((await post(`${f.path}/pair`, code, { controller_token: secret(), label: 'After hibernation' })).status, 200);
  await assert.rejects(connect(`${f.path}/control?ticket=${issued.body.ticket}`), /401/);
  extra.close(); c.peer.close(); f.host.close();
});

test('host replacement fences the old generation and host loss closes controllers without queuing requests', async () => {
  const f = await fixture(), g = await grant(f), c = await controller(f, g);
  const replacement = await connect(`${f.path}/host`, f.hostToken);
  assert.equal((await replacement.next()).version, 1);
  assert.equal((await f.host.closed).code, 1012);
  assert.equal((await c.peer.closed).code, 1012);
  assert.equal((await post(`${f.path}/tickets`, g.controllerToken, {})).status, 503);
  replacement.send({ type: 'hello', version: 1 });
  replacement.send({ type: 'grants', grants: [{ controller_id: g.controllerId, grant_epoch: 1 }] });
  await synced(replacement);
  f.host = replacement;
  const next = await controller(f, g);
  replacement.close();
  assert.equal((await next.peer.closed).code, 1012);
  assert.equal((await post(`${f.path}/tickets`, g.controllerToken, {})).status, 503);
  assert.equal((await post(`${f.path}/pair`, secret(), { controller_token: secret(), label: 'Offline' })).status, 503);
});

test('host must negotiate the supported protocol before publishing grants', async () => {
  const f = await fixture();
  const host = await connect(`${f.path}/host`, f.hostToken);
  await host.next();
  host.send({ type: 'grants', grants: [] });
  assert.equal((await host.closed).code, 1008);
  const unsupported = await connect(`${f.path}/host`, f.hostToken);
  await unsupported.next();
  unsupported.send({ type: 'hello', version: 999 });
  assert.equal((await unsupported.closed).code, 1008);
});

test('shared protocol validates endpoint origins and rejects unbounded or unknown envelopes', () => {
  assert.equal(assertRelayUrl('https://relay.example:443/'), 'https://relay.example');
  assert.equal(assertRelayUrl('http://127.0.0.1:1234/', { allowLoopback: true }), 'http://127.0.0.1:1234');
  for (const address of ['http://relay.example', 'https://relay.example:444', 'https://user:secret@relay.example',
    'https://relay.example/path', 'https://relay.example/?token=value', 'https://relay.example/#fragment']) {
    assert.throws(() => assertRelayUrl(address));
  }
  assert.throws(() => validateControllerRequest({ id: '1', method: 'filesystem', params: {} }));
  assert.throws(() => validateControllerRequest({ id: '1', method: 'snapshot', params: { path: '/etc' } }));
  assert.throws(() => validateHostFrame({ type: 'grants', grants: [{ controller_id: 'x', grant_epoch: 1 }] }));
  assert.throws(() => parseRemoteFrame(new Uint8Array(), validateHostFrame));
  assert.throws(() => parseRemoteFrame('{', validateHostFrame));
});

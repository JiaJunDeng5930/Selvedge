import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { startRelay, WebSocket } from '../relay/test/runtime.mjs';

const token = () => randomBytes(32).toString('base64url');

test('remote transport admits an exact exponent-compensated integer and preserves opaque number tokens', async t => {
  const enrollmentToken = token();
  const relay = await startRelay({ enrollmentToken });
  const sockets = [];
  t.after(async () => { for (const socket of sockets) socket.terminate(); await relay.close(); });
  async function post(path, credential, body) {
    const response = await fetch(relay.url + path, { method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` },
      body: JSON.stringify(body) });
    assert.equal(response.status, 200);
    return response.json();
  }
  async function connect(path, credential) {
    const socket = new WebSocket(relay.url.replace('http:', 'ws:') + path,
      credential ? { headers: { authorization: `Bearer ${credential}` } } : {});
    sockets.push(socket);
    const pending = [], waiting = [];
    socket.on('message', data => {
      const message = data.toString();
      const resolve = waiting.shift();
      if (resolve) resolve(message); else pending.push(message);
    });
    await new Promise((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject); });
    return { socket, async next() {
      if (pending.length) return pending.shift();
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Remote integer wire message timed out')), 4000);
        waiting.push(value => { clearTimeout(timer); resolve(value); });
      });
    } };
  }
  const hostId = randomUUID(), hostToken = token(), controllerToken = token();
  const controllerId = createHash('sha256').update(controllerToken).digest('hex');
  const root = `/v1/hosts/${hostId}`;
  await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: hostToken });
  const host = await connect(root + '/host', hostToken);
  assert.equal(JSON.parse(await host.next()).type, 'ready');
  host.socket.send('{"type":"hello","version":0.000000000000000001e18}');
  host.socket.send(JSON.stringify({ type: 'grants', grants: [{ controller_id: controllerId, grant_epoch: 1 }] }));
  // A pong observes processing of the preceding frames before issuing a ticket.
  host.socket.send('{"type":"ping"}');
  assert.equal(JSON.parse(await host.next()).type, 'pong');
  const ticket = await post(root + '/tickets', controllerToken, {});
  const controller = await connect(root + '/control?ticket=' + ticket.ticket);
  assert.equal(JSON.parse(await controller.next()).type, 'ready');
  assert.equal(JSON.parse(await host.next()).type, 'controller_open');
  controller.socket.send(`{"id":0.000000000000000001e18,"method":"command","params":{"request_id":"${randomUUID()}","command":{"op":"wire_probe","opaque":9007199254740993e0}}}`);
  const requestText = await host.next();
  const request = JSON.parse(requestText);
  assert.equal(request.type, 'request');
  assert.equal(request.request.id, 1);
  assert.match(requestText, /"opaque":9007199254740993e0/);
  host.socket.send(JSON.stringify({ type: 'response', connection_id: request.connection_id,
    response: { id: request.request.id, result: { accepted: true } } }));
  assert.deepEqual(JSON.parse(await controller.next()), { id: 1, result: { accepted: true } });
});

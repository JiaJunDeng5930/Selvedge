import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { startRelay, WebSocket } from '../relay/test/runtime.mjs';

const secret = () => randomBytes(32).toString('base64url');

test('real Durable Object hibernation restores live WebSocket identities and an unspent ticket', async t => {
  const enrollmentToken = secret();
  const relay = await startRelay({ enrollmentToken });
  const sockets = new Set();
  t.after(async () => { for (const socket of sockets) socket.terminate(); await relay.close(); });
  const post = async (path, credential, body) => {
    const response = await fetch(relay.url + path, { method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` },
      body: JSON.stringify(body) });
    assert.equal(response.status, 200);
    return response.json();
  };
  const connect = async (path, credential) => {
    const socket = new WebSocket(relay.url.replace('http:', 'ws:') + path,
      credential ? { headers: { authorization: `Bearer ${credential}` } } : {});
    sockets.add(socket);
    const messages = [], waiters = new Set();
    let ended = false;
    socket.on('message', raw => { messages.push(JSON.parse(raw.toString())); for (const wake of waiters) wake(); });
    socket.on('close', () => { ended = true; for (const wake of waiters) wake(); });
    // DEFENSE: Peer teardown emits error followed by close; connect errors reject below and later closure fails any pending next() observation.
    socket.on('error', () => {});
    await new Promise((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject); });
    return {
      send: value => socket.send(JSON.stringify(value)),
      async next(matches = () => true) {
        const deadline = Date.now() + 4000;
        for (;;) {
          const index = messages.findIndex(matches);
          if (index >= 0) return messages.splice(index, 1)[0];
          assert.equal(ended, false, 'The relay closed a live hibernated socket');
          const remaining = deadline - Date.now();
          assert.ok(remaining > 0, 'The relay did not forward the hibernated socket message');
          await new Promise(resolve => {
            const wake = () => { clearTimeout(timer); waiters.delete(wake); resolve(); };
            const timer = setTimeout(wake, remaining); waiters.add(wake);
          });
        }
      },
    };
  };
  const hostId = randomUUID(), hostToken = secret(), controllerToken = secret();
  const controllerId = createHash('sha256').update(controllerToken).digest('hex');
  const path = `/v1/hosts/${hostId}`;
  await post('/v1/hosts/register', enrollmentToken, { host_id: hostId, host_token: hostToken });
  const host = await connect(path + '/host', hostToken);
  await host.next(value => value.type === 'ready');
  host.send({ type: 'hello', version: 1 });
  host.send({ type: 'grants', grants: [{ controller_id: controllerId, grant_epoch: 1 }] });
  host.send({ type: 'ping' }); await host.next(value => value.type === 'pong');
  const ticket = await post(path + '/tickets', controllerToken, {});
  const controller = await connect(path + '/control?ticket=' + ticket.ticket);
  await controller.next(value => value.type === 'ready');
  const opened = await host.next(value => value.type === 'controller_open');
  const unspent = await post(path + '/tickets', controllerToken, {});

  await relay.hibernate(hostId);
  const request = { id: 'after-hibernation', method: 'snapshot', params: {} };
  controller.send(request);
  assert.deepEqual(await host.next(value => value.type === 'request'), {
    type: 'request', connection_id: opened.connection_id, controller_id: controllerId, grant_epoch: 1, request,
  });
  const response = { id: request.id, result: { marker: '恢复 😀' } };
  host.send({ type: 'response', connection_id: opened.connection_id, response });
  assert.deepEqual(await controller.next(), response);
  const resumed = await connect(path + '/control?ticket=' + unspent.ticket);
  const ready = await resumed.next(value => value.type === 'ready');
  assert.equal(ready.controller_id, controllerId);
  assert.equal(ready.grant_epoch, 1);
});

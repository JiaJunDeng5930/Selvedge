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
  const postResponse = (path, credential, body) => fetch(relay.url + path, { method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` },
    body: JSON.stringify(body) });
  const post = async (path, credential, body) => {
    const response = await postResponse(path, credential, body);
    assert.equal(response.status, 200);
    return response.json();
  };
  const connect = async (path, credential) => {
    const socket = new WebSocket(relay.url.replace('http:', 'ws:') + path,
      credential ? { headers: { authorization: `Bearer ${credential}` } } : {});
    sockets.add(socket);
    const messages = [], rawMessages = [], waiters = new Set();
    let ended = false;
    const closed = new Promise(resolve => socket.once('close', code => resolve(code)));
    socket.on('message', raw => { rawMessages.push(raw.toString()); messages.push(JSON.parse(raw.toString())); for (const wake of waiters) wake(); });
    socket.on('close', () => { ended = true; for (const wake of waiters) wake(); });
    // DEFENSE: Peer teardown emits error followed by close; connect errors reject below and later closure fails any pending next() observation.
    socket.on('error', () => {});
    await new Promise((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject); });
    return {
      send: value => socket.send(JSON.stringify(value)),
      sendRaw: value => socket.send(value),
      rawMessages,
      closed,
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
  host.sendRaw('{"type":"hello","version":1.0}');
  host.sendRaw(`{"type":"grants","grants":[{"controller_id":"${controllerId}","grant_epoch":1e0}]}`);
  host.send({ type: 'ping' }); await host.next(value => value.type === 'pong');
  const pairingCode = secret(), pairingBody = { controller_token: controllerToken, label: '设备'.repeat(40) };
  host.send({ type: 'pairing', code: pairingCode, expires_at: Date.now() + 300_000 });
  let pairingResponse;
  const pairingDeadline = Date.now() + 4000;
  do {
    pairingResponse = await postResponse(path + '/pair', pairingCode, pairingBody);
    if (pairingResponse.status === 200) break;
    assert.equal(pairingResponse.status, 401);
    await pairingResponse.body.cancel();
    assert.ok(Date.now() < pairingDeadline, 'The relay did not install the pairing code');
    await new Promise(resolve => setTimeout(resolve, 5));
  } while (true);
  const pairing = await pairingResponse.json();
  const pairRequest = await host.next(value => value.type === 'pair_request');
  assert.equal(pairing.request_id, pairRequest.request_id);
  assert.equal(pairRequest.controller_id, controllerId);
  assert.equal(pairRequest.label, pairingBody.label);
  const reusedPairing = await postResponse(path + '/pair', pairingCode, pairingBody);
  assert.equal(reusedPairing.status, 401);
  assert.equal((await reusedPairing.json()).error.code, 'invalid_pairing_code');
  const ticket = await post(path + '/tickets', controllerToken, {});
  const controller = await connect(path + '/control?ticket=' + ticket.ticket);
  await controller.next(value => value.type === 'ready');
  const opened = await host.next(value => value.type === 'controller_open');

  for (const spelling of ['1.0', '1e0', '-0', '0e999999999999999999999999999']) {
    controller.sendRaw(`{"id":${spelling},"method":"snapshot","params":{}}`);
    const delivered = await host.next(value => value.type === 'request');
    assert.equal(delivered.request.id, spelling.startsWith('1') ? 1 : 0);
    host.sendRaw(`{"type":"response","connection_id":"${opened.connection_id}","response":{"id":${spelling},"result":{"exact":9007199254740993}}}`);
    await controller.next(value => value.result?.exact !== undefined);
    assert.match(controller.rawMessages.at(-1), /"exact":9007199254740993/u);
  }

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
  const spent = await fetch(relay.url + path + '/control?ticket=' + unspent.ticket, { headers: { upgrade: 'websocket' } });
  assert.equal(spent.status, 401);
  assert.equal((await spent.json()).error.code, 'invalid_ticket');

  for (const spelling of ['1.1', '9007199254740992', '1e999999999999999999999999']) {
    const rejectedTicket = await post(path + '/tickets', controllerToken, {});
    const rejected = await connect(path + '/control?ticket=' + rejectedTicket.ticket);
    await rejected.next(value => value.type === 'ready');
    rejected.sendRaw(`{"id":${spelling},"method":"snapshot","params":{}}`);
    const code = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('The relay retained an invalid numeric request')), 4000);
      rejected.closed.then(value => { clearTimeout(timer); resolve(value); });
    });
    assert.equal(code, 1008);
  }
  host.send({ type: 'ping' });
  await host.next(value => value.type === 'pong');

});

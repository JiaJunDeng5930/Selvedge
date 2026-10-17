import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';
import { observeConnection } from '../host/public/connection.mjs';
import { bendValue, bendTag } from '../host/public/bend-value.mjs';
import { browserBoundaryModel } from './browser-model-support.mjs';

test('a failed snapshot closes the actual event stream and the model schedules a fresh connection and snapshot', { timeout: 180_000 }, async t => {
  const { module: model } = await browserBoundaryModel(t);
  let snapshots = 0;
  let subscriptions = 0;
  const streams = new Set();
  const server = http.createServer((request, response) => {
    if (request.url === '/api/browser/state') {
      snapshots++;
      if (snapshots === 2) { response.writeHead(503); response.end(JSON.stringify({ error: 'temporary snapshot failure' })); return; }
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify({ sequence: snapshots === 1 ? 0 : 1, program: { marker: 'current snapshot' } }));
      return;
    }
    if (request.url.startsWith('/api/events?after=')) {
      subscriptions++;
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.write('data: {"type":"commit","sequence":1}\n\n');
      streams.add(response); response.once('close', () => streams.delete(response));
      return;
    }
    response.writeHead(404); response.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = `http://127.0.0.1:${server.address().port}`;
  const controllers = new Set();
  t.after(async () => {
    for (const controller of controllers) controller.abort();
    for (const stream of streams) stream.end();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  const service = (name, fields = {}) => bendValue(`interaction/services/MODEL.${name}`, fields);
  const values = list => { const result = []; for (; bendTag(list) === 'Con'; list = list.tail) result.push(list.head); return result; };
  let state = model.service_initial();
  let sequence = 0;
  let observed;
  let recovered;
  const complete = new Promise(resolve => { recovered = resolve; });
  function input(value) {
    const decision = model.service_step(value, state); state = decision.state;
    for (const effect of values(decision.effects)) {
      if (bendTag(effect) === 'Authenticate') connect(effect);
      if (bendTag(effect) === 'ScheduleReconnect') {
        void delay(Number(effect.delay_ms)).then(() => input(service('RetryConnection', { ticket: effect.ticket })));
      }
    }
  }
  function connect(effect) {
    const controller = new AbortController(); controllers.add(controller);
    void observeConnection({
      signal: controller.signal,
      sequence: () => sequence,
      request: async (url, signal) => {
        const response = await fetch(address + url, { signal });
        if (!response.ok) throw new Error(`snapshot HTTP ${response.status}`);
        return response.json();
      },
      fetchEvents: (url, signal) => fetch(address + url, { signal }),
      snapshot: body => {
        sequence = body.sequence; observed = body.program;
        if (sequence === 1 && subscriptions >= 2) recovered();
      },
      ready: () => {
        input(service('Authenticated', { ticket: effect.ticket, result: bendValue('Done', { value: bendValue('Unit') }) }));
      },
      notice() {},
    }).catch(error => {
      if (!controller.signal.aborted) {
        controller.abort();
        input(service('Disconnected', { ticket: effect.ticket, reason: error.message }));
      }
    });
  }
  input(service('Connect'));
  let timeout;
  try {
    await Promise.race([complete, new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Browser connection did not recover')), 15_000); })]);
  } finally { clearTimeout(timeout); }
  assert.equal(bendTag(state.access), 'Connected');
  assert.equal(state.access.ticket, 1n);
  assert.equal(sequence, 1);
  assert.deepEqual(observed, { marker: 'current snapshot' });
  assert.ok(snapshots >= 3);
  assert.equal(subscriptions, 2);
});

test('an aborted connection cannot publish a late physical snapshot', async () => {
  const controller = new AbortController();
  let resolve;
  const pending = new Promise(done => { resolve = done; });
  const published = [];
  const observed = observeConnection({
    request: () => pending, fetchEvents: () => { throw new Error('Aborted connection subscribed'); },
    signal: controller.signal, sequence: () => 0,
    snapshot: value => published.push(value), ready: () => { throw new Error('Aborted connection became ready'); }, notice() {},
  });
  controller.abort(); resolve({ sequence: 3 });
  await observed;
  assert.deepEqual(published, []);
});

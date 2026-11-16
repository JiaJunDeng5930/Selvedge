import test from 'node:test';
import assert from 'node:assert/strict';
import { observeConnection } from '../host/public/connection.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { events } from '../host/network.mjs';
import { startServer } from '../host/server.mjs';
import { home } from './support.mjs';

async function subscribed(t) {
  const connected = Promise.withResolvers();
  const cancellation = new AbortController();
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  let current = 0;
  let requestLatest = 0;
  let requests = 0;
  const notices = new Map();
  const worlds = new Map();
  const replies = new Map();
  const waiting = (map, key) => {
    if (!map.has(key)) map.set(key, Promise.withResolvers());
    return map.get(key);
  };
  const task = observeConnection({
    request: async () => { requests++; return { sequence: requestLatest }; },
    fetchEvents: async () => { connected.resolve(); return new Response(readable); },
    signal: cancellation.signal,
    namespace: () => 'source',
    sequence: () => current,
    snapshot(body) { current = body.sequence; waiting(worlds, current).resolve(); },
    ready() {},
    notice(value) { waiting(notices, value.name).resolve(); return false; },
    refreshNeeded: event => current < Number(event.sequence),
    commandReply: id => replies.get(id)?.promise,
  });
  t.after(async () => { cancellation.abort(); await writer.close(); await task; });
  await connected.promise;
  return {
    get requests() { return requests; },
    accept(sequence) { current = sequence; },
    async commit(sequence, id) {
      requestLatest = sequence;
      await writer.write(new TextEncoder().encode(`data: ${JSON.stringify({ type: 'commit', sequence, ...(id ? { browser_request_id: id } : {}) })}\n\n`));
    },
    reply: id => waiting(replies, id),
    world: sequence => waiting(worlds, sequence).promise,
    async barrier(name) {
      await writer.write(new TextEncoder().encode(`data: ${JSON.stringify({ type: 'diagnostic', name })}\n\n`));
      await waiting(notices, name).promise;
    },
  };
}

test('a matching live reply can cover only its own commit, without stopping the event stream', async t => {
  const client = await subscribed(t);
  const reply = client.reply('first');
  await client.commit(1, 'first');
  await client.barrier('one');
  assert.equal(client.requests, 1);
  client.accept(1);
  reply.resolve();
  await client.barrier('two');
  assert.equal(client.requests, 1);
  await client.commit(2, 'another-browser');
  await client.world(2);
  assert.equal(client.requests, 2);
});

test('a lost command receipt falls back to the authenticated world', async t => {
  const client = await subscribed(t);
  const reply = client.reply('first');
  await client.commit(1, 'first');
  await client.barrier('one');
  assert.equal(client.requests, 1);
  reply.resolve();
  await client.world(1);
  assert.equal(client.requests, 2);
});

test('a stalled command receipt does not indefinitely hold publication', async t => {
  const client = await subscribed(t);
  client.reply('stalled');
  await client.commit(1, 'stalled');
  await client.world(1);
  assert.equal(client.requests, 2);
});

test('a browser command marker identifies just its own durable commit', async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const running = await startServer({ home: directory, cwd: directory, config });
  t.after(() => running.close());
  const page = await fetch(running.url);
  const headers = { cookie: page.headers.get('set-cookie').split(';')[0], origin: running.address };
  const controller = new AbortController();
  const stream = await fetch(`${running.address}/api/events`, { headers, signal: controller.signal });
  const reader = events(stream.body, running.service.limits.frame_bytes);
  const next = async () => JSON.parse((await reader.next()).value);
  try {
    assert.equal((await next()).type, 'stream-state');
    const initial = await next();
    assert.equal(initial.type, 'commit');
    assert.equal(initial.browser_request_id, undefined);

    const id = '9ef97a10c037693a26e17b3ec523f9a9';
    const response = await fetch(`${running.address}/api/browser/command`, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json', 'x-selvedge-browser-request-id': id },
      body: JSON.stringify({ command: { op: 'create_card', title: 'Browser request' } }),
    });
    const body = await response.json();
    assert.equal(body.reply.ok, true, JSON.stringify(body.reply));
    const owned = await next();
    assert.equal(owned.type, 'commit');
    assert.equal(owned.sequence, body.sequence);
    assert.equal(owned.browser_request_id, id);

    const unrelated = await running.service.command({ op: 'create_card', title: 'Other request' });
    assert.equal(unrelated.reply.ok, true);
    const other = await next();
    assert.equal(other.type, 'commit');
    assert.equal(other.sequence, unrelated.sequence);
    assert.equal(other.browser_request_id, undefined);
  } finally {
    controller.abort();
    await reader.return().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
});

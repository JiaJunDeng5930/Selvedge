import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { eventForForm } from '../host/public/renderer.mjs';
import { taskIdle, presentationNodes as nodes } from './support.mjs';

function find(presentation, key) { return nodes(presentation.root).find(node => node.key === key); }

test('the HTTP presentation boundary is authenticated, command-only, and replayable', async t => {
  const home = await mkdtemp(path.join(tmpdir(), 'selvedge-ui-'));
  t.after(() => rm(home, { recursive: true, force: true }));
  const config = validateConfig({ ...defaultConfig, port: 0 });
  let running = await startServer({ home, config, cwd: home });
  t.after(() => running.close());
  const post = async (body, authorized = true) => {
    const response = await fetch(`${running.address}/api/ui`, { method: 'POST',
      headers: { 'content-type': 'application/json', ...(authorized ? { authorization: `Bearer ${running.token}` } : {}) }, body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  };
  assert.equal((await post({ event: { type: 'refresh' } }, false)).status, 401);
  const before = running.service.journal.sequence;
  const initial = await post({ event: { type: 'refresh' } });
  assert.equal(initial.status, 200);
  assert.equal(running.service.journal.sequence, before);
  const form = find(initial.body.result.presentation, 'create');
  const created = await post({ state: initial.body.result.presentation.state, event: eventForForm(form, { profile: 'demo', reasoning: 'medium', message: 'Native UI', settings: '{}' }) });
  assert.equal(created.body.result.receipt.ok, true);
  assert.equal((await post({ kind: 'tool', event: { type: 'refresh' } })).status, 400);
  const page = await taskIdle(running.service);
  await running.close();
  running = await startServer({ home, config, cwd: home });
  const restored = await post({ state: created.body.result.presentation.state, event: { type: 'refresh' } });
  assert.deepEqual(find(restored.body.result.presentation, 'state').value, page.task);
  const thread = find(restored.body.result.presentation, 'task/0');
  assert.equal(thread.kind, 'thread');
  assert.equal(thread.title, 'Native UI');
  assert.equal(thread.timeline[0].key, 'transcript');
  assert.equal(thread.composer[0].kind, 'composer');
  assert.equal(thread.composer[0].draft_key, 'task/0');
  for (const asset of ['/', '/app.mjs', '/renderer.mjs', '/style.css', '/widgets.mjs', '/events.mjs',
    '/streams.mjs', '/conversation.mjs', '/dom.mjs', '/markdown.mjs', '/markdown-worker.mjs', '/vendor/streaming-markdown.mjs',
    '/desktop.mjs', '/vendor/desktop-ui.mjs', '/vendor/desktop-scroll.mjs', '/vendor/desktop.css', '/vendor/desktop-tokens.css',
    '/vendor/highlight.mjs', '/vendor/katex.mjs']) assert.equal((await fetch(`${running.address}${asset}`)).status, 200);
  assert.notEqual((await fetch(`${running.address}/vendor/../../config.mjs`)).status, 200);
});

test('the web adapter binds fields generically and refuses undeclared or prototype routes', () => {
  const form = { event: { arbitrary: { count: 0, text: '', data: null } }, fields: [
    { name: 'x', label: 'Count', kind: 'integer', binding: ['arbitrary', 'count'] },
    { name: 'y', label: 'Text', kind: 'text', binding: ['arbitrary', 'text'] },
    { name: 'z', label: 'Data', kind: 'json', binding: ['arbitrary', 'data'] },
  ] };
  assert.deepEqual(eventForForm(form, { x: '3', y: '<script>alert(1)</script>', z: '[true]' }), { arbitrary: { count: 3, text: '<script>alert(1)</script>', data: [true] } });
  assert.throws(() => eventForForm(form, { x: '1e3', z: '[]' }), /integer/);
  for (const binding of [['__proto__', 'polluted'], ['arbitrary', 'missing'], ['missing', 'x']]) {
    assert.throws(() => eventForForm({ event: form.event, fields: [{ name: 'x', kind: 'text', binding }] }, { x: 'value' }), /binding/);
  }
  assert.equal({}.polluted, undefined);
});

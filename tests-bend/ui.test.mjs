import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { eventForForm, mount } from '../host/public/renderer.mjs';
import { taskIdle } from './support.mjs';

function nodes(node) { return [node, ...(node.children ?? []).flatMap(nodes)]; }
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
  const created = await post({ state: initial.body.result.presentation.state, event: eventForForm(form, { profile: 'demo', reasoning: 'medium', message: 'Native UI' }) });
  assert.equal(created.body.result.receipt.ok, true);
  assert.equal((await post({ kind: 'tool', event: { type: 'refresh' } })).status, 400);
  const page = await taskIdle(running.service);
  await running.close();
  running = await startServer({ home, config, cwd: home });
  const restored = await post({ state: created.body.result.presentation.state, event: { type: 'refresh' } });
  assert.deepEqual(find(restored.body.result.presentation, 'state').value, page.task);
  for (const asset of ['/', '/app.mjs', '/renderer.mjs', '/style.css', '/widgets.mjs', '/events.mjs',
    '/streams.mjs', '/markdown.mjs', '/markdown-worker.mjs', '/vendor/streaming-markdown.mjs',
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

// A DOM harness checks the actual adapter without introducing a browser framework
// or npm runtime dependency. A real-browser interaction is a separate host check.
class Element {
  constructor(tagName, ownerDocument) { Object.assign(this, { tagName, ownerDocument, children: [], dataset: {}, attributes: {}, listeners: {}, value: '' }); }
  get childNodes() { return this.children; }
  append(...children) { for (const child of children) this.insertBefore(child, null); }
  insertBefore(child, before) {
    child.remove();
    const index = before ? this.children.indexOf(before) : this.children.length;
    this.children.splice(index, 0, child); child.parentNode = this;
  }
  remove() {
    if (this.parentNode) this.parentNode.children.splice(this.parentNode.children.indexOf(this), 1);
    this.parentNode = null;
  }
  replaceChildren(...children) { for (const child of [...this.children]) child.remove(); this.append(...children); }
  setAttribute(name, value) { this.attributes[name] = value; }
  addEventListener(name, listener) { this.listeners[name] = listener; }
  focus() { this.ownerDocument.activeElement = this; }
  setSelectionRange(start, end) { this.selectionStart = start; this.selectionEnd = end; }
}

test('the adapter renders literal content, native enabled flags and stable unsent drafts without domain tables', async () => {
  const document = { createElement(tag) { return new Element(tag, this); }, getElementById(id) { return walk(root).find(node => node.id === id); } };
  const root = new Element('main', document);
  function walk(node) { return [node, ...node.children.flatMap(walk)]; }
  const events = [];
  const drafts = new Map();
  const tree = { kind: 'group', key: 'root', role: 'screen', title: 'A new domain', children: [
    { kind: 'text', key: 'text', role: 'note', title: 'Literal', text: '<img src=x onerror=alert(1)>' },
    { kind: 'action', key: 'denied', label: 'Not allowed', enabled: false, selected: false, event: { type: 'arbitrary' } },
    { kind: 'form', key: 'form', title: 'Generic', label: 'Submit', enabled: true, event: { payload: { free: '' } }, fields: [
      { name: 'free', label: 'Text', kind: 'text', value: '', schema: {}, required: true, binding: ['payload', 'free'] },
    ] },
  ] };
  mount(root, tree, (event, key) => events.push({ event, key }), { drafts });
  assert.equal(walk(root).some(node => node.tagName === 'img'), false);
  assert.equal(walk(root).some(node => node.textContent === '<img src=x onerror=alert(1)>'), true);
  const denied = walk(root).find(node => node.textContent === 'Not allowed');
  assert.equal(denied.disabled, true);
  denied.onclick();
  assert.deepEqual(events, []);
  let input = walk(root).find(node => node.tagName === 'input');
  input.value = 'Not submitted yet';
  input.listeners.input();
  input.focus();
  input.selectionStart = 3;
  input.selectionEnd = 3;
  mount(root, tree, (event, key) => events.push({ event, key }), { drafts });
  input = walk(root).find(node => node.tagName === 'input');
  assert.equal(input.value, 'Not submitted yet');
  assert.equal(document.activeElement, input);
  assert.equal(input.selectionStart, 3);
  await walk(root).find(node => node.tagName === 'form').onsubmit({ preventDefault() {} });
  assert.deepEqual(events, [{ event: { payload: { free: 'Not submitted yet' } }, key: '/root/form' }]);
  assert.throws(() => mount(root, { kind: 'invented', key: 'bad' }, () => {}), /Unsupported/);
  for (const name of ['app.mjs', 'renderer.mjs', 'widgets.mjs', 'streams.mjs']) {
    const source = await readFile(new URL(`../host/public/${name}`, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /taskSnapshot|\.status\s*===\s*['"](?:active|archived)|message\.role|\/api\/commands|\.innerHTML\s*=/);
  }
});

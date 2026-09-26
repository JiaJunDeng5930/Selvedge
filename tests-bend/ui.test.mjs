import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Kernel } from '../host/kernel.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { eventForForm, mount } from '../host/public/renderer.mjs';
import { providerOutput } from '../host/providers.mjs';
import { taskIdle } from './support.mjs';

function nodes(node) { return [node, ...(node.children ?? []).flatMap(nodes)]; }
function find(presentation, key) { return nodes(presentation.root).find(node => node.key === key); }

async function fixture(t) {
  const kernel = new Kernel({ timeout: 5000 });
  t.after(() => kernel.close());
  await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = value => input({ kind: 'command', command: value });
  await input({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'model' }], tools: [], max_fork: 4, max_descendants: 64 });
  let state = null;
  const ui = async event => {
    const result = await input({ kind: 'ui', state, event });
    if (result.reply.ok) state = result.reply.result.presentation.state;
    return result;
  };
  const settle = (ticket, items, task_id = 0) => input({ kind: 'model', task_id, ticket, ok: true, items });
  return { input, command, ui, settle };
}

test('Bend presents profiles, interprets generic form bindings, and renders the committed post-state', async t => {
  const { ui, command, settle } = await fixture(t);
  let decision = await ui({ type: 'refresh' });
  assert.equal(decision.durable, false);
  assert.deepEqual(decision.effects, []);
  const form = find(decision.reply.result.presentation, 'create');
  assert.equal(form.enabled, true);
  assert.deepEqual(form.fields[0].choices, [{ value: 'fixture', label: 'fixture · responses / model' }]);
  const event = eventForForm(form, { profile: 'fixture', reasoning: 'medium', message: 'Hello <script>世界</script>' });
  assert.equal(form.event.command.message, 'message', 'the native event template is immutable');
  decision = await ui(event);
  assert.equal(decision.durable, true);
  const { presentation, receipt } = decision.reply.result;
  assert.equal(receipt.ok, true);
  assert.deepEqual(presentation.state, { selected: 0, after: null, tasks_after: 0 });
  const actual = (await command({ op: 'read', task_id: 0 })).reply.result.task;
  assert.deepEqual(find(presentation, 'state').value, actual);
  assert.equal(actual.phase, 'model_pending');
  assert.equal(find(presentation, 'fork/0').enabled, false);
  assert.equal(find(presentation, 'message/0').text, 'Hello <script>世界</script>');
  await settle(decision.effects[0].ticket, providerOutput([
    { type: 'message', role: 'assistant', phase: 'final_answer', content: [{ type: 'output_text', text: 'A response. ' }, { type: 'refusal', refusal: 'A refusal.' }] },
    { type: 'reasoning', encrypted_content: 'not presentation text', summary: [{ type: 'summary_text', text: 'Public summary' }] },
  ]));
  decision = await ui({ type: 'refresh' });
  assert.equal(find(decision.reply.result.presentation, 'fork/0').enabled, true);
  assert.equal(find(decision.reply.result.presentation, 'message/1').text, 'A response. A refusal.');
  assert.equal(find(decision.reply.result.presentation, 'message/2').text, 'Public summary');
  assert.equal(JSON.stringify(decision.reply.result.presentation).includes('not presentation text'), false);
});

test('native controls and forms revalidate stale actions rather than trusting the presentation', async t => {
  const { ui, command, settle } = await fixture(t);
  const created = await ui({ type: 'submit', command: { op: 'create', profile: 'fixture', message: 'Start' } });
  await settle(created.effects[0].ticket, [{ type: 'text', text: 'done' }]);
  const view = (await ui({ type: 'refresh' })).reply.result.presentation;
  const stale = find(view, 'freeze').event;
  assert.equal(find(view, 'freeze').enabled, true);
  await command({ op: 'archive', task_id: 0 });
  const rejected = await ui(stale);
  assert.equal(rejected.reply.ok, true, 'a refused command still returns its live surface');
  assert.equal(rejected.reply.result.receipt.ok, false);
  assert.deepEqual(rejected.effects, []);
  for (const node of nodes(rejected.reply.result.presentation.root)) {
    if (node.kind === 'form' || (node.kind === 'action' && node.event.type === 'submit')) assert.equal(node.enabled, false, node.key);
  }
  const forged = await ui({ type: 'submit', command: { op: 'send', task_id: 0, message: 'Must not be accepted' } });
  assert.equal(forged.reply.result.receipt.ok, false);
  assert.equal((await command({ op: 'read', task_id: 0 })).reply.result.messages.some(message => message.content === 'Must not be accepted'), false);
});

test('selection and paging are effect-free observations; unknown tasks and invalid events are explicit', async t => {
  const { ui, command, input } = await fixture(t);
  const created = await ui({ type: 'submit', command: { op: 'create', profile: 'fixture', message: 'Start' } });
  const before = (await command({ op: 'read', task_id: 0 })).reply.result;
  for (const event of [{ type: 'select', task_id: 0 }, { type: 'history', after: 0 }, { type: 'history', after: null }, { type: 'tasks', after: 0 }, { type: 'refresh' }]) {
    const result = await ui(event);
    assert.equal(result.durable, false);
    assert.deepEqual(result.effects, []);
    assert.deepEqual((await command({ op: 'read', task_id: 0 })).reply.result, before);
  }
  assert.equal(find((await ui({ type: 'select', task_id: 90 })).reply.result.presentation, 'missing/reason').role, 'error');
  for (const body of [
    { state: { selected: '0', after: null, tasks_after: 0 }, event: { type: 'refresh' } },
    { state: null, event: { type: 'model', ticket: created.effects[0].ticket, ok: true } },
    { state: null, event: { type: 'select', task_id: -1 } },
    { state: null, event: { type: 'refresh', command: { op: 'archive', task_id: 0 } } },
    { state: null, event: { type: 'submit', command: { op: 'list' }, extra: true } },
    { state: null, event: { type: 'submit', command: { op: 'create', profile: 'fixture' } } },
  ]) {
    const result = await input({ kind: 'ui', ...body });
    assert.equal(result.reply.ok, false, JSON.stringify(body));
    assert.equal(result.durable, false);
    assert.deepEqual(result.effects, []);
  }
});

test('Bend owns independent-operation controls and bounded conversation paging', async t => {
  const { ui, settle, command, input } = await fixture(t);
  const created = await ui({ type: 'submit', command: { op: 'create', profile: 'fixture', message: 'Start' } });
  const tools = await settle(created.effects[0].ticket, [
    ...Array.from({ length: 48 }, (_, index) => ({ type: 'text', text: `Line ${index}` })),
    { type: 'call', id: 'slow', name: 'bash', arguments: { command: 'sleep 60' } },
  ]);
  const ticket = tools.effects.find(effect => effect.kind === 'tool').ticket;
  let view = (await ui({ type: 'refresh' })).reply.result.presentation;
  assert.equal(find(view, `cancel/${ticket}`).enabled, true);
  assert.equal(find(view, 'history/previous').enabled, true);
  assert.equal(find(view, 'history/next').enabled, false);
  assert.ok(nodes(view.root).filter(node => node.key.startsWith('message/')).length <= 40);
  const cancel = find(view, `cancel/${ticket}`).event;
  await input({ kind: 'tool', task_id: 0, ticket, value: 'done', error: false });
  const rejected = await ui(cancel);
  assert.equal(rejected.reply.result.receipt.ok, false);
  assert.equal(find(rejected.reply.result.presentation, `cancel/${ticket}`), undefined);
  view = (await ui({ type: 'history', after: 0 })).reply.result.presentation;
  assert.equal(find(view, 'message/0').text, 'Start');
  assert.equal(find(view, 'history/next').enabled, true);
  assert.equal((await command({ op: 'read', task_id: 0 })).reply.result.task.operations.length, 0);
});

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
  for (const asset of ['/', '/app.mjs', '/renderer.mjs', '/style.css']) assert.equal((await fetch(`${running.address}${asset}`)).status, 200);
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
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
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
  for (const name of ['app.mjs', 'renderer.mjs']) {
    const source = await readFile(new URL(`../host/public/${name}`, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /taskSnapshot|\.status\s*===\s*['"](?:active|archived)|message\.role|\/api\/commands|\.innerHTML\s*=/);
  }
});

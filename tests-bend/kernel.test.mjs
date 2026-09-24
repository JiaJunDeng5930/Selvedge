import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';
import { parseJson, stringifyJson, JsonNumber } from '../host/codec.mjs';

const remote = { name: 'mcp__fixture__inspect', description: 'Inspect input', schema: { type: 'object' }, server: 'fixture', remote: 'inspect' };

async function kernel(t, overrides = {}) {
  const k = new Kernel({ timeout: 5000 });
  t.after(() => k.close());
  await k.initialize();
  const send = async input => (await k.request(input)).value;
  const command = body => send({ kind: 'command', command: body });
  const configure = config => send({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model' }], tools: [], max_fork: 4, max_descendants: 8, ...config });
  assert.equal((await configure(overrides)).reply.ok, true);
  return { k, send, command, configure };
}

function model(task_id, ticket, text = 'done', calls = []) {
  return { kind: 'model', task_id, ticket, ok: true,
    items: [...(text ? [{ type: 'text', text }] : []), ...calls.map(call => ({ type: 'call', ...call }))] };
}

test('the native program exposes its command model and preserves Unicode and exact JSON numbers', async t => {
  const { k, send, command } = await kernel(t, { tools: [remote] });
  assert.deepEqual(k.description.commands.map(x => x.name), ['create', 'send', 'freeze', 'unfreeze', 'stop', 'archive', 'fork', 'read', 'list', 'describe']);
  const text = 'hello\n"\\\0 世界 😀';
  const created = await command({ op: 'create', profile: 'fixture', message: text });
  assert.equal(created.effects[0].history[0].content, text);
  const arguments_ = parseJson('{"huge":9007199254740993,"fraction":1.2300,"nested":[null,true,{"0":"x"}]}');
  const result = await send(model(0, 0, '', [{ id: 'inspect', name: remote.name, arguments: arguments_ }]));
  assert.equal(result.effects[0].kind, 'tool');
  assert.equal(stringifyJson(result.effects[0].call.arguments), stringifyJson(arguments_));
  await send({ kind: 'tool', task_id: 0, ticket: 1, value: arguments_, error: false });
  const page = await command({ op: 'read', task_id: 0 });
  const output = page.reply.result.messages.find(x => x.role === 'function_output');
  assert.ok(output.content.huge instanceof JsonNumber);
  assert.equal(output.content.huge.source, '9007199254740993');
  assert.equal(page.durable, false);
  assert.deepEqual(page.effects, []);
  assert.equal((await command({ op: 'read', task_id: 0, limit: 0 })).reply.ok, false);
  assert.equal((await command({ op: 'create', profile: 'fixture', message: 'x', unknown: 1 })).reply.ok, false);
});

test('queued inputs are FIFO; freeze settles results without dispatch and stop reactivates only on input', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'first' });
  await command({ op: 'send', task_id: 0, message: 'second' });
  await command({ op: 'send', task_id: 0, message: 'third' });
  const next = await send(model(0, 0));
  assert.deepEqual(next.effects[0].history.map(x => x.content), ['first', 'done', 'second', 'third']);
  await command({ op: 'freeze', task_id: 0 });
  const completed = await send(model(0, 1, 'settled while frozen'));
  assert.deepEqual(completed.effects, []);
  await command({ op: 'send', task_id: 0, message: 'fourth' });
  const frozen = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(frozen.task.status, 'frozen');
  assert.equal(frozen.task.queued, 1);
  assert.deepEqual(frozen.task.controls, ['unfreeze', 'archive']);
  const resumed = await command({ op: 'unfreeze', task_id: 0 });
  assert.equal(resumed.effects[0].history.at(-1).content, 'fourth');
  await command({ op: 'stop', task_id: 0 });
  assert.deepEqual((await send(model(0, 2))).effects, []);
  const stopped = (await command({ op: 'read', task_id: 0 })).reply.result.task;
  assert.equal(stopped.status, 'stopped');
  assert.deepEqual(stopped.controls, ['archive']);
  const input = await command({ op: 'send', task_id: 0, message: 'resume' });
  assert.equal(input.effects[0].kind, 'model');
});

test('fork shares the call prefix, numbers its outputs, and never repeats an inherited unsafe call', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'start' });
  await command({ op: 'send', task_id: 0, message: 'parent-only queue' });
  const reply = await send(model(0, 0, '', [
    { id: 'split', name: 'fork_task', arguments: { child_count: 2, messages: ['left', 'right'] } },
    { id: 'external', name: 'bash', arguments: { command: 'printf hello' } }
  ]));
  assert.equal(reply.effects.filter(x => x.kind === 'tool').length, 1);
  assert.equal(reply.effects.find(x => x.kind === 'tool').task_id, 0);
  for (const id of [1, 2]) {
    const page = (await command({ op: 'read', task_id: id })).reply.result;
    assert.equal(page.task.parent, 0);
    const messages = page.messages;
    assert.equal(messages.find(x => x.role === 'function_output' && x.call_id === 'split').content, id);
    assert.equal(messages.find(x => x.role === 'function_output' && x.call_id === 'external').content.error.code, 'outcome_unknown');
    assert.equal(messages.some(x => x.content === 'parent-only queue'), false);
    assert.equal(messages.filter(x => x.role === 'function_call').length, 2);
  }
  await send({ kind: 'tool', task_id: 0, ticket: 1, value: { exit_code: 0 }, error: false });
  const caller = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(caller.messages.find(x => x.role === 'function_output' && x.call_id === 'split').content, 0);
  assert.equal(caller.messages.at(-1).content, 'parent-only queue');
});

test('every ancestor quota includes archived descendants', async t => {
  const { send, command } = await kernel(t, { max_descendants: 2 });
  await command({ op: 'create', profile: 'fixture', message: 'root' });
  await send(model(0, 0));
  const forked = await command({ op: 'fork', task_id: 0, child_count: 2 });
  assert.deepEqual(forked.reply.result.children, [1, 2]);
  const childEffect = forked.effects.find(x => x.kind === 'model' && x.task_id === 1);
  await send(model(1, childEffect.ticket));
  await command({ op: 'archive', task_id: 2 });
  const rejected = await command({ op: 'fork', task_id: 1, child_count: 1 });
  assert.equal(rejected.reply.ok, false);
  assert.equal(rejected.reply.error.code, 'resource_limit');
  assert.equal((await command({ op: 'list' })).reply.result.tasks.length, 3);
});

test('catalog changes preserve frozen definitions and validate replies against the sent manifest', async t => {
  const { send, command, configure } = await kernel(t, { tools: [remote] });
  await command({ op: 'create', profile: 'fixture', message: 'inspect' });
  await configure({ tools: [] });
  const completed = await send(model(0, 0, '', [{ id: 'call', name: remote.name, arguments: {} }]));
  const next = completed.effects.find(x => x.kind === 'model');
  assert.ok(next.tools.some(x => x.name === remote.name));
  assert.equal(next.callable.includes(remote.name), false);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.messages.find(x => x.role === 'function_output').content.error.code, 'tool_unavailable');
  const invalid = await send(model(0, next.ticket, '', [{ id: 'new', name: remote.name, arguments: {} }]));
  assert.deepEqual(invalid.effects, []);
  assert.equal((await command({ op: 'read', task_id: 0 })).reply.result.messages.at(-1).role, 'error');
});

test('recovery records an unknown external outcome and stale or repeated results cannot append output', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'run' });
  const started = await send(model(0, 0, '', [{ id: 'shell', name: 'bash', arguments: { command: 'printf once' } }]));
  const ticket = started.effects[0].ticket;
  const recovery = await send({ kind: 'recover' });
  assert.equal(recovery.effects.some(x => x.kind === 'tool'), false);
  const stale = await send({ kind: 'tool', task_id: 0, ticket, value: 'late', error: false });
  assert.equal(stale.reply.result.accepted, false);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.messages.filter(x => x.role === 'function_output').length, 1);
  assert.equal(page.messages.find(x => x.role === 'function_output').content.error.code, 'outcome_unknown');
  const modelTicket = recovery.effects[0].ticket;
  await send(model(0, modelTicket));
  assert.equal((await send(model(0, modelTicket, 'duplicate'))).reply.result.accepted, false);
});

test('self-archive and its tool output commit together, and later task writes are rejected', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'archive me' });
  const archived = await send(model(0, 0, '', [{ id: 'archive', name: 'archive_task', arguments: { task_id: 0 } }]));
  assert.deepEqual(archived.effects, [{ kind: 'cancel', task_id: 0 }]);
  const before = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(before.task.status, 'archived');
  assert.equal(before.task.phase, 'idle');
  assert.equal(before.messages.at(-1).call_id, 'archive');
  assert.equal((await command({ op: 'send', task_id: 0, message: 'too late' })).reply.ok, false);
  assert.equal((await command({ op: 'unfreeze', task_id: 0 })).reply.ok, false);
  assert.deepEqual((await command({ op: 'read', task_id: 0 })).reply.result, before);
});

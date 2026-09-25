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

test('interrupt closes accepted calls without replay, ignores late results, and retains FIFO input', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'start' });
  const pending = await send(model(0, 0, '', [
    { id: 'running', name: 'bash', arguments: { command: 'sleep 60' } },
    { id: 'waiting', name: 'bash', arguments: { command: 'must not run' } },
  ]));
  await command({ op: 'send', task_id: 0, message: 'older queued instruction' });
  await command({ op: 'freeze', task_id: 0 });
  const stopped = await command({ op: 'interrupt', task_id: 0 });
  assert.equal(stopped.reply.ok, true);
  assert.deepEqual(stopped.effects, [{ kind: 'cancel', task_id: 0 }]);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.task.status, 'stopped');
  assert.equal(page.task.phase, 'idle');
  assert.equal(page.task.queued, 1);
  const outputs = page.messages.filter(message => message.role === 'function_output');
  assert.deepEqual(outputs.map(message => [message.call_id, message.content.error.code]), [
    ['running', 'outcome_unknown'], ['waiting', 'cancelled_before_execution'],
  ]);
  await command({ op: 'interrupt', task_id: 0 });
  const late = await send({ kind: 'tool', task_id: 0, ticket: pending.effects[0].ticket, value: 'late', error: false });
  assert.equal(late.reply.result.accepted, false);
  assert.deepEqual((await command({ op: 'read', task_id: 0 })).reply.result.messages, page.messages);
  const resumed = await command({ op: 'send', task_id: 0, message: 'newer instruction' });
  assert.deepEqual(resumed.effects[0].history.filter(message => message.role === 'user').map(message => message.content),
    ['start', 'older queued instruction', 'newer instruction']);
  assert.ok(resumed.effects[0].ticket > pending.effects[0].ticket);
});

test('manual compaction is a no-tool checkpoint; full history and inherited context are retained', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'original request' });
  assert.equal((await command({ op: 'compact', task_id: 0 })).reply.error.code, 'task_busy');
  await send(model(0, 0, 'original answer'));
  const original = (await command({ op: 'read', task_id: 0 })).reply.result.messages;
  const compact = await command({ op: 'compact', task_id: 0 });
  assert.equal(compact.effects[0].kind, 'summary');
  assert.deepEqual(compact.effects[0].tools, []);
  assert.deepEqual(compact.effects[0].callable, []);
  await send(model(0, compact.effects[0].ticket, 'Retained facts and next steps.'));
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.task.phase, 'idle');
  assert.deepEqual(page.messages.slice(0, original.length), original);
  assert.equal(page.messages.at(-1).role, 'context_summary');
  const fork = await command({ op: 'fork', task_id: 0, child_count: 1 });
  const inherited = fork.effects.find(effect => effect.task_id === 1);
  assert.equal(inherited.history[0].role, 'context_summary');
  assert.equal(inherited.history.some(message => message.content === 'original request'), false);
  await send(model(0, fork.effects.find(effect => effect.task_id === 0).ticket));
  const resumed = await command({ op: 'send', task_id: 0, message: 'continue precisely' });
  const effect = resumed.effects.find(effect => effect.task_id === 0);
  assert.equal(effect.history[0].role, 'context_summary');
  assert.equal(effect.history.at(-1).content, 'continue precisely');
});

test('failed or tool-bearing summaries preserve original history and never authorize a tool', async t => {
  const { k, send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'work' });
  await send(model(0, 0));
  for (const [text, calls] of [
    ['', []], ['x'.repeat(k.description.limits.summary_limit_bytes + 1), []],
    ['summary with an unauthorized tool', [{ id: 'injected', name: 'bash', arguments: { command: 'do not run' } }]],
  ]) {
    const compact = await command({ op: 'compact', task_id: 0 });
    const settled = await send(model(0, compact.effects[0].ticket, text, calls));
    assert.deepEqual(settled.effects, []);
    const page = (await command({ op: 'read', task_id: 0 })).reply.result;
    assert.equal(page.task.phase, 'idle');
    assert.equal(page.messages.some(message => message.role === 'context_summary' || message.role === 'function_call'), false);
    assert.equal(page.messages[0].content, 'work');
  }
});

test('automatic compaction resumes after a bounded checkpoint and retries interrupted summaries with fresh tickets', { timeout: 15_000 }, async t => {
  const { k, send, command } = await kernel(t);
  const original = 'large request '.repeat(Math.ceil(k.description.limits.context_threshold_bytes / 14));
  const created = await command({ op: 'create', profile: 'fixture', message: original });
  assert.equal(created.effects[0].kind, 'summary', JSON.stringify(created.reply));
  const recovered = await send({ kind: 'recover' });
  assert.equal(recovered.effects[0].kind, 'summary');
  assert.notEqual(recovered.effects[0].ticket, created.effects[0].ticket);
  const stale = await send(model(0, created.effects[0].ticket, 'stale summary'));
  assert.equal(stale.reply.result.accepted, false);
  const resumed = await send(model(0, recovered.effects[0].ticket, 'Preserved user goal and constraints.'));
  assert.equal(resumed.effects[0].kind, 'model');
  assert.deepEqual(resumed.effects[0].history.map(message => message.role), ['context_summary']);
  assert.equal((await command({ op: 'read', task_id: 0 })).reply.result.messages[0].content, original);
  await command({ op: 'interrupt', task_id: 0 });
});

test('compaction settlement respects freeze and interruption does not install a stale checkpoint', async t => {
  const { send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'work' });
  await send(model(0, 0));
  const first = await command({ op: 'compact', task_id: 0 });
  await command({ op: 'freeze', task_id: 0 });
  await command({ op: 'send', task_id: 0, message: 'queued during summary' });
  assert.deepEqual((await send(model(0, first.effects[0].ticket, 'frozen summary'))).effects, []);
  const resumed = await command({ op: 'unfreeze', task_id: 0 });
  assert.equal(resumed.effects[0].history.at(-1).content, 'queued during summary');
  await send(model(0, resumed.effects[0].ticket));
  const next = await command({ op: 'compact', task_id: 0 });
  await command({ op: 'interrupt', task_id: 0 });
  assert.equal((await send(model(0, next.effects[0].ticket, 'must not install'))).reply.result.accepted, false);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.task.status, 'stopped');
  assert.equal(page.messages.some(message => message.content === 'must not install'), false);
});

test('a supplied checkpoint recovers oversized context without needing a working model', async t => {
  const { k, send, command } = await kernel(t);
  const created = await command({ op: 'create', profile: 'fixture', message: 'x'.repeat(k.description.limits.context_threshold_bytes) });
  assert.equal(created.effects[0].kind, 'summary');
  await command({ op: 'interrupt', task_id: 0 });
  const before = (await command({ op: 'read', task_id: 0 })).reply.result.messages;
  assert.equal((await command({ op: 'compact', task_id: 0, summary: ' ' })).reply.error.code, 'invalid_summary');
  assert.deepEqual((await command({ op: 'read', task_id: 0 })).reply.result.messages, before);
  const compacted = await command({ op: 'compact', task_id: 0, summary: 'User-supplied continuation note.' });
  assert.equal(compacted.reply.ok, true);
  assert.deepEqual(compacted.effects, []);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.task.status, 'stopped');
  assert.deepEqual(page.messages.slice(0, before.length), before);
  const resumed = await command({ op: 'send', task_id: 0, message: 'Continue.' });
  assert.equal(resumed.effects[0].kind, 'model');
  assert.deepEqual(resumed.effects[0].history.map(message => message.content), ['User-supplied continuation note.', 'Continue.']);
  await command({ op: 'archive', task_id: 0 });
  assert.equal((await command({ op: 'compact', task_id: 0, summary: 'not allowed' })).reply.error.code, 'task_archived');
});

test('automatic context cuts wait for every accepted tool result', async t => {
  const { k, send, command } = await kernel(t);
  await command({ op: 'create', profile: 'fixture', message: 'run two tools' });
  const first = await send(model(0, 0, '', [
    { id: 'one', name: 'bash', arguments: { command: 'first' } },
    { id: 'two', name: 'bash', arguments: { command: 'second' } },
  ]));
  assert.equal((await command({ op: 'compact', task_id: 0, summary: 'must not cut' })).reply.error.code, 'task_busy');
  const second = await send({ kind: 'tool', task_id: 0, ticket: first.effects[0].ticket,
    value: 'x'.repeat(k.description.limits.context_threshold_bytes), error: false });
  assert.equal(second.effects[0].kind, 'tool');
  const summary = await send({ kind: 'tool', task_id: 0, ticket: second.effects[0].ticket, value: 'done', error: false });
  assert.equal(summary.effects[0].kind, 'summary');
  const history = summary.effects[0].history;
  assert.deepEqual(history.filter(item => item.role === 'function_call').map(item => item.content.id), ['one', 'two']);
  assert.deepEqual(history.filter(item => item.role === 'function_output').map(item => item.call_id), ['one', 'two']);
});

test('file tools use committed external tickets and recovery repeats only observations', async t => {
  for (const [name, arguments_] of [
    ['read_file', { path: 'example.txt' }],
    ['write_file', { path: 'example.txt', content: 'new', expected_revision: 'absent' }],
    ['edit_file', { path: 'example.txt', old_text: 'old', new_text: 'new', expected_revision: 'a'.repeat(64) }],
  ]) {
    const { send, command } = await kernel(t);
    const created = await command({ op: 'create', profile: 'fixture', message: 'work' });
    assert.ok(created.effects[0].tools.some(tool => tool.name === name));
    const result = await send(model(0, 0, '', [{ id: 'file-op', name, arguments: arguments_ }]));
    assert.equal(result.effects[0].kind, 'tool');
    assert.equal(result.effects[0].tool.name, name);
    const recovered = await send({ kind: 'recover' });
    const tools = recovered.effects.filter(effect => effect.kind === 'tool');
    assert.equal(tools.length, name === 'read_file' ? 1 : 0);
    if (tools.length) assert.notEqual(tools[0].ticket, result.effects[0].ticket);
    else {
      const page = (await command({ op: 'read', task_id: 0 })).reply.result;
      assert.equal(page.messages.find(message => message.role === 'function_output').is_error, true);
    }
  }
});

test('the native program exposes its command model and preserves Unicode and exact JSON numbers', async t => {
  const { k, send, command } = await kernel(t, { tools: [remote] });
  assert.deepEqual(k.description.commands.map(x => x.name), ['create', 'send', 'freeze', 'unfreeze', 'stop', 'interrupt', 'archive', 'compact', 'fork', 'read', 'list', 'describe']);
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
  assert.deepEqual(frozen.task.controls, ['unfreeze', 'interrupt', 'archive']);
  const resumed = await command({ op: 'unfreeze', task_id: 0 });
  assert.equal(resumed.effects[0].history.at(-1).content, 'fourth');
  await command({ op: 'stop', task_id: 0 });
  assert.deepEqual((await send(model(0, 2))).effects, []);
  const stopped = (await command({ op: 'read', task_id: 0 })).reply.result.task;
  assert.equal(stopped.status, 'stopped');
  assert.deepEqual(stopped.controls, ['interrupt', 'archive']);
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

test('an archive withdraws a model intent created earlier in the same commit', async t => {
  const { send, command } = await kernel(t);
  const first = await command({ op: 'create', profile: 'fixture', message: 'target' });
  await send(model(0, first.effects[0].ticket));
  const caller = await command({ op: 'create', profile: 'fixture', message: 'wake and archive target' });
  const result = await send(model(1, caller.effects[0].ticket, '', [
    { id: 'wake', name: 'send_message_to_task', arguments: { task_id: 0, message: 'new work' } },
    { id: 'seal', name: 'archive_task', arguments: { task_id: 0 } },
  ]));
  assert.equal(result.reply.ok, true);
  assert.equal(result.effects.some(effect => effect.kind === 'model' && effect.task_id === 0), false);
  assert.ok(result.effects.some(effect => effect.kind === 'cancel' && effect.task_id === 0));
  const target = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(target.task.status, 'archived');
  assert.equal(target.task.phase, 'idle');
  assert.equal(target.messages.at(-1).content, 'new work');
});

test('ambiguous profile and tool identities cannot replace the admitted catalog', async t => {
  const { command, configure } = await kernel(t);
  const before = (await command({ op: 'list' })).reply.result;
  for (const invalid of [
    { profiles: [{ key: 'duplicate', provider: 'echo', name: 'one' }, { key: 'duplicate', provider: 'echo', name: 'two' }] },
    { tools: [remote, { ...remote, description: 'A second route with the same exposed identity' }] },
  ]) {
    const rejected = await configure(invalid);
    assert.equal(rejected.reply.ok, false);
    assert.deepEqual(rejected.effects, []);
    assert.deepEqual((await command({ op: 'list' })).reply.result, before);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';

const plugin = (name, revision = '1', before_tool = true, events = []) => ({ reference: { name, revision }, before_tool, events });
const first = plugin('first');
const second = plugin('second');
const addedTool = { name: 'plugin__first__echo', description: 'Echo a value', schema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false }, plugin: first.reference, remote: 'echo' };
const remoteTool = { name: 'mcp__fixture__echo', description: 'Echo remotely', schema: { type: 'object' }, server: 'fixture', remote: 'echo' };
const call = (name, arguments_ = {}, id = 'call') => ({ type: 'call', id, name, arguments: arguments_ });

async function fixture(t, plugins = [first, second]) {
  const kernel = new Kernel({ timeout: 10_000 });
  t.after(() => kernel.close());
  await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = value => input({ kind: 'command', command: value });
  const environment = { kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture' }], tools: [addedTool, remoteTool], plugins, max_fork: 4, max_descendants: 64 };
  assert.equal((await input(environment)).reply.ok, true);
  const create = () => command({ op: 'create', profile: 'fixture', message: 'Exercise the native protocol without executing any effects' });
  const model = (effect, items) => input({ kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true, items });
  const hook = (effect, outcome = { decision: 'allow' }) => input({ kind: 'hook', task_id: effect.task_id, ticket: effect.ticket, outcome });
  const read = async (task_id = 0) => (await command({ op: 'read', task_id })).reply.result;
  return { input, command, create, model, hook, read, environment };
}

test('every internal, Bash, MCP and extension call enters the same native denial gate', async t => {
  const f = await fixture(t);
  for (const name of ['fork_task', 'read_task', 'send_message_to_task', 'archive_task', 'cancel_operation', 'bash', remoteTool.name, addedTool.name]) {
    const created = await f.create();
    const requested = await f.model(created.effects[0], [call(name)]);
    assert.equal(requested.reply.ok, true);
    assert.equal(requested.effects.length, 1);
    const effect = requested.effects[0];
    assert.equal(effect.kind, 'hook', name);
    assert.deepEqual(effect.plugin, first.reference);
    assert.equal(effect.call.name, name);
    const denied = await f.hook(effect, { decision: 'deny', reason: `Denied ${name}` });
    assert.equal(denied.reply.ok, true);
    assert.equal(denied.effects.some(effect => ['tool', 'hook'].includes(effect.kind)), false);
    const page = await f.read(effect.task_id);
    assert.equal(page.messages.filter(message => message.role === 'hook_record').length, 1);
    assert.equal(page.messages.find(message => message.role === 'function_output').content.error.code, 'hook_denied');
    assert.equal(page.task.operations.length, 0);
  }
  const listed = (await f.command({ op: 'list' })).reply.result;
  assert.equal(listed.tasks.length, 8, 'denied fork and archive did not mutate task ownership');
});

test('ordered native certificates preserve the original invocation and authorize only the final rewritten arguments', async t => {
  const f = await fixture(t);
  const created = await f.create();
  const initial = call('bash', { command: 'printf original' });
  const gate = (await f.model(created.effects[0], [initial])).effects[0];
  const rewritten = await f.hook(gate, { decision: 'rewrite', arguments: { command: 'printf rewritten' } });
  assert.equal(rewritten.effects[0].kind, 'hook');
  assert.deepEqual(rewritten.effects[0].plugin, second.reference);
  assert.deepEqual(rewritten.effects[0].call, { id: initial.id, name: initial.name, arguments: { command: 'printf rewritten' } });
  const launched = await f.hook(rewritten.effects[0]);
  assert.equal(launched.reply.ok, true);
  const tool = launched.effects.find(effect => effect.kind === 'tool');
  assert.deepEqual(tool.call.arguments, { command: 'printf rewritten' });
  const page = await f.read();
  assert.deepEqual(page.messages.find(message => message.role === 'function_call').content.arguments, initial.arguments);
  const records = page.messages.filter(message => message.role === 'hook_record');
  assert.deepEqual(records.map(message => message.plugin), [first.reference, second.reference]);
  assert.deepEqual(records.map(message => message.task_id), [0, 0]);
  const completion = await f.input({ kind: 'tool', task_id: 0, ticket: tool.ticket, value: 'finished', error: false });
  assert.equal(completion.reply.ok, true);
  assert.equal((await f.read()).messages.find(message => message.role === 'function_output').content, 'finished');
});

test('internal fork uses rewritten arguments and inherited calls acquire their own task-bound certificates', async t => {
  const f = await fixture(t);
  const created = await f.create();
  let result = await f.model(created.effects[0], [call('fork_task', { child_count: 1 }, 'branch'), call('read_task', { task_id: 0 }, 'inherited')]);
  result = await f.hook(result.effects[0], { decision: 'rewrite', arguments: { child_count: 2, messages: ['one', 'two'] } });
  result = await f.hook(result.effects[0]);
  assert.equal(result.reply.ok, true);
  const gates = result.effects.filter(effect => effect.kind === 'hook');
  assert.deepEqual(gates.map(effect => effect.task_id), [0, 1, 2]);
  assert.ok(gates.every(effect => effect.call.id === 'inherited' && effect.plugin.name === 'first'));
  for (const gate of gates) {
    const next = await f.hook(gate);
    const secondGate = next.effects.find(effect => effect.kind === 'hook' && effect.task_id === gate.task_id);
    assert.equal(secondGate.plugin.name, 'second');
    await f.hook(secondGate);
    const page = await f.read(gate.task_id);
    assert.equal(page.messages.filter(message => message.role === 'hook_record' && message.task_id === gate.task_id && message.call_id === 'inherited').length, 2);
  }
  const parent = await f.read();
  assert.equal(parent.messages.find(message => message.role === 'function_output' && message.call_id === 'branch').content, 0);
  assert.equal((await f.read(1)).messages.find(message => message.role === 'function_output' && message.call_id === 'branch').content, 1);
});

test('post-hook schema validation rejects invalid rewrites and the completion wire cannot retarget a call', async t => {
  const f = await fixture(t);
  const created = await f.create();
  let gate = (await f.model(created.effects[0], [call('bash', { command: 'printf original' })])).effects[0];
  const before = await f.read();
  for (const outcome of [
    { decision: 'allow', name: 'fork_task' }, { decision: 'rewrite', arguments: [] },
    { decision: 'rewrite', arguments: { command: 'true' }, call_id: 'different' },
    { decision: 'allow', plugin: second.reference }, { decision: 'unknown' }, { decision: 'deny', reason: '' },
  ]) {
    const invalid = await f.hook(gate, outcome);
    assert.equal(invalid.reply.ok, false);
    assert.equal(invalid.durable, false);
    assert.deepEqual(invalid.effects, []);
    assert.deepEqual(await f.read(), before);
  }
  gate = (await f.hook(gate, { decision: 'rewrite', arguments: { command: 123 } })).effects[0];
  const rejected = await f.hook(gate);
  assert.equal(rejected.effects.some(effect => effect.kind === 'tool'), false);
  assert.equal((await f.read()).messages.find(message => message.role === 'function_output').content.error.code, 'invalid_arguments');
});

test('stale and duplicate hook completions carry no authority after interruption or consumption', async t => {
  const f = await fixture(t);
  const created = await f.create();
  const gate = (await f.model(created.effects[0], [call('bash', { command: 'true' })])).effects[0];
  const secondGate = (await f.hook(gate)).effects[0];
  assert.equal((await f.hook(gate, { decision: 'rewrite', arguments: { command: 'false' } })).reply.result.accepted, false);
  const interrupted = await f.command({ op: 'interrupt', task_id: 0 });
  assert.ok(interrupted.effects.some(effect => effect.kind === 'cancel'));
  const before = await f.read();
  const late = await f.hook(secondGate);
  assert.equal(late.reply.result.accepted, false);
  assert.deepEqual(late.effects, []);
  assert.deepEqual(await f.read(), before);
  assert.equal(before.task.phase, 'idle');
  assert.equal(before.messages.find(message => message.role === 'function_output').content.error.code, 'hook_cancelled');
});

test('recovery retains completed grants, never repeats an issued callback, and freezing suspends dispatch only', async t => {
  const f = await fixture(t);
  const created = await f.create();
  const gate = (await f.model(created.effects[0], [call('bash', { command: 'true' })])).effects[0];
  await f.command({ op: 'freeze', task_id: 0 });
  assert.deepEqual((await f.hook(gate)).effects, []);
  assert.equal((await f.read()).task.phase, 'ready');
  assert.deepEqual((await f.input({ kind: 'recover' })).effects, []);
  const resumed = await f.command({ op: 'unfreeze', task_id: 0 });
  assert.equal(resumed.effects[0].plugin.name, 'second', 'a committed first grant is not requested again');
  const recovered = await f.input({ kind: 'recover' });
  assert.equal(recovered.effects.some(effect => ['hook', 'tool'].includes(effect.kind)), false);
  assert.equal((await f.hook(resumed.effects[0])).reply.result.accepted, false);
  const records = (await f.read()).messages.filter(message => message.role === 'hook_record');
  assert.deepEqual(records.map(record => record.content.decision), ['allow', 'failed']);
});

test('independent operation completion cannot overwrite a pending authorization phase', async t => {
  const f = await fixture(t);
  const created = await f.create();
  let gate = (await f.model(created.effects[0], [call('bash', { command: 'slow' }, 'a'), call('bash', { command: 'later' }, 'b')])).effects[0];
  gate = (await f.hook(gate)).effects[0];
  const launched = await f.hook(gate);
  const tool = launched.effects.find(effect => effect.kind === 'tool');
  const next = launched.effects.find(effect => effect.kind === 'hook');
  assert.equal(next.call.id, 'b');
  const finished = await f.input({ kind: 'tool', task_id: 0, ticket: tool.ticket, value: 'done', error: false });
  assert.deepEqual(finished.effects, []);
  assert.equal((await f.read()).task.phase, 'hook_pending');
  const resumed = await f.hook(next);
  assert.equal(resumed.effects[0].plugin.name, 'second');
  assert.equal(resumed.effects[0].call.id, 'b');
});

test('frozen plugin revisions fail closed after live configuration changes', async t => {
  const f = await fixture(t);
  const created = await f.create();
  await f.input({ ...f.environment, plugins: [plugin('first', '2'), second], tools: [{ ...addedTool, plugin: { name: 'first', revision: '2' } }, remoteTool] });
  const refused = await f.model(created.effects[0], [call('bash', { command: 'true' })]);
  assert.equal(refused.effects.some(effect => ['hook', 'tool'].includes(effect.kind)), false);
  assert.equal((await f.read()).messages.find(message => message.role === 'function_output').content.error.code, 'hook_unavailable');
  for (const plugins of [
    [first, first], [{ ...first, events: ['not_a_native_event'] }], [{ ...first, before_tool: 'yes' }],
    [{ ...first, reference: { name: 'first', revision: '' } }],
  ]) {
    const invalid = await f.input({ ...f.environment, plugins });
    assert.equal(invalid.reply.ok, false);
    assert.deepEqual(invalid.effects, []);
  }
});

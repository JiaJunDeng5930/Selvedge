import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';

const notices = decision => decision.effects.filter(effect => effect.kind === 'plugin_events').flatMap(effect => effect.events);
const call = (name, id, arguments_) => ({ type: 'call', id, name, arguments: arguments_ });

async function fixture(t, events) {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const description = await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = value => input({ kind: 'command', command: value });
  const configured = await input({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'echo', name: 'echo' }], tools: [],
    plugins: [{ reference: { name: 'observer', revision: '1' }, before_tool: false, events: events ?? description.plugins.events }], max_fork: 4, max_descendants: 64 });
  assert.equal(configured.reply.ok, true);
  const create = () => command({ op: 'create', profile: 'fixture', message: 'Pure event tests; no external effects are executed' });
  const model = (effect, items) => input({ kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true, items });
  return { input, command, create, model, configured };
}

test('event types and frozen recipients are native; queries and stale completions produce no fabricated occurrences', async t => {
  const f = await fixture(t, ['task_created', 'model_completed']);
  assert.deepEqual(notices(f.configured), [], 'unsubscribed configuration is not sent');
  const created = await f.create();
  const born = notices(created);
  assert.equal(born.length, 1);
  assert.equal(born[0].type, 'task_created');
  assert.deepEqual(born[0].recipients, [{ name: 'observer', revision: '1' }]);
  for (const command of [{ op: 'read', task_id: 0 }, { op: 'list' }, { op: 'describe' }]) {
    assert.deepEqual((await f.command(command)).effects, []);
  }
  assert.deepEqual((await f.input({ kind: 'ui', state: null, event: { type: 'refresh' } })).effects, []);
  const effect = created.effects.find(effect => effect.kind === 'model');
  const settled = await f.model(effect, [{ type: 'text', text: 'done' }]);
  assert.deepEqual(notices(settled).map(event => event.type), ['model_completed']);
  const repeated = await f.model(effect, [{ type: 'text', text: 'late' }]);
  assert.equal(repeated.reply.result.accepted, false);
  assert.deepEqual(notices(repeated), []);
});

test('fork birth markers preserve public return values while excluding inherited occurrences from child events', async t => {
  const f = await fixture(t);
  const created = await f.create();
  const first = await f.model(created.effects.find(effect => effect.kind === 'model'), [call('read_task', 'old-call', { task_id: 0 })]);
  assert.equal(notices(first).filter(event => event.type === 'tool_completed' && event.payload.call_id === 'old-call').length, 1);
  const forked = await f.model(first.effects.find(effect => effect.kind === 'model'), [call('fork_task', 'birth', { child_count: 2, messages: ['one', 'two'] })]);
  assert.equal(forked.reply.ok, true);
  const events = notices(forked);
  assert.deepEqual(events.filter(event => event.type === 'task_created').map(event => event.task_id), [1, 2]);
  assert.equal(events.some(event => event.payload?.call_id === 'old-call'), false);
  assert.equal(events.filter(event => event.type === 'tool_requested').length, 1, 'inherited accepted calls are not new model requests');
  for (const task_id of [1, 2]) {
    const returns = events.filter(event => event.task_id === task_id && event.type === 'tool_completed');
    assert.equal(returns.length, 1);
    assert.equal(returns[0].payload.origin, 'fork_return');
    assert.equal(returns[0].payload.value, task_id);
    const page = (await f.command({ op: 'read', task_id })).reply.result;
    assert.equal(page.messages.find(message => message.role === 'function_output' && message.call_id === 'birth').content, task_id);
  }
});

test('running announcements are not completions; cancellation and genuine running-shaped results are', async t => {
  const f = await fixture(t);
  const created = await f.create();
  const launch = await f.model(created.effects.find(effect => effect.kind === 'model'), [call('bash', 'slow', { command: 'no actual process is invoked by this test' })]);
  const operation = launch.effects.find(effect => effect.kind === 'tool');
  assert.equal(notices(launch).filter(event => event.type === 'tool_dispatched').length, 1);
  assert.equal(notices(launch).some(event => event.type === 'tool_completed'), false);
  const continued = await f.command({ op: 'send', task_id: 0, message: 'Continue independent work' });
  assert.equal(notices(continued).some(event => event.type === 'tool_completed'), false);
  const nextModel = continued.effects.find(effect => effect.kind === 'model');
  assert.ok(nextModel, 'running outputs are published to the next model snapshot');
  const done = await f.input({ kind: 'tool', task_id: 0, ticket: operation.ticket, value: { status: 'running', text: 'literal final value' }, error: false });
  const completed = notices(done).filter(event => event.type === 'tool_completed');
  assert.equal(completed.length, 1);
  assert.deepEqual(completed[0].payload.value, { status: 'running', text: 'literal final value' });
  assert.deepEqual(notices(await f.input({ kind: 'tool', task_id: 0, ticket: operation.ticket, value: 'late', error: false })), []);
  const launchedAgain = await f.model(nextModel, [call('bash', 'cancelled', { command: 'still no process' })]);
  const running = launchedAgain.effects.find(effect => effect.kind === 'tool');
  const cancelled = await f.command({ op: 'cancel_operation', task_id: 0, operation_id: running.ticket });
  const cancellation = notices(cancelled).filter(event => event.type === 'tool_completed');
  assert.equal(cancellation.length, 1);
  assert.equal(cancellation[0].payload.call_id, 'cancelled');
  assert.equal(cancellation[0].payload.error, true);
});

test('large observation payloads are explicitly omitted with a durable history cursor, without rejecting execution', async t => {
  const f = await fixture(t);
  const created = await f.create();
  const launched = await f.model(created.effects.find(effect => effect.kind === 'model'), [call('bash', 'large', { command: 'not executed' })]);
  const operation = launched.effects.find(effect => effect.kind === 'tool');
  const value = '数据'.repeat(10_000);
  const settled = await f.input({ kind: 'tool', task_id: 0, ticket: operation.ticket, value, error: false });
  assert.equal(settled.reply.ok, true);
  const event = notices(settled).find(event => event.type === 'tool_completed');
  assert.equal(event.payload, null);
  assert.equal(event.payload_omitted, true);
  assert.equal(event.task_id, 0);
  assert.ok(event.cursor > 0);
  const page = (await f.command({ op: 'read', task_id: 0, after: event.cursor - 1, limit: 1 })).reply.result;
  assert.equal(page.messages[0].content, value);
});

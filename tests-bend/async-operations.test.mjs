import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';

const call = (id, command = 'sleep 60') => ({ type: 'call', id, name: 'bash', arguments: { command } });
const answer = [{ type: 'text', text: 'done' }];

async function harness(t) {
  const kernel = new Kernel({ timeout: 10_000 });
  t.after(() => kernel.close());
  await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = body => input({ kind: 'command', command: body });
  const configured = await input({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture' }],
    tools: [], max_fork: 4, max_descendants: 8 });
  assert.equal(configured.reply.ok, true);
  const created = await command({ op: 'create', profile: 'fixture', message: 'start' });
  assert.equal(created.reply.ok, true);
  const model = (effect, items = answer) => input({ kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true, items });
  const tool = (effect, value = 'done') => input({ kind: 'tool', task_id: effect.task_id, ticket: effect.ticket, value, error: false });
  const page = async (task_id = 0) => (await command({ op: 'read', task_id })).reply.result;
  return { kernel, input, command, model, tool, page, initial: created.effects[0] };
}

test('independent calls run together; partial results wake a model and raced completions are not lost or duplicated', async t => {
  const h = await harness(t);
  const launched = await h.model(h.initial, [call('left'), call('right')]);
  assert.equal(launched.reply.ok, true);
  assert.deepEqual(launched.effects.map(effect => effect.kind), ['tool', 'tool']);
  assert.deepEqual((await h.page()).task.operations.map(op => op.operation_id), launched.effects.map(effect => effect.ticket));
  assert.equal((await h.page()).task.phase, 'idle', 'quiet in-flight operations do not poll the model');

  const partial = await h.tool(launched.effects[0], 'left result');
  assert.equal(partial.reply.ok, true);
  assert.equal(partial.effects.length, 1);
  const request = partial.effects[0];
  assert.equal(request.kind, 'model');
  const outputs = request.history.filter(message => message.role === 'function_output');
  assert.equal(outputs.find(message => message.call_id === 'left').content, 'left result');
  assert.equal(outputs.find(message => message.call_id === 'right').content.status, 'running');
  assert.equal((await h.page()).task.operations[0].announced, true);

  const raced = await h.tool(launched.effects[1], 'right result');
  assert.equal(raced.reply.result.accepted, true);
  assert.deepEqual(raced.effects, [], 'completion must not create a second concurrent model request');
  const before = await h.page();
  const duplicate = await h.tool(launched.effects[1], 'duplicate must disappear');
  assert.equal(duplicate.reply.result.accepted, false);
  assert.deepEqual(await h.page(), before);
  const continued = await h.model(request);
  assert.deepEqual(continued.effects.map(effect => effect.kind), ['model']);
  const asynchronous = continued.effects[0].history.filter(message => message.role === 'operation_result');
  assert.deepEqual(asynchronous.map(message => [message.call_id, message.content]), [['right', 'right result']]);
  assert.equal(continued.effects[0].history.filter(message => message.role === 'function_output' && message.call_id === 'right').length, 1);
  assert.deepEqual((await h.model(continued.effects[0])).effects, []);
  assert.deepEqual((await h.page()).task.operations, []);
});

test('steering replaces only model work, preserves live operations and queued follow-ups, and rejects stale replies', async t => {
  const h = await harness(t);
  const launched = await h.model(h.initial, [call('left'), call('right')]);
  const working = await h.command({ op: 'send', task_id: 0, message: 'independent work' });
  const previous = working.effects.find(effect => effect.kind === 'model');
  await h.command({ op: 'send', task_id: 0, message: 'queued follow-up' });
  const operations = (await h.page()).task.operations;
  const steered = await h.command({ op: 'steer', task_id: 0, message: 'higher priority' });
  assert.equal(steered.reply.ok, true);
  assert.deepEqual(steered.effects.filter(effect => effect.kind.startsWith('cancel')),
    [{ kind: 'cancel_ticket', task_id: 0, ticket: previous.ticket }]);
  assert.deepEqual((await h.page()).task.operations, operations);
  assert.equal((await h.page()).task.queued, 1);
  const current = steered.effects.find(effect => effect.kind === 'model');
  assert.equal(current.history.at(-1).content, 'higher priority');
  const before = await h.page();
  assert.equal((await h.model(previous, [{ type: 'text', text: 'stale' }])).reply.result.accepted, false);
  assert.deepEqual(await h.page(), before);
  const followed = await h.model(current);
  assert.equal(followed.effects[0].history.filter(message => message.role === 'user').at(-1).content, 'queued follow-up');
  assert.deepEqual((await h.page()).task.operations.map(op => op.operation_id), launched.effects.map(effect => effect.ticket));
});

test('cancelling one operation preserves other operation and model authority; late completion is ignored', async t => {
  const h = await harness(t);
  const launched = await h.model(h.initial, [call('left'), call('right')]);
  const request = (await h.command({ op: 'send', task_id: 0, message: 'continue independently' })).effects[0];
  const cancelled = await h.command({ op: 'cancel_operation', task_id: 0, operation_id: launched.effects[0].ticket });
  assert.equal(cancelled.reply.ok, true);
  assert.deepEqual(cancelled.effects, [{ kind: 'cancel_ticket', task_id: 0, ticket: launched.effects[0].ticket }]);
  assert.equal((await h.page()).task.phase, 'model_pending');
  assert.deepEqual((await h.page()).task.operations.map(op => op.operation_id), [launched.effects[1].ticket]);
  assert.equal((await h.tool(launched.effects[0])).reply.result.accepted, false);
  assert.equal((await h.tool(launched.effects[1])).reply.result.accepted, true);
  const continued = await h.model(request);
  const results = continued.effects[0].history.filter(message => message.role === 'operation_result');
  assert.equal(results.find(message => message.call_id === 'left').content.error.code, 'cancelled');
  assert.equal(results.find(message => message.call_id === 'right').content, 'done');
});

test('same-commit cancellation withdraws an external intent before the host could execute it', async t => {
  const h = await harness(t);
  const ticket = h.initial.ticket + 1;
  const result = await h.model(h.initial, [call('must-not-start'),
    { type: 'call', id: 'cancel-before-dispatch', name: 'cancel_operation', arguments: { operation_id: ticket } }]);
  assert.equal(result.reply.ok, true);
  assert.equal(result.effects.some(effect => effect.kind === 'tool'), false);
  assert.ok(result.effects.some(effect => effect.kind === 'cancel_ticket' && effect.ticket === ticket));
  assert.deepEqual((await h.page()).task.operations, []);
  const messages = (await h.page()).messages;
  assert.equal(messages.find(message => message.call_id === 'must-not-start').content.error.code, 'cancelled');
  assert.equal(messages.find(message => message.call_id === 'cancel-before-dispatch').is_error, false);
});

test('fork copies context, never operation rights; children receive explicit nonownership results', async t => {
  const h = await harness(t);
  const launched = await h.model(h.initial, [call('left'), call('right')]);
  const forked = await h.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['child objective'] });
  assert.equal(forked.reply.ok, true);
  assert.deepEqual(forked.reply.result.children, [1]);
  assert.equal(forked.effects.some(effect => effect.kind === 'tool'), false);
  const parent = await h.page();
  const child = await h.page(1);
  assert.deepEqual(parent.task.operations.map(op => op.operation_id), launched.effects.map(effect => effect.ticket));
  assert.deepEqual(child.task.operations, []);
  for (const id of ['left', 'right']) {
    assert.equal(child.messages.find(message => message.role === 'function_output' && message.call_id === id).content.error.code,
      'inherited_operation_not_owned');
  }
});

test('recovery closes every unknown operation once and never repeats shell effects', async t => {
  const h = await harness(t);
  const launched = await h.model(h.initial, [call('left'), call('right')]);
  await h.command({ op: 'send', task_id: 0, message: 'independent input' });
  const recovered = await h.input({ kind: 'recover' });
  assert.equal(recovered.reply.ok, true);
  assert.equal(recovered.effects.some(effect => effect.kind === 'tool'), false);
  const page = await h.page();
  assert.deepEqual(page.task.operations, []);
  assert.equal(page.messages.filter(message => message.role === 'operation_result' && message.content.error?.code === 'outcome_unknown').length, 2);
  for (const effect of launched.effects) assert.equal((await h.tool(effect)).reply.result.accepted, false);
  await h.input({ kind: 'recover' });
  assert.equal((await h.page()).messages.filter(message => message.role === 'operation_result').length, 2);
});

test('context recovery waits for live results and a cancelled summary cannot replace newer user input', async t => {
  const h = await harness(t);
  const launched = await h.model(h.initial, [call('left'), call('right')]);
  const request = (await h.tool(launched.effects[0])).effects[0];
  const limited = await h.input({ kind: 'model', task_id: 0, ticket: request.ticket, ok: false, failure_kind: 'context_limit', message: 'too large' });
  assert.equal(limited.reply.ok, true);
  assert.deepEqual(limited.effects, []);
  assert.equal((await h.page()).task.phase, 'compaction_ready');
  const settled = await h.tool(launched.effects[1], 'result absent from the previous model request');
  assert.deepEqual(settled.effects.map(effect => effect.kind), ['summary']);
  const summary = settled.effects[0];
  assert.equal(summary.history.at(-1).role, 'operation_result');
  const steered = await h.command({ op: 'steer', task_id: 0, message: 'newer input must survive' });
  assert.equal(steered.reply.ok, true);
  assert.ok(steered.effects.some(effect => effect.kind === 'cancel_ticket' && effect.ticket === summary.ticket));
  const before = await h.page();
  assert.equal((await h.model(summary, [{ type: 'text', text: 'stale summary' }])).reply.result.accepted, false);
  assert.deepEqual(await h.page(), before);
});

test('interruption closes accepted but undispatched calls while freeze retains completed operation results', async t => {
  const h = await harness(t);
  await h.command({ op: 'freeze', task_id: 0 });
  const accepted = await h.model(h.initial, [call('not-started-a'), call('not-started-b')]);
  assert.deepEqual(accepted.effects, []);
  await h.command({ op: 'interrupt', task_id: 0 });
  assert.deepEqual((await h.page()).messages.filter(message => message.role === 'function_output').map(message => message.content.error.code),
    ['cancelled_before_execution', 'cancelled_before_execution']);
  const resumed = await h.command({ op: 'send', task_id: 0, message: 'resume' });
  const launched = await h.model(resumed.effects[0], [call('started')]);
  await h.command({ op: 'freeze', task_id: 0 });
  assert.deepEqual((await h.tool(launched.effects[0])).effects, []);
  const unfreeze = await h.command({ op: 'unfreeze', task_id: 0 });
  assert.equal(unfreeze.effects[0].kind, 'model');
  assert.equal(unfreeze.effects[0].history.at(-1).content, 'done');
});

test('per-task operation capacity rejects only excess calls and does not strand their accepted identities', async t => {
  const h = await harness(t);
  const limit = h.kernel.description.limits.operations_per_task;
  const launched = await h.model(h.initial, Array.from({ length: limit + 1 }, (_, index) => call(`operation-${index}`)));
  assert.equal(launched.reply.ok, true);
  assert.equal(launched.effects.filter(effect => effect.kind === 'tool').length, limit);
  const request = launched.effects.find(effect => effect.kind === 'model');
  assert.ok(request);
  const overflow = request.history.find(message => message.role === 'function_output' && message.call_id === `operation-${limit}`);
  assert.equal(overflow.content.error.code, 'operation_limit');
  assert.equal(request.history.filter(message => message.role === 'function_output' && message.content.status === 'running').length, limit);
});

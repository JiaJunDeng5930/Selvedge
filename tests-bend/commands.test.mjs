import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';

async function harness(t, configuration = {}) {
  const kernel = new Kernel({ timeout: 10_000 });
  t.after(() => kernel.close());
  await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = value => input({ kind: 'command', command: value });
  const configured = await input({ kind: 'configure',
    profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model' }],
    tools: [], max_fork: 4, max_descendants: 8, ...configuration });
  assert.equal(configured.reply.ok, true);
  const complete = (task_id, ticket, items = [{ type: 'text', text: 'done' }]) =>
    input({ kind: 'model', task_id, ticket, ok: true, items });
  const page = async id => (await command({ op: 'read', task_id: id })).reply.result;
  const snapshot = async () => {
    const listed = (await command({ op: 'list' })).reply.result;
    const pages = [];
    for (const task of listed.tasks) pages.push(await page(task.id));
    return { listed, pages };
  };
  return { input, command, complete, page, snapshot };
}

test('the command vocabulary has positive operational coverage, including every lifecycle control', async t => {
  const { command, complete, page } = await harness(t);
  const observed = await command({ op: 'describe' });
  assert.equal(observed.durable, false);
  assert.deepEqual(observed.effects, []);
  assert.deepEqual(observed.reply.result.commands.map(x => x.name).sort(),
    ['archive', 'cancel_operation', 'compact', 'create', 'describe', 'fork', 'freeze', 'interrupt', 'list', 'read', 'send', 'steer', 'stop', 'unfreeze']);
  const created = await command({ op: 'create', profile: 'fixture', reasoning: 'high', message: 'original objective' });
  assert.deepEqual(created.reply.result, { task_id: 0 });
  assert.equal(created.effects[0].kind, 'model');
  assert.equal(created.effects[0].model.reasoning, 'high');
  const steered = await command({ op: 'steer', task_id: 0, message: 'prioritize this instruction' });
  assert.equal(steered.reply.ok, true);
  assert.deepEqual(steered.effects[0], { kind: 'cancel_ticket', task_id: 0, ticket: created.effects[0].ticket });
  await command({ op: 'freeze', task_id: 0 });
  await complete(0, steered.effects.find(effect => effect.kind === 'model').ticket);
  assert.equal((await page(0)).task.status, 'frozen');
  const queued = await command({ op: 'send', task_id: 0, message: 'next objective' });
  assert.deepEqual(queued.effects, []);
  const resumed = await command({ op: 'unfreeze', task_id: 0 });
  assert.equal(resumed.effects[0].kind, 'model');
  assert.equal(resumed.effects[0].history.at(-1).content, 'next objective');
  await command({ op: 'stop', task_id: 0 });
  await complete(0, resumed.effects[0].ticket);
  assert.equal((await page(0)).task.status, 'stopped');
  const checkpoint = await command({ op: 'compact', task_id: 0, summary: 'Retain both objectives and the completed answers.' });
  assert.deepEqual(checkpoint.reply.result, { task_id: 0 });
  assert.deepEqual(checkpoint.effects, []);
  assert.equal((await page(0)).messages.at(-1).role, 'context_summary');
  const next = await command({ op: 'send', task_id: 0, message: 'branch next' });
  await complete(0, next.effects[0].ticket);
  const forked = await command({ op: 'fork', task_id: 0, child_count: 1, messages: ['child objective'] });
  assert.deepEqual(forked.reply.result, { children: [1] });
  assert.equal(forked.effects.find(x => x.task_id === 1).history.at(-1).content, 'child objective');
  const launched = await complete(0, forked.effects.find(effect => effect.kind === 'model' && effect.task_id === 0).ticket,
    [{ type: 'call', id: 'cancel-me', name: 'bash', arguments: { command: 'sleep 60' } }]);
  const ticket = launched.effects.find(effect => effect.kind === 'tool').ticket;
  const cancelled = await command({ op: 'cancel_operation', task_id: 0, operation_id: ticket });
  assert.equal(cancelled.reply.ok, true);
  assert.deepEqual(cancelled.reply.result, { task_id: 0, operation_id: ticket });
  assert.ok(cancelled.effects.some(effect => effect.kind === 'cancel_ticket' && effect.ticket === ticket));
  const interrupted = await command({ op: 'interrupt', task_id: 0 });
  assert.deepEqual(interrupted.effects, [{ kind: 'cancel', task_id: 0 }]);
  const archived = await command({ op: 'archive', task_id: 1 });
  assert.deepEqual(archived.effects, [{ kind: 'cancel', task_id: 1 }]);
  const listed = await command({ op: 'list' });
  assert.equal(listed.durable, false);
  assert.deepEqual(listed.reply.result.tasks.map(x => x.status), ['stopped', 'archived']);
});

test('command refusals leave task state, history, identities, and dispatch tickets untouched', async t => {
  const { command, complete, snapshot, page } = await harness(t);
  const created = await command({ op: 'create', profile: 'fixture', message: 'root' });
  await complete(0, created.effects[0].ticket);
  const before = await snapshot();
  const refusals = [
    [{ op: 'create', profile: 'missing', message: 'x' }, 'unknown_profile'],
    [{ op: 'create', profile: 'fixture', message: ' ' }, 'invalid_arguments'],
    [{ op: 'send', task_id: 0, message: ' ' }, 'invalid_arguments'],
    [{ op: 'send', task_id: 999, message: 'x' }, 'task_not_found'],
    [{ op: 'steer', task_id: 999, message: 'x' }, 'task_not_found'],
    [{ op: 'steer', task_id: 0, message: ' ' }, 'invalid_arguments'],
    [{ op: 'cancel_operation', task_id: 0, operation_id: 999 }, 'operation_not_found'],
    [{ op: 'cancel_operation', task_id: 999, operation_id: 0 }, 'task_not_found'],
    [{ op: 'freeze', task_id: 999 }, 'task_not_found'],
    [{ op: 'unfreeze', task_id: 0 }, 'invalid_transition'],
    [{ op: 'fork', task_id: 0, child_count: 5 }, 'resource_limit'],
    [{ op: 'fork', task_id: 0, child_count: 2, messages: ['unaligned'] }, 'resource_limit'],
    [{ op: 'compact', task_id: 0, summary: ' ' }, 'invalid_summary'],
    [{ op: 'read', task_id: 0, after: 999 }, 'invalid_page'],
  ];
  for (const [request, code] of refusals) {
    const refused = await command(request);
    assert.equal(refused.reply.ok, false, JSON.stringify(request));
    assert.equal(refused.reply.error.code, code);
    assert.deepEqual(refused.effects, []);
    assert.deepEqual(await snapshot(), before);
  }
  const forked = await command({ op: 'fork', task_id: 0, child_count: 1 });
  assert.deepEqual(forked.reply.result.children, [1]);
  const recorded = (await page(0)).messages.find(x => x.role === 'function_call');
  assert.equal(recorded.content.id, 'manual-fork-1', 'A rejected fork must not allocate its synthetic call ticket');
  assert.deepEqual(forked.effects.filter(x => x.kind === 'model').map(x => x.ticket), [2, 3]);
});

test('refusing a user command cannot secretly run unrelated ready work; Continue can', { timeout: 15_000 }, async t => {
  const { input, command, complete, page } = await harness(t);
  await command({ op: 'create', profile: 'fixture', message: 'settle a finite internal batch' });
  const pending = await complete(0, 0, Array.from({ length: 260 }, (_, i) => ({
    type: 'call', id: `batch-${i}`, name: 'archive_task', arguments: { task_id: 999 },
  })));
  assert.deepEqual(pending.effects, [{ kind: 'continue' }]);
  const before = (await page(0)).task;
  assert.equal(before.phase, 'ready');
  const refused = await command({ op: 'send', task_id: 999, message: 'must not tick another task' });
  assert.equal(refused.reply.error.code, 'task_not_found');
  assert.deepEqual(refused.effects, []);
  assert.deepEqual((await page(0)).task, before);
  const continued = await input({ kind: 'continue' });
  assert.equal(continued.effects.length, 1);
  assert.equal(continued.effects[0].kind, 'model');
  assert.ok((await page(0)).task.cursor > before.cursor);
});

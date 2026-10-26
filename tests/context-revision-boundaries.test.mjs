import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';

const summaryCancelled = 'Context summary was not sent because the task is frozen or stopped; original history retained';
const echoTool = {
  name: 'mcp__fixture__echo', description: 'Echo fixture',
  schema: { type: 'object', properties: {}, additionalProperties: false },
  remote: 'echo', server: 'fixture',
};

async function packetFixture(t, tools = []) {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  await kernel.initialize();
  const event = async input => {
    const { value } = await kernel.request(input);
    assert.equal(value.reply.ok, true, JSON.stringify(value.reply));
    // Drive durable continuations; each scenario still controls its physical observations.
    const pending = [...value.effects];
    const effects = [];
    for (let index = 0; index < pending.length; index++) {
      const effect = pending[index];
      if (effect.kind === 'continue') {
        const { value: next } = await kernel.request({ kind: 'continue' });
        assert.equal(next.reply.ok, true, JSON.stringify(next.reply));
        pending.push(...next.effects);
      } else effects.push(effect);
    }
    return { ...value, effects };
  };
  await event({ kind: 'configure',
    profiles: [{ key: 'fixture', provider: 'openai', name: 'fixture-model', reasoning_options: null }],
    tools, plugins: [], max_fork: 4, max_descendants: 64,
    instructions: { configured: '', global: null },
  });
  const command = command => event({ kind: 'command', command });
  const read = async task_id => (await command({ op: 'read', task_id })).reply.result;
  const observe = (effect, outcome = { ok: true, observations: [] }) => event({
    kind: 'context_observed', task_id: effect.task_id, ticket: effect.ticket, ...outcome,
  });
  return { event, command, read, observe };
}

function effect(packet, kind) {
  const matches = packet.effects.filter(value => value.kind === kind);
  assert.equal(matches.length, 1, `Expected one ${kind} effect: ${JSON.stringify(packet.effects)}`);
  return matches[0];
}

function noIO(packet) {
  assert.deepEqual(packet.effects, []);
}

test('the production packet rejects an unrelated Context ticket and rereads after another tool receipt changes history', async t => {
  const fixture = await packetFixture(t, [echoTool]);
  const created = await fixture.command({ op: 'create', profile: 'fixture', message: 'Run both independent echoes.' });
  const task_id = created.reply.result.task_id;
  const initial = effect(created, 'observe_context');
  const before = await fixture.read(task_id);
  const unrelated = await fixture.observe({ ...initial, ticket: initial.ticket + 1000 });
  assert.equal(unrelated.reply.result.ignored, true);
  noIO(unrelated);
  assert.deepEqual(await fixture.read(task_id), before);

  const model = effect(await fixture.observe(initial), 'model');
  const calls = await fixture.event({ kind: 'model', task_id, ticket: model.ticket, ok: true, items: [
    { type: 'call', id: 'echo-a', name: echoTool.name, arguments_json: '{}' },
    { type: 'call', id: 'echo-b', name: echoTool.name, arguments_json: '{}' },
  ] });
  const tools = calls.effects.filter(value => value.kind === 'tool');
  assert.equal(tools.length, 2);
  const receipt = (ticket, text) => fixture.event({ kind: 'tool', task_id, ticket, value: { text }, error: false });
  const pending = effect(await receipt(tools[0].ticket, 'First concurrent receipt.'), 'observe_context');
  noIO(await receipt(tools[1].ticket, 'Second concurrent receipt.'));
  assert.ok(JSON.stringify((await fixture.read(task_id)).messages).includes('Second concurrent receipt.'));

  // The second real tool result arrives while the first result's Context IO is outstanding.
  const staleFailure = 'STALE-CONTEXT-FAILURE-MUST-NOT-BE-APPLIED';
  const retried = await fixture.observe(pending, { ok: false, message: staleFailure });
  const fresh = effect(retried, 'observe_context');
  assert.notEqual(fresh.ticket, pending.ticket);
  assert.equal(retried.effects.length, 1);
  assert.equal(JSON.stringify((await fixture.read(task_id)).messages).includes(staleFailure), false);
  const nextModel = effect(await fixture.observe(fresh), 'model');
  const history = JSON.stringify(nextModel.history);
  assert.ok(history.includes('First concurrent receipt.'));
  assert.ok(history.includes('Second concurrent receipt.'));
  assert.equal(history.includes(staleFailure), false);
});

test('a frozen or stopped generation waits for a fresh Context observation when explicitly resumed', async t => {
  for (const suspension of ['freeze', 'stop']) await t.test(suspension, async t => {
    const fixture = await packetFixture(t);
    const created = await fixture.command({ op: 'create', profile: 'fixture', message: 'Observe before responding.' });
    const task_id = created.reply.result.task_id;
    const pending = effect(created, 'observe_context');
    await fixture.command({ op: suspension, task_id });
    noIO(await fixture.observe(pending));
    noIO(await fixture.event({ kind: 'continue' }));
    const resumed = await fixture.command(suspension === 'freeze'
      ? { op: 'unfreeze', task_id }
      : { op: 'send', task_id, message: 'Resume the ordinary task.' });
    const fresh = effect(resumed, 'observe_context');
    assert.notEqual(fresh.ticket, pending.ticket);
    assert.equal(resumed.effects.some(value => value.kind === 'model'), false);
    effect(await fixture.observe(fresh), 'model');
  });
});

test('a frozen or stopped manual summary is cancelled and cannot restart after resumption', async t => {
  for (const suspension of ['freeze', 'stop']) await t.test(suspension, async t => {
    const fixture = await packetFixture(t);
    const created = await fixture.command({ op: 'create_idle', profile: 'fixture' });
    const task_id = created.reply.result.task_id;
    const pending = effect(await fixture.command({ op: 'compact', task_id }), 'observe_context');
    await fixture.command({ op: suspension, task_id });
    const cancelled = await fixture.observe(pending);
    assert.deepEqual(cancelled.effects, [{ kind: 'compaction_cancel', task_id, ticket: pending.ticket }]);
    const page = await fixture.read(task_id);
    assert.equal(page.task.phase, 'idle');
    assert.ok(JSON.stringify(page.messages).includes(summaryCancelled));
    noIO(await fixture.event({ kind: 'continue' }));
    if (suspension === 'freeze') {
      noIO(await fixture.command({ op: 'unfreeze', task_id }));
      noIO(await fixture.event({ kind: 'continue' }));
    }
    const resumed = await fixture.command({ op: 'send', task_id, message: 'Start ordinary work after the cancelled summary.' });
    assert.equal(resumed.effects.some(value => value.kind === 'context_scope'), false);
    const fresh = effect(resumed, 'observe_context');
    const generated = await fixture.observe(fresh);
    assert.equal(generated.effects.some(value => value.kind === 'context_scope'), false);
    const model = effect(generated, 'model');
    assert.ok(JSON.stringify(model.history).includes('Start ordinary work after the cancelled summary.'));
  });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';

async function kernel(t) {
  const k = new Kernel({ timeout: 5000 });
  t.after(() => k.close());
  await k.initialize();
  const send = async input => (await k.request(input)).value;
  const command = command => send({ kind: 'command', command });
  const configured = await send({ kind: 'configure', profiles: [
    { key: 'worker', provider: 'responses', name: 'worker-model' },
    { key: 'reviewer', provider: 'responses', name: 'review-model' },
  ], tools: [], max_fork: 4, max_descendants: 8 });
  assert.equal(configured.reply.ok, true);
  const page = async (id = 0) => (await command({ op: 'read', task_id: id })).reply.result;
  return { send, command, page };
}

const done = effect => ({ kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true,
  items: [{ type: 'text', text: 'Waiting for the result.' }] });
const escalation = { command: 'printf approved > /outside-workspace', sandbox_permissions: 'require_escalated',
  justification: 'Write the exact output file requested by the user.' };

async function request(t) {
  const k = await kernel(t);
  const created = await k.command({ op: 'create', profile: 'worker', message: 'Write this specific output.', settings: {
    workspace: { roots: [] }, approval: { mode: 'approval-for-me', reviewer_profile: 'reviewer' },
  } });
  assert.equal(created.reply.ok, true);
  const initial = created.effects.find(effect => effect.kind === 'model');
  const decision = await k.send({ kind: 'model', task_id: 0, ticket: initial.ticket, ok: true,
    items: [{ type: 'call', id: 'bash-one', name: 'bash', arguments: escalation }] });
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  for (const effect of decision.effects.filter(effect => effect.kind === 'model')) {
    assert.equal((await k.send(done(effect))).reply.ok, true);
  }
  return { ...k, operation: (await k.page()).task.operations[0] };
}

test('Bend-generated JavaScript rejects malformed pending approval outcomes', async t => {
  const k = await request(t);
  const id = k.operation.operation_id;
  for (const outcome of [
    { decision: 'allow', reason: 'yes', command: 'a different command' },
    { decision: 'allow' }, { decision: 'yes', reason: 'not a decision' },
    { decision: 'allow', reason: 'x'.repeat(2049) },
  ]) {
    const invalid = await k.send({ kind: 'approval', task_id: 0, ticket: id, outcome });
    assert.equal(invalid.reply.ok, false, JSON.stringify(outcome));
    assert.deepEqual(invalid.effects, []);
  }
});


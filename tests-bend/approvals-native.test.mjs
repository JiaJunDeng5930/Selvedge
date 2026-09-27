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

async function request(t, mode = 'ask-for-approval', args = escalation) {
  const k = await kernel(t);
  const created = await k.command({ op: 'create', profile: 'worker', message: 'Write this specific output.', settings: {
    workspace: { roots: [] }, approval: { mode, ...(mode === 'approval-for-me' ? { reviewer_profile: 'reviewer' } : {}) },
  } });
  assert.equal(created.reply.ok, true);
  const initial = created.effects.find(effect => effect.kind === 'model');
  const decision = await k.send({ kind: 'model', task_id: 0, ticket: initial.ticket, ok: true,
    items: [{ type: 'call', id: 'bash-one', name: 'bash', arguments: args }] });
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  for (const effect of decision.effects.filter(effect => effect.kind === 'model')) {
    assert.equal((await k.send(done(effect))).reply.ok, true);
  }
  return { ...k, decision, operation: (await k.page()).task.operations[0] };
}

test('human review binds the complete command; a frozen grant cannot execute or be used as a tool callback', async t => {
  const k = await request(t);
  const id = k.operation.operation_id;
  assert.equal(k.operation.status, 'awaiting_approval');
  assert.deepEqual(k.operation.arguments, escalation);
  assert.deepEqual(k.operation.reviewer, { kind: 'human' });
  assert.ok(!k.decision.effects.some(effect => ['tool', 'approval'].includes(effect.kind)));
  const before = (await k.page()).task.settings;
  assert.equal((await k.command({ op: 'freeze', task_id: 0 })).reply.ok, true);
  const grant = await k.command({ op: 'review_approval', task_id: 0, operation_id: id, decision: 'allow', reason: 'This file is intended.' });
  assert.equal(grant.reply.ok, true, JSON.stringify(grant.reply));
  assert.deepEqual(grant.effects, []);
  assert.equal((await k.page()).task.operations[0].status, 'approved_waiting_to_run');
  assert.deepEqual((await k.page()).task.settings, before);
  const premature = await k.send({ kind: 'tool', task_id: 0, ticket: id, value: 'forged execution', error: false });
  assert.equal(premature.reply.result.accepted, false);
  assert.equal((await k.command({ op: 'review_approval', task_id: 0, operation_id: id, decision: 'allow' })).reply.ok, false);
  const resumed = await k.command({ op: 'unfreeze', task_id: 0 });
  assert.equal(resumed.reply.ok, true, JSON.stringify(resumed.reply));
  const execution = resumed.effects.find(effect => effect.kind === 'tool');
  assert.ok(execution, JSON.stringify(resumed));
  assert.ok(execution.ticket > id);
  assert.equal(execution.execution.access, 'unrestricted');
  assert.deepEqual(execution.call.arguments, escalation);
  const late = await k.send({ kind: 'approval', task_id: 0, ticket: id, outcome: { decision: 'allow', reason: 'stale' } });
  assert.equal(late.reply.result.accepted, false);
  assert.equal((await k.send({ kind: 'tool', task_id: 0, ticket: execution.ticket, value: 'real result', error: false })).reply.ok, true);
  const page = await k.page();
  assert.equal(page.task.operations.length, 0);
  assert.equal(page.messages.filter(message => message.role === 'approval_record').length, 1);
  assert.deepEqual(page.messages.find(message => message.role === 'function_output' && message.call_id === 'bash-one'),
    { role: 'function_output', call_id: 'bash-one', content: 'real result', is_error: false });
});

test('model approval is one independent effect, cannot be supplied by the human-command route, and rejects authority-shaped payloads', async t => {
  const k = await request(t, 'approval-for-me');
  const id = k.operation.operation_id;
  const reviews = k.decision.effects.filter(effect => effect.kind === 'approval');
  assert.equal(reviews.length, 1);
  assert.equal(reviews[0].model.profile, 'reviewer');
  assert.equal(reviews[0].tools, undefined);
  assert.deepEqual(reviews[0].user_requests, ['Write this specific output.']);
  assert.equal((await k.command({ op: 'list' })).reply.result.tasks.length, 1);
  assert.equal((await k.command({ op: 'review_approval', task_id: 0, operation_id: id, decision: 'allow' })).reply.ok, false);
  for (const outcome of [
    { decision: 'allow', reason: 'yes', command: 'a different command' },
    { decision: 'allow' }, { decision: 'yes', reason: 'not a decision' },
    { decision: 'allow', reason: 'x'.repeat(2049) },
  ]) {
    const invalid = await k.send({ kind: 'approval', task_id: 0, ticket: id, outcome });
    assert.equal(invalid.reply.ok, false, JSON.stringify(outcome));
    assert.deepEqual(invalid.effects, []);
  }
  const reviewed = await k.send({ kind: 'approval', task_id: 0, ticket: id, outcome: { decision: 'allow', reason: 'One narrow requested file write.' } });
  assert.equal(reviewed.reply.ok, true, JSON.stringify(reviewed.reply));
  assert.equal(reviewed.effects.filter(effect => effect.kind === 'tool').length, 1);
  assert.equal((await k.command({ op: 'list' })).reply.result.tasks.length, 1);
  const repeated = await k.send({ kind: 'approval', task_id: 0, ticket: id, outcome: { decision: 'allow', reason: 'again' } });
  assert.equal(repeated.reply.result.accepted, false);
  assert.deepEqual(repeated.effects, []);
});

test('denial, cancellation and recovery never execute a pending approval', async t => {
  for (const action of ['deny', 'cancel', 'recover', 'archive']) {
    await t.test(action, async t => {
      const k = await request(t);
      const id = k.operation.operation_id;
      const result = action === 'recover' ? await k.send({ kind: 'recover' }) : await k.command(
        action === 'deny' ? { op: 'review_approval', task_id: 0, operation_id: id, decision: 'deny', reason: 'Not authorized.' } :
        action === 'cancel' ? { op: 'cancel_operation', task_id: 0, operation_id: id } : { op: 'archive', task_id: 0 });
      assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
      assert.ok(!result.effects.some(effect => effect.kind === 'tool'));
      assert.equal((await k.page()).task.operations.length, 0);
      const stale = await k.command({ op: 'review_approval', task_id: 0, operation_id: id, decision: 'allow' });
      assert.equal(stale.reply.ok, false);
      assert.ok(!stale.effects.some(effect => effect.kind === 'tool'));
      if (action === 'recover') assert.ok(JSON.stringify(await k.page()).includes('approval_interrupted'));
    });
  }
});

test('full access needs no review, default access stays sandboxed, and missing escalation justification is rejected', async t => {
  const full = await request(t, 'full-access');
  assert.equal(full.decision.effects.find(effect => effect.kind === 'tool').execution.access, 'unrestricted');
  assert.ok(!full.decision.effects.some(effect => effect.kind === 'approval'));
  const ordinary = await request(t, 'approval-for-me', { command: 'pwd' });
  assert.equal(ordinary.decision.effects.find(effect => effect.kind === 'tool').execution.access, 'sandboxed');
  assert.ok(!ordinary.decision.effects.some(effect => effect.kind === 'approval'));
  const invalid = await request(t, 'ask-for-approval', { command: 'pwd', sandbox_permissions: 'require_escalated' });
  assert.equal(invalid.operation, undefined);
  assert.ok(!invalid.decision.effects.some(effect => ['approval', 'tool'].includes(effect.kind)));
});

test('project defaults are snapshots and an explicit user fork cannot transfer an outstanding approval right', async t => {
  const k = await request(t);
  const created = await k.command({ op: 'create_project', name: 'Two roots', workspace: { roots: ['/a', '/b'], primary_root: '/b' } });
  assert.equal(created.reply.ok, true);
  const project_id = created.reply.result.project_id;
  const inherited = await k.command({ op: 'fork', task_id: 0, child_count: 1 });
  assert.equal(inherited.reply.ok, true, JSON.stringify(inherited.reply));
  assert.deepEqual((await k.page(1)).task.settings, (await k.page()).task.settings);
  assert.equal((await k.page(1)).task.operations.length, 0);
  assert.equal((await k.command({ op: 'review_approval', task_id: 1, operation_id: k.operation.operation_id, decision: 'allow' })).reply.ok, false);
  for (const effect of inherited.effects.filter(effect => effect.kind === 'model')) await k.send(done(effect));
  const branch = await k.command({ op: 'fork', task_id: 0, child_count: 1, settings: {
    project_id, sandbox: { mode: 'read-only' }, approval: { mode: 'full-access' },
  } });
  assert.equal(branch.reply.ok, true, JSON.stringify(branch.reply));
  const snapshot = (await k.page(2)).task.settings;
  assert.equal(snapshot.workspace.primary_root, '/b');
  assert.equal(snapshot.approval.mode, 'full-access');
  assert.equal((await k.page()).task.settings.approval.mode, 'ask-for-approval');
  assert.equal((await k.command({ op: 'update_project', project_id, workspace: { roots: [] } })).reply.ok, true);
  assert.deepEqual((await k.page(2)).task.settings, snapshot);
  assert.equal((await k.command({ op: 'delete_project', project_id })).reply.ok, false);
  const newTask = await k.command({ op: 'create', profile: 'worker', message: 'Use new defaults', settings: { project_id } });
  assert.equal(newTask.reply.ok, true);
  assert.deepEqual((await k.page(3)).task.settings.workspace, { roots: [], primary_root: null });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalFixture, auditRecord, denialReason, eventually, originalReviewerModel, replacementReviewerModel } from './fixtures/approval-provenance-runtime.mjs';

test('a completed human approval keeps its reviewer and exact native invocation in HTTP history', async t => {
  const fixture = await approvalFixture(t, 'human');
  const pending = await fixture.pending();
  const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
  assert.deepEqual(operation.reviewer, { kind: 'human' });
  await fixture.markerAbsent();
  await fixture.successful({ op: 'review_approval', task_id: fixture.taskId,
    operation_id: operation.operation_id, decision: 'deny', reason: denialReason });
  auditRecord(await fixture.idle(), fixture.taskId, operation.operation_id, fixture.commandText, { kind: 'human' });
  await fixture.markerAbsent();
  assert.deepEqual(fixture.upstream.failures, []);
});

test('model approval audit evidence survives a real configuration reload under the same profile key', async t => {
  const fixture = await approvalFixture(t, 'model');
  const pending = await fixture.pending();
  const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
  assert.equal(operation.reviewer.kind, 'model');
  assert.equal(typeof operation.reviewer.profile, 'object');
  assert.ok(Object.values(operation.reviewer.profile).includes(originalReviewerModel),
    'The public pending reviewer must expose the configured original model');
  const reviewer = structuredClone(operation.reviewer);
  await eventually(() => fixture.upstream.requests, requests => requests.some(body => body.model === originalReviewerModel),
    'The actual reviewer HTTP request must use the original model');
  const stale = await fixture.command({ op: 'review_approval', task_id: fixture.taskId,
    operation_id: operation.operation_id, decision: 'deny', reason: 'A human cannot impersonate the requested model.' });
  assert.equal(stale.reply.ok, false);
  assert.match(JSON.stringify(stale.reply.error), /approval_not_pending/);
  fixture.releaseReviewer();
  const before = auditRecord(await fixture.idle(), fixture.taskId, operation.operation_id, fixture.commandText, reviewer);
  await fixture.markerAbsent();

  await fixture.reconfigureReviewer();
  const replacement = await fixture.successful({ op: 'create', profile: 'judge', message: 'Confirm the reloaded profile.' });
  await eventually(() => fixture.successful({ op: 'read', task_id: replacement.task_id }),
    page => page.task.phase === 'idle' && page.task.operations.length === 0, 'Reloaded profile probe must settle');
  assert.ok(fixture.upstream.requests.some(body => body.model === replacementReviewerModel),
    'A real subsequent request must demonstrate that the replacement configuration is active');
  const after = auditRecord(await fixture.read(), fixture.taskId, operation.operation_id, fixture.commandText, reviewer);
  assert.deepEqual(after, before);
  assert.ok(!Object.values(after.reviewer.profile).includes(replacementReviewerModel));
  await fixture.markerAbsent();
  assert.deepEqual(fixture.upstream.failures, []);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalFixture, approvalRecord, denialReason } from './fixtures/approval-runtime.mjs';

test('invalid human approval reasons leave the review pending and a denial is recorded in HTTP history', async t => {
  const fixture = await approvalFixture(t);
  const pending = await fixture.pending();
  const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
  assert.deepEqual(operation.reviewer, { kind: 'human' });
  await fixture.markerAbsent();

  for (const reason of ['界'.repeat(683), 'Allow\u0000trailing']) {
    const rejected = await fixture.command({ op: 'review_approval', task_id: fixture.taskId,
      operation_id: operation.operation_id, decision: 'allow', reason });
    assert.equal(rejected.status, 400);
    assert.equal(rejected.reply.ok, false);
    const page = await fixture.read();
    assert.equal(page.task.operations.find(value => value.operation_id === operation.operation_id)?.status, 'awaiting_approval');
    await fixture.markerAbsent();
  }

  await fixture.successful({ op: 'review_approval', task_id: fixture.taskId,
    operation_id: operation.operation_id, decision: 'deny', reason: denialReason });
  approvalRecord(await fixture.idle(), fixture.taskId, operation.operation_id, fixture.commandText);
  await fixture.markerAbsent();
  assert.deepEqual(fixture.upstream.failures, []);
});

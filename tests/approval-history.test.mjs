import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalFixture, approvalRecord, denialReason } from './fixtures/approval-runtime.mjs';

test('a completed human approval explains its exact command and decision in HTTP history', async t => {
  const fixture = await approvalFixture(t);
  const pending = await fixture.pending();
  const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
  assert.deepEqual(operation.reviewer, { kind: 'human' });
  await fixture.markerAbsent();
  await fixture.successful({ op: 'review_approval', task_id: fixture.taskId,
    operation_id: operation.operation_id, decision: 'deny', reason: denialReason });
  approvalRecord(await fixture.idle(), fixture.taskId, operation.operation_id, fixture.commandText);
  await fixture.markerAbsent();
  assert.deepEqual(fixture.upstream.failures, []);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalFixture, denialReason } from './fixtures/approval-runtime.mjs';

for (const [description, reason] of [['an overlong UTF-8 reason', '界'.repeat(683)], ['a NUL in the reason', 'Allow\u0000trailing']]) {
  test(`a human approval with ${description} is rejected without consuming the pending review`, async t => {
    const fixture = await approvalFixture(t);
    const pending = await fixture.pending();
    const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
    const rejected = await fixture.command({ op: 'review_approval', task_id: fixture.taskId,
      operation_id: operation.operation_id, decision: 'allow', reason });
    assert.equal(rejected.status, 400);
    assert.equal(rejected.reply.ok, false);
    const page = await fixture.read();
    assert.equal(page.task.operations.find(value => value.operation_id === operation.operation_id)?.status, 'awaiting_approval');
    await fixture.markerAbsent();
    await fixture.successful({ op: 'review_approval', task_id: fixture.taskId,
      operation_id: operation.operation_id, decision: 'deny', reason: denialReason });
    await fixture.idle();
    await fixture.markerAbsent();
    assert.deepEqual(fixture.upstream.failures, []);
  });
}

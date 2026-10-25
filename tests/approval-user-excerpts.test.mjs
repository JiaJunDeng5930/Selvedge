import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalFixture } from './fixtures/approval-provenance-runtime.mjs';

for (const [description, reason] of [['an overlong UTF-8 reason', '界'.repeat(683)], ['a NUL in the reason', 'Allow\u0000trailing']]) {
  test(`a human approval with ${description} settles as failed without executing the command`, async t => {
    const fixture = await approvalFixture(t, 'human');
    const pending = await fixture.pending();
    const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
    await fixture.successful({ op: 'review_approval', task_id: fixture.taskId,
      operation_id: operation.operation_id, decision: 'allow', reason });
    const page = await fixture.idle();
    const records = page.messages.filter(value => value.role === 'approval_record' && value.operation_id === operation.operation_id);
    assert.equal(records.length, 1);
    assert.deepEqual(records[0].content, { decision: 'failed', reason: 'The review response exceeded its bounded decision contract' });
    assert.ok(JSON.stringify(page.messages).includes('approval_denied'), 'The original pending tool receives a denial result');
    await fixture.markerAbsent();
    assert.deepEqual(fixture.upstream.failures, []);
  });
}

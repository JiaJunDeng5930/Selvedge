import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

export async function taskIdle(service, taskId, timeoutMs = 20_000) {
  // These scenarios include multiple model/tool roundtrips before becoming idle;
  // their physical IO deadlines are asserted separately.
  const deadline = Date.now() + timeoutMs;
  let page;
  do {
    const result = await service.command({ op: 'read', task_id: taskId });
    assert.equal(result.reply.ok, true);
    page = result.reply.result;
    if (page.task.phase === 'idle' && page.task.operations.length === 0) return page;
    await delay(10);
  } while (Date.now() < deadline);
  // DEFENSE: A service/provider regression can leave a real asynchronous task unsettled beyond the fixture deadline.
  throw new Error(`Task did not settle: ${JSON.stringify(page)}`);
}

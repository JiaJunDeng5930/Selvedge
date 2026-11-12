import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function modelRequest(fixture, index) {
  const deadline = Date.now() + 10000;
  while (!fixture.requests[index] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[index], 'The conversation reaches the model');
  return fixture.requests[index];
}

async function conversationEntry(fixture, taskId) {
  const { task } = await fixture.command({ op: 'read', task_id: taskId });
  return fixture.page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true });
}

test('conversation details leave a reading gutter beside tables and code', async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Inspect reading space.' });
  await modelRequest(fixture, 0);
  fixture.finish(0, { text: [
    '| Item | Description |', '| --- | --- |',
    '| First | ' + 'a wide table value '.repeat(10) + ' |', '',
    '```text', 'A code value '.repeat(12), '```', '',
    ...Array.from({ length: 24 }, (_, index) => 'Reading paragraph ' + index + '.\n'),
  ].join('\n') });
  await taskIdle(running.service, task_id);
  await (await conversationEntry(fixture, task_id)).click();

  const reading = page.locator('[data-reading-root]');
  await reading.locator('.table-scroll').waitFor();
  const measure = () => reading.evaluate(root => {
    const bounds = root.getBoundingClientRect();
    const blocks = [...root.querySelectorAll('.table-scroll, .code-block')];
    return { bounds: bounds.toJSON(),
      gutter: Math.min(...blocks.map(block => bounds.right - block.getBoundingClientRect().right)),
      scrolls: root.scrollHeight > root.clientHeight };
  });
  const assertDesktopGutter = geometry => {
    assert.ok(geometry.scrolls && geometry.gutter >= 16,
      'A scrolling desktop conversation leaves space between its table or code and the reading edge');
  };
  assertDesktopGutter(await measure());

  await page.getByRole('button', { name: '任务详情', exact: true }).click();
  const details = page.getByRole('complementary', { name: '任务详情', exact: true });
  await details.getByRole('heading', { name: '运行信息', exact: true }).waitFor();
  const detailsWidth = (await details.boundingBox()).width;
  assert.ok(detailsWidth > 210 && detailsWidth <= 270, 'Short metadata uses a compact desktop panel');
  assertDesktopGutter(await measure());

  await page.setViewportSize({ width: 390, height: 730 });
  const compactDetails = page.getByRole('dialog', { name: '任务详情', exact: true });
  await compactDetails.getByRole('heading', { name: '运行信息', exact: true }).waitFor();
  const compactBounds = await compactDetails.boundingBox();
  assert.ok(compactBounds.x >= 0 && compactBounds.x + compactBounds.width <= 390);
  await compactDetails.getByRole('button', { name: '任务详情', exact: true, expanded: true }).click();
  await compactDetails.waitFor({ state: 'hidden' });
  const compact = await measure();
  assert.ok(compact.scrolls && compact.bounds.right <= 390 && compact.gutter >= 6 && compact.gutter < 20,
    'A compact conversation preserves a reading edge and uses the available width');
});

test('conversation rows keep one resting dot and identify execution that needs attention', async t => {
  const fixture = await browserFixture(t);
  const { command, profile, running } = fixture;
  const { task_id: idle } = await command({ op: 'create_idle', profile: 'demo' });
  const idleEntry = await conversationEntry(fixture, idle);
  await idleEntry.waitFor();
  assert.equal(await idleEntry.evaluate(button => {
    const marker = button.parentElement.querySelector('[data-task-marker]');
    return !!marker && getComputedStyle(marker, '::after').content === '""';
  }), true, 'The resting row keeps the tree marker');
  assert.equal(await idleEntry.locator('[data-navigation-slot="status"]').count(), 0,
    'The ordinary conversation needs no second dot');

  async function assertNotice(entry, caption) {
    const notice = entry.getByRole('img', { name: caption, exact: true });
    await notice.waitFor();
    assert.equal(await notice.locator('svg').count(), 1);
    const description = await entry.getAttribute('aria-describedby');
    assert.ok(description?.split(/\s+/).includes(await notice.getAttribute('id')),
      'The conversation button includes its execution status in its accessible description');
  }

  const { task_id: runningTask } = await command({ op: 'create', profile, message: 'Hold this response open.' });
  const pending = await modelRequest(fixture, 0);
  const activeEntry = await conversationEntry(fixture, runningTask);
  await assertNotice(activeEntry, '运行中');
  pending.response.end('data: {"type":"response.failed","response":{"status":"failed"}}\n\n');
  await taskIdle(running.service, runningTask);
  await assertNotice(activeEntry, '执行出错');

  const { task_id: approvalTask } = await command({ op: 'create', profile, message: 'Wait for approval.',
    settings: { approval: { mode: 'ask-for-approval' } } });
  const review = await modelRequest(fixture, 1);
  fixture.finish(review.index, { output: [{ type: 'function_call', call_id: 'request-review',
    name: 'bash', arguments: JSON.stringify({ command: 'printf "review"', sandbox_permissions: 'require_escalated',
      justification: 'Verify that a pending approval is visible.' }) }] });
  await assertNotice(await conversationEntry(fixture, approvalTask), '等待审批');
});

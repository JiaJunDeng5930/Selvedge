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

test('opening conversation details preserves the desktop reading position and composer', async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Inspect reading space.' });
  await modelRequest(fixture, 0);
  const columns = Array.from({ length: 36 }, (_, index) => 'Check ' + (index + 1));
  const matrix = [columns, columns.map(() => '---'), columns.map(() => 'Pass')]
    .map(row => '| ' + row.join(' | ') + ' |');
  fixture.finish(0, { text: [
    '| Item | Description |', '| --- | --- |',
    '| First | ' + 'a wide table value '.repeat(10) + ' |', '',
    '```text', 'A code value '.repeat(12), '```', '',
    ...Array.from({ length: 24 }, (_, index) => 'Reading paragraph ' + index + '.\n'),
    ...matrix,
  ].join('\n') });
  await taskIdle(running.service, task_id);
  await (await conversationEntry(fixture, task_id)).click();

  const reading = page.locator('[data-reading-root]');
  const wideTable = reading.locator('.table-scroll')
    .filter({ has: page.getByRole('columnheader', { name: 'Check 36', exact: true }) });
  await wideTable.waitFor();
  assert.ok(await wideTable.evaluate(table => {
    table.scrollLeft = table.scrollWidth;
    return table.scrollLeft > 0 && table.closest('[data-reading-root]').scrollLeft === 0;
  }), 'A wide table scrolls horizontally inside the reading region');
  const measure = () => reading.evaluate(root => {
    const bounds = root.getBoundingClientRect();
    const view = root.closest('[data-view]');
    const blocks = [...root.querySelectorAll('.table-scroll, .code-block')];
    return { bounds: bounds.toJSON(),
      gutter: Math.min(...blocks.map(block => bounds.right - block.getBoundingClientRect().right)),
      scrolls: root.scrollHeight > root.clientHeight,
      viewOverflow: view.scrollWidth > view.clientWidth,
      viewportWidth: innerWidth };
  });
  const assertDesktopGutter = geometry => {
    assert.ok(geometry.scrolls && geometry.gutter >= 40 &&
      !geometry.viewOverflow && geometry.bounds.right <= geometry.viewportWidth,
      'The native scrollbar is outside the reading measure and inside the conversation viewport');
  };
  const composer = page.getByRole('combobox', { name: 'Message', exact: true });
  const readingPosition = () => reading.evaluate(root => {
    const { x, width } = root.getBoundingClientRect();
    return { x, width, scrollTop: root.scrollTop };
  });
  await page.waitForFunction(() => document.querySelector('[data-reading-root]')?.scrollTop > 200);
  const tail = await readingPosition();
  const dockAtTail = await composer.boundingBox();
  const readingAtTail = await reading.boundingBox();
  await reading.hover({ position: { x: 4, y: 100 } });
  await page.mouse.wheel(0, -160);
  const latest = page.getByRole('button', { name: 'Return to latest', exact: true });
  await latest.waitFor();
  const [latestBounds, readingBounds, dockBounds] = await Promise.all([
    latest.boundingBox(), reading.boundingBox(), composer.boundingBox(),
  ]);
  assert.ok(latestBounds.x >= readingBounds.x + readingBounds.width &&
    latestBounds.y >= readingBounds.y && latestBounds.y + latestBounds.height <= readingBounds.y + readingBounds.height,
  'The return button has its own space outside the reading column');
  assert.deepEqual(readingBounds, readingAtTail, 'Showing the return button preserves reading height');
  assert.deepEqual(dockBounds, dockAtTail, 'Showing the return button preserves the composer position');
  await page.waitForFunction(last => {
    const top = document.querySelector('[data-reading-root]')?.scrollTop;
    return top > 0 && top < last - 100;
  }, tail.scrollTop);
  const before = await readingPosition();
  assert.ok(before.scrollTop > 0, 'Open details while reading in the middle of a conversation');
  const composerBefore = await composer.boundingBox();
  assertDesktopGutter(await measure());

  const toggle = page.getByRole('button', { name: '任务详情', exact: true });
  await toggle.press('Enter');
  const details = page.getByRole('complementary', { name: '任务详情', exact: true });
  await details.getByRole('heading', { name: '运行信息', exact: true }).waitFor();
  await page.waitForFunction(() => document.activeElement?.textContent === '任务详情' &&
    document.activeElement?.matches('[data-semantic-key="task-details"] [data-semantic-key="heading"]'));
  const bounds = await details.boundingBox();
  assert.ok(bounds.width > 210 && bounds.width <= 270, 'Short metadata uses a compact desktop panel');
  assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 1280 &&
    bounds.y >= 0 && bounds.y + bounds.height <= 900, 'The details panel fits within the viewport');
  assert.deepEqual(await readingPosition(), before);
  const composerWithDetails = await composer.boundingBox();
  assert.equal(composerWithDetails.x, composerBefore.x);
  assert.equal(composerWithDetails.width, composerBefore.width);
  assertDesktopGutter(await measure());

  await page.keyboard.press('Tab');
  await page.waitForFunction(() => document.activeElement?.getAttribute('aria-label') === '关闭任务详情');
  await page.keyboard.press('Enter');
  await details.waitFor({ state: 'hidden' });
  await page.waitForFunction(() => document.activeElement?.matches('[data-semantic-key="details"]'));
  assert.deepEqual(await readingPosition(), before);
  await reading.press('PageUp');
  await page.waitForFunction(previous => {
    const root = document.querySelector('[data-reading-root]');
    return document.activeElement === root && root.scrollTop < previous;
  }, before.scrollTop);
  await toggle.press('Enter');
  await page.setViewportSize({ width: 1280, height: 360 });
  const short = await details.boundingBox();
  assert.ok(short.y >= 0 && short.y + short.height <= 360, 'Details fit a short desktop window');

  await page.setViewportSize({ width: 390, height: 730 });
  const compactDetails = page.getByRole('dialog', { name: '任务详情', exact: true });
  await compactDetails.getByRole('heading', { name: '运行信息', exact: true }).waitFor();
  const compactBounds = await compactDetails.boundingBox();
  assert.ok(compactBounds.x >= 0 && compactBounds.x + compactBounds.width <= 390);
  await compactDetails.getByRole('button', { name: '任务详情', exact: true, expanded: true }).press('Enter');
  await compactDetails.waitFor({ state: 'hidden' });
  const compact = await measure();
  assert.ok(compact.scrolls && compact.bounds.right <= 390 && compact.gutter >= 6 && compact.gutter < 20 &&
    !compact.viewOverflow,
    'A compact conversation preserves a reading edge and uses the available width');

  await page.setViewportSize({ width: 900, height: 730 });
  assertDesktopGutter(await measure());
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

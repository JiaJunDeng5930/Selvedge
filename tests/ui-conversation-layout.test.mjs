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

test('reading follows new output after the reader scrolls back to the bottom', async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  await page.evaluate(() => {
    let aligned;
    window.addEventListener('scroll', event => {
      const reader = event.target;
      if (aligned || !reader.hasAttribute?.('data-reading-root') ||
          reader.scrollTop <= 0 || reader.scrollHeight - reader.clientHeight - reader.scrollTop > 1) return;
      aligned = reader;
      window.readingAlignmentHeld = true;
      event.stopImmediatePropagation();
    }, true);
    window.addEventListener('keydown', event => {
      if (event.key === 'Home' && aligned === event.target) aligned.dispatchEvent(new Event('scroll'));
    });
  });
  const { task_id } = await command({ op: 'create', profile, message: 'Give me a long first reply.' });
  await modelRequest(fixture, 0);
  fixture.finish(0, { text: Array.from({ length: 30 }, (_, index) => `Paragraph ${index + 1} of the first reply.`).join('\n\n') });
  await taskIdle(running.service, task_id);
  await (await conversationEntry(fixture, task_id)).click();

  const reading = page.getByRole('region', { name: 'Conversation', exact: true });
  await reading.getByText('Paragraph 30 of the first reply.', { exact: true }).waitFor();
  await page.waitForFunction(() => window.readingAlignmentHeld);
  await reading.press('Home');
  await page.getByRole('button', { name: 'Return to latest', exact: true }).waitFor();
  await page.waitForFunction(() => document.querySelector('[data-reading-root]').scrollTop <= 2);
  const atBottom = () => page.waitForFunction(() => {
    const node = document.querySelector('[data-reading-root]');
    return node.scrollHeight - node.clientHeight - node.scrollTop <= 2;
  }, undefined, { timeout: 3000 });
  await reading.hover();
  await page.mouse.wheel(0, await reading.evaluate(node => node.scrollHeight));
  await atBottom();
  await reading.press('End');

  await command({ op: 'send', task_id, message: 'Keep reading the latest output.' });
  await modelRequest(fixture, 1);
  const lines = Array.from({ length: 18 }, (_, index) => `Fresh output ${index + 1}.`);
  fixture.emit(1, `${lines.join('\n\n')}\n\n`);
  await reading.getByText(lines.at(-1), { exact: true }).waitFor();
  await atBottom();
  fixture.finish(1, { text: `${lines.join('\n\n')}\n\nAll the new output is visible.` });
  await reading.getByText('All the new output is visible.', { exact: true }).waitFor();
  await atBottom();
});

test('a small wheel movement from the latest reply keeps the reader near the latest processing card', async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Run the first check.', settings: {
    approval: { mode: 'full-access' },
  } });
  const reply = turn => Array.from({ length: 18 }, (_, index) =>
    `Check ${turn}, paragraph ${index + 1}.`).join('\n\n');
  for (const turn of [1, 2]) {
    if (turn === 2) await command({ op: 'send', task_id, message: 'Run the second check.' });
    const index = 2 * (turn - 1);
    await modelRequest(fixture, index);
    fixture.finish(index, { output: [{
      type: 'function_call', call_id: `check-${turn}`, name: 'bash',
      arguments: JSON.stringify({ command: `printf 'check ${turn}'` }),
    }] });
    await modelRequest(fixture, index + 1);
    fixture.finish(index + 1, { text: reply(turn) });
    await taskIdle(running.service, task_id);
  }
  await (await conversationEntry(fixture, task_id)).click();
  const reading = page.getByRole('region', { name: 'Conversation', exact: true });
  await reading.getByText('Check 2, paragraph 18.', { exact: true }).waitFor();
  const secondProcess = reading.getByRole('button', { name: '处理完成', exact: true }).nth(1);
  const viewport = page.viewportSize();
  const wheelDistance = 40;
  // Put the top edge of the viewport inside the second card after one wheel step.
  const heightChange = await secondProcess.evaluate((button, distance) => {
    const root = button.closest('[data-reading-root]');
    return root.scrollHeight - root.clientHeight - root.scrollTop
      + root.getBoundingClientRect().top - button.getBoundingClientRect().top - distance - 16;
  }, wheelDistance);
  await page.setViewportSize({ ...viewport, height: viewport.height + Math.round(heightChange) });
  await page.waitForFunction(() => {
    const root = document.querySelector('[data-reading-root]');
    return root.scrollHeight - root.clientHeight - root.scrollTop <= 2;
  });
  await reading.hover({ position: { x: 5, y: 120 } });
  const before = await reading.evaluate(root => root.scrollTop);
  await page.mouse.wheel(0, -wheelDistance);
  await page.getByRole('button', { name: 'Return to latest', exact: true }).waitFor();
  const after = await reading.evaluate(async root => {
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return root.scrollTop;
  });
  assert.ok(Math.abs(before - after - wheelDistance) <= 2, `Reader moved from ${before} to ${after}`);
});

test('expanding recent tool output keeps the reader at the end and scrolls independently', async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  const { task_id } = await command({ op: 'create', profile, message: 'Produce scrollable command output.', settings: {
    approval: { mode: 'full-access' },
  } });
  await modelRequest(fixture, 0);
  fixture.finish(0, { text: Array.from({ length: 30 }, (_, index) => `Earlier paragraph ${index + 1}.`).join('\n\n') });
  await taskIdle(running.service, task_id);
  await command({ op: 'send', task_id, message: 'Now run the command.' });
  await modelRequest(fixture, 1);
  fixture.finish(1, { output: [{
    type: 'function_call', call_id: 'scrollable-command', name: 'bash',
    arguments: JSON.stringify({ command: "for i in $(seq 1 32); do printf '%s\\n' \"line $i\"; done" }),
  }] });
  await modelRequest(fixture, 2);
  fixture.finish(2, { text: 'The command has finished.' });
  await taskIdle(running.service, task_id);
  await (await conversationEntry(fixture, task_id)).click();

  const reading = page.locator('[data-reading-root]');
  const atBottom = () => reading.evaluate(node => node.scrollHeight - node.clientHeight - node.scrollTop <= 2);
  await reading.getByText('The command has finished.', { exact: true }).waitFor();
  assert.equal(await atBottom(), true);
  await reading.getByRole('button', { name: '处理完成', exact: true }).click();
  await reading.locator('[data-tool-call-toggle]').click();
  const stdout = reading.locator('[data-tool-output]');
  await stdout.waitFor();
  await stdout.evaluate(async node => {
    await new Promise(resolve => requestAnimationFrame(resolve));
    const process = node.closest('[data-task-process]');
    const transitions = process.getAnimations({ subtree: true })
      .filter(animation => animation.effect.getComputedTiming().endTime !== Infinity);
    await Promise.allSettled(transitions.map(animation => animation.finished));
  });
  assert.equal(await atBottom(), true);

  await stdout.hover();
  await page.mouse.wheel(0, 80);
  await page.waitForFunction(() => document.querySelector('[data-tool-output]').scrollTop > 0);
  await stdout.press('PageUp');
  const latest = page.getByRole('button', { name: 'Return to latest', exact: true });
  assert.equal(await latest.count(), 0);
  assert.equal(await atBottom(), true);
});

test('conversation rows keep one resting dot and identify execution that needs attention', async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id: idle } = await command({ op: 'create_idle', profile: 'demo' });
  const idleEntry = await conversationEntry(fixture, idle);
  await idleEntry.waitFor();
  const title = await idleEntry.getAttribute('aria-label');
  assert.equal(await idleEntry.evaluate(button => {
    const marker = button.querySelector('[data-task-marker]');
    return !!marker && getComputedStyle(marker, '::after').content === '""';
  }), true, 'The resting row includes its tree marker in the open target');
  assert.equal(await idleEntry.locator('[data-navigation-slot="status"]').count(), 0,
    'The ordinary conversation needs no second dot');
  await idleEntry.locator('[data-task-marker]').click();
  await page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  await page.setViewportSize({ width: 390, height: 740 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).click();
  const drawer = page.getByRole('dialog', { name: '对话', exact: true });
  await drawer.getByRole('button', { name: title, exact: true }).locator('[data-task-marker]').click();
  await drawer.waitFor({ state: 'hidden' });
  await page.setViewportSize({ width: 1280, height: 900 });

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
  await activeEntry.click();
  const activity = page.getByRole('main').locator('section[data-expanded]').filter({
    has: page.getByRole('button', { name: '执行错误', exact: true }),
  });
  const disclosure = activity.getByRole('button', { name: '执行错误', exact: true });
  await disclosure.waitFor();
  if (await activity.getAttribute('data-expanded') === 'false') await disclosure.click();
  await activity.getByText('Model stream ended with response.failed', { exact: true }).waitFor();
  assert.equal(await activity.getByText('执行错误', { exact: true }).count(), 1);

  const { task_id: approvalTask } = await command({ op: 'create', profile, message: 'Wait for approval.',
    settings: { approval: { mode: 'ask-for-approval' } } });
  const review = await modelRequest(fixture, 1);
  fixture.finish(review.index, { output: [{ type: 'function_call', call_id: 'request-review',
    name: 'bash', arguments: JSON.stringify({ command: 'printf "review"', sandbox_permissions: 'require_escalated',
      justification: 'Verify that a pending approval is visible.' }) }] });
  await assertNotice(await conversationEntry(fixture, approvalTask), '等待审批');
});

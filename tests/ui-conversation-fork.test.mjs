import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

const forkActionLabel = '创建对话分支';

async function waitForAnswer(fixture, index) {
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[index] && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests[index], 'The conversation started its model request');
}

async function openTask(page, title) {
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: title, exact: true }).click();
}

async function expectFocus(page, locator) {
  await page.waitForFunction(id => document.activeElement?.id === id, await locator.getAttribute('id'));
}

async function expectForkTooltip(page, fork) {
  await page.waitForFunction(({ id, label }) => {
    const button = document.getElementById(id);
    if (!button) return false;
    const tooltip = getComputedStyle(button, '::after');
    return tooltip.content === JSON.stringify(label) && tooltip.display !== 'none' && tooltip.visibility === 'visible';
  }, { id: await fork.getAttribute('id'), label: forkActionLabel });
}

test('a conversation offers its fork at the end and Cancel restores the reading position', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, running, profile } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Fork this conversation at its end.' });
  const earlier = 'Earlier answer belongs to the same conversation.';
  const latest = 'Latest answer belongs to the fork too.';
  const background = Array.from({ length: 24 }, (_, index) =>
    `Part ${index + 1}. ${'Background details for the conversation. '.repeat(4)}`).join('\n\n');
  await waitForAnswer(fixture, 0);
  fixture.finish(0, { text: `${earlier}\n\n${background}` });
  const { task } = await taskIdle(running.service, task_id);
  await openTask(page, task.title);
  const main = page.getByRole('main');
  const timeline = main.getByRole('region', { name: 'Conversation', exact: true });
  const finalAnswer = timeline.getByText(latest, { exact: true });
  const fork = timeline.getByRole('button', { name: forkActionLabel, exact: true });
  await fork.waitFor();
  await command({ op: 'send', task_id, message: 'Finish the source conversation.' });
  await waitForAnswer(fixture, 1);
  fixture.emit(1, `${latest}\n\n`);
  await finalAnswer.waitFor();
  assert.equal(await fork.count(), 0, 'The end action is absent while a reply is streaming');
  fixture.finish(1);
  await taskIdle(running.service, task_id);
  await fork.waitFor();
  assert.equal(await fork.locator('svg').count(), 1);
  assert.equal(await fork.locator('span:not(.visually-hidden)').count(), 0);

  const dialog = page.getByRole('dialog', { name: forkActionLabel, exact: true });
  const source = dialog.getByText(task.title, { exact: true });
  const history = dialog.getByText('分支会继承这条对话当前的历史。', { exact: true });
  const cancel = dialog.getByRole('button', { name: '取消', exact: true });
  const moreActions = main.getByRole('button', { name: '对话操作', exact: true });
  await moreActions.press('Enter');
  const menu = page.getByRole('menu', { name: '对话操作', exact: true });
  for (const name of ['暂停对话', '归档对话', '侧边对话', '压缩上下文']) {
    const action = menu.getByRole('button', { name, exact: true });
    await action.waitFor();
    assert.equal(await action.locator('svg').count(), 1);
  }
  assert.equal(await menu.getByRole('button', { name: forkActionLabel, exact: true }).count(), 0);
  await page.keyboard.press('Escape');
  await menu.waitFor({ state: 'hidden' });
  await expectFocus(page, moreActions);

  await page.setViewportSize({ width: 390, height: 700 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
  const message = main.getByRole('combobox', { name: 'Message', exact: true });
  const returnLatest = main.getByRole('button', { name: 'Return to latest', exact: true });
  await finalAnswer.waitFor();
  assert.equal(await fork.count(), 1);
  const timelineId = await timeline.getAttribute('id');
  await timeline.press('Home');
  await returnLatest.waitFor();
  await page.waitForFunction(id => document.getElementById(id)?.scrollTop <= 2, timelineId);
  assert.ok(await fork.evaluate(button => button.getBoundingClientRect().top >= button.parentElement.getBoundingClientRect().bottom),
    'Earlier history does not carry a fork control');
  await timeline.hover();
  await page.mouse.wheel(0, await timeline.evaluate(node => node.scrollHeight));
  await page.waitForFunction(id => {
    const node = document.getElementById(id);
    return node && node.scrollHeight - node.clientHeight - node.scrollTop <= 2;
  }, timelineId);
  const [answerBounds, forkBounds, messageBounds] = await Promise.all([
    finalAnswer.boundingBox(), fork.boundingBox(), message.boundingBox(),
  ]);
  assert.ok(answerBounds && forkBounds && messageBounds && answerBounds.y + answerBounds.height <= forkBounds.y
    && forkBounds.y >= 0 && forkBounds.y + forkBounds.height <= messageBounds.y
    && forkBounds.x >= 0 && forkBounds.x + forkBounds.width <= 390,
  'The action is visible after the current answer and above the composer');

  const offset = await timeline.evaluate(node => node.scrollTop);
  await fork.hover();
  await expectForkTooltip(page, fork);
  await page.mouse.move(0, 0);
  await page.keyboard.press('Tab');
  await expectFocus(page, fork);
  await expectForkTooltip(page, fork);
  await fork.press('Enter');
  await source.waitFor();
  await history.waitFor();
  await cancel.click();
  await dialog.waitFor({ state: 'hidden' });
  await expectFocus(page, fork);
  assert.ok(Math.abs(await timeline.evaluate(node => node.scrollTop) - offset) <= 1);
  assert.equal(await returnLatest.isVisible(), true);
  assert.deepEqual(await message.boundingBox(), messageBounds);

  await fork.press('Enter');
  const response = page.waitForResponse(value => value.url().endsWith('/api/browser/command')
    && value.request().postDataJSON()?.command?.op === 'fork');
  await dialog.getByRole('button', { name: '创建分支', exact: true }).click();
  const receipt = await response;
  assert.equal(receipt.request().postDataJSON().command.task_id, task_id);
  const { reply } = await receipt.json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.equal(reply.result.children.length, 1);
  const child = await command({ op: 'read', task_id: reply.result.children[0] });
  assert.equal(child.task.parent, task_id);
  assert.ok(JSON.stringify(child.messages).includes(earlier));
  assert.ok(JSON.stringify(child.messages).includes(latest));
});

test('the side conversation end opens its own fork editor and restores the tail trigger', { timeout: 60000 }, async t => {
  const { page, command, running } = await browserFixture(t);
  const { task_id: parentId } = await command({ op: 'create_idle', profile: 'demo' });
  const { task_id: sideId } = await command({ op: 'open_side_conversation', task_id: parentId, message: 'Separate side question.' });
  const { task: sideTask } = await taskIdle(running.service, sideId);
  const { task: parentTask } = await command({ op: 'read', task_id: parentId });
  await openTask(page, parentTask.title);
  await page.setViewportSize({ width: 390, height: 700 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
  await page.getByRole('main').getByRole('button', { name: 'Open side conversation', exact: true }).click();
  const side = page.getByRole('dialog', { name: sideTask.title, exact: true });
  const fork = side.getByRole('region', { name: 'Conversation', exact: true }).getByRole('button', { name: forkActionLabel, exact: true });
  await fork.waitFor();
  assert.equal(await fork.locator('svg').count(), 1);
  assert.equal(await fork.locator('span:not(.visually-hidden)').count(), 0);
  await fork.press('Enter');
  const dialog = page.getByRole('dialog', { name: forkActionLabel, exact: true });
  await dialog.getByText(sideTask.title, { exact: true }).waitFor();
  assert.equal(await dialog.getByText(parentTask.title, { exact: true }).count(), 0);
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
  await expectFocus(page, fork);
  assert.equal(await side.isVisible(), true);
});

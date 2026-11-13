import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture, creationEnvironmentTrigger, openCreationEnvironment } from './fixtures/browser.mjs';

function insideViewport(bounds, { width, height }) {
  return bounds && bounds.width > 0 && bounds.height > 0 && bounds.x >= -1 && bounds.y >= -1
    && bounds.x + bounds.width <= width + 1 && bounds.y + bounds.height <= height + 1;
}

function iconWithoutCaption(button) {
  return button.evaluate(node => [...node.childNodes].every(child => {
    if (child.nodeType === Node.TEXT_NODE) return child.textContent.trim() === '';
    return child instanceof SVGElement ||
      child instanceof HTMLElement && getComputedStyle(child).clipPath === 'inset(50%)';
  }));
}

test('the composer gear keeps its menu clear of the draft at desktop and mobile sizes', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const viewports = [{ width: 1280, height: 900 }, { width: 390, height: 620 },
    { width: 740, height: 390 }, { width: 320, height: 620 }];
  const main = page.getByRole('main');
  const input = main.getByRole('combobox', { name: 'Task', exact: true });
  const start = main.getByRole('button', { name: 'Start task', exact: true, disabled: false });
  const gear = creationEnvironmentTrigger(page);
  const settings = page.getByRole('dialog', { name: '工作环境', exact: true });
  const message = 'Keep the task draft in place while I check its settings.';

  for (const viewport of viewports) {
    await page.setViewportSize(viewport);
    await input.fill(message);
    await start.waitFor();
    const closed = await input.boundingBox();
    const trigger = await gear.boundingBox();
    const size = `${viewport.width}×${viewport.height}`;
    assert.ok(insideViewport(closed, viewport) && insideViewport(trigger, viewport), size);
    assert.ok(trigger.y >= closed.y + closed.height - 2, 'The gear is in the input toolbar');
    assert.equal(await gear.locator('svg').count(), 1);
    assert.equal(await iconWithoutCaption(gear), true, 'The closed control only paints a gear');
    assert.equal(await settings.isVisible(), false);

    await gear.press('Enter');
    await settings.waitFor();
    const opened = await input.boundingBox();
    const panel = await settings.boundingBox();
    assert.ok(opened && Math.abs(opened.y - closed.y) <= 2 && Math.abs(opened.x - closed.x) <= 2,
      `Opening settings keeps the input in place at ${size}`);
    assert.ok(insideViewport(panel, viewport), `The menu fits the viewport at ${size}`);
    assert.ok(viewport.height >= 640
      ? panel.y >= trigger.y + trigger.height - 2
      : panel.y + panel.height <= trigger.y + 2, `The menu uses the available side of its gear at ${size}`);
    assert.ok(insideViewport(await start.boundingBox(), viewport), `Start stays in view at ${size}`);

    await page.keyboard.press('Escape');
    await settings.waitFor({ state: 'hidden' });
    await page.waitForFunction(() => document.activeElement?.dataset.semanticKey === 'composer/environment');
    assert.equal(await input.inputValue(), message);
  }
});

test('desktop and landscape composer menus open on the same side of their triggers', async t => {
  const { page } = await browserFixture(t);
  for (const viewport of [{ width: 1280, height: 720 }, { width: 844, height: 390 }]) {
    await page.setViewportSize(viewport);
    for (const [trigger, name] of [
      [page.getByRole('button', { name: /^Model:/ }), 'Model'],
      [page.getByRole('button', { name: /^权限:/ }), '权限'],
      [creationEnvironmentTrigger(page), '工作环境'],
    ]) {
      const anchor = await trigger.boundingBox();
      await trigger.click();
      const menu = page.getByRole('dialog', { name, exact: true });
      await menu.waitFor();
      const box = await menu.boundingBox();
      assert.ok(insideViewport(box, viewport));
      assert.ok(viewport.height === 720 ? box.y >= anchor.y + anchor.height - 2 : box.y + box.height <= anchor.y + 2,
        `${name} opens from its trigger at ${viewport.width}×${viewport.height}`);
      assert.ok(Math.abs(box.x + box.width - anchor.x - anchor.width) <= 2,
        `${name} aligns its trailing edge to the trigger`);
      await page.keyboard.press('Escape');
      await menu.waitFor({ state: 'hidden' });
    }
  }
});

test('an explicit send shows the captured new message in a temporary conversation before admission', { timeout: 90_000 }, async t => {
  const fixture = await browserFixture(t);
  const { page } = fixture;
  const model = page.getByRole('button', { name: /^Model:/ });
  if (!(await model.getAttribute('aria-label')).includes('interactive-fixture')) {
    await model.click();
    const picker = page.getByRole('dialog', { name: 'Model', exact: true });
    const choose = picker.getByRole('button', { name: /^Choose model:/ });
    const option = picker.getByRole('menuitemradio', { name: 'interactive-fixture', exact: true });
    await Promise.any([choose.waitFor(), option.waitFor()]);
    if (await choose.isVisible()) await choose.click();
    await option.click();
    if (await picker.isVisible()) await page.keyboard.press('Escape');
  }
  const assessmentStarted = Promise.withResolvers();
  const admit = Promise.withResolvers();
  const commandStarted = Promise.withResolvers();
  const submit = Promise.withResolvers();
  const resumeSnapshots = Promise.withResolvers();
  const prefix = 'Verify the composer progress';
  const sent = prefix + '!';
  const messageText = command => typeof command?.message === 'string' ? command.message : command?.message?.[0]?.text;
  const isMessage = (request, text) => {
    const command = request.postDataJSON()?.command;
    return command?.op === 'create' && messageText(command) === text;
  };
  await page.route('**/api/assess', async route => {
    if (isMessage(route.request(), sent)) {
      assessmentStarted.resolve();
      await admit.promise;
    }
    await route.continue();
  });
  const submissions = [];
  await page.route('**/api/browser/command', async route => {
    const command = route.request().postDataJSON()?.command;
    if (command?.op === 'create') {
      submissions.push(messageText(command));
      commandStarted.resolve();
      await submit.promise;
    }
    await route.continue();
  });
  await page.route('**/api/browser/state', async route => {
    // Observe the real creation receipt before later scheduled phases arrive.
    await resumeSnapshots.promise;
    await route.continue();
  });
  try {
    const main = page.getByRole('main');
    const reader = main.getByRole('region', { name: 'Conversation', exact: true });
    const draft = page.getByRole('combobox', { name: 'Task', exact: true });
    const send = page.getByRole('button', { name: 'Start task', exact: true });
    const status = page.getByRole('status').filter({ hasText: '正在提交消息…' });
    await draft.fill(prefix);
    await send.and(page.locator(':enabled')).waitFor();
    await draft.press('End');
    await page.keyboard.insertText('!');
    await assessmentStarted.promise;
    assert.equal(await send.isEnabled(), true);
    assert.equal(await status.count(), 0, 'Typing and admission show no sending message before an explicit click');
    await send.click();
    const pending = page.getByRole('button', { name: '正在提交消息…', exact: true });
    const captured = reader.getByText(sent, { exact: true });
    const progress = reader.getByRole('status').filter({ hasText: '正在提交消息…' });
    await captured.waitFor();
    await progress.waitFor();
    assert.equal(await draft.isVisible(), false);
    assert.equal(await send.isVisible(), false);
    assert.ok(insideViewport(await progress.boundingBox(), page.viewportSize()));
    assert.deepEqual(submissions, []);
    admit.resolve();
    await commandStarted.promise;
    assert.equal(await captured.isVisible(), true);
    assert.equal(await progress.isVisible(), true);
    assert.deepEqual(submissions, [sent]);
    const creation = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
      && response.request().postDataJSON()?.command?.op === 'create');
    submit.resolve();
    const { reply } = await (await creation).json();
    assert.equal(reply.ok, true);
    await reader.getByRole('status').filter({ hasText: '正在准备回复…' }).waitFor();
    resumeSnapshots.resolve();
    await captured.waitFor();
    await status.waitFor({ state: 'hidden' });
    const generation = reader.getByRole('status').filter({ hasText: '正在生成回复…' });
    await generation.waitFor();
    const requestDeadline = Date.now() + 30_000;
    while (!fixture.requests[0] && Date.now() < requestDeadline)
      await new Promise(resolve => setTimeout(resolve, 20));
    assert.ok(fixture.requests[0]);
    fixture.finish(0, { text: 'The submission and reply are visible.' });
    await reader.getByText('The submission and reply are visible.', { exact: true }).waitFor();
    await generation.waitFor({ state: 'hidden' });

    const compact = { width: 390, height: 720 };
    const message = 'Check the progress of an existing conversation.';
    await page.setViewportSize(compact);
    const followUp = page.getByRole('combobox', { name: 'Message', exact: true });
    await followUp.fill(message);
    await page.waitForFunction(() => {
      const composer = document.querySelector('[data-composer-dock]');
      return composer?.getBoundingClientRect().width < innerWidth;
    });
    const nextSend = page.getByRole('button', { name: '发送', exact: true });
    const messageReceipt = Promise.withResolvers();
    const releaseMessage = Promise.withResolvers();
    try {
      await page.route('**/api/browser/command', async route => {
        if (route.request().postDataJSON()?.command?.op === 'send') {
          messageReceipt.resolve();
          await releaseMessage.promise;
        }
        await route.continue();
      });
      await nextSend.and(page.locator(':enabled')).waitFor();
      const previousBox = await nextSend.boundingBox();
      await nextSend.click();
      await messageReceipt.promise;
      await status.waitFor();
      assert.ok(insideViewport(await status.boundingBox(), compact));
      assert.deepEqual(await pending.boundingBox(), previousBox);
    } finally {
      releaseMessage.resolve();
    }
    await reader.getByText(message, { exact: true }).waitFor();
    await status.waitFor({ state: 'hidden' });
    await generation.waitFor();
  } finally {
    admit.resolve();
    submit.resolve();
    resumeSnapshots.resolve();
  }
});

test('a refused new conversation restores its draft and a late receipt respects another page', { timeout: 60_000 }, async t => {
  const { page, command } = await browserFixture(t);
  const refused = 'Keep this first message if it is refused.';
  const later = 'Create this conversation in the background.';
  const refusal = 'The submitted test message was refused.';
  const releaseRefusal = Promise.withResolvers();
  const releaseReceipt = Promise.withResolvers();
  const created = Promise.withResolvers();
  t.after(() => {
    releaseRefusal.resolve();
    releaseReceipt.resolve();
  });
  let createdCount = 0;
  await page.route('**/api/assess', async route => {
    const request = route.request().postDataJSON();
    const message = request?.command?.message;
    if (request?.command?.op !== 'create' || (typeof message === 'string' ? message : message?.[0]?.text) !== refused)
      return route.continue();
    const response = await route.fetch();
    const observation = await response.json();
    await releaseRefusal.promise;
    await route.fulfill({ response, json: {
      ...observation, admitted: false, refusal: { code: 'test_refusal', message: refusal },
    } });
  });
  await page.route('**/api/browser/command', async route => {
    const request = route.request().postDataJSON()?.command;
    if (request?.op !== 'create') return route.continue();
    createdCount++;
    const response = await route.fetch();
    const { reply } = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    created.resolve(reply.result.task_id);
    await releaseReceipt.promise;
    await route.fulfill({ response });
  });
  const main = page.getByRole('main');
  const reader = main.getByRole('region', { name: 'Conversation', exact: true });
  const draft = main.getByRole('combobox', { name: 'Task', exact: true });
  const send = main.getByRole('button', { name: 'Start task', exact: true });
  await draft.fill(refused);
  await send.click();
  await reader.getByText(refused, { exact: true }).waitFor();
  releaseRefusal.resolve();
  await draft.waitFor();
  assert.equal(await draft.inputValue(), refused);
  await main.getByText(refusal, { exact: true }).first().waitFor();
  assert.equal(createdCount, 0);

  await draft.fill(later);
  await send.click();
  await reader.getByText(later, { exact: true }).waitFor();
  const task = await created.promise;
  const projects = page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true });
  await projects.click();
  const newProject = main.getByRole('button', { name: '新建项目', exact: true });
  await newProject.waitFor();
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === 'create');
  releaseReceipt.resolve();
  await receipt;
  assert.equal(await newProject.isVisible(), true);
  assert.equal(await reader.count(), 0);
  assert.equal(createdCount, 1);
  assert.match(JSON.stringify((await command({ op: 'read', task_id: task })).messages), /Create this conversation in the background/);
});

test('project and directory choices open inside the composer menu and return to it', async t => {
  const { page } = await browserFixture(t);
  const menu = page.getByRole('dialog', { name: '工作环境', exact: true });
  const project = page.getByRole('dialog', { name: '选择项目', exact: true });
  const workspace = page.getByRole('dialog', { name: '工作目录', exact: true });
  for (const viewport of [{ width: 1280, height: 720 }, { width: 320, height: 620 },
    { width: 740, height: 390 }]) {
    await page.setViewportSize(viewport);
    await openCreationEnvironment(page);
    const settings = await menu.boundingBox();
    await menu.getByText('未关联项目', { exact: true }).click();
    await project.waitFor();
    assert.equal(await menu.isVisible(), false);
    const projects = await project.boundingBox();
    await project.getByRole('button', { name: '返回工作环境', exact: true }).click();
    await menu.waitFor();
    assert.equal(await project.isVisible(), false);

    await menu.locator('button[data-logical-key="composer/workspace"]').click();
    await workspace.getByRole('textbox', { name: '目录路径', exact: true }).waitFor();
    assert.equal(await workspace.getByRole('heading', { name: /^工作目录/ }).count(), 1);
    assert.equal(await menu.isVisible(), false);
    const directories = await workspace.boundingBox();
    for (const panel of [projects, directories]) {
      assert.ok(insideViewport(panel, viewport));
      assert.ok(Math.abs(panel.x - settings.x) <= 2, 'Each level shares the same left edge');
      assert.ok(Math.abs(panel.width - settings.width) <= 2, 'Each level shares the same width');
      const attachment = panel => viewport.height >= 640 ? panel.y : panel.y + panel.height;
      assert.ok(Math.abs(attachment(panel) - attachment(settings)) <= 2,
        'Each level opens from the same edge of the composer gear');
    }
    await page.keyboard.press('Escape');
    await menu.waitFor();
    assert.equal(await workspace.isVisible(), false);
    await page.keyboard.press('Escape');
    await menu.waitFor({ state: 'hidden' });
  }
});

test('configured run environments show the current choice in the gear menu', async t => {
  const { page } = await browserFixture(t, { cloud: true });
  const viewport = { width: 320, height: 620 };
  await page.setViewportSize(viewport);
  await page.reload();
  const menu = await openCreationEnvironment(page);
  const choice = (name, checked) => menu.getByRole('menuitemradio', { name, exact: true, checked });
  const cases = ['在 Selvedge 主机上新建 Git 工作树', '在腾讯云 CVM 上运行', '使用当前工作目录'];
  await choice(cases[2], true).waitFor();
  for (const name of cases) {
    await choice(name, false).click();
    await choice(name, true).waitFor();
    assert.ok(insideViewport(await menu.boundingBox(), viewport));
    assert.equal(await iconWithoutCaption(creationEnvironmentTrigger(page)), true);
  }
});

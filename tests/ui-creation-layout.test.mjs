import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture, creationContext, creationEnvironmentTrigger, creationProjectTrigger, creationWorktreeSwitch, openCreationEnvironment } from './fixtures/browser.mjs';
import { taskIdle } from './fixtures/task-idle.mjs';

function insideViewport(bounds, { width, height }) {
  return bounds && bounds.width > 0 && bounds.height > 0 && bounds.x >= -1 && bounds.y >= -1
    && bounds.x + bounds.width <= width + 1 && bounds.y + bounds.height <= height + 1;
}

test('creation controls stay together above the draft at desktop and mobile sizes', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const viewports = [{ width: 1280, height: 900 }, { width: 390, height: 620 },
    { width: 740, height: 390 }, { width: 320, height: 620 }];
  const main = page.getByRole('main');
  const input = main.getByRole('combobox', { name: 'Task', exact: true });
  const start = main.getByRole('button', { name: 'Start task', exact: true, disabled: false });
  const workspace = creationEnvironmentTrigger(page);
  const menu = page.getByRole('dialog', { name: '工作环境', exact: true });
  const message = 'Keep the task draft in place while I check its settings.';

  for (const viewport of viewports) {
    await page.setViewportSize(viewport);
    await input.fill(message);
    await start.waitFor();
    const closed = await input.boundingBox();
    const [project, selectedWorkspace, worktree] = await Promise.all(
      [creationProjectTrigger(page), workspace, creationWorktreeSwitch(page)].map(control => control.boundingBox()));
    const size = `${viewport.width}×${viewport.height}`;
    for (const bounds of [closed, project, selectedWorkspace, worktree]) assert.ok(insideViewport(bounds, viewport), size);
    assert.ok([project, selectedWorkspace, worktree].every(control => control.y + control.height <= closed.y + 2), size);
    assert.ok(Math.abs(project.x - closed.x) <= 24, 'Project starts at the input’s left edge');
    if (viewport.width >= 740) {
      assert.ok(selectedWorkspace.x - (project.x + project.width) <= 20, 'Workspace is next to the project');
      assert.ok(worktree.x - (selectedWorkspace.x + selectedWorkspace.width) <= 20, 'Worktree is next to Workspace');
    }
    assert.equal(await creationContext(page).evaluate(element => getComputedStyle(element).backgroundColor), 'rgba(0, 0, 0, 0)');

    await workspace.press('Enter');
    await menu.waitFor();
    const opened = await input.boundingBox();
    assert.ok(opened && Math.abs(opened.y - closed.y) <= 2 && Math.abs(opened.x - closed.x) <= 2, size);
    assert.ok(insideViewport(await menu.boundingBox(), viewport), size);
    await page.keyboard.press('Escape');
    await menu.waitFor({ state: 'hidden' });
    await workspace.and(page.locator(':focus')).waitFor();
    assert.equal(await input.inputValue(), message);
  }
});

test('an explicit send shows the captured new message in a temporary conversation before the command receipt', { timeout: 90_000 }, async t => {
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
  const assessments = [];
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
    const operation = route.request().postDataJSON()?.command?.op;
    if (isMessage(route.request(), sent) || operation === 'send') {
      assessments.push(operation);
      return route.abort();
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
    assert.equal(await send.isEnabled(), true);
    assert.equal(await status.count(), 0, 'Typing shows no sending message before an explicit click');
    await send.click();
    const pending = page.getByRole('button', { name: '正在提交消息…', exact: true });
    const captured = reader.getByText(sent, { exact: true });
    const progress = reader.getByRole('status').filter({ hasText: '正在提交消息…' });
    await captured.waitFor();
    await progress.waitFor();
    assert.equal(await draft.isVisible(), false);
    assert.equal(await send.isVisible(), false);
    assert.ok(insideViewport(await progress.boundingBox(), page.viewportSize()));
    await commandStarted.promise;
    assert.equal(await captured.isVisible(), true);
    assert.equal(await progress.isVisible(), true);
    assert.deepEqual(submissions, [sent]);
    const creation = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
      && response.request().postDataJSON()?.command?.op === 'create');
    submit.resolve();
    const { reply } = await (await creation).json();
    assert.equal(reply.ok, true);
    const replyPlaceholders = reader.getByText(/^正在(?:准备|生成)回复…$/u);
    await status.waitFor({ state: 'hidden' });
    assert.equal(await replyPlaceholders.count(), 0);
    resumeSnapshots.resolve();
    await captured.waitFor();
    const requestDeadline = Date.now() + 30_000;
    while (!fixture.requests[0] && Date.now() < requestDeadline)
      await new Promise(resolve => setTimeout(resolve, 20));
    assert.ok(fixture.requests[0]);
    fixture.emit(0, 'The submission and reply are visible.\n\n');
    await reader.getByText('The submission and reply are visible.', { exact: true }).waitFor();
    assert.equal(await replyPlaceholders.count(), 0);
    fixture.finish(0);
    await taskIdle(fixture.running.service, reply.result.task_id);
    await reader.getByText('The submission and reply are visible.', { exact: true }).waitFor();

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
      await pending.waitFor();
      assert.equal(await status.count(), 0, 'The existing composer has one visible sending indicator');
      assert.equal(await pending.getAttribute('aria-busy'), 'true');
      assert.equal(await pending.evaluate(button => getComputedStyle(button, '::before').animationName), 'interactive-spin');
      assert.deepEqual(await pending.boundingBox(), previousBox);
    } finally {
      releaseMessage.resolve();
    }
    await reader.getByText(message, { exact: true }).waitFor();
    await status.waitFor({ state: 'hidden' });
    assert.equal(await replyPlaceholders.count(), 0);
    assert.deepEqual(assessments, []);
  } finally {
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
  await page.route('**/api/browser/command', async route => {
    const request = route.request().postDataJSON()?.command;
    if (request?.op !== 'create') return route.continue();
    const message = typeof request.message === 'string' ? request.message : request.message?.[0]?.text;
    if (message === refused) {
      await releaseRefusal.promise;
      const state = await page.request.get(new URL('/api/browser/state', page.url()).href).then(response => response.json());
      return route.fulfill({ status: 400, json: {
        ...state, reply: { ok: false, error: { code: 'test_refusal', message: refusal } },
      } });
    }
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
  await main.getByText(refusal).first().waitFor();
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

test('the project and Workspace open independently and cloud selection disables the worktree switch', async t => {
  const { page } = await browserFixture(t, { cloud: true });
  const menu = page.getByRole('dialog', { name: '工作环境', exact: true });
  const project = page.getByRole('dialog', { name: '选择项目', exact: true });
  const workspace = page.getByRole('dialog', { name: '工作目录', exact: true });
  for (const viewport of [{ width: 1280, height: 720 }, { width: 320, height: 620 }, { width: 740, height: 390 }]) {
    await page.setViewportSize(viewport);
    await creationProjectTrigger(page).click();
    await project.waitFor();
    assert.equal(await menu.isVisible(), false);
    assert.ok(insideViewport(await project.boundingBox(), viewport));
    await page.keyboard.press('Escape');
    await project.waitFor({ state: 'hidden' });

    await openCreationEnvironment(page);
    await menu.locator('button[data-logical-key="composer/workspace"]').click();
    await workspace.getByRole('textbox', { name: '目录路径', exact: true }).waitFor();
    assert.ok(insideViewport(await workspace.boundingBox(), viewport));
    await page.keyboard.press('Escape');
    await menu.waitFor();
    await page.keyboard.press('Escape');
    await menu.waitFor({ state: 'hidden' });
  }

  await openCreationEnvironment(page);
  const choice = (name, checked) => menu.getByRole('menuitemradio', { name, exact: true, checked });
  await choice('使用当前工作目录', true).waitFor();
  await choice('在腾讯云 CVM 上运行', false).click();
  await choice('在腾讯云 CVM 上运行', true).waitFor();
  assert.equal(await creationWorktreeSwitch(page).isDisabled(), true);
  await choice('使用当前工作目录', false).click();
  await choice('使用当前工作目录', true).waitFor();
});

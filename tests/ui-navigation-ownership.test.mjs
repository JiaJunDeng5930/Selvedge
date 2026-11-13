import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import path from 'node:path';
import { browserFixture, enableCreationWorktree, openCreationEnvironment } from './fixtures/browser.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((accept, fail) => { resolve = accept; reject = fail; });
  return { promise, resolve, reject };
}

function commandResponse(page, operation) {
  return page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === operation);
}

// Hold a real server response, so creation still runs through HTTP admission and the journal.
async function holdNextCommand(t, page, operation) {
  const started = deferred(), released = deferred(), completed = deferred();
  let held = false;
  t.after(() => released.resolve());
  await page.route('**/api/browser/command', async route => {
    if (held || route.request().postDataJSON()?.command?.op !== operation) return route.continue();
    held = true;
    try {
      const response = await route.fetch();
      const body = await response.json();
      assert.equal(body.reply.ok, true, JSON.stringify(body));
      started.resolve(body.reply.result);
      await released.promise;
      await route.fulfill({ response });
      completed.resolve();
    } catch (error) {
      started.reject(error);
      completed.reject(error);
      await route.abort();
    }
  });
  return { started: started.promise, async release() {
    released.resolve();
    await completed.promise;
    // The fetch continuation and its paint finish before checking who owns the selection.
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  } };
}

async function selectTask(fixture, taskId) {
  const { task } = await fixture.command({ op: 'read', task_id: taskId });
  await fixture.page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  await fixture.page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  return task;
}

async function openProjectTask(fixture, name, directory, createWorktree = false) {
  await fixture.command({ op: 'create_project', name, create_worktree: createWorktree,
    workspace: { roots: [directory], primary_root: directory } });
  await fixture.page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await fixture.page.getByRole('main').getByRole('button', { name, exact: true }).click();
  await fixture.page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();
  await fixture.page.getByRole('button', { name: 'Start task', exact: true }).waitFor();
}

async function repository(directory) {
  await mkdir(directory);
  await writeFile(path.join(directory, 'tracked.txt'), 'Navigation ownership acceptance.\n');
  const execute = promisify(execFile);
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  for (const arguments_ of [['init', '--initial-branch=main'], ['add', '.'], ['commit', '-m', 'Create acceptance repository']]) {
    await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
      '-c', 'user.name=Browser acceptance', '-c', 'user.email=browser@example.test', '-C', directory, ...arguments_], { env });
  }
}

async function home(page) {
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: '首页', exact: true }).click();
}

async function requestWork(page, name = '浏览器工作组', verifyName = false) {
  await page.getByRole('button', { name: /^对话范围 · / }).click();
  const menu = page.getByRole('menu', { name: '对话范围', exact: true });
  await menu.getByRole('menuitem', { name: '新建工作组', exact: true }).click();
  await menu.waitFor({ state: 'hidden' });
  const editor = page.getByRole('dialog', { name: '新建工作组', exact: true });
  const title = editor.getByRole('textbox', { name: '工作组名称', exact: true });
  const create = editor.getByRole('button', { name: '创建工作组', exact: true });
  await title.and(page.locator(':focus')).waitFor();
  assert.equal(await create.isDisabled(), true);
  if (verifyName) {
    assert.equal(await title.getAttribute('placeholder'), '请输入工作组名称');
    assert.equal(await title.getAttribute('aria-required'), 'true');
    const alerts = editor.getByRole('alert');
    const reason = editor.locator('[data-semantic-key="editor-commit-reason"]');
    const quiet = async () => {
      await alerts.waitFor({ state: 'hidden' });
      await reason.waitFor({ state: 'hidden' });
      assert.equal(await create.isDisabled(), true);
    };
    await quiet();
    await title.fill('\u3000 ');
    await quiet();
    await title.press('Enter');
    await quiet();
    await title.fill('组'.repeat(1366));
    await alerts.filter({ hasText: '工作组名称不能超过 4096 个 UTF-8 字节。' }).waitFor();
    assert.equal(await create.isDisabled(), true);
    await title.clear();
    await quiet();
  }
  await title.fill(name);
  await create.click();
  return editor;
}

async function startWork(page, name = '浏览器工作组', verifyName = false) {
  const response = commandResponse(page, 'create_work');
  const editor = await requestWork(page, name, verifyName);
  const { reply } = await (await response).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.equal(reply.result.name, name);
  await editor.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: `对话范围 · ${name}`, exact: true }).waitFor();
  await page.getByRole('combobox', { name: 'Task', exact: true }).waitFor();
  return reply.result;
}

async function sendSide(page, question) {
  const message = page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true });
  await message.fill(`/side ${question}`);
  await message.press('Enter');
}

test('conversation scope stays anchored and opens a separate named Work editor', async t => {
  const { page } = await browserFixture(t);
  const picker = page.getByRole('button', { name: '对话范围 · 全部对话', exact: true });
  const menu = page.getByRole('menu', { name: '对话范围', exact: true });
  for (const width of [1280, 390]) {
    await page.setViewportSize({ width, height: 844 });
    if (width === 390) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const anchor = await picker.boundingBox();
    await picker.click();
    await menu.getByRole('menuitemradio', { name: '全部对话', exact: true, checked: true })
      .and(page.locator(':focus')).waitFor();
    const bounds = await menu.boundingBox();
    assert.ok(anchor && bounds && bounds.x >= anchor.x - 12 && bounds.x <= anchor.x + 24);
    assert.ok(bounds.y >= anchor.y + anchor.height && bounds.y < anchor.y + anchor.height + 30);
    assert.ok(await menu.getByText('0 个对话', { exact: true })
      .evaluate(count => count.scrollWidth <= count.clientWidth), 'The complete scope count is visible');
    assert.equal(await menu.evaluate(node => getComputedStyle(node.closest('dialog'), '::backdrop').backgroundColor),
      'rgba(0, 0, 0, 0)');
    await page.keyboard.press('Escape');
    await menu.waitFor({ state: 'hidden' });
    await picker.and(page.locator(':focus')).waitFor();
  }
  await startWork(page, '产品调研', true);
});

test('late Work creation cannot replace newer creation, navigation, or sidebar visibility choices', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  await selectTask(fixture, task_id);

  let pending = await holdNextCommand(t, page, 'create_work');
  let editor = await requestWork(page);
  await pending.started;
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await page.getByRole('button', { name: '新建对话', exact: true }).click();
  await pending.release();
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Create this independent Task after the newer conversation request.');
  const created = commandResponse(page, 'create');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const { reply } = await (await created).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.equal((await command({ op: 'read', task_id: reply.result.task_id })).task.work_id, null,
    'The newer independent conversation must not inherit the pending Work');

  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'create_work');
  editor = await requestWork(page);
  await pending.started;
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByText('卡片看板', { exact: true }).isVisible(), true);

  await home(page);
  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'create_work');
  editor = await requestWork(page);
  await pending.started;
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await page.getByRole('button', { name: 'Collapse Task sidebar', exact: true }).click();
  await pending.release();
  assert.equal(await page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true }).isVisible(), true,
    'Collapsing navigation while creation is pending keeps the selected conversation');
  assert.equal(await page.getByRole('navigation', { name: 'Task tree', exact: true }).isVisible(), false);
  await page.getByRole('button', { name: 'Expand Task sidebar', exact: true }).click();

  pending = await holdNextCommand(t, page, 'create_work');
  editor = await requestWork(page);
  await pending.started;
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await page.setViewportSize({ width: 450, height: 900 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).click();
  await page.getByRole('dialog', { name: '对话', exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true }).isVisible(), true,
    'Opening the narrow Task list is newer navigation intent than a pending Work response');
  assert.equal(await page.getByRole('dialog', { name: '对话', exact: true }).isVisible(), true);
  await page.keyboard.press('Escape');

});

test('collapsed desktop navigation can search and start a conversation with the keyboard', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const { task_id } = await command({ op: 'create_idle', profile });
  await selectTask(fixture, task_id);
  const collapse = page.getByRole('button', { name: 'Collapse Task sidebar', exact: true });
  await collapse.focus();
  await page.keyboard.press('Enter');
  const shortcuts = page.getByRole('navigation', { name: '快捷操作', exact: true });
  const expand = shortcuts.getByRole('button', { name: 'Expand Task sidebar', exact: true });
  const create = shortcuts.getByRole('button', { name: '新建对话', exact: true });
  const search = shortcuts.getByRole('button', { name: '搜索对话', exact: true });
  const focused = page.locator(':focus');
  await expand.and(focused).waitFor();
  assert.equal(await page.getByRole('combobox', { name: 'Message', exact: true }).isVisible(), true);
  await page.keyboard.press('Tab');
  await create.and(focused).waitFor();
  await page.keyboard.press('Tab');
  await search.and(focused).waitFor();
  await page.keyboard.press('Space');
  await page.getByRole('heading', { name: '搜索对话', exact: true }).and(focused).waitFor();
  await page.keyboard.press('Tab');
  await page.getByRole('searchbox', { name: '标题或消息关键词', exact: true }).and(focused).waitFor();
  await create.click();
  const draft = page.getByRole('combobox', { name: 'Task', exact: true });
  await draft.and(focused).waitFor();
  await draft.fill('Keep the new conversation draft.');
  await expand.focus();
  await page.keyboard.press('Enter');
  await collapse.and(focused).waitFor();
  await shortcuts.waitFor({ state: 'hidden' });
  assert.equal(await draft.inputValue(), 'Keep the new conversation draft.');
});

test('late Side creation cannot reopen a side after newer navigation or Work creation', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  await selectTask(fixture, task_id);
  let pending = await holdNextCommand(t, page, 'open_side_conversation');
  await sendSide(page, 'Keep this first question in the captured side.');
  const older = await pending.started;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByText('卡片看板', { exact: true }).isVisible(), true);
  assert.equal(await page.getByRole('complementary', { name: 'Side conversation', exact: true }).count(), 0,
    'The old Side is created durably without being reopened over the new page');
  assert.ok(JSON.stringify(await command({ op: 'read', task_id: older.task_id })).includes('Keep this first question in the captured side.'));

  await home(page);
  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'open_side_conversation');
  await sendSide(page, 'Keep this second question in its own side.');
  await pending.started;
  const newer = await startWork(page);
  await pending.release();
  assert.equal(await page.getByRole('combobox', { name: 'Task', exact: true }).isVisible(), true);
  assert.equal(await page.getByRole('complementary', { name: 'Side conversation', exact: true }).count(), 0);
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('The newer Work still owns this editor.');
  const receipt = commandResponse(page, 'create_work_task');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const { reply } = await (await receipt).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.equal((await command({ op: 'read', task_id: reply.result.task_id })).task.work_id, newer.work_id);
});

// The endpoint itself produces each failure; the browser receives its unmodified diagnostic.
async function rejectNextCommand(page, operation, change) {
  const completed = deferred();
  let intercepted = false;
  await page.route('**/api/browser/command', async route => {
    const body = route.request().postDataJSON();
    if (intercepted || body.command?.op !== operation) return route.continue();
    intercepted = true;
    body.command = change(body.command);
    const response = await route.fetch({ postData: JSON.stringify(body) });
    const result = await response.json();
    // A command rejected before submission has no committed world or nested reply.
    const reply = result.reply ?? result;
    assert.equal(reply.ok, false, JSON.stringify(result));
    await route.fulfill({ response });
    completed.resolve(reply.error);
  });
  return completed.promise;
}

test('Work and Side creation failures display the exact server code and explanation', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  let failure = rejectNextCommand(page, 'create_work', command => ({ ...command, name: 'x'.repeat(4097) }));
  const editor = await requestWork(page);
  let diagnostic = await failure;
  assert.equal(diagnostic.code, 'command_not_submitted');
  const workAlert = editor.getByRole('alert').filter({ hasText: `${diagnostic.code}: ${diagnostic.message}` });
  await workAlert.waitFor();
  await page.setViewportSize({ width: 500, height: 800 });
  await page.locator('[data-surface-role="compact-header"]').waitFor();
  assert.equal(await workAlert.isVisible(), true,
    'A completed physical viewport observation must preserve the creation diagnostic');
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await page.setViewportSize({ width: 1280, height: 900 });

  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  await selectTask(fixture, task_id);
  failure = rejectNextCommand(page, 'open_side_conversation', command => ({ ...command, task_id: 999999 }));
  await sendSide(page, 'Show the parent creation failure.');
  diagnostic = await failure;
  assert.equal(diagnostic.code, 'task_not_found');
  await page.getByRole('alert').filter({ hasText: `${diagnostic.code}: ${diagnostic.message}` }).waitFor();
  assert.equal(await page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true }).isVisible(), true);
});

function gitResponse(page, primary) {
  return page.waitForResponse(response => response.url().endsWith('/api/browser/observation')
    && response.request().postDataJSON()?.kind === 'workspace-git'
    && response.request().postDataJSON().primary === primary);
}

async function replaceWorkspace(page, environment, directory) {
  await environment.locator('button[data-logical-key="composer/workspace"]').click();
  const dialog = page.getByRole('dialog', { name: '工作目录', exact: true });
  const remove = dialog.getByRole('button', { name: '移除目录', exact: true });
  while (await remove.count()) await remove.first().click();
  await dialog.getByRole('textbox', { name: '目录路径', exact: true }).fill(directory);
  await dialog.getByRole('button', { name: '添加目录', exact: true }).click();
  await dialog.getByText(directory, { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
  await environment.waitFor();
}

test('an unavailable Git worktree preserves Local intent and a stale Git reply cannot authorize another draft', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, root, command } = fixture;
  const source = path.join(root, 'Git primary');
  const nonGit = path.join(root, 'Plain primary');
  await repository(source);
  await mkdir(nonGit);
  const plain = gitResponse(page, nonGit);
  await openProjectTask(fixture, 'Legacy local worktree default', nonGit, true);
  const response = await plain;
  assert.equal(response.status(), 200);
  assert.equal((await response.json()).available, false);

  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  const ready = page.getByRole('button', { name: 'Start task', exact: true, disabled: false });
  const repositoryRequired = '请选择包含提交的 Git 仓库，或直接使用当前工作目录。';
  const required = page.getByRole('status').filter({ hasText: repositoryRequired });
  await page.setViewportSize({ width: 390, height: 700 });
  await message.fill('Keep my selected run environment.');
  await required.waitFor();
  assert.equal(await required.count(), 1, 'The composer exposes the reason with the gear menu closed');
  assert.equal(await start.isDisabled(), true);
  const environment = await openCreationEnvironment(page);
  const worktree = checked => environment.getByRole('menuitemcheckbox', { name: '新建工作树', exact: true, checked });
  const menuReason = environment.getByRole('status').filter({ hasText: repositoryRequired });
  await worktree(true).waitFor();
  await menuReason.waitFor();
  assert.equal(await required.count(), 1, 'Opening the menu moves the visible reason into the menu');
  const selectBounds = await worktree(true).boundingBox(), reasonBounds = await menuReason.boundingBox();
  assert.ok(selectBounds && reasonBounds && reasonBounds.y >= selectBounds.y + selectBounds.height
    && reasonBounds.x >= 0 && reasonBounds.x + reasonBounds.width <= 390);
  await worktree(true).click();
  await worktree(false).waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await ready.waitFor();
  await enableCreationWorktree(page);
  await menuReason.waitFor();
  assert.equal(await worktree(true).isVisible(), true, 'The explicit Local choice survives the failed Git check');
  await page.setViewportSize({ width: 1280, height: 900 });

  const started = deferred(), released = deferred(), completed = deferred();
  let held = false;
  t.after(() => released.resolve());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (held || request.kind !== 'workspace-git' || request.primary !== source) return route.continue();
    held = true;
    const response = await route.fetch();
    started.resolve(await response.json());
    await released.promise;
    await route.fulfill({ response });
    completed.resolve();
  });
  await replaceWorkspace(page, environment, source);
  assert.equal((await started.promise).available, true);
  await environment.getByRole('status').filter({ hasText: '正在检查工作目录是否支持 Git 工作树…' }).waitFor();
  await worktree(true).waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  assert.equal(await start.isDisabled(), true);
  await startWork(page);
  const newerMessage = 'Retain the newer default-workspace draft.';
  await message.fill(newerMessage);
  await enableCreationWorktree(page);
  const workspace = environment.locator('button[data-logical-key="composer/workspace"]');
  const primary = await workspace.innerText();
  assert.ok(primary.includes(root), primary);
  assert.ok(!primary.includes(source), primary);
  await menuReason.waitFor();
  released.resolve();
  await completed.promise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await worktree(true).isVisible(), true);
  assert.equal(await workspace.innerText(), primary);
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  assert.equal(await message.inputValue(), newerMessage);
  assert.equal(await start.isDisabled(), true, 'An old Git success cannot authorize a worktree in the newer non-Git draft');
  await required.waitFor();
  await openCreationEnvironment(page);
  await worktree(true).click();
  await worktree(false).waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await ready.waitFor();
  const creation = commandResponse(page, 'create_work_task');
  await start.click();
  const { reply } = await (await creation).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.deepEqual((await command({ op: 'list_worktrees' })).worktrees, []);
});

test('a verified Local choice creates a real managed Git worktree', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, root, command } = fixture;
  const source = path.join(root, 'Verified Git primary');
  await repository(source);
  const git = gitResponse(page, source);
  await openProjectTask(fixture, 'Verified Git project', source);
  assert.equal((await (await git).json()).available, true);
  const environment = await enableCreationWorktree(page);
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Start in the verified Git worktree.');
  const creation = commandResponse(page, 'create_worktree_task');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const { reply } = await (await creation).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  const taskId = reply.result.task_id;
  const deadline = Date.now() + 10_000;
  let checkout;
  do {
    checkout = await command({ op: 'read_worktree', task_id: taskId });
    assert.notEqual(checkout.status, 'create_failed', JSON.stringify(checkout));
    if (checkout.status === 'ready') break;
    await delay(20);
  } while (Date.now() < deadline);
  assert.equal(checkout.status, 'ready', JSON.stringify(checkout));
  assert.equal(checkout.source_root, source);
  assert.equal(checkout.backend, 'local');
  assert.notEqual(checkout.root, source);
  const [project] = await command({ op: 'list_projects' });
  assert.equal(project.create_worktree, true, 'A verified project default remains a deliberate saved preference');
});

test('a captured Git worktree submission survives another Project form taking over the Git check', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, root, command } = fixture;
  const source = path.join(root, 'Captured Git primary');
  await repository(source);
  const git = gitResponse(page, source);
  await openProjectTask(fixture, 'Project with a valid Git primary', source);
  assert.equal((await (await git).json()).available, true);
  const environment = await enableCreationWorktree(page);
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Start the captured Git worktree.');
  const preference = await holdNextCommand(t, page, 'update_project');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  await preference.started;

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '新建项目', exact: true }).click();
  const project = page.getByRole('dialog', { name: '新建项目', exact: true });
  await project.getByRole('checkbox', { name: '新对话默认创建 Git 工作树', exact: true }).check();
  await project.getByRole('status').filter({ hasText: '请先添加并选择主目录。' }).waitFor();

  const creation = commandResponse(page, 'create_worktree_task');
  await preference.release();
  const { reply } = await (await creation).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  const checkout = await command({ op: 'read_worktree', task_id: reply.result.task_id });
  assert.equal(checkout.source_root, source);
  assert.equal(checkout.backend, 'local');
  assert.equal(await project.isVisible(), true, 'The captured submission leaves the newer Project dialog in place');
});

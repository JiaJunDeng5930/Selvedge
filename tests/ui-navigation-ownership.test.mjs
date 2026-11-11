import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import path from 'node:path';
import { browserFixture } from './fixtures/browser.mjs';

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
    .getByRole('button', { name: 'Home', exact: true }).click();
}

async function requestWork(page) {
  await page.getByRole('button', { name: /^对话范围 · / }).click();
  await page.getByRole('dialog', { name: '对话范围', exact: true })
    .getByRole('button', { name: '新建工作组', exact: true }).click();
}

async function startWork(page) {
  const response = commandResponse(page, 'create_work');
  await requestWork(page);
  const { reply } = await (await response).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  await page.getByRole('combobox', { name: 'Task', exact: true }).waitFor();
  return reply.result;
}

async function sendSide(page, question) {
  const message = page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true });
  await message.fill(`/side ${question}`);
  await message.press('Enter');
}

test('late Work creation cannot replace newer creation, navigation, or sidebar visibility choices', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  await selectTask(fixture, task_id);

  let pending = await holdNextCommand(t, page, 'create_work');
  await requestWork(page);
  await pending.started;
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
  await requestWork(page);
  await pending.started;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByText('卡片看板', { exact: true }).isVisible(), true);

  await home(page);
  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'create_work');
  await requestWork(page);
  await pending.started;
  await page.getByRole('button', { name: 'Collapse Task sidebar', exact: true }).click();
  await pending.release();
  assert.equal(await page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true }).isVisible(), true,
    'Collapsing navigation while creation is pending keeps the selected conversation');
  assert.equal(await page.getByRole('navigation', { name: 'Task tree', exact: true }).isVisible(), false);
  await page.getByRole('button', { name: 'Expand Task sidebar', exact: true }).click();

  pending = await holdNextCommand(t, page, 'create_work');
  await requestWork(page);
  await pending.started;
  await page.setViewportSize({ width: 450, height: 900 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).click();
  await page.getByRole('dialog', { name: '对话', exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByRole('combobox', { name: 'Message', exact: true }).isVisible(), true,
    'Opening the narrow Task list is newer navigation intent than a pending Work response');
  assert.equal(await page.getByRole('dialog', { name: '对话', exact: true }).isVisible(), true);
  await page.keyboard.press('Escape');

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
  await requestWork(page);
  let diagnostic = await failure;
  assert.equal(diagnostic.code, 'command_not_submitted');
  await page.getByRole('alert').filter({ hasText: `${diagnostic.code}: ${diagnostic.message}` }).waitFor();
  await page.setViewportSize({ width: 500, height: 800 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
  assert.equal(await page.getByRole('alert').filter({ hasText: `${diagnostic.code}: ${diagnostic.message}` }).isVisible(), true,
    'A completed physical viewport observation must preserve the creation diagnostic');
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

async function replaceWorkspace(page, directory) {
  await page.locator('button[data-logical-key="composer/workspace"]').click();
  const dialog = page.getByRole('dialog', { name: 'Workspace', exact: true });
  const remove = dialog.getByRole('button', { name: 'Remove directory', exact: true });
  while (await remove.count()) await remove.first().click();
  await dialog.getByRole('textbox', { name: 'Directory path', exact: true }).fill(directory);
  await dialog.getByRole('button', { name: 'Add directory', exact: true }).click();
  await dialog.getByText(directory, { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
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

  const options = page.getByText('Project and run settings', { exact: true });
  const environment = page.getByRole('combobox', { name: 'Run environment', exact: true });
  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  const ready = page.getByRole('button', { name: 'Start task', exact: true, disabled: false });
  const repositoryRequired = 'Choose a Git repository with a commit, or use the working directory as is.';
  const required = page.getByRole('status').filter({ hasText: repositoryRequired });
  await page.setViewportSize({ width: 390, height: 700 });
  await message.fill('Keep my selected run environment.');
  await required.waitFor();
  assert.equal(await required.count(), 1, 'A collapsed settings disclosure still exposes the reason');
  assert.equal(await environment.isVisible(), false);
  assert.equal(await start.isDisabled(), true);
  await options.click();
  assert.equal(await environment.inputValue(), 'local');
  await required.waitFor();
  assert.equal(await required.count(), 1, 'Opening the settings moves the visible reason beside the selector');
  const selectBounds = await environment.boundingBox(), reasonBounds = await required.boundingBox();
  assert.ok(selectBounds && reasonBounds && reasonBounds.y >= selectBounds.y + selectBounds.height
    && reasonBounds.x >= 0 && reasonBounds.x + reasonBounds.width <= 390);
  await environment.selectOption({ label: 'Use working directory as is' });
  await ready.waitFor();
  await environment.selectOption({ label: 'New Git worktree on the Selvedge host' });
  await required.waitFor();
  assert.equal(await environment.inputValue(), 'local', 'The explicit Local choice is accepted even for the failed Git check');
  assert.equal(await start.isDisabled(), true);
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
  await replaceWorkspace(page, source);
  assert.equal((await started.promise).available, true);
  await page.getByRole('status').filter({ hasText: 'Checking the working directory for Git…' }).waitFor();
  assert.equal(await environment.inputValue(), 'local');
  assert.equal(await start.isDisabled(), true);
  await startWork(page);
  const newerMessage = 'Retain the newer default-workspace draft.';
  await message.fill(newerMessage);
  if (!(await environment.isVisible())) await options.click();
  const primary = await page.locator('button[data-logical-key="composer/workspace"]').innerText();
  assert.ok(primary.includes(root), primary);
  assert.ok(!primary.includes(source), primary);
  await environment.selectOption({ label: 'New Git worktree on the Selvedge host' });
  await required.waitFor();
  released.resolve();
  await completed.promise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await environment.inputValue(), 'local');
  assert.equal(await message.inputValue(), newerMessage);
  assert.equal(await page.locator('button[data-logical-key="composer/workspace"]').innerText(), primary);
  assert.equal(await start.isDisabled(), true, 'An old Git success cannot authorize a worktree in the newer non-Git draft');
  await required.waitFor();
  await environment.selectOption({ label: 'Use working directory as is' });
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
  await page.getByText('Project and run settings', { exact: true }).click();
  const environment = page.getByRole('combobox', { name: 'Run environment', exact: true });
  await environment.selectOption({ label: 'New Git worktree on the Selvedge host' });
  assert.equal(await environment.inputValue(), 'local');
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
  await page.getByText('Project and run settings', { exact: true }).click();
  await page.getByRole('combobox', { name: 'Run environment', exact: true })
    .selectOption({ label: 'New Git worktree on the Selvedge host' });
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

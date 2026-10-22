import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
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
  await fixture.page.getByRole('textbox', { name: 'Message', exact: true }).waitFor();
  return task;
}

async function openProjectTask(fixture, name, directory) {
  await fixture.command({ op: 'create_project', name, workspace: { roots: [directory], primary_root: directory } });
  await fixture.page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await fixture.page.getByRole('main').getByRole('button', { name, exact: true }).click();
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
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: 'Home', exact: true }).click();
}

async function startWork(page) {
  const response = commandResponse(page, 'create_work');
  await page.getByRole('button', { name: 'New Work', exact: true }).click();
  const { reply } = await (await response).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  await page.getByRole('textbox', { name: 'Task', exact: true }).waitFor();
  return reply.result;
}

async function sendSide(page, question) {
  const message = page.getByRole('main').getByRole('textbox', { name: 'Message', exact: true });
  await message.fill(`/side ${question}`);
  await message.press('Enter');
}

test('late Work creation cannot replace newer creation, navigation, or sidebar visibility choices', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  await selectTask(fixture, task_id);

  let pending = await holdNextCommand(t, page, 'create_work');
  await page.getByRole('button', { name: 'New Work', exact: true }).click();
  await pending.started;
  await page.getByRole('button', { name: '新建对话', exact: true }).click();
  await pending.release();
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('Create this independent Task after the newer conversation request.');
  const created = commandResponse(page, 'create');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const { reply } = await (await created).json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.equal((await command({ op: 'read', task_id: reply.result.task_id })).task.work_id, null,
    'The newer independent conversation must not inherit the pending Work');

  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'create_work');
  await page.getByRole('button', { name: 'New Work', exact: true }).click();
  await pending.started;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '智能体', exact: true }).click();
  await page.getByRole('main').getByText('Agents', { exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByText('Agents', { exact: true }).isVisible(), true);

  await home(page);
  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'create_work');
  await page.getByRole('button', { name: 'New Work', exact: true }).click();
  await pending.started;
  await page.getByRole('button', { name: 'Collapse Task sidebar', exact: true }).click();
  await pending.release();
  assert.equal(await page.getByRole('main').getByRole('textbox', { name: 'Message', exact: true }).isVisible(), true,
    'Collapsing navigation while creation is pending keeps the selected conversation');
  assert.equal(await page.getByRole('navigation', { name: 'Task tree', exact: true }).isVisible(), false);
  await page.getByRole('button', { name: 'Expand Task sidebar', exact: true }).click();

  pending = await holdNextCommand(t, page, 'create_work');
  await page.getByRole('button', { name: 'New Work', exact: true }).click();
  await pending.started;
  await page.setViewportSize({ width: 450, height: 900 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).click();
  await page.getByRole('dialog', { name: 'Task tree', exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByRole('textbox', { name: 'Message', exact: true }).isVisible(), true,
    'Opening the narrow Task list is newer navigation intent than a pending Work response');
  assert.equal(await page.getByRole('dialog', { name: 'Task tree', exact: true }).isVisible(), true);
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
    .getByRole('button', { name: '智能体', exact: true }).click();
  await page.getByRole('main').getByText('Agents', { exact: true }).waitFor();
  await pending.release();
  assert.equal(await page.getByRole('main').getByText('Agents', { exact: true }).isVisible(), true);
  assert.equal(await page.getByRole('button', { name: '关闭', exact: true }).count(), 0,
    'The old Side is created durably without being reopened over the new page');
  assert.ok(JSON.stringify(await command({ op: 'read', task_id: older.task_id })).includes('Keep this first question in the captured side.'));

  await home(page);
  await selectTask(fixture, task_id);
  pending = await holdNextCommand(t, page, 'open_side_conversation');
  await sendSide(page, 'Keep this second question in its own side.');
  await pending.started;
  const newer = await startWork(page);
  await pending.release();
  assert.equal(await page.getByRole('textbox', { name: 'Task', exact: true }).isVisible(), true);
  assert.equal(await page.getByRole('button', { name: '关闭', exact: true }).count(), 0);
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('The newer Work still owns this editor.');
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
    assert.equal(result.reply.ok, false, JSON.stringify(result));
    await route.fulfill({ response });
    completed.resolve(result.reply.error);
  });
  return completed.promise;
}

test('Work and Side creation failures display the exact server code and explanation', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  let failure = rejectNextCommand(page, 'create_work', command => ({ ...command, name: 'x'.repeat(4097) }));
  await page.getByRole('button', { name: 'New Work', exact: true }).click();
  let diagnostic = await failure;
  assert.equal(diagnostic.code, 'invalid_name');
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
  assert.equal(await page.getByRole('main').getByRole('textbox', { name: 'Message', exact: true }).isVisible(), true);
});

function gitResponse(page, primary) {
  return page.waitForResponse(response => response.url().endsWith('/api/browser/observation')
    && response.request().postDataJSON()?.kind === 'workspace-git'
    && response.request().postDataJSON().primary === primary);
}

async function replaceWorkspace(page, directory) {
  await page.getByRole('button', { name: 'Workspace', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Workspace', exact: true });
  const remove = dialog.getByRole('button', { name: 'Remove directory', exact: true });
  while (await remove.count()) await remove.first().click();
  await dialog.getByRole('textbox', { name: 'Add directory', exact: true }).fill(directory);
  await dialog.getByRole('button', { name: 'Add directory', exact: true }).click();
  await dialog.getByText(directory, { exact: true }).waitFor();
  await dialog.getByRole('button', { name: 'Done', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });
}

test('a real non-Git observation resets the local environment and an old Git reply cannot change a newer draft', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, root } = fixture;
  const source = path.join(root, 'Git primary');
  const nonGit = path.join(root, 'Plain primary');
  await repository(source);
  await mkdir(nonGit);
  const observed = gitResponse(page, source);
  await openProjectTask(fixture, 'Observed Git project', source);
  await (await observed).finished();
  const environment = page.getByRole('combobox', { name: 'Task environment', exact: true });
  await environment.selectOption({ label: 'Local worktree' });
  assert.equal(await environment.inputValue(), 'local');

  const plain = gitResponse(page, nonGit);
  await replaceWorkspace(page, nonGit);
  const response = await plain;
  assert.equal(response.status(), 200, await response.text());
  await page.waitForFunction(() => document.querySelector('select[aria-label="Task environment"]')?.value === 'current');
  assert.equal(await environment.inputValue(), 'current', 'A real observation of the replacement primary removes the obsolete local choice');

  const started = deferred(), released = deferred(), completed = deferred();
  let held = false;
  t.after(() => released.resolve());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (held || request.kind !== 'workspace-git' || request.primary !== source) return route.continue();
    held = true;
    const response = await route.fetch();
    started.resolve();
    await released.promise;
    await route.fulfill({ response });
    completed.resolve();
  });
  await replaceWorkspace(page, source);
  await started.promise;
  await startWork(page);
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('Retain the newer default-workspace draft.');
  const primary = await page.getByRole('button', { name: 'Workspace', exact: true }).innerText();
  assert.ok(primary.includes(root), primary);
  assert.ok(!primary.includes(source), primary);
  released.resolve();
  await completed.promise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await environment.inputValue(), 'current');
  assert.equal(await page.getByRole('textbox', { name: 'Task', exact: true }).inputValue(), 'Retain the newer default-workspace draft.');
  assert.equal(await page.getByRole('button', { name: 'Workspace', exact: true }).innerText(), primary);
  await environment.selectOption({ label: 'Local worktree' });
  assert.equal(await environment.inputValue(), 'current', 'The stale Git success must not authorize Local worktree for a non-Git draft');
});

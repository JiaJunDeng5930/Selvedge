import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { browserFixture, creationWorktreeSwitch, openCreationEnvironment } from './fixtures/browser.mjs';

const execute = promisify(execFile);
const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
const git = (root, ...args) => execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
  '-c', 'user.name=Cloud setup fixture', '-c', 'user.email=cloud-setup@example.test', '-C', root, ...args], { env });
const addRemote = root => git(root, 'remote', 'add', 'origin', 'https://github.com/selvedge-fixtures/source.git');

async function repository(root) {
  await mkdir(root, { recursive: true });
  await git(root, 'init', '--initial-branch=main');
  await git(root, 'commit', '--allow-empty', '-m', 'Cloud setup fixture');
}

function cloudResponse(page, primary) {
  return page.waitForResponse(response => response.url().endsWith('/api/browser/observation')
    && response.request().postDataJSON()?.kind === 'cloud-repository'
    && response.request().postDataJSON().primary === primary);
}

async function chooseCloud(page) {
  const settings = await openCreationEnvironment(page);
  await settings.getByRole('menuitemradio', { name: '在腾讯云 CVM 上运行', exact: true }).click();
  assert.equal(await creationWorktreeSwitch(page).isDisabled(), true);
  return settings;
}

test('without configured cloud, the composer offers current and host Git directories', async t => {
  const { page, running, command, profile } = await browserFixture(t);
  const probes = [];
  page.on('request', request => {
    if (request.url().endsWith('/api/browser/observation') && request.postDataJSON()?.kind === 'cloud-repository') probes.push(request);
  });
  const settings = await openCreationEnvironment(page);
  await creationWorktreeSwitch(page).waitFor();
  assert.equal(await settings.getByText(/腾讯云 CVM/).count(), 0);
  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Start a host conversation.');
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(probes.length, 0);

  const response = await fetch(`${running.address}/api/commands`, {
    method: 'POST', headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ op: 'create_workspace_task', backend: 'tencent_cvm', profile, message: 'Attempt an unavailable cloud run.' }),
  });
  assert.equal(response.status, 400);
  const reply = await response.json();
  assert.equal(reply.ok, false);
  assert.equal(reply.error.code, 'command_not_submitted');
  assert.equal(reply.error.message, 'Tencent Cloud CVM is not configured on this Selvedge host');
  assert.deepEqual((await command({ op: 'list' })).tasks, []);
  assert.deepEqual((await command({ op: 'list_worktrees' })).worktrees, []);
});

test('Tencent Cloud checks the working directory GitHub source before a message is entered', { timeout: 60000 }, async t => {
  const { page, root } = await browserFixture(t, { cloud: true });
  await repository(root);
  const settings = await chooseCloud(page);
  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  const reason = settings.getByRole('status').filter({ hasText: '请选择包含提交和 GitHub 远端的 Git 仓库中的主目录。' });
  await reason.waitFor();
  await settings.getByText(/请推送包含 \.selvedge\/env\.sh 的当前提交/).waitFor();
  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  await message.fill('Keep this draft while I configure the GitHub source.');
  assert.equal(await start.isDisabled(), true);
  await addRemote(root);
  await openCreationEnvironment(page);
  await settings.getByRole('button', { name: '重新检查', exact: true }).click();
  await reason.waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(await message.inputValue(), 'Keep this draft while I configure the GitHub source.');
});

test('Tencent Cloud uses the project primary and rejects a stale check after a working directory override', { timeout: 60000 }, async t => {
  const { page, root, command } = await browserFixture(t, { cloud: true });
  const source = path.join(root, 'Project GitHub source');
  const override = path.join(root, 'Different GitHub repository');
  await repository(source);
  await addRemote(source);
  await repository(override);
  await addRemote(override);
  const { project_id } = await command({ op: 'create_project', name: 'Cloud setup project',
    workspace: { roots: [source], primary_root: source } });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'Cloud setup project', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();

  const observed = Promise.withResolvers(), release = Promise.withResolvers(), delivered = Promise.withResolvers();
  let held = false;
  t.after(() => release.resolve());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (request?.kind !== 'cloud-repository') return route.continue();
    if (held || request.primary !== source) return route.continue();
    held = true;
    const response = await route.fetch();
    observed.resolve();
    await release.promise;
    await route.fulfill({ response });
    delivered.resolve();
  });
  const settings = await chooseCloud(page);
  await observed.promise;
  await settings.getByRole('status').filter({ hasText: '正在检查 GitHub 仓库…' }).waitFor();
  await settings.getByText(/腾讯云会克隆项目主目录对应的 GitHub 仓库/).waitFor();

  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  await message.fill('Keep this project conversation draft.');
  await openCreationEnvironment(page);
  await settings.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: '工作目录', exact: true });
  await workspace.getByRole('button', { name: '移除目录', exact: true }).click();
  await workspace.getByRole('textbox', { name: '目录路径', exact: true }).fill(override);
  await workspace.getByRole('button', { name: '添加目录', exact: true }).click();
  await workspace.getByText(override, { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });

  const mismatch = settings.getByRole('status').filter({ hasText: "云端运行使用项目主目录。" });
  await mismatch.waitFor();
  release.resolve();
  await delivered.promise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await mismatch.isVisible(), true);

  const submissions = [];
  await page.route('**/api/browser/command', route => {
    const submission = route.request().postDataJSON()?.command;
    if (submission?.op !== 'create_workspace_task') return route.continue();
    submissions.push(submission);
    return route.abort();
  });
  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  await message.press('Enter');

  await openCreationEnvironment(page);
  await settings.getByRole('button', { name: '使用项目目录…', exact: true }).click();
  const refreshed = cloudResponse(page, source);
  await workspace.getByRole('button', { name: '使用继承的工作目录', exact: true }).click();
  assert.equal((await (await refreshed).json()).available, true);
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await settings.waitFor();
  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(await message.inputValue(), 'Keep this project conversation draft.');
  assert.deepEqual(submissions, [], 'Submitting with the override does not send a cloud command');
  const submitted = page.waitForRequest(request => request.url().endsWith('/api/browser/command')
    && request.postDataJSON()?.command?.op === 'create_workspace_task');
  await message.press('Enter');
  const { backend, settings: submittedSettings } = (await submitted).postDataJSON().command;
  assert.equal(backend, 'tencent_cvm');
  assert.equal(submittedSettings.project_id, project_id);
});

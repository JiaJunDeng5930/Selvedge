import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { browserFixture } from './fixtures/browser.mjs';

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

function cloudSettings(page) {
  return page.getByRole('group', { name: /^Project and run settings · / });
}

async function chooseCloud(page) {
  const settings = cloudSettings(page);
  const environment = settings.getByRole('combobox', { name: 'Run environment', exact: true });
  if (!(await environment.isVisible())) await settings.locator('summary').click();
  await environment.selectOption({ label: 'Run on Tencent Cloud CVM' });
  return settings;
}

test('without configured cloud, the composer offers current and host Git directories', async t => {
  const { page, running, command, profile } = await browserFixture(t);
  const probes = [];
  page.on('request', request => {
    if (request.url().endsWith('/api/browser/observation') && request.postDataJSON()?.kind === 'cloud-repository') probes.push(request);
  });
  const settings = cloudSettings(page);
  await settings.locator('summary').click();
  const choices = settings.getByRole('combobox', { name: 'Run environment', exact: true }).getByRole('option');
  assert.deepEqual(await choices.allTextContents(), ['Use working directory as is', 'New Git worktree on the Selvedge host']);
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
  const { page, root, command, requests } = await browserFixture(t, { cloud: true });
  await repository(root);
  const initial = cloudResponse(page, root);
  const settings = await chooseCloud(page);
  assert.equal((await (await initial).json()).available, false, 'A committed repository without a GitHub remote is not a cloud source');
  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  const reason = settings.getByRole('status').filter({ hasText: 'Choose a primary directory in a Git repository with a commit and a GitHub remote.' });
  await reason.waitFor();
  assert.equal(await message.inputValue(), '');
  assert.equal(await start.isDisabled(), true);
  await settings.getByText(/Push the current commit with \.selvedge\/env\.sh/).waitFor();

  await settings.getByRole('button', { name: 'Choose working directory…', exact: true }).click();
  const workspace = page.getByRole('dialog', { name: 'Workspace', exact: true });
  await workspace.getByRole('button', { name: 'Browse…', exact: true }).click();
  const picker = page.getByRole('dialog', { name: 'Choose a directory on the Selvedge host', exact: true });
  await picker.getByText('Tencent Cloud clones the GitHub repository from the primary directory on the Selvedge host.', { exact: true }).waitFor();
  await picker.getByRole('button', { name: 'Cancel', exact: true }).click();
  await picker.waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });

  await message.fill('Keep this draft while I configure the GitHub source.');
  assert.equal(await start.isDisabled(), true);
  await addRemote(root);
  const rechecked = cloudResponse(page, root);
  await settings.getByRole('button', { name: 'Check again', exact: true }).click();
  assert.equal((await (await rechecked).json()).available, true);
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(await message.inputValue(), 'Keep this draft while I configure the GitHub source.');
  assert.equal(requests.length, 0);
  assert.deepEqual((await command({ op: 'list_worktrees' })).worktrees, []);
});

test('Tencent Cloud uses the project primary and rejects a stale check after a working directory override', { timeout: 60000 }, async t => {
  const { page, root, command, requests } = await browserFixture(t, { cloud: true });
  const source = path.join(root, 'Project GitHub source');
  const override = path.join(root, 'Different GitHub repository');
  await repository(source);
  await addRemote(source);
  await repository(override);
  await addRemote(override);
  await command({ op: 'create_project', name: 'Cloud setup project', workspace: { roots: [source], primary_root: source } });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'Cloud setup project', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();

  const observed = Promise.withResolvers(), release = Promise.withResolvers(), delivered = Promise.withResolvers();
  let held = false;
  const observedPaths = [];
  t.after(() => release.resolve());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (request?.kind !== 'cloud-repository') return route.continue();
    observedPaths.push(request.primary);
    if (held || request.primary !== source) return route.continue();
    held = true;
    const response = await route.fetch();
    observed.resolve(await response.json());
    await release.promise;
    await route.fulfill({ response });
    delivered.resolve();
  });
  const settings = await chooseCloud(page);
  assert.equal((await observed.promise).available, true);
  await settings.getByRole('status').filter({ hasText: 'Checking the GitHub source…' }).waitFor();
  await settings.getByText(/clones the GitHub repository from the project's primary directory/).waitFor();

  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  await message.fill('Keep this project conversation draft.');
  await page.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: 'Workspace', exact: true });
  await workspace.getByRole('button', { name: 'Remove directory', exact: true }).click();
  await workspace.getByRole('textbox', { name: 'Directory path', exact: true }).fill(override);
  await workspace.getByRole('button', { name: 'Add directory', exact: true }).click();
  await workspace.getByText(override, { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });

  const mismatch = settings.getByRole('status').filter({ hasText: "Cloud runs use the project's primary directory." });
  await mismatch.waitFor();
  release.resolve();
  await delivered.promise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await mismatch.isVisible(), true);
  assert.equal(await page.getByRole('button', { name: 'Start task', exact: true }).isDisabled(), true);
  assert.deepEqual(observedPaths, [source], 'The override is not probed as the project GitHub source');

  await settings.getByRole('button', { name: 'Use project directory…', exact: true }).click();
  const refreshed = cloudResponse(page, source);
  await workspace.getByRole('button', { name: 'Use inherited workspace', exact: true }).click();
  assert.equal((await (await refreshed).json()).available, true);
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(await message.inputValue(), 'Keep this project conversation draft.');
  assert.equal(requests.length, 0);
  assert.deepEqual((await command({ op: 'list_worktrees' })).worktrees, []);
});

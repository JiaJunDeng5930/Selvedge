import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { browserFixture, enableCreationWorktree, openCreationEnvironment } from './fixtures/browser.mjs';

test('the English workspace picker identifies host directories and supports keyboard navigation', async t => {
  const { page, root } = await browserFixture(t);
  const folder = 'Selected workspace';
  const directory = path.join(root, folder);
  await mkdir(path.join(directory, 'Nested folder'), { recursive: true });

  const environment = await openCreationEnvironment(page);
  await environment.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: 'Workspace', exact: true });
  const browse = workspace.getByRole('button', { name: 'Browse…', exact: true });
  await browse.press('Enter');

  const picker = page.getByRole('dialog', { name: 'Choose a directory on the Selvedge host', exact: true });
  const location = picker.getByRole('textbox', { name: 'Directory', exact: true });
  const folderButton = picker.getByRole('button', { name: folder, exact: true });
  await folderButton.waitFor();
  assert.equal(await location.inputValue(), root);
  assert.equal(await picker.getByRole('status').count(), 0, 'Ordinary browsing has no Git status');
  const nested = picker.getByRole('button', { name: 'Nested folder', exact: true });
  await folderButton.press('Enter');
  await nested.waitFor();
  assert.equal(await location.inputValue(), directory);

  await picker.getByRole('button', { name: 'Parent directory', exact: true }).press('Enter');
  await folderButton.waitFor();
  assert.equal(await location.inputValue(), root);
  const choose = picker.getByRole('button', { name: 'Use this directory', exact: true });
  const unvisited = picker.getByRole('status').filter({ hasText: 'Press Enter or click Go to open the entered directory.' });
  await location.fill(directory);
  await unvisited.waitFor();
  assert.equal(await choose.isDisabled(), true);
  await location.fill(root);
  await unvisited.waitFor({ state: 'hidden' });
  assert.equal(await choose.isEnabled(), true);
  await location.fill(directory);
  await unvisited.waitFor();
  await location.press('Enter');
  await nested.waitFor();
  await unvisited.waitFor({ state: 'hidden' });
  await choose.press('Enter');
  await picker.waitFor({ state: 'hidden' });
  await workspace.getByText(directory, { exact: true }).waitFor();
  assert.equal(await browse.evaluate(button => document.activeElement === button), true);
  await workspace.getByRole('button', { name: '返回工作环境', exact: true }).press('Enter');
  await workspace.waitFor({ state: 'hidden' });
  await environment.waitFor();
});

test('a local worktree picker checks the visited directory before selecting a primary', { timeout: 60000 }, async t => {
  const { page, root } = await browserFixture(t);
  const ordinary = path.join(root, 'Plain directory');
  const repository = path.join(root, 'Git directory');
  await mkdir(ordinary);
  await mkdir(repository);
  const execute = promisify(execFile);
  const git = (...args) => execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Directory fixture', '-c', 'user.email=directory@example.test', '-C', repository, ...args]);
  await git('init', '--initial-branch=main');
  await git('commit', '--allow-empty', '-m', 'Initial commit');

  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Open this conversation in a Git worktree.');
  const environment = await enableCreationWorktree(page);
  await environment.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: 'Workspace', exact: true });
  await workspace.getByRole('button', { name: 'Remove directory', exact: true }).click();
  const browse = workspace.getByRole('button', { name: 'Browse…', exact: true });
  await browse.click();

  const picker = page.getByRole('dialog', { name: 'Choose a directory on the Selvedge host', exact: true });
  const location = picker.getByRole('textbox', { name: 'Directory', exact: true });
  const choose = picker.getByRole('button', { name: 'Use this directory', exact: true });
  const status = message => picker.getByRole('status').filter({ hasText: message });
  const rejected = status('The primary directory must be in a Git repository with a commit.');
  const eligible = status('This directory can be the primary for a Git worktree.');
  await rejected.waitFor();
  assert.equal(await choose.isDisabled(), true);

  let gitChecks = 0;
  const requested = Promise.withResolvers(), release = Promise.withResolvers(), delivered = Promise.withResolvers();
  t.after(() => release.resolve());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (request?.kind !== 'workspace-git' || request.primary !== repository) return route.continue();
    gitChecks++;
    if (gitChecks === 3) return route.abort('failed');
    if (gitChecks > 1) return route.continue();
    const response = await route.fetch();
    requested.resolve(await response.json());
    await release.promise;
    await route.fulfill({ response });
    delivered.resolve();
  });

  await location.fill(repository);
  await status('Press Enter or click Go to open the entered directory.').waitFor();
  assert.equal(await rejected.count(), 0);
  assert.equal(await choose.isDisabled(), true);
  await location.press('Enter');
  assert.equal((await requested.promise).available, true);
  await status('Checking this directory for Git worktrees…').waitFor();
  assert.equal(await choose.isDisabled(), true);

  await location.fill(ordinary);
  await location.press('Enter');
  await rejected.waitFor();
  release.resolve();
  await delivered.promise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.equal(await choose.isDisabled(), true, 'An old positive result cannot enable this non-Git directory');

  await location.fill(repository);
  await location.press('Enter');
  await eligible.waitFor();
  assert.equal(gitChecks, 2);
  await location.press('Enter');
  await status('Could not check this directory for Git worktrees.').waitFor();
  assert.equal(await choose.isDisabled(), true);
  await picker.getByRole('button', { name: 'Retry Git check', exact: true }).click();
  await eligible.waitFor();
  await choose.click();
  await picker.waitFor({ state: 'hidden' });
  await workspace.getByText(repository, { exact: true }).waitFor();
  assert.equal(await browse.evaluate(button => document.activeElement === button), true);
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await environment.waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(gitChecks, 4, 'The selected primary reuses its verified Git result');
});

test('a failed directory visit keeps the address editable and can return to the last listed directory', { timeout: 60000 }, async t => {
  const { page, root, command } = await browserFixture(t);
  const directory = path.join(root, 'Previous directory');
  const corrected = path.join(root, 'Corrected directory');
  const missing = path.join(directory, 'Missing directory');
  const file = path.join(directory, 'Ordinary file.txt');
  await mkdir(path.join(directory, 'Visible child'), { recursive: true });
  await mkdir(corrected);
  await writeFile(file, 'A file cannot be selected as a directory.');

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '新建项目', exact: true }).click();
  const project = page.getByRole('dialog', { name: '新建项目', exact: true });
  const name = project.getByRole('textbox', { name: '项目名称', exact: true });
  const browse = project.getByRole('button', { name: '浏览…', exact: true });
  await name.fill('目录恢复测试');
  await browse.click();

  const picker = page.getByRole('dialog', { name: '选择 Selvedge 主机上的目录', exact: true });
  const location = picker.getByRole('textbox', { name: '目录路径', exact: true });
  const go = picker.getByRole('button', { name: '前往', exact: true });
  const choose = picker.getByRole('button', { name: '使用此目录', exact: true });
  const previous = picker.getByRole('button', { name: '返回上一个可用目录', exact: true });
  const child = picker.getByRole('button', { name: 'Visible child', exact: true });
  const missingMessage = '找不到这个目录，请检查路径。';
  const failure = message => picker.getByRole('alert').filter({ hasText: message });
  const addressFocused = () => location.evaluate(input => document.activeElement === input);
  const listingResponse = address => page.waitForResponse(response => response.url().endsWith('/api/browser/observation')
    && response.request().postDataJSON()?.kind === 'browse-directories'
    && response.request().postDataJSON().path === address);
  await choose.waitFor();

  const entered = `${directory}/.`;
  const observed = Promise.withResolvers(), release = Promise.withResolvers();
  let interrupted = false;
  t.after(() => release.resolve());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (request?.kind !== 'browse-directories') return route.continue();
    if (!interrupted && request.path === corrected) {
      interrupted = true;
      return route.abort('failed');
    }
    if (request.path !== entered) return route.continue();
    const response = await route.fetch();
    observed.resolve(await response.json());
    await release.promise;
    await route.fulfill({ response });
  });
  await location.fill(entered);
  await location.press('Enter');
  assert.equal((await observed.promise).path, directory);
  await location.fill(missing);
  release.resolve();
  await child.waitFor();
  assert.equal(await location.inputValue(), missing, 'A listing receipt cannot overwrite a newer address edit');
  assert.equal(await choose.isDisabled(), true, 'An edited address cannot confirm the earlier listing');

  const missingResponse = listingResponse(missing);
  await go.click();
  const missingOutcome = await (await missingResponse).json();
  assert.equal(missingOutcome.ok, false);
  assert.equal(typeof missingOutcome.error, 'string');
  assert.equal(missingOutcome.errno, 'ENOENT');
  assert.equal(await failure(missingMessage).innerText(), missingMessage);
  assert.equal(await location.inputValue(), missing);
  assert.equal(await location.isEditable(), true);
  assert.equal(await addressFocused(), true);
  assert.equal(await go.isEnabled(), true);
  assert.equal(await picker.getByRole('button', { name: '重试', exact: true }).count(), 0);

  const anotherMissing = path.join(directory, 'Another missing directory');
  const anotherResponse = listingResponse(anotherMissing);
  await location.fill(anotherMissing);
  await location.press('Enter');
  await anotherResponse;
  await failure(missingMessage).waitFor();
  const returnRequest = page.waitForRequest(request => {
    if (!request.url().endsWith('/api/browser/observation')) return false;
    const body = request.postDataJSON();
    return body?.kind === 'browse-directories' && body.path === directory;
  });
  await previous.press('Enter');
  await returnRequest;
  await child.waitFor();
  assert.equal(await location.inputValue(), directory);
  assert.equal(await addressFocused(), true);

  const fileMessage = '这个路径不是目录。';
  const fileResponse = listingResponse(file);
  await location.fill(file);
  await location.press('Enter');
  assert.equal((await (await fileResponse).json()).errno, 'ENOTDIR');
  assert.equal(await failure(fileMessage).innerText(), fileMessage);
  assert.equal(await location.inputValue(), file);

  const transportMessage = '无法读取目录，请检查路径或稍后再试。';
  await location.fill(corrected);
  await location.press('Enter');
  assert.equal(await failure(transportMessage).innerText(), transportMessage);
  assert.equal(await location.inputValue(), corrected);
  await location.press('Enter');
  await choose.click();
  await picker.waitFor({ state: 'hidden' });
  await project.getByRole('region', { name: corrected, exact: true }).waitFor();
  assert.equal(await browse.evaluate(button => document.activeElement === button), true);
  await project.getByRole('button', { name: '创建项目', exact: true }).click();
  await project.waitFor({ state: 'hidden' });
  const [saved] = await command({ op: 'list_projects' });
  assert.equal(saved.name, '目录恢复测试');
  assert.deepEqual(saved.workspace, { roots: [corrected], primary_root: corrected });
});

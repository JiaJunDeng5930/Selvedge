import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { browserFixture } from './fixtures/browser.mjs';

test('the English workspace picker identifies host directories and supports keyboard navigation', async t => {
  const { page, root } = await browserFixture(t);
  const folder = 'Selected workspace';
  const directory = path.join(root, folder);
  await mkdir(path.join(directory, 'Nested folder'), { recursive: true });

  await page.getByText('Project and run settings', { exact: true }).click();
  await page.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: 'Workspace', exact: true });
  const browse = workspace.getByRole('button', { name: 'Browse…', exact: true });
  await browse.press('Enter');

  const picker = page.getByRole('dialog', { name: 'Choose a directory on the Selvedge host', exact: true });
  const location = picker.getByRole('textbox', { name: 'Directory', exact: true });
  assert.equal(await location.inputValue(), root);
  assert.equal(await picker.getByRole('status').count(), 0, 'Ordinary browsing has no Git status');
  const nested = picker.getByRole('button', { name: 'Nested folder', exact: true });
  const folderButton = picker.getByRole('button', { name: folder, exact: true });
  await folderButton.press('Enter');
  await nested.waitFor();
  assert.equal(await location.inputValue(), directory);

  await picker.getByRole('button', { name: 'Parent directory', exact: true }).press('Enter');
  await folderButton.waitFor();
  assert.equal(await location.inputValue(), root);
  await location.fill(directory);
  await location.press('Enter');
  await nested.waitFor();
  await picker.getByRole('button', { name: 'Use this directory', exact: true }).press('Enter');
  await picker.waitFor({ state: 'hidden' });
  await workspace.getByText(directory, { exact: true }).waitFor();
  assert.equal(await browse.evaluate(button => document.activeElement === button), true);
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
  await page.getByText('Project and run settings', { exact: true }).click();
  await page.getByRole('combobox', { name: 'Run environment', exact: true })
    .selectOption({ label: 'New Git worktree on the Selvedge host' });
  await page.locator('button[data-logical-key="composer/workspace"]').click();
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
  await status('Open the entered directory before selecting it.').waitFor();
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
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  assert.equal(gitChecks, 4, 'The selected primary reuses its verified Git result');
});

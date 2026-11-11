import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
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

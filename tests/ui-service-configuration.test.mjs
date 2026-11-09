import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('Settings applies configuration edits and shows their saved values after reload', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const instructions = 'Keep headings concise.\n保留中文。';
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const editInstructions = dialog.getByRole('button', { name: 'Edit instructions', exact: true });
  const instructionsInput = dialog.getByRole('textbox', { name: 'Instructions', exact: true });
  const listenAddress = dialog.getByRole('combobox', { name: 'Listen address', exact: true });
  const general = dialog.getByRole('radio', { name: 'General', exact: true });
  const connection = dialog.getByRole('radio', { name: 'Connection', exact: true });

  async function openSettings() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
  }

  async function applyChange() {
    await dialog.getByRole('button', { name: 'Apply configuration change', exact: true }).click();
    await dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();
  }

  await openSettings();
  await editInstructions.click();
  await instructionsInput.fill(instructions);
  await connection.click();
  await listenAddress.waitFor();
  await general.click();
  assert.equal(await instructionsInput.inputValue(), instructions);
  await applyChange();

  await connection.click();
  await listenAddress.selectOption({ label: '::1' });
  await applyChange();

  await page.reload();
  await openSettings();
  await editInstructions.click();
  assert.equal(await instructionsInput.inputValue(), instructions);

  await connection.click();
  assert.equal(await listenAddress.locator('option:checked').textContent(), '::1');
});

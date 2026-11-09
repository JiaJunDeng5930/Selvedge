import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('Settings applies a configuration edit and shows the saved value after reload', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const instructions = 'Keep headings concise.\n保留中文。';

  async function openConfiguration() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
    await dialog.getByRole('button', { name: 'Edit service configuration', exact: true }).click();
    return dialog;
  }

  let dialog = await openConfiguration();
  await dialog.getByRole('combobox', { name: 'Configuration item', exact: true })
    .selectOption({ label: 'instructions' });
  await dialog.getByRole('textbox', { name: 'Configuration value', exact: true }).fill(instructions);
  await dialog.getByRole('button', { name: 'Apply configuration change', exact: true }).click();
  await dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();

  await dialog.getByRole('combobox', { name: 'Configuration item', exact: true })
    .selectOption({ label: 'host' });
  await dialog.getByRole('combobox', { name: 'Configuration value', exact: true })
    .selectOption({ label: '::1' });
  await dialog.getByRole('button', { name: 'Apply configuration change', exact: true }).click();
  await dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();

  await page.reload();
  dialog = await openConfiguration();
  await dialog.getByRole('combobox', { name: 'Configuration item', exact: true })
    .selectOption({ label: 'instructions' });
  assert.equal(await dialog.getByRole('textbox', { name: 'Configuration value', exact: true }).inputValue(),
    instructions);
  await dialog.getByRole('combobox', { name: 'Configuration item', exact: true })
    .selectOption({ label: 'host' });
  assert.equal(await dialog.getByRole('combobox', { name: 'Configuration value', exact: true })
    .locator('option:checked').textContent(), '::1');
});

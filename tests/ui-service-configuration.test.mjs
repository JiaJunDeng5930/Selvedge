import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('Settings applies configuration edits and shows their saved values after reload', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const instructions = 'Keep headings concise.\n保留中文。';
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const instructionsInput = dialog.getByRole('textbox', { name: 'Instructions', exact: true });
  const listenAddress = dialog.getByRole('combobox', { name: 'Listen address', exact: true });
  const general = dialog.getByRole('radio', { name: 'General', exact: true });
  const connection = dialog.getByRole('radio', { name: 'Connection', exact: true });

  async function openSettings() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
  }

  async function applyChange(label) {
    await dialog.getByRole('button', { name: label, exact: true }).click();
    await dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();
  }

  await openSettings();
  await instructionsInput.fill(instructions);
  await connection.click();
  await listenAddress.waitFor();
  await general.click();
  assert.equal(await instructionsInput.inputValue(), instructions);
  await applyChange('Save instructions');

  await connection.click();
  await listenAddress.selectOption({ label: '::1' });
  await applyChange('Save address');

  await page.reload();
  await openSettings();
  assert.equal(await instructionsInput.inputValue(), instructions);

  await connection.click();
  assert.equal(await listenAddress.locator('option:checked').textContent(), '::1');
});

test('Model profiles open as fields and persist an edited model name', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const model = dialog.getByRole('textbox', { name: 'Model', exact: true });
  await page.setViewportSize({ width: 629, height: 588 });

  async function openProfile() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
    await dialog.getByRole('radio', { name: 'Models', exact: true }).click();
    await dialog.getByRole('button', { name: 'Edit demo', exact: true }).click();
  }

  await openProfile();
  assert.equal(await dialog.locator('textarea').count(), 0);
  await dialog.getByRole('heading', { name: 'Models', exact: true }).waitFor();
  assert.equal(await dialog.getByRole('button', { name: 'Configure access', exact: true }).isVisible(), true);
  const provider = dialog.getByRole('combobox', { name: 'Provider', exact: true });
  assert.equal(await provider.inputValue(), 'echo');
  await provider.click();
  await page.keyboard.press('Escape');
  assert.equal(await model.isVisible(), true);
  assert.equal(await model.inputValue(), 'echo');
  await model.fill('demo-custom');
  await dialog.getByRole('button', { name: 'Save profiles', exact: true }).click();
  await dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();

  await page.reload();
  await openProfile();
  assert.equal(await model.inputValue(), 'demo-custom');
});


test('Settings edits named evaluator services and applies the compaction switch in place', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const toggle = dialog.getByRole('switch', { name: 'Automatic compaction', exact: true });
  const openSettings = () => page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: 'Settings', exact: true }).click();
  const category = name => dialog.getByRole('radio', { name, exact: true }).click();
  const button = name => dialog.getByRole('button', { name, exact: true });
  const updated = () => dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();

  await openSettings();
  await category('Models');
  const sidebar = dialog.getByRole('radiogroup', { name: 'Settings categories', exact: true });
  const categories = await sidebar.getByRole('radio').allTextContents();
  await button('Add evaluator').click();
  await dialog.getByRole('heading', { name: 'New evaluator', exact: true }).waitFor();
  assert.deepEqual(await sidebar.getByRole('radio').allTextContents(), categories);
  const name = dialog.getByRole('textbox', { name: 'evaluator name', exact: true });
  await name.fill('review');
  await category('Tools');
  await button('Return to edit').click();
  assert.equal(await name.inputValue(), 'review');
  await button('Add').click();
  await dialog.getByRole('combobox', { name: 'Provider', exact: true }).selectOption('typesafe');
  const timeout = dialog.getByRole('textbox', { name: 'Timeout (ms)', exact: true });
  await timeout.fill('4000');
  assert.equal(await button('Done editing review').isEnabled(), false);
  await category('Tools');
  await button('Return to edit').click();
  assert.equal(await timeout.inputValue(), '4000');
  await button('Save evaluators').click();
  await updated();
  await button('Done editing review').click();
  await dialog.getByText('review', { exact: true }).waitFor();
  assert.equal(await dialog.locator('textarea').count(), 0);

  await category('Context');
  const before = await toggle.getAttribute('aria-checked');
  await toggle.click();
  await updated();
  const after = before === 'true' ? 'false' : 'true';
  assert.equal(await toggle.getAttribute('aria-checked'), after);

  await page.reload();
  await openSettings();
  await category('Context');
  assert.equal(await toggle.getAttribute('aria-checked'), after);
  await category('Models');
  await button('Edit review').click();
  assert.equal(await dialog.getByRole('combobox', { name: 'Provider', exact: true }).inputValue(), 'typesafe');
  assert.equal(await dialog.getByRole('textbox', { name: 'Timeout (ms)', exact: true }).inputValue(), '4000');
});

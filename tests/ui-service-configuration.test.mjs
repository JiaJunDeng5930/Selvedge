import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('Settings applies configuration edits and shows their saved values after reload', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const instructions = 'Keep headings concise.\n保留中文。';
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const instructionsEditor = page.getByRole('dialog', { name: 'Instructions', exact: true });
  const instructionsInput = instructionsEditor.getByRole('textbox', { name: 'Instructions', exact: true });
  const editInstructions = dialog.getByRole('button', { name: 'Edit instructions', exact: true });
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
  assert.equal(await instructionsInput.count(), 0);
  await editInstructions.click();
  await instructionsInput.fill(instructions);
  await instructionsEditor.getByRole('button', { name: 'Save', exact: true }).click();
  await instructionsEditor.waitFor({ state: 'hidden' });
  assert.equal(await editInstructions.evaluate(button => document.activeElement === button), true);

  await connection.click();
  await listenAddress.selectOption({ label: '::1' });
  await general.click();
  await connection.click();
  assert.equal(await listenAddress.locator('option:checked').textContent(), '::1');
  await applyChange('Save address');

  const configureRelay = dialog.getByRole('button', { name: 'Configure relay', exact: true });
  const relayEditor = page.getByRole('dialog', { name: 'Remote control relay', exact: true });
  const relayUrl = relayEditor.getByRole('textbox', { name: 'Relay URL', exact: true });
  await configureRelay.click();
  await relayUrl.fill('http://invalid.example');
  await relayEditor.getByRole('button', { name: 'Save', exact: true }).click();
  await relayEditor.getByRole('status').filter({ hasText: 'HTTPS origin' }).waitFor();
  assert.equal(await relayUrl.inputValue(), 'http://invalid.example');
  await relayEditor.getByRole('button', { name: 'Discard changes', exact: true }).click();
  await relayEditor.waitFor({ state: 'hidden' });
  assert.equal(await configureRelay.evaluate(button => document.activeElement === button), true);

  await page.reload();
  await openSettings();
  await editInstructions.click();
  assert.equal(await instructionsInput.inputValue(), instructions);
  await instructionsEditor.getByRole('button', { name: 'Cancel', exact: true }).click();
  await instructionsEditor.waitFor({ state: 'hidden' });

  await connection.click();
  assert.equal(await listenAddress.locator('option:checked').textContent(), '::1');
  await configureRelay.click();
  assert.equal(await relayUrl.inputValue(), '');
});

test('Model profile edits keep focus in the editor, discard drafts, and persist saved values', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const settings = page.getByRole('dialog', { name: 'Settings', exact: true, includeHidden: true });
  const launch = settings.getByRole('button', { name: 'Edit demo', exact: true });
  const editor = page.getByRole('dialog', { name: 'Edit demo', exact: true });
  const provider = editor.getByRole('combobox', { name: 'Provider', exact: true });
  const model = editor.getByRole('textbox', { name: 'Model', exact: true });
  await page.setViewportSize({ width: 629, height: 588 });

  async function openProfile() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
    await settings.getByRole('radio', { name: 'Models', exact: true }).click();
    await launch.click();
  }

  await openProfile();
  await editor.waitFor();
  assert.equal(await settings.getByRole('heading', { name: 'Models', exact: true, includeHidden: true }).isVisible(), true);
  assert.equal(await settings.getByRole('textbox', { name: 'Model', exact: true, includeHidden: true }).count(), 0);
  await page.keyboard.press('Tab');
  assert.equal(await editor.evaluate(dialog => dialog.matches(':modal') && dialog.contains(document.activeElement)), true);

  assert.equal(await provider.inputValue(), 'echo');
  assert.equal(await model.inputValue(), 'echo');
  await page.setViewportSize({ width: 320, height: 360 });
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%'; });
  await provider.selectOption({ label: 'Responses API' });
  const timeout = editor.getByRole('textbox', { name: 'Timeout (ms)', exact: true });
  await timeout.fill('4000');
  assert.equal(await timeout.evaluate(input => {
    const bounds = input.getBoundingClientRect();
    return document.activeElement === input && bounds.top >= 0 && bounds.bottom <= innerHeight &&
      bounds.left >= 0 && bounds.right <= innerWidth;
  }), true);
  await page.keyboard.press('Escape');
  assert.equal(await timeout.inputValue(), '4000');
  await editor.getByRole('button', { name: 'Discard changes', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  await launch.waitFor();
  assert.equal(await launch.evaluate(button => document.activeElement === button), true);

  await page.setViewportSize({ width: 629, height: 588 });
  await page.evaluate(() => { document.documentElement.style.removeProperty('font-size'); });
  await launch.click();
  assert.equal(await provider.inputValue(), 'echo');
  await page.keyboard.press('Escape');
  await editor.waitFor({ state: 'hidden' });
  assert.equal(await launch.evaluate(button => document.activeElement === button), true);

  await launch.click();
  assert.equal(await model.inputValue(), 'echo');
  await model.fill('demo-custom');
  await editor.getByRole('button', { name: 'Save', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  assert.equal(await launch.evaluate(button => document.activeElement === button), true);

  await page.reload();
  await openProfile();
  assert.equal(await model.inputValue(), 'demo-custom');
});


test('Settings manages named evaluators and applies the compaction switch in place', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  const toggle = dialog.getByRole('switch', { name: 'Automatic compaction', exact: true });
  const openSettings = () => page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: 'Settings', exact: true }).click();
  const category = name => dialog.getByRole('radio', { name, exact: true }).click();
  const button = name => dialog.getByRole('button', { name, exact: true });
  const updated = () => dialog.getByRole('status').filter({ hasText: 'Configuration updated' }).waitFor();
  const naming = page.getByRole('dialog', { name: 'New evaluator', exact: true });
  const name = naming.getByRole('textbox', { name: 'Name', exact: true });
  const newTimeout = naming.getByRole('textbox', { name: 'Timeout (ms)', exact: true });
  const editor = page.getByRole('dialog', { name: 'Edit review', exact: true });
  const provider = editor.getByRole('combobox', { name: 'Provider', exact: true });
  const timeout = editor.getByRole('textbox', { name: 'Timeout (ms)', exact: true });

  await openSettings();
  await category('Models');
  await button('Add evaluator').click();
  await name.fill('review');
  await newTimeout.fill('3000');
  await naming.getByRole('button', { name: 'Discard changes', exact: true }).click();
  await naming.waitFor({ state: 'hidden' });
  assert.equal(await button('Add evaluator').evaluate(button => document.activeElement === button), true);
  assert.equal(await button('Edit review').count(), 0);

  await button('Add evaluator').click();
  assert.equal(await name.inputValue(), '');
  assert.equal(await newTimeout.inputValue(), '');
  await name.fill('review');
  await naming.getByRole('combobox', { name: 'Provider', exact: true }).selectOption('typesafe');
  await newTimeout.fill('4000');
  await naming.getByRole('button', { name: 'Add evaluator', exact: true }).click();
  await naming.waitFor({ state: 'hidden' });
  await button('Edit review').waitFor();
  assert.equal(await button('Add evaluator').evaluate(button => document.activeElement === button), true);

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
  assert.equal(await provider.inputValue(), 'typesafe');
  assert.equal(await timeout.inputValue(), '4000');

  const remove = { name: 'Remove evaluator', exact: true };
  const removal = page.getByRole('dialog', { name: 'Remove review?', exact: true });
  await editor.getByRole('button', remove).click();
  await removal.getByRole('button', { name: 'Discard changes', exact: true }).click();
  await removal.waitFor({ state: 'hidden' });
  await button('Edit review').click();
  assert.equal(await timeout.inputValue(), '4000');

  await editor.getByRole('button', remove).click();
  await removal.getByRole('button', remove).click();
  await removal.waitFor({ state: 'hidden' });
  assert.equal(await button('Edit review').count(), 0);
  await page.reload();
  await openSettings();
  await category('Models');
  await button('Add evaluator').waitFor();
  assert.equal(await button('Edit review').count(), 0);
});

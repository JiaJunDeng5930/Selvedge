import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('closing Project and title prompt editors discards their unsaved drafts through the browser', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const projectName = 'Editor dismissal project';
  await command({ op: 'create_project', name: projectName,
    workspace: { roots: [], primary_root: null } });

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('region', { name: projectName, exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: 'Project actions', exact: true }).click();
  await page.getByRole('button', { name: 'Edit project', exact: true }).click();
  let dialog = page.getByRole('dialog');
  const projectNameInput = dialog.getByRole('textbox', { name: 'Name', exact: true });
  await projectNameInput.fill('Unsaved project name');
  await page.keyboard.press('Escape');
  await projectNameInput.waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  await page.getByRole('main').getByRole('region', { name: projectName, exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: 'Project actions', exact: true }).click();
  await page.getByRole('button', { name: 'Edit project', exact: true }).click();
  dialog = page.getByRole('dialog');
  assert.equal(await dialog.getByRole('textbox', { name: 'Name', exact: true }).inputValue(), projectName);
  await page.keyboard.press('Escape');
  await dialog.getByRole('textbox', { name: 'Name', exact: true }).waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  async function openTitlePrompts() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
    await page.getByRole('button', { name: 'Edit title prompts', exact: true }).click();
    return page.getByRole('dialog');
  }

  dialog = await openTitlePrompts();
  const prompt = dialog.getByRole('textbox', { name: 'Task 看板标题提示词', exact: true });
  const savedPrompt = await prompt.inputValue();
  await prompt.fill('Unsaved title prompt');
  await page.keyboard.press('Escape');
  await prompt.waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  dialog = await openTitlePrompts();
  assert.equal(await dialog.getByRole('textbox', { name: 'Task 看板标题提示词', exact: true }).inputValue(), savedPrompt);

  const titleModel = dialog.getByLabel('Agent 会话标题模型', { exact: true });
  const options = await titleModel.locator('option').evaluateAll(nodes => nodes.map(node => ({
    label: node.label, value: node.value,
  })));
  const automatic = options.find(option => option.label === '自动');
  const configured = options.find(option => option.label.includes('interactive') || option.value.includes('interactive'));
  assert.ok(automatic, 'The title model selector exposes automatic selection');
  assert.ok(configured, 'The selector exposes the configured interactive model connection');
  assert.equal(await titleModel.inputValue(), automatic.value, 'Automatic selection is the initial title model');
  await titleModel.selectOption(configured.value);
  await dialog.getByRole('button', { name: 'Save', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });

  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  dialog = await openTitlePrompts();
  assert.equal(await dialog.getByLabel('Agent 会话标题模型', { exact: true }).inputValue(), configured.value,
    'The selected title model remains saved after the page reloads');
});

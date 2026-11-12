import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig } from '../host/config.mjs';
import { browserFixture } from './fixtures/browser.mjs';

test('Settings applies configuration edits and shows their saved values after reload', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const instructions = 'Keep headings concise.\n保留中文。';
  const dialog = page.getByRole('dialog', { name: '设置', exact: true });
  const instructionsEditor = page.getByRole('dialog', { name: '对话指引', exact: true });
  const instructionsInput = instructionsEditor.getByRole('textbox', { name: '对话指引', exact: true });
  const editInstructions = dialog.getByRole('button', { name: '编辑指引', exact: true });
  const listenAddress = dialog.getByRole('combobox', { name: '监听地址', exact: true });
  const general = dialog.getByRole('radio', { name: '常规', exact: true });
  const connection = dialog.getByRole('radio', { name: '服务', exact: true });

  async function openSettings() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: '设置', exact: true }).click();
  }

  async function applyChange(label) {
    await dialog.getByRole('button', { name: label, exact: true }).click();
    await dialog.getByRole('status').filter({ hasText: '设置已保存' }).waitFor();
  }

  await openSettings();
  assert.equal(await instructionsInput.count(), 0);
  await editInstructions.click();
  await instructionsInput.fill(instructions);
  await instructionsEditor.getByRole('button', { name: '保存', exact: true }).click();
  await instructionsEditor.waitFor({ state: 'hidden' });
  assert.equal(await editInstructions.evaluate(button => document.activeElement === button), true);

  await connection.click();
  await listenAddress.selectOption({ label: '::1' });
  await general.click();
  await connection.click();
  assert.equal(await listenAddress.locator('option:checked').textContent(), '::1');
  await applyChange('保存地址');

  const restoreAddress = listenAddress.locator('xpath=ancestor::*[@data-semantic-key="settings-controls"]')
    .getByRole('button', { name: '恢复默认', exact: true });
  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 740 });
    await restoreAddress.waitFor();
    const field = await listenAddress.boundingBox();
    const button = await restoreAddress.boundingBox();
    assert.ok(field && button);
    assert.ok(Math.abs(field.y + field.height / 2 - button.y - button.height / 2) <= 1,
      `${width}px: restore stays beside the address field`);
    assert.ok(button.x >= field.x + field.width - 1 && button.x + button.width <= width,
      `${width}px: field and restore control fit without overlap`);
  }
  await page.setViewportSize({ width: 1280, height: 900 });

  const configureRelay = dialog.getByRole('button', { name: '配置中继', exact: true });
  const relayEditor = page.getByRole('dialog', { name: '远程控制中继', exact: true });
  const relayUrl = relayEditor.getByRole('textbox', { name: '中继网址', exact: true });
  await configureRelay.click();
  await relayUrl.fill('http://invalid.example');
  await relayEditor.getByRole('button', { name: '保存', exact: true }).click();
  await relayEditor.getByRole('status').filter({ hasText: 'HTTPS origin' }).waitFor();
  assert.equal(await relayUrl.inputValue(), 'http://invalid.example');
  await relayEditor.getByRole('button', { name: '放弃更改', exact: true }).click();
  await relayEditor.waitFor({ state: 'hidden' });
  assert.equal(await configureRelay.evaluate(button => document.activeElement === button), true);

  await page.reload();
  await openSettings();
  await editInstructions.click();
  assert.equal(await instructionsInput.inputValue(), instructions);
  await instructionsEditor.getByRole('button', { name: '取消', exact: true }).click();
  await instructionsEditor.waitFor({ state: 'hidden' });

  await connection.click();
  assert.equal(await listenAddress.locator('option:checked').textContent(), '::1');
  await configureRelay.click();
  assert.equal(await relayUrl.inputValue(), '');
});

test('Context settings show seconds and offer reset only for a changed value', { timeout: 60000 }, async t => {
  const { page, running } = await browserFixture(t);
  const configuration = path.join(running.service.home, 'config.json');
  // Explicit settings with equivalent numeric spellings are still at their defaults.
  await writeFile(configuration, `{"format":${JSON.stringify(defaultConfig.format)},
    "compaction":{"enabled":true,"background_percent":6.5e1,"blocking_percent":90,"idle_lead_ms":6e4}}`);
  const dialog = page.getByRole('dialog', { name: '设置', exact: true });
  const openContext = async () => {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: '设置', exact: true }).click();
    await dialog.getByRole('radio', { name: '上下文', exact: true }).click();
  };
  const idle = dialog.getByRole('textbox', { name: '空闲提前量（秒）', exact: true });
  const background = dialog.getByRole('textbox', { name: '后台压缩阈值（%）', exact: true });
  const restore = dialog.getByRole('button', { name: '恢复默认', exact: true });
  const restoreIdle = idle.locator('xpath=ancestor::*[@data-semantic-key="settings-controls"]')
    .getByRole('button', { name: '恢复默认', exact: true });
  const save = dialog.getByRole('button', { name: '保存', exact: true });
  const saved = () => dialog.getByRole('status').filter({ hasText: '设置已保存' }).waitFor();
  const policy = async () => JSON.parse(await readFile(configuration, 'utf8')).compaction;

  await openContext();
  assert.equal(await idle.inputValue(), '60');
  assert.equal(await restore.count(), 0);

  await idle.fill('60.0001');
  assert.equal(await save.isDisabled(), true, 'The seconds editor must not round a fraction of a millisecond');
  await idle.fill('6.0001e1');
  await save.click();
  await saved();
  assert.equal((await policy()).idle_lead_ms, 60001);
  assert.equal(await idle.inputValue(), '60.001');
  await restoreIdle.waitFor();
  assert.equal(await restore.count(), 1);

  await page.reload();
  await openContext();
  await restoreIdle.waitFor();
  assert.equal(await idle.inputValue(), '60.001');
  assert.equal(await restore.count(), 1);

  await background.fill('95');
  await save.click();
  await dialog.getByRole('status').filter({ hasText: 'Invalid compaction settings' }).waitFor();
  assert.equal((await policy()).background_percent, 65);
  await dialog.getByRole('button', { name: '撤销编辑', exact: true }).click();

  await restoreIdle.click();
  await saved();
  assert.equal(await idle.inputValue(), '60');
  assert.equal(Object.hasOwn(await policy(), 'idle_lead_ms'), false);
  assert.equal(await restore.count(), 0);
});

test('Model profile edits keep focus in the editor, discard drafts, and persist saved values', { timeout: 60000 }, async t => {
  const { page, running } = await browserFixture(t);
  await writeFile(path.join(running.service.home, 'config.json'), JSON.stringify({
    format: defaultConfig.format,
    profiles: { interactive: { provider: 'responses', model: 'interactive-fixture' } },
  }));
  const settings = page.getByRole('dialog', { name: '设置', exact: true, includeHidden: true });
  const launch = settings.getByRole('button', { name: '编辑「interactive」', exact: true });
  const editor = page.getByRole('dialog', { name: '编辑「interactive」', exact: true });
  const provider = editor.getByRole('radiogroup', { name: '提供方', exact: true });
  const responses = provider.getByRole('radio', { name: 'Responses API', exact: true });
  const model = editor.getByRole('textbox', { name: '模型', exact: true });
  await page.setViewportSize({ width: 629, height: 588 });

  async function openProfile() {
    await page.getByRole('button', { name: 'Global navigation', exact: true }).click();
    await page.getByRole('button', { name: '设置', exact: true }).click();
    await settings.getByRole('radio', { name: '模型', exact: true }).click();
    await launch.click();
  }

  await openProfile();
  await editor.waitFor();
  const modelSettings = settings.getByRole('heading', { name: '模型', exact: true, includeHidden: true });
  assert.equal(await modelSettings.count(), 1);
  assert.equal(await modelSettings.isVisible(), false, 'The covered settings stay mounted without being painted');
  assert.equal(await settings.getByRole('textbox', { name: '模型', exact: true, includeHidden: true }).count(), 0);
  await page.keyboard.press('Tab');
  assert.equal(await editor.evaluate(dialog => dialog.matches(':modal') && dialog.contains(document.activeElement)), true);

  assert.equal(await responses.getAttribute('aria-checked'), 'true');
  assert.equal(await model.inputValue(), 'interactive-fixture');
  await page.setViewportSize({ width: 320, height: 360 });
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%'; });
  await provider.getByRole('radio', { name: 'ChatGPT', exact: true }).click();
  const overrides = editor.getByRole('button', { name: '自定义连接参数', exact: true });
  if ((await overrides.getAttribute('aria-expanded')) === 'false') await overrides.click();
  const timeout = editor.getByRole('textbox', { name: '超时（ms）', exact: true });
  await timeout.fill('4000');
  assert.equal(await timeout.evaluate(input => {
    const bounds = input.getBoundingClientRect();
    return document.activeElement === input && bounds.top >= 0 && bounds.bottom <= innerHeight &&
      bounds.left >= 0 && bounds.right <= innerWidth;
  }), true);
  await page.keyboard.press('Escape');
  assert.equal(await timeout.inputValue(), '4000');
  await editor.getByRole('button', { name: '放弃更改', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  await launch.waitFor();
  await modelSettings.waitFor();
  assert.equal(await launch.evaluate(button => document.activeElement === button), true);

  await page.setViewportSize({ width: 629, height: 588 });
  await page.evaluate(() => { document.documentElement.style.removeProperty('font-size'); });
  await launch.click();
  assert.equal(await responses.getAttribute('aria-checked'), 'true');
  await page.keyboard.press('Escape');
  await editor.waitFor({ state: 'hidden' });
  assert.equal(await launch.evaluate(button => document.activeElement === button), true);

  await launch.click();
  assert.equal(await model.inputValue(), 'interactive-fixture');
  await model.fill('interactive-custom');
  await editor.getByRole('button', { name: '保存', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  assert.equal(await launch.evaluate(button => document.activeElement === button), true);

  await page.reload();
  await openProfile();
  assert.equal(await model.inputValue(), 'interactive-custom');
});

test('new model profiles start blank, hide the offline demo, and require a provider and model', { timeout: 60000 }, async t => {
  const { page, running } = await browserFixture(t);
  await writeFile(path.join(running.service.home, 'config.json'), JSON.stringify({
    format: defaultConfig.format,
    profiles: { demo: { provider: 'echo', model: 'echo' } },
  }));
  const settings = page.getByRole('dialog', { name: '设置', exact: true, includeHidden: true });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '设置', exact: true }).click();
  await settings.getByRole('radio', { name: '模型', exact: true }).click();
  await settings.getByRole('button', { name: '添加模型配置', exact: true }).click();

  const editor = page.getByRole('dialog', { name: '新建模型配置', exact: true });
  const name = editor.getByRole('textbox', { name: '名称', exact: true });
  const model = editor.getByRole('textbox', { name: '模型', exact: true });
  const provider = editor.getByRole('radiogroup');
  const add = editor.getByRole('button', { name: '添加模型配置', exact: true });

  assert.equal(await model.inputValue(), '');
  assert.equal(await editor.getByRole('radio', { name: '离线回显', exact: true }).count(), 0);
  assert.ok(await provider.getByRole('radio').count() > 0);
  assert.equal(await provider.getByRole('radio', { checked: true }).count(), 0);
  assert.equal(await add.isEnabled(), false);

  await name.fill('production');
  await model.fill('provider-model');
  assert.equal(await add.isEnabled(), false);
  await model.fill('');
  await editor.getByRole('radio', { name: 'Responses API', exact: true }).click();
  assert.equal(await add.isEnabled(), false);
  await model.fill('   ');
  assert.equal(await add.isEnabled(), false);
  await model.fill('provider-model');
  assert.equal(await add.isEnabled(), true);
  await add.click();
  await editor.waitFor({ state: 'hidden' });
  await settings.getByRole('button', { name: '编辑「production」', exact: true }).waitFor();

  await settings.getByRole('button', { name: '编辑「demo」', exact: true }).click();
  const existing = page.getByRole('dialog', { name: '编辑「demo」', exact: true });
  assert.equal(await existing.getByRole('radio', { name: '离线回显', exact: true }).getAttribute('aria-checked'), 'true');
  assert.equal(await existing.getByRole('textbox', { name: '模型', exact: true }).inputValue(), 'echo');
});


test('Settings manages named evaluators and applies the compaction switch in place', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  const dialog = page.getByRole('dialog', { name: '设置', exact: true });
  const toggle = dialog.getByRole('switch', { name: '自动压缩', exact: true });
  const openSettings = () => page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '设置', exact: true }).click();
  const category = name => dialog.getByRole('radio', { name, exact: true }).click();
  const button = name => dialog.getByRole('button', { name, exact: true });
  const updated = () => dialog.getByRole('status').filter({ hasText: '设置已保存' }).waitFor();
  const naming = page.getByRole('dialog', { name: '新建评估器', exact: true });
  const name = naming.getByRole('textbox', { name: '名称', exact: true });
  const newTimeout = naming.getByRole('textbox', { name: '超时（ms）', exact: true });
  const editor = page.getByRole('dialog', { name: '编辑「review」', exact: true });
  const provider = editor.getByRole('combobox', { name: '提供方', exact: true });
  const timeout = editor.getByRole('textbox', { name: '超时（ms）', exact: true });

  await openSettings();
  await category('模型');
  await button('添加评估器').click();
  await name.fill('review');
  await naming.getByRole('button', { name: '连接与重试', exact: true }).click();
  await newTimeout.fill('3000');
  await naming.getByRole('button', { name: '放弃更改', exact: true }).click();
  await naming.waitFor({ state: 'hidden' });
  assert.equal(await button('添加评估器').evaluate(button => document.activeElement === button), true);
  assert.equal(await button('编辑「review」').count(), 0);

  await button('添加评估器').click();
  assert.equal(await name.inputValue(), '');
  await naming.getByRole('button', { name: '连接与重试', exact: true }).click();
  assert.equal(await newTimeout.inputValue(), '');
  await name.fill('review');
  await naming.getByRole('combobox', { name: '提供方', exact: true }).selectOption('typesafe');
  await newTimeout.fill('4000');
  await naming.getByRole('button', { name: '添加评估器', exact: true }).click();
  await naming.waitFor({ state: 'hidden' });
  await button('编辑「review」').waitFor();
  assert.equal(await button('添加评估器').evaluate(button => document.activeElement === button), true);

  await category('上下文');
  const before = await toggle.getAttribute('aria-checked');
  await toggle.click();
  await updated();
  const after = before === 'true' ? 'false' : 'true';
  assert.equal(await toggle.getAttribute('aria-checked'), after);

  await page.reload();
  await openSettings();
  await category('上下文');
  assert.equal(await toggle.getAttribute('aria-checked'), after);
  await category('模型');
  await button('编辑「review」').click();
  assert.equal(await provider.inputValue(), 'typesafe');
  assert.equal(await timeout.inputValue(), '4000');

  const remove = { name: '移除评估器', exact: true };
  const removal = page.getByRole('dialog', { name: '移除「review」？', exact: true });
  await editor.getByRole('button', remove).click();
  await removal.getByRole('button', { name: '放弃更改', exact: true }).click();
  await removal.waitFor({ state: 'hidden' });
  await button('编辑「review」').click();
  assert.equal(await timeout.inputValue(), '4000');

  await editor.getByRole('button', remove).click();
  await removal.getByRole('button', remove).click();
  await removal.waitFor({ state: 'hidden' });
  assert.equal(await button('编辑「review」').count(), 0);
  await page.reload();
  await openSettings();
  await category('模型');
  await button('添加评估器').waitFor();
  assert.equal(await button('编辑「review」').count(), 0);
});

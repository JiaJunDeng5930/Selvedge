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

test('conversation guidance displays complete lines and preserves saved text', { timeout: 60000 }, async t => {
  const { page, running } = await browserFixture(t);
  const configuration = path.join(running.service.home, 'config.json');
  const instructions = [
    '  保留前后空格  ',
    '',
    ...Array.from({ length: 60 }, (_, index) => 'Keep original line ' + (index + 1) + '.'),
    '\t',
  ].join('\r\n');
  await writeFile(configuration, JSON.stringify({
    format: defaultConfig.format, host: '127.0.0.1', instructions,
  }));
  const saved = async () => JSON.parse(await readFile(configuration, 'utf8'));
  const settings = page.getByRole('dialog', { name: '设置', exact: true });
  const editor = page.getByRole('dialog', { name: '对话指引', exact: true });
  const field = editor.getByRole('textbox', { name: '对话指引', exact: true });
  const open = settings.getByRole('button', { name: '编辑指引', exact: true });
  const cancel = editor.getByRole('button', { name: '取消', exact: true });
  const save = editor.getByRole('button', { name: '保存', exact: true });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '设置', exact: true }).click();
  await open.click();
  assert.equal(await field.inputValue(), instructions.replaceAll('\r\n', '\n'),
    'A native textarea displays the saved text with browser-normalized line endings');

  for (const { width, height, minimumLines } of [{ width: 1280, height: 900, minimumLines: 16 },
    { width: 390, height: 500, minimumLines: 11 }]) {
    await page.setViewportSize({ width, height });
    const lines = await field.evaluate(text => {
      const style = getComputedStyle(text);
      const insets = Number.parseFloat(style.paddingTop) + Number.parseFloat(style.paddingBottom);
      return (text.clientHeight - insets) / Number.parseFloat(style.lineHeight);
    });
    assert.ok(lines >= minimumLines && Math.abs(lines - Math.round(lines)) < .05,
      `${width}px: a long document has ${lines} complete editing lines`);
    const decision = await cancel.boundingBox();
    assert.ok(decision.y >= 0 && decision.y + decision.height <= height,
      'The dialog footer stays reachable while the field scrolls');
  }
  await field.hover();
  await page.mouse.wheel(0, 1200);
  await page.waitForFunction(() => document.querySelector('textarea[aria-label="对话指引"]')?.scrollTop > 0);
  assert.equal(await save.isDisabled(), true);
  await cancel.click();
  await editor.waitFor({ state: 'hidden' });
  assert.equal((await saved()).instructions, instructions);

  await page.setViewportSize({ width: 1280, height: 900 });
  await settings.getByRole('radio', { name: '服务', exact: true }).click();
  await settings.getByRole('combobox', { name: '监听地址', exact: true }).selectOption({ label: '::1' });
  await settings.getByRole('button', { name: '保存地址', exact: true }).click();
  await settings.getByRole('status').filter({ hasText: '设置已保存' }).waitFor();
  assert.equal((await saved()).instructions, instructions);

  await settings.getByRole('radio', { name: '常规', exact: true }).click();
  await open.click();
  await editor.getByRole('button', { name: '恢复默认', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  assert.equal(Object.hasOwn(await saved(), 'instructions'), false);
  await open.click();
  const restored = await field.inputValue();
  assert.equal(restored, defaultConfig.instructions);
  assert.ok(restored.split('\n\n').length >= 4, 'The built-in guidance is organized into paragraphs');
});

test('Task and Service settings restore only saved values that differ from their defaults', { timeout: 60000 }, async t => {
  const { page, running } = await browserFixture(t);
  const configuration = path.join(running.service.home, 'config.json');
  await writeFile(configuration, `{"format":${JSON.stringify(defaultConfig.format)},
    "max_fork":4e0,"max_descendants":64,"cloud":null,"host":"127.0.0.1","port":7421,"remote":false}`);
  const saved = async () => JSON.parse(await readFile(configuration, 'utf8'));
  const settings = page.getByRole('dialog', { name: '设置', exact: true });
  const button = (container, name) => container.getByRole('button', { name, exact: true });
  const reset = container => button(container, '恢复默认');
  const category = name => settings.getByRole('radio', { name, exact: true }).click();
  const openSettings = () => button(page.getByRole('navigation', { name: 'Global navigation', exact: true }), '设置').click();
  const textbox = (container, name) => container.getByRole('textbox', { name, exact: true });
  const controls = field => field.locator('xpath=ancestor::*[@data-semantic-key="settings-controls"]');

  async function restoreField(field, key, initial, changed, saveLabel) {
    const restore = reset(controls(field));
    await restore.waitFor({ state: 'hidden' });
    if (key === 'host') await field.selectOption({ label: changed });
    else await field.fill(changed);
    await button(settings, saveLabel).click();
    await restore.waitFor();
    assert.equal((await saved())[key], key === 'host' ? changed : Number(changed));
    assert.equal(await reset(settings).count(), 1, `Only ${key} differs from its default`);
    await restore.click();
    await restore.waitFor({ state: 'hidden' });
    const displayed = key === 'host' ? await field.locator('option:checked').textContent() : await field.inputValue();
    assert.equal(displayed, initial);
    assert.equal(Object.hasOwn(await saved(), key), false);
  }

  async function restoreForm(openLabel, title, key, fill, expected) {
    const form = page.getByRole('dialog', { name: title, exact: true });
    const open = () => button(settings, openLabel).click();
    await open();
    await form.waitFor();
    assert.equal(await reset(form).count(), 0);
    await fill(form);
    await button(form, '保存').click();
    await form.waitFor({ state: 'hidden' });
    assert.deepEqual((await saved())[key], expected);
    await open();
    await reset(form).click();
    await form.waitFor({ state: 'hidden' });
    assert.equal(Object.hasOwn(await saved(), key), false);
    await open();
    await form.waitFor();
    assert.equal(await reset(form).count(), 0);
    await button(form, '取消').click();
    await form.waitFor({ state: 'hidden' });
  }

  await openSettings();
  await category('任务');
  const direct = textbox(settings, '直接分支上限');
  const total = textbox(settings, '分支总数上限');
  await total.waitFor();
  assert.equal(await reset(settings).count(), 0);
  await restoreField(direct, 'max_fork', '4', '4294967295', '保存');
  await restoreField(total, 'max_descendants', '64', '4294967294', '保存');
  assert.equal((await saved()).cloud, null);

  const cloud = { backend: 'tencent_cvm', tencent_cvm: {
    region: 'ap-guangzhou', zone: 'ap-guangzhou-1', image_id: 'img-fixture', instance_type: 'S5.MEDIUM4',
    spot_max_price: '0.25', vpc_id: 'vpc-fixture', subnet_id: 'subnet-fixture',
    security_group_ids: ['sg-fixture'], key_id: 'skey-fixture', ssh_private_key: '/fixture/id_rsa',
  } };
  await page.setViewportSize({ width: 1280, height: 720 });
  await restoreForm('配置云端工作区', '云端工作区', 'cloud', async form => {
    const save = button(form, '保存');
    const privateKey = textbox(form, '私钥路径');
    const actionsBeforeScroll = await save.boundingBox();
    const ssh = form.getByRole('heading', { name: 'SSH', exact: true });
    const [sshBounds, privateKeyBounds, bodyBounds] = await Promise.all([
      ssh.boundingBox(), privateKey.boundingBox(), form.locator('[data-surface-role="dialog-body"]').boundingBox(),
    ]);
    const scrollEdge = bodyBounds.y + bodyBounds.height;
    assert.ok(sshBounds.y >= scrollEdge || privateKeyBounds.y + privateKeyBounds.height <= scrollEdge,
      'The first screen shows the SSH heading with its fields or leaves the section below the scroll edge');
    await privateKey.click();
    const actionsAfterScroll = await save.boundingBox();
    assert.deepEqual(actionsAfterScroll, actionsBeforeScroll,
      'Scrolling the cloud settings keeps the save action fixed');
    const keyBounds = await privateKey.boundingBox();
    assert.ok(keyBounds.y + keyBounds.height < actionsAfterScroll.y,
      'The last field can be brought fully above the fixed actions');
    const config = cloud.tencent_cvm;
    for (const [name, value] of [
      ['地域', config.region], ['可用区', config.zone], ['镜像 ID', config.image_id],
      ['实例规格', config.instance_type], ['竞价价格上限（账户币种/小时）', config.spot_max_price],
      ['VPC ID', config.vpc_id], ['子网 ID', config.subnet_id], ['SSH 密钥 ID', config.key_id],
      ['私钥路径', config.ssh_private_key],
    ]) await textbox(form, name).fill(value);
    await button(form, '添加安全组 ID').click();
    await textbox(form, '安全组 ID 1').fill(config.security_group_ids[0]);
  }, cloud);
  await page.setViewportSize({ width: 1280, height: 900 });

  await category('服务');
  const address = settings.getByRole('combobox', { name: '监听地址', exact: true });
  const port = textbox(settings, '监听端口');
  await port.waitFor();
  assert.equal(await reset(settings).count(), 0);
  await restoreField(address, 'host', '127.0.0.1', '::1', '保存地址');
  await restoreField(port, 'port', '7421', '65535', '保存端口');
  await restoreForm('配置中继', '远程控制中继', 'remote',
    form => textbox(form, '中继网址').fill('https://relay.example'), { relay_url: 'https://relay.example' });

  await page.reload();
  await openSettings();
  await category('服务');
  assert.equal(await address.locator('option:checked').textContent(), '127.0.0.1');
  assert.equal(await port.inputValue(), '7421');
  assert.equal(await reset(settings).count(), 0);
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
  await dialog.getByRole('button', { name: '编辑限制', exact: true }).click();
  const limits = page.getByRole('dialog', { name: '模型上下文限制', exact: true });
  await limits.getByText('当前使用默认限制。添加配置项可为指定模型设置限制。', { exact: true }).waitFor();
  const limitSave = limits.getByRole('button', { name: '保存', exact: true });
  assert.equal(await limitSave.isDisabled(), true);
  assert.equal(await limitSave.getAttribute('data-help'), '添加配置项后可以保存');
  await limits.getByRole('button', { name: '添加配置项', exact: true }).click();
  await limits.getByRole('textbox', { name: '模型配置名称', exact: true }).waitFor();
  await limits.getByRole('button', { name: '放弃更改', exact: true }).click();
  await limits.waitFor({ state: 'hidden' });

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
  const model = editor.getByRole('textbox', { name: '模型标识', exact: true });
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
  assert.equal(await modelSettings.isVisible(), true, 'The editor keeps the owning settings category visible');
  await editor.getByText('设置 / 模型', { exact: true }).waitFor();
  assert.equal(await settings.getByRole('textbox', { name: '模型标识', exact: true, includeHidden: true }).count(), 0);
  await page.keyboard.press('Tab');
  assert.equal(await editor.evaluate(dialog => dialog.matches(':modal') && dialog.contains(document.activeElement)), true);

  assert.equal(await responses.getAttribute('aria-checked'), 'true');
  assert.equal(await model.inputValue(), 'interactive-fixture');
  await page.setViewportSize({ width: 320, height: 360 });
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%'; });
  await provider.getByRole('radio', { name: 'ChatGPT 账号', exact: true }).click();
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
  await page.getByRole('button', { name: '搜索对话', exact: true }).click();
  await page.getByRole('searchbox', { name: '标题或消息关键词', exact: true }).waitFor();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '设置', exact: true }).click();
  await settings.getByRole('radio', { name: '模型', exact: true }).click();
  await settings.getByRole('button', { name: '添加模型配置', exact: true }).click();

  const editor = page.getByRole('dialog', { name: '新建模型配置', exact: true });
  const name = editor.getByRole('textbox', { name: '配置名称', exact: true });
  const model = editor.getByRole('textbox', { name: '模型标识', exact: true });
  const provider = editor.getByRole('radiogroup', { name: '提供方', exact: true });
  const responses = provider.getByRole('radio', { name: 'Responses API', exact: true });
  const account = provider.getByRole('radio', { name: 'ChatGPT 账号', exact: true });
  const web = provider.getByRole('radio', { name: 'ChatGPT Web API', exact: true });
  const add = editor.getByRole('button', { name: '添加模型配置', exact: true });

  await editor.getByText('配置名称', { exact: true }).waitFor();
  await editor.getByText('模型标识', { exact: true }).waitFor();
  await editor.getByText('设置 / 模型', { exact: true }).waitFor();
  assert.equal(await page.locator('[data-measure-region="workspace"]').evaluate(workspace =>
    getComputedStyle(workspace).opacity), '0', 'Only the owning Settings page paints behind its editor');
  assert.equal(await settings.isVisible(), true);
  assert.equal(await name.inputValue(), '');
  assert.equal(await model.inputValue(), '');
  assert.equal(await editor.getByRole('radio', { name: '离线回显', exact: true }).count(), 0);
  assert.equal(await provider.getByRole('radio').count(), 3);
  assert.equal(await provider.getByRole('radio', { checked: true }).count(), 0);
  assert.equal(await add.isEnabled(), false);

  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 740 });
    const rows = await Promise.all([responses, account, web].map(option => option.boundingBox()));
    assert.ok(rows.every(row => row && row.x >= 0 && row.x + row.width <= width + 1));
    assert.ok(rows.every(row => Math.abs(row.x - rows[0].x) < 1 && Math.abs(row.width - rows[0].width) < 1));
    assert.ok(rows.slice(1).every((row, index) => row.y >= rows[index].y + rows[index].height));
  }

  await name.fill('production');
  await model.fill('provider-model');
  assert.equal(await add.isEnabled(), false);
  await model.fill('');
  const details = editor.getByRole('button', { name: '自定义连接参数', exact: true });
  const showDetails = async () => {
    if ((await details.getAttribute('aria-expanded')) === 'false') await details.click();
  };
  const authFile = editor.getByRole('textbox', { name: '认证文件', exact: true });
  const endpoint = editor.getByRole('textbox', { name: '端点', exact: true });
  await responses.press('ArrowDown');
  await account.and(provider.getByRole('radio', { checked: true })).waitFor();
  await showDetails();
  await authFile.waitFor();
  assert.equal(await endpoint.count(), 0);
  await account.press('ArrowDown');
  await web.and(provider.getByRole('radio', { checked: true })).waitFor();
  await showDetails();
  await endpoint.waitFor();
  await editor.getByRole('textbox', { name: 'API 密钥环境变量', exact: true }).waitFor();
  assert.equal(await authFile.count(), 0);

  await responses.click();
  assert.equal(await add.isEnabled(), false);
  await model.fill('   ');
  assert.equal(await add.isEnabled(), false);
  await model.fill('provider-model');
  await name.fill('demo');
  assert.equal(await add.isEnabled(), false);
  await name.fill('production');
  assert.equal(await add.isEnabled(), true);
  await add.click();
  await editor.waitFor({ state: 'hidden' });
  const saved = settings.getByRole('button', { name: '编辑「production」', exact: true });
  await saved.waitFor();

  await page.setViewportSize({ width: 1280, height: 740 });
  await saved.click();
  const production = page.getByRole('dialog', { name: '编辑「production」', exact: true });
  await production.getByRole('heading', { name: '编辑「production」', exact: true }).waitFor();
  assert.equal(await production.getByRole('textbox', { name: '模型标识', exact: true }).inputValue(), 'provider-model');
  await production.getByRole('button', { name: '取消', exact: true }).click();
  await production.waitFor({ state: 'hidden' });

  await settings.getByRole('button', { name: '编辑「demo」', exact: true }).click();
  const existing = page.getByRole('dialog', { name: '编辑「demo」', exact: true });
  assert.equal(await existing.getByRole('radio', { name: '离线回显', exact: true }).getAttribute('aria-checked'), 'true');
  assert.equal(await existing.getByRole('textbox', { name: '模型标识', exact: true }).inputValue(), 'echo');
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

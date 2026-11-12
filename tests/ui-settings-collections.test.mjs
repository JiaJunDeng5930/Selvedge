import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig } from '../host/config.mjs';
import { browserFixture } from './fixtures/browser.mjs';

async function saveFixtureConfig(fixture, values) {
  const filename = path.join(fixture.running.service.home, 'config.json');
  await writeFile(filename, JSON.stringify({ format: defaultConfig.format, ...values }));
  return filename;
}

const emptyCollection = name => name === '模型配置' ? '暂无自定义模型配置。' : `暂无${name}。`;

async function openSettings(page, width) {
  await page.setViewportSize({ width, height: 740 });
  const settings = page.getByRole('dialog', { name: '设置', exact: true });
  if (width === 1280) await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '设置', exact: true }).click();
  else {
    await page.getByRole('button', { name: 'Global navigation', exact: true }).click();
    await page.getByRole('button', { name: '设置', exact: true }).click();
  }
  const select = async label => {
    if (width === 1280) await settings.getByRole('radio', { name: label, exact: true }).click();
    else await settings.getByRole('combobox', { name: '设置分类', exact: true }).selectOption({ label });
  };
  return { settings, select };
}

test('empty settings collections show what can be added without an empty-list reset', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  await saveFixtureConfig(fixture, {
    profiles: {}, reasoning_evaluators: {}, mcp: {}, chatgpt_plugin: { connections: {} }, plugins: {},
  });
  for (const width of [1280, 320]) {
    const { settings, select } = await openSettings(fixture.page, width);
    const sections = [
      ['模型', [['模型配置', '添加模型配置'], ['推理评估器', '添加评估器']]],
      ['连接器', [['MCP 服务器', '添加服务器'], ['ChatGPT 应用连接', '添加连接']]],
      ['扩展', [['插件', '添加插件']]],
    ];
    for (const [section, collections] of sections) {
      await select(section);
      for (const [, add] of collections)
        assert.equal(await settings.getByRole('button', { name: add, exact: true }).isEnabled(), true);
      assert.equal(await settings.getByRole('button', { name: '恢复列表默认值', exact: true }).count(), 0);
      for (const [name] of collections) {
        await settings.getByRole('region', { name, exact: true })
          .getByText(emptyCollection(name), { exact: true }).waitFor();
      }
    }
    await settings.getByRole('button', { name: '关闭设置', exact: true }).click();
    await settings.waitFor({ state: 'hidden' });
  }
});

test('saved collections place their effective reset beside Add and show the result', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const filename = await saveFixtureConfig(fixture, {
    profiles: { local: { provider: 'responses', model: 'fixture' } },
    reasoning_evaluators: { review: { provider: 'typesafe' } },
    plugins: { example: { command: '/usr/bin/true', args: [] } },
  });
  const { settings, select } = await openSettings(fixture.page, 390);
  const collections = [
    ['模型', '添加模型配置', 'local', '模型配置', 'profiles'],
    ['模型', '添加评估器', 'review', '推理评估器', 'reasoning_evaluators'],
    ['扩展', '添加插件', 'example', '插件', 'plugins'],
  ];
  for (const [section, add, item, name, key] of collections) {
    await select(section);
    const addition = settings.getByRole('button', { name: add, exact: true });
    const reset = addition.locator('..').getByRole('button', { name: '恢复列表默认值', exact: true });
    const edit = settings.getByRole('region', { name, exact: true })
      .getByRole('button', { name: `编辑「${item}」`, exact: true });
    await edit.waitFor();
    await reset.click();
    await settings.getByRole('region', { name, exact: true })
      .getByText(emptyCollection(name), { exact: true }).waitFor();
    assert.equal(await edit.count(), 0);
    assert.equal(await reset.count(), 0);
    assert.equal(await addition.isEnabled(), true);
    const saved = JSON.parse(await readFile(filename, 'utf8'));
    assert.equal(Object.hasOwn(saved, key), false, `${key} is restored by the actual settings operation`);
  }
});

test('a malformed saved collection can still be restored', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const filename = await saveFixtureConfig(fixture, { profiles: [] });
  const { settings, select } = await openSettings(fixture.page, 1280);
  await select('模型');
  const profiles = settings.getByRole('region', { name: '模型配置', exact: true });
  await profiles.getByText('无法读取模型配置列表。', { exact: true }).waitFor();
  await settings.getByRole('button', { name: '恢复列表默认值', exact: true }).click();
  await profiles.getByText('暂无自定义模型配置。', { exact: true }).waitFor();
  assert.equal(Object.hasOwn(JSON.parse(await readFile(filename, 'utf8')), 'profiles'), false);
});

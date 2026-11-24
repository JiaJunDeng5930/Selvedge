import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { browserFixture } from './fixtures/browser.mjs';

async function projectFixture(t) {
  const fixture = await browserFixture(t);
  const workspace = path.join(fixture.root, 'Disconnect admission workspace');
  await mkdir(workspace);
  await fixture.command({ op: 'create_project', name: 'Disconnect admission project',
    workspace: { roots: [workspace], primary_root: workspace } });
  const { page } = fixture;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('region', { name: 'Disconnect admission project', exact: true }).hover();
  return fixture;
}

async function editorFixture(t) {
  const fixture = await projectFixture(t);
  const { page } = fixture;
  await page.getByRole('main').getByRole('button', { name: 'Disconnect admission project', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();
  return fixture;
}

test('a disconnect guards both a new draft and an already open confirmation', { timeout: 60000 }, async t => {
  const fixture = await editorFixture(t);
  const { page, running } = fixture;
  const submit = page.getByRole('button', { name: 'Start task', exact: true });
  await submit.waitFor();
  const draft = page.getByRole('combobox', { name: 'Task', exact: true });
  const text = 'Keep this draft while the service is disconnected.';
  await draft.fill(text);
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: false }).waitFor();
  await draft.focus();
  const editor = await draft.elementHandle();
  const position = await draft.boundingBox();
  const attempts = [Promise.withResolvers(), Promise.withResolvers()];
  let attempt = 0;
  await page.route('**/api/browser/state', route => { attempts[attempt++].resolve(route); }, { times: attempts.length });

  let commands = 0;
  page.on('request', request => {
    if (request.url().endsWith('/api/browser/command') && request.method() === 'POST') commands++;
  });
  running.disconnect();
  await page.getByRole('button', { name: 'Start task', exact: true, disabled: true }).waitFor();
  assert.equal(commands, 0, 'The disabled Submit control must not dispatch a command');
  const notice = page.getByRole('region', { name: '服务连接', exact: true });
  await notice.getByText('无法连接到 Selvedge，正在自动重试。', { exact: true }).waitFor();
  const first = await attempts[0].promise;
  await first.abort('failed');
  const retry = await attempts[1].promise;
  assert.equal(await notice.getByRole('button', { name: '立即重连', exact: true }).isVisible(), true);
  assert.equal(await page.getByRole('dialog', { name: '设置', exact: true }).count(), 0);
  assert.deepEqual(await draft.boundingBox(), position);
  assert.equal(await editor.evaluate(node => node === document.activeElement), true);
  assert.equal(await draft.inputValue(), text);
  await retry.continue();
  await notice.waitFor({ state: 'hidden' });
  assert.equal(await draft.inputValue(), text);

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('region', { name: 'Disconnect admission project', exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: '项目操作', exact: true }).click();
  await page.getByRole('button', { name: '删除项目', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirm', exact: true, disabled: false }).waitFor();

  running.disconnect();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirm', exact: true, disabled: true }).waitFor();
  assert.equal(commands, 0, 'The disabled Confirm control must not dispatch a command');
});

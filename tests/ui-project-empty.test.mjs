import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('Project empty state groups its only create action and restores focus after cancel', { timeout: 60000 }, async t => {
  const { page, command } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  const main = page.getByRole('main');
  const entries = main.locator('[data-page-region="project-entries"]');
  const empty = entries.locator('[data-semantic-key="project/empty"]');
  const create = empty.getByRole('button', { name: '新建项目', exact: true });
  await empty.getByText('还没有项目。', { exact: true }).waitFor();
  await create.waitFor();
  assert.equal(await main.getByRole('button', { name: '新建项目', exact: true }).count(), 1,
    'The empty page has one create entry');
  assert.equal(await main.locator('[data-page-region="collection-actions"] button').count(), 0,
    'The empty page does not keep a second create action in the header');

  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 780 });
    const geometry = await empty.evaluate(node => {
      const description = node.querySelector('[data-semantic-key="project/empty-description"]')?.getBoundingClientRect();
      const button = node.querySelector('button')?.getBoundingClientRect();
      const group = node.getBoundingClientRect();
      return { grouped: !!description && !!button && description.top >= group.top && button.top >= description.bottom,
        fits: group.left >= 0 && group.right <= innerWidth };
    });
    assert.deepEqual(geometry, { grouped: true, fits: true }, `Project empty state at ${width}px`);
  }

  await page.setViewportSize({ width: 1280, height: 900 });
  const launcherId = await create.getAttribute('id');
  await create.click();
  const editor = page.getByRole('dialog', { name: '新建项目', exact: true });
  await editor.waitFor();
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  await page.waitForFunction(id => document.activeElement?.id === id, launcherId);
  assert.equal(await create.evaluate(node => node === document.activeElement), true,
    'Cancel restores focus to the empty-state create action');

  await create.click();
  await editor.getByRole('textbox', { name: '项目名称', exact: true }).fill('One project');
  await editor.getByRole('button', { name: '创建项目', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  await main.getByRole('region', { name: 'One project', exact: true }).waitFor();
  assert.equal(await main.getByRole('button', { name: '新建项目', exact: true }).count(), 1,
    'A populated list retains one clear create entry');
  assert.equal(await entries.locator('[data-semantic-key="project/empty"]').count(), 0,
    'The empty state disappears after creating a project');
  assert.equal(await main.locator('[data-page-region="collection-actions"]')
    .getByRole('button', { name: '新建项目', exact: true }).count(), 1,
    'The populated page places its single create entry in the heading');
  assert.equal((await command({ op: 'list_projects' })).length, 1);
});

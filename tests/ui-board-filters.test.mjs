import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('task board exposes ordinary model and unassigned filter choices', async t => {
  const { page } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '任务看板', exact: true }).click();
  await page.getByRole('button', { name: '筛选任务', exact: true }).click();
  const dialog = page.getByRole('dialog').last();
  for (const label of ['interactive-fixture', '未分配', '未分配项目']) {
    const choice = dialog.getByRole('checkbox', { name: label, exact: true });
    await choice.click();
    assert.equal(await choice.getAttribute('aria-checked'), 'true', label);
    await choice.click();
    assert.equal(await choice.getAttribute('aria-checked'), 'false', label);
  }
});

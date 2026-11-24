import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { browserFixture, openCreationEnvironment } from './fixtures/browser.mjs';

async function openProjectTask(fixture, name, workspace) {
  await fixture.command({ op: 'create_project', name, workspace: { roots: [workspace], primary_root: workspace } });
  await openProjectDraft(fixture.page, name);
  await fixture.page.getByRole('button', { name: 'Start task', exact: true }).waitFor();
}

async function openProjectDraft(page, name) {
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name, exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();
}

test('a captured Project submission preserves its workspace, the newer draft and navigation', async t => {
  const fixture = await browserFixture(t);
  const { page, root, command } = fixture;
  const workspace = path.join(root, 'Captured directory preparation');
  await mkdir(workspace);
  const submitted = Promise.withResolvers();
  const release = Promise.withResolvers();
  t.after(() => release.resolve());
  await page.route('**/api/browser/command', async route => {
    const request = route.request().postDataJSON();
    if (request.command?.op !== 'create') return route.continue();
    submitted.resolve();
    await release.promise;
    await route.continue();
  });
  await openProjectTask(fixture, 'Captured submission Project', workspace);
  const environment = await openCreationEnvironment(page);
  await environment.locator('button[data-logical-key="composer/workspace"]').click();
  const directories = page.getByRole('dialog', { name: '工作目录', exact: true });
  await directories.getByRole('button', { name: '移除目录', exact: true }).click();
  await directories.getByRole('textbox', { name: '目录路径', exact: true }).fill(workspace);
  await directories.getByRole('button', { name: '添加目录', exact: true }).click();
  await directories.getByText(workspace, { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await directories.waitFor({ state: 'hidden' });
  await environment.waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  const draft = page.getByRole('combobox', { name: 'Task', exact: true });
  await draft.fill('Run exactly this captured submission.');
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  await submitted.promise;
  await page.getByRole('region', { name: 'Conversation', exact: true })
    .getByText('Run exactly this captured submission.', { exact: true }).waitFor();
  await openProjectDraft(page, 'Captured submission Project');
  await draft.fill('Keep this later unsent draft.');
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
  release.resolve();
  const response = await receipt;
  assert.equal(response.status(), 200);
  const { reply } = await response.json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  const task = await command({ op: 'read', task_id: reply.result.task_id });
  assert.deepEqual(task.task.settings.workspace, { roots: [workspace], primary_root: workspace });
  assert.ok(JSON.stringify(task.messages).includes('Run exactly this captured submission.'));
  assert.ok(!JSON.stringify(task.messages).includes('Keep this later unsent draft.'));
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
  await openProjectDraft(page, 'Captured submission Project');
  assert.equal(await page.getByRole('combobox', { name: 'Task', exact: true }).inputValue(), 'Keep this later unsent draft.');
});

test('supporting controls compact and stack when measured space shrinks, then recover their full information', async t => {
  const fixture = await browserFixture(t);
  const { page, root } = fixture;
  const workspace = path.join(root, 'A readable workspace directory for supporting controls');
  await mkdir(workspace);
  await page.setViewportSize({ width: 1920, height: 1000 });
  await openProjectTask(fixture, 'Responsive controls acceptance', workspace);
  const supporting = page.getByLabel('Supporting controls', { exact: true });
  const commit = page.getByRole('button', { name: 'Start task', exact: true });
  await supporting.waitFor();
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Measure the responsive controls.');
  await page.waitForFunction(() => [...document.querySelectorAll('button')]
    .some(node => node.getAttribute('aria-label') === 'Start task' && !node.disabled));
  const fullText = await supporting.innerText();
  const names = await supporting.getByRole('button').evaluateAll(nodes => nodes.map(node => node.getAttribute('aria-label')));
  assert.ok(names.length > 0);
  await page.setViewportSize({ width: 320, height: 1000 });
  await page.waitForFunction(previous => {
    const group = document.querySelector('[aria-label="Supporting controls"]');
    return group && group.innerText.length < previous.length;
  }, fullText);
  assert.deepEqual(await supporting.getByRole('button').evaluateAll(nodes => nodes.map(node => node.getAttribute('aria-label'))), names,
    'Compact presentation keeps the same available settings');
  await page.setViewportSize({ width: 200, height: 1000 });
  await page.waitForFunction(() => {
    const group = document.querySelector('[aria-label="Supporting controls"]');
    const button = [...document.querySelectorAll('button')].find(node => node.getAttribute('aria-label') === 'Start task');
    if (!group || !button) return false;
    const controls = [...group.querySelectorAll('button')].map(node => node.getBoundingClientRect());
    const support = group.getBoundingClientRect(), commit = button.getBoundingClientRect();
    return controls.length > 1 && controls.at(-1).top >= controls[0].bottom - 1
      && support.right <= innerWidth + 1 && commit.right <= innerWidth + 1;
  });
  assert.equal(await commit.isVisible(), true, 'The primary action remains available beside the stacked compact settings');
  await page.setViewportSize({ width: 1920, height: 1000 });
  await page.waitForFunction(previous => document.querySelector('[aria-label="Supporting controls"]')?.innerText === previous, fullText);
  const [supportBounds, commitBounds] = await Promise.all([supporting.boundingBox(), commit.boundingBox()]);
  assert.ok(Math.min(supportBounds.y + supportBounds.height, commitBounds.y + commitBounds.height)
    > Math.max(supportBounds.y, commitBounds.y), 'Restored desktop capacity puts the controls back beside the primary action');
});

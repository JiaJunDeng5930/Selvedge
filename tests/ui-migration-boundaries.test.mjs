import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig } from '../host/config.mjs';
import { browserFixture } from './fixtures/browser.mjs';

async function openProjectTask(fixture, name, workspace) {
  await fixture.command({ op: 'create_project', name, workspace: { roots: [workspace], primary_root: workspace } });
  const { page } = fixture;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name, exact: true }).click();
  await page.getByRole('button', { name: 'Start task', exact: true }).waitFor();
}

test('a submitted Task survives directory preparation while newer writing and navigation remain intact', async t => {
  const fixture = await browserFixture(t);
  const { page, root, command } = fixture;
  const workspace = path.join(root, 'Captured directory preparation');
  await mkdir(workspace);
  let release, started, held = false;
  const preparation = new Promise(resolve => { started = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  t.after(() => release());
  await page.route('**/api/browser/observation', async route => {
    const request = route.request().postDataJSON();
    if (request.kind !== 'directories' || held) return route.continue();
    held = true;
    const response = await route.fetch();
    started();
    await gate;
    await route.fulfill({ response });
  });
  await openProjectTask(fixture, 'Captured submission Project', workspace);
  await page.locator('button[data-logical-key="composer/workspace"]').click();
  await page.getByRole('button', { name: 'Use as primary', exact: true }).click();
  await page.keyboard.press('Escape');
  const draft = page.getByRole('combobox', { name: 'Task', exact: true });
  await draft.fill('Run exactly this captured submission.');
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  await preparation;
  await draft.fill('Keep this later unsent draft.');
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '智能体', exact: true }).click();
  await page.getByRole('main').getByText('Agents', { exact: true }).waitFor();
  release();
  const response = await receipt;
  assert.equal(response.status(), 200);
  const { reply } = await response.json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  const task = await command({ op: 'read', task_id: reply.result.task_id });
  assert.deepEqual(task.task.settings.workspace, { roots: [workspace], primary_root: workspace });
  assert.ok(JSON.stringify(task.messages).includes('Run exactly this captured submission.'));
  assert.ok(!JSON.stringify(task.messages).includes('Keep this later unsent draft.'));
  await page.getByRole('main').getByText('Agents', { exact: true }).waitFor();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'Captured submission Project', exact: true }).click();
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

test('a saved Agent still shows its model ID and reasoning after that profile leaves the catalog', async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  await command({ op: 'save_board_agent', agent: '', revision: 0, name: 'Persisted inspection role',
    profile: fixture.profile, reasoning: 'high', instructions: 'Inspect the workspace.', concurrency: 1 });
  await fixture.restart({ profiles: defaultConfig.profiles });
  const navigation = await page.goto(fixture.running.url);
  assert.equal(navigation.status(), 200, 'The restarted browser entry must serve the application');
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '智能体', exact: true }).click();
  const agent = page.getByRole('heading', { name: 'Persisted inspection role', exact: true }).locator('..');
  await agent.getByText('Model', { exact: true }).waitFor();
  await agent.getByText(fixture.profile, { exact: true }).waitFor();
  await agent.getByText('Reasoning', { exact: true }).waitFor();
  await agent.getByText('high', { exact: true }).waitFor();
});

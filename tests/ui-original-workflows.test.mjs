import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('a Project task keeps its readable context and its primary and supporting actions', async t => {
  const { page, command, root } = await browserFixture(t);
  const workspace = path.join(root, 'Long path '.repeat(10).trim(), 'Original project workspace');
  await mkdir(workspace, { recursive: true });
  await writeFile(path.join(workspace, 'AGENTS.md'), 'Original Project guidance.');
  const project = await command({ op: 'create_project', name: 'Harbour 海港',
    workspace: { roots: [workspace], primary_root: workspace } });
  const savedProject = await command({ op: 'read_project', project_id: project.project_id });
  const revision = savedProject.guidance.revision;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'Harbour 海港', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();
  await page.getByText('新建对话 · Harbour 海港', { exact: true }).waitFor();

  const message = page.getByRole('combobox', { name: 'Task', exact: true });
  const commit = page.getByRole('button', { name: 'Start task', exact: true });
  const supporting = page.getByLabel('Supporting controls', { exact: true });
  await supporting.waitFor();
  assert.equal(await commit.isDisabled(), true, 'An empty draft must not start a Task');
  assert.ok(await supporting.getByRole('button').count() > 0,
    'Execution settings are supporting controls of this action');
  assert.equal(await supporting.locator('input, textarea, select').count(), 0,
    'Closed supporting properties must not become an expanded settings form');
  const [supportBounds, commitBounds, messageBounds] = await Promise.all([
    supporting.boundingBox(), commit.boundingBox(), message.boundingBox(),
  ]);
  assert.ok(supportBounds && commitBounds && messageBounds, 'The complete composer must be visible');
  assert.ok(Math.min(supportBounds.y + supportBounds.height, commitBounds.y + commitBounds.height)
    > Math.max(supportBounds.y, commitBounds.y),
  'At desktop capacity, supporting controls and the primary action share the composer action row');
  assert.ok(supportBounds.x + supportBounds.width <= commitBounds.x + 1,
    'The primary commit follows the supporting action group');
  assert.ok(commitBounds.y >= messageBounds.y + messageBounds.height - 1,
    'The action row belongs below the writing area');

  await message.fill('Preserve the original Project context.');
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().method() === 'POST');
  await commit.click();
  const response = await receipt;
  assert.equal(response.status(), 200);
  const { reply } = await response.json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  const { task } = await command({ op: 'read', task_id: reply.result.task_id });
  assert.equal(task.settings.project_id, project.project_id);
  assert.deepEqual(task.settings.workspace, { roots: [workspace], primary_root: workspace });
  await page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  await page.getByRole('button', { name: '任务详情', exact: true }).click();
  const details = page.getByRole('complementary', { name: '任务详情', exact: true });
  await details.getByText('Harbour 海港', { exact: true }).waitFor();
  for (const name of ['工作环境', '权限', '运行信息']) {
    const heading = details.getByRole('heading', { name, exact: true });
    await heading.waitFor();
    if (name !== '工作环境') {
      const separation = await heading.evaluate(node =>
        node.getBoundingClientRect().top -
        node.parentElement.previousElementSibling.lastElementChild.getBoundingClientRect().bottom);
      assert.ok(separation >= 12, `${name} is separated from the preceding section`);
    }
  }
  const pathText = details.getByText(workspace, { exact: true });
  assert.equal(await pathText.isVisible(), false, 'The compact summary shows the directory name before revealing its path');
  await details.getByText(`工作目录 · ${path.basename(workspace)}`, { exact: true }).click();
  await pathText.waitFor();
  assert.equal(await details.getByText(workspace, { exact: true }).count(), 1,
    'Task details show a shared working and guidance directory once');
  const pathLayout = await pathText.evaluate(node => {
    const range = document.createRange();
    range.selectNodeContents(node);
    const lines = [...range.getClientRects()];
    const region = node.closest('details').getBoundingClientRect();
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    let text;
    for (let current; (current = walker.nextNode());) if (current.length) text = current;
    const end = text.length;
    range.setStart(text, text.data.lastIndexOf('/') + 1);
    range.setEnd(text, end);
    return { lines: lines.length, fits: lines.every(line => line.left >= region.left && line.right <= region.right),
      directoryLines: range.getClientRects().length };
  });
  assert.ok(pathLayout.lines > 1 && pathLayout.fits, 'The full directory path wraps inside the narrow details');
  assert.equal(pathLayout.directoryLines, 1, 'A directory that fits a line wraps as a whole segment');
  const copy = details.getByRole('button', { name: '复制工作目录路径', exact: true });
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await copy.press('Enter');
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), workspace);
  await details.getByText('指引版本', { exact: true }).waitFor();
  await details.getByText(revision, { exact: true }).waitFor();
  const model = details.getByText('模型', { exact: true });
  const bottomRow = () => model.evaluate(label => {
    const body = label.closest('[data-surface-role="dialog-body"]');
    const viewport = body.getBoundingClientRect();
    const row = label.parentElement.getBoundingClientRect();
    return { fits: row.top >= viewport.top && row.bottom <= viewport.bottom, scrollable: body.scrollHeight > body.clientHeight };
  });
  assert.equal((await bottomRow()).fits, true, 'The expanded desktop details show the entire model row');
  await page.setViewportSize({ width: 1280, height: 360 });
  await page.waitForFunction(() => document.querySelector('[data-semantic-key="task-details"]')
    ?.getBoundingClientRect().bottom <= innerHeight);
  await model.scrollIntoViewIfNeeded();
  assert.deepEqual(await bottomRow(), { fits: true, scrollable: true },
    'A short details panel scrolls to expose the entire model row');
  await page.setViewportSize({ width: 1280, height: 900 });
});

test('a projectless task identifies its context without inventing a Project revision', async t => {
  const { page, command } = await browserFixture(t);
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  const { task } = await command({ op: 'read', task_id });
  const entry = page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true });
  const caption = entry.getByText(task.title, { exact: true });
  await caption.hover();
  assert.equal(await caption.getAttribute('title'), null, 'Hovering a fully visible title does not repeat the label');
  assert.equal(await entry.getAttribute('title'), null);
  assert.equal(await entry.getAttribute('data-help'), null);
  await entry.click();
  await page.getByRole('button', { name: '任务详情', exact: true }).click();
  const details = page.getByRole('complementary', { name: '任务详情', exact: true });
  await details.getByText('未关联项目', { exact: true }).waitFor();
  assert.equal(await details.getByText('项目指引', { exact: true }).count(), 0);
  assert.equal(await details.getByText('指引版本', { exact: true }).count(), 0,
    'A projectless task has no Project guidance revision');
});

test('interactive source disclosure controls the original Markdown fence without duplicating it', async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const source = `<ui id="original-source-owner">
<state id="count" type="integer" initial={0} min={0} max={10} />
<stack id="body">
<text id="count-label" label={"Original count: " + text(count)} />
<button id="increase" label="Increase original count" action="set" target="count" value={count + 1} />
</stack>
</ui>`;
  const requestIndex = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile: fixture.profile,
    message: 'Inspect the original interactive fence ownership.' });
  const deadline = Date.now() + 5000;
  while (fixture.requests.length <= requestIndex && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests.length > requestIndex, 'The service must request an actual model reply');
  fixture.finish(requestIndex, { text: '```text\nOrdinary fence remains readable\n```\n\n```selvedge-ui\n'
    + source + '\n```' });
  const { task } = await taskIdle(fixture.running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button').filter({ hasText: task.title }).click();
  const increase = page.getByRole('button', { name: 'Increase original count', exact: true });
  await increase.waitFor();
  const originalSource = page.getByRole('main').locator('pre').filter({ hasText: '<ui id="original-source-owner">' });
  const ordinarySource = page.getByRole('main').locator('pre').filter({ hasText: 'Ordinary fence remains readable' });
  assert.equal(await originalSource.count(), 1, 'One fence must own exactly one source element');
  assert.equal(await originalSource.isVisible(), false, 'The active preview hides its original source');
  assert.equal(await ordinarySource.isVisible(), true, 'Ordinary Markdown code remains readable');
  const sourceElement = await originalSource.elementHandle();

  await increase.click();
  await page.getByText('Original count: 1', { exact: true }).waitFor();
  await page.getByRole('button', { name: '展开源码', exact: true }).click();
  await originalSource.waitFor({ state: 'visible' });
  assert.equal(await originalSource.count(), 1, 'Disclosure must not append a second copy of the source');
  assert.equal(await originalSource.evaluate((node, original) => node === original, sourceElement), true,
    'Disclosure exposes the original Markdown source element');
  assert.equal(await ordinarySource.isVisible(), true, 'Disclosure targets the selected fence, not its preceding code block');
  await page.getByText('Original count: 1', { exact: true }).waitFor();
  await page.getByRole('button', { name: '收起源码', exact: true }).click();
  await originalSource.waitFor({ state: 'hidden' });
  assert.equal(await originalSource.evaluate((node, original) => node === original, sourceElement), true);
  await increase.click();
  await page.getByText('Original count: 2', { exact: true }).waitFor();
  assert.equal(fixture.requests.length, requestIndex + 1, 'Local preview actions must not call the model');
  assert.deepEqual(fixture.failures, []);
});

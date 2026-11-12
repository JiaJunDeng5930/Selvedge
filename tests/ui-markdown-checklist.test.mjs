import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('conversation checklists use one marker and align wrapped text with ordinary list items', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Show a release checklist.' });
  const checked = 'Verify the deployment checklist against all of the requirements before publishing the release.';
  const unchecked = 'Confirm the release notes.';
  const ordinary = 'The next release is on Monday.';
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests[0], 'The conversation started its model request');
  fixture.finish(0, { text: [`- [x] ${checked}`, `- [ ] ${unchecked}`, `- ${ordinary}`].join('\n') });
  const { task } = await taskIdle(running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  await page.setViewportSize({ width: 390, height: 700 });
  await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
  const timeline = page.getByRole('main').getByRole('region', { name: 'Conversation', exact: true });
  await timeline.getByText(ordinary, { exact: true }).waitFor();
  const items = timeline.getByRole('listitem');
  assert.equal(await items.count(), 3);
  const boxes = timeline.getByRole('checkbox');
  assert.equal(await boxes.count(), 2);
  assert.equal(await boxes.nth(0).isChecked(), true);
  assert.equal(await boxes.nth(1).isChecked(), false);
  assert.equal(await boxes.nth(0).isEnabled(), false);
  const geometry = await items.evaluateAll(elements => elements.map(item => {
    const marker = item.querySelector('input[type="checkbox"]')?.getBoundingClientRect();
    const text = [...item.childNodes].find(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim());
    const range = document.createRange();
    range.selectNodeContents(text);
    const lines = Array.from(range.getClientRects()).filter(rect => rect.width > 0);
    return {
      bullet: getComputedStyle(item).listStyleType !== 'none',
      markerInGutter: marker && marker.left >= 0 && marker.right < lines[0].left,
      textStart: lines[0].left,
      wrapped: lines.length > 1,
      aligned: lines.every(line => Math.abs(line.left - lines[0].left) < 1),
    };
  }));
  assert.deepEqual(geometry.map(item => item.bullet), [false, false, true]);
  assert.ok(geometry[0].wrapped && geometry[0].aligned, 'Wrapped checklist text has one consistent inset');
  assert.ok(geometry[0].markerInGutter && geometry[1].markerInGutter, 'Checkboxes occupy the list gutter');
  assert.ok(Math.abs(geometry[0].textStart - geometry[2].textStart) < 1, 'Mixed list text has a shared start');
});

test('interactive answer sections keep a readable outline and each source control with its own section', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Show two sections with controls.' });
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests[0], 'The conversation started its model request');
  const fence = (id, label, extra = '') => [
    '```selvedge-ui',
    `<ui id="${id}"><stack id="layout"><metric id="value" label="${label}" value="3"/>${extra}</stack></ui>`,
    '```',
  ].join('\n');
  fixture.finish(0, { text: [
    '这份答复包含两个交互章节。',
    '| 产品 | 数量 |\n| --- | --- |\n| 线轴 | 3 |\n| 织针 | 7 |',
    '## 1. 指标概览', fence('summary', '访问量'),
    '## 2. 详细检查', fence('detail', '完成项',
      '<table id="counts" label="产品明细" row-key="id" rows={[{id:"a",product:"线轴",count:3},{id:"b",product:"织针",count:7}]}><column id="product" field="product" label="产品"/><column id="count" field="count" label="数量"/></table><button id="reset" label="重置本区" action="reset"/>'),
    '```text\nOrdinary code with its own actions.\n```',
  ].join('\n\n') });
  const { task } = await taskIdle(running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const timeline = page.getByRole('main').getByRole('region', { name: 'Conversation', exact: true });
  const heading = timeline.getByRole('heading', { name: '2. 详细检查', exact: true });
  const panels = timeline.locator('.code-block[data-interactive-active="true"]');
  await panels.nth(1).waitFor();

  for (const width of [1280, 390]) {
    await page.setViewportSize({ width, height: 800 });
    if (width === 390) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const geometry = await heading.evaluate(node => {
      const before = node.previousElementSibling.getBoundingClientRect();
      const title = node.getBoundingClientRect();
      const caption = node.parentElement.querySelector(':scope > p');
      const code = node.nextElementSibling;
      const footer = code.querySelector('[data-semantic-key="interactive-markdown/source-controls"]');
      const action = footer.querySelector(':scope > button').getBoundingClientRect();
      const reset = footer.querySelector('[data-interactive-component="button"] button').getBoundingClientRect();
      const controls = footer.getBoundingClientRect();
      return {
        headingSize: parseFloat(getComputedStyle(node).fontSize),
        textSize: parseFloat(getComputedStyle(caption).fontSize),
        precedingGap: title.top - before.bottom,
        contentGap: code.getBoundingClientRect().top - title.bottom,
        footerInset: controls.left - code.getBoundingClientRect().left,
        sharesRow: Math.abs(action.top - reset.top) <= 1 && reset.right < action.left,
        footerFits: controls.left >= 0 && controls.right <= innerWidth + 1,
      };
    });
    assert.ok(geometry.headingSize > geometry.textSize, 'The section heading is larger than the explanation');
    assert.ok(geometry.precedingGap > geometry.contentGap, 'Section boundaries are clearer than gaps inside a section');
    assert.ok(Math.abs(geometry.footerInset) <= 2 && geometry.footerFits, 'The source action starts at its own section edge');
    assert.ok(geometry.sharesRow, 'Reset and source actions share one footer row');
    const tableChrome = await timeline.getByRole('table').evaluateAll(tables => tables.map(table => {
      const header = getComputedStyle(table.tHead.rows[0].cells[0]);
      const body = getComputedStyle(table.tBodies[0].rows[1].cells[0]);
      return [header.paddingInlineStart, header.borderBlockEnd, body.borderBlockStart, body.borderInlineEndWidth];
    }));
    assert.equal(tableChrome.length, 2);
    assert.deepEqual(tableChrome[0], tableChrome[1], 'Markdown and authored tables share the same header and row separators');
    assert.equal(tableChrome[0].at(-1), '0px');
  }

  const detail = panels.nth(1);
  const footer = detail.locator('[data-semantic-key="interactive-markdown/source-controls"]');
  const codeActions = detail.getByRole('toolbar', { name: 'Code actions', exact: true });
  await footer.getByRole('button', { name: '重置本区', exact: true }).waitFor();
  assert.equal(await codeActions.isVisible(), false);
  await timeline.locator('.code-block:has(code[data-language="text"])')
    .getByRole('button', { name: 'Copy code', exact: true }).waitFor();
  await footer.getByRole('button', { name: '展开源码', exact: true }).click();
  await detail.locator('pre').waitFor();
  const wrap = codeActions.getByRole('button', { name: 'Wrap code', exact: true });
  await wrap.click();
  assert.equal(await codeActions.getByRole('button', { name: 'Unwrap code', exact: true }).getAttribute('aria-pressed'), 'true');
  const sourceAfterPreview = await detail.evaluate(block =>
    block.querySelector('.code-toolbar').getBoundingClientRect().top >=
    block.querySelector('.interactive-markdown-target').getBoundingClientRect().bottom);
  assert.equal(sourceAfterPreview, true);
  assert.equal(await panels.nth(0).locator('pre').isVisible(), false);
  assert.match(await detail.locator('pre').textContent(), /id="detail"/);
  await footer.getByRole('button', { name: '收起源码', exact: true }).click();
  await codeActions.waitFor({ state: 'hidden' });
});

test('an execution error has one activity title and keeps its reason', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Inspect a provider failure.' });
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[0], 'The provider received the task request');
  fixture.requests[0].response.end('data: {"type":"response.failed","response":{"status":"failed"}}\n\n');
  const { task } = await taskIdle(running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const activity = page.getByRole('main').locator('section[data-expanded]').filter({
    has: page.getByRole('button', { name: '执行错误', exact: true }),
  });
  const disclosure = activity.getByRole('button', { name: '执行错误', exact: true });
  await disclosure.waitFor();
  if (await activity.getAttribute('data-expanded') === 'false') await disclosure.click();
  await activity.getByText('Model stream ended with response.failed', { exact: true }).waitFor();
  assert.equal(await activity.getByText('执行错误', { exact: true }).count(), 1);
});

test('interactive fences keep their original source collapsed while the preview is mounting', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Show a report with interactive sections.' });
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests[0], 'The provider received the task request');
  const sections = Array.from({ length: 17 }, (_, index) => [
    '```selvedge-ui',
    `<ui id="preview-${index}">${' '.repeat(2800)}<metric id="value" label="章节 ${index + 1}" value="3"/></ui>`,
    '```',
  ].join('\n'));
  fixture.finish(0, { text: [...sections, '```selvedge-ui example\nAn ordinary example.\n```'].join('\n\n') });
  const { task } = await taskIdle(running.service, task_id);
  await page.evaluate(() => {
    const probe = { flashing: false, running: true };
    window.fencePaintProbe = probe;
    function sample() {
      for (const code of document.querySelectorAll('pre > code')) {
        if (code.textContent.startsWith('<ui id="preview-') && code.getClientRects().length > 0) probe.flashing = true;
      }
      if (probe.running) requestAnimationFrame(sample);
    }
    requestAnimationFrame(sample);
  });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const timeline = page.getByRole('region', { name: 'Conversation', exact: true });
  const previews = timeline.locator('.code-block[data-interactive-active="true"]');
  await previews.nth(15).waitFor();
  await timeline.getByText('An ordinary example.', { exact: true }).waitFor();
  const flashing = await page.evaluate(() => {
    window.fencePaintProbe.running = false;
    return window.fencePaintProbe.flashing;
  });
  assert.equal(flashing, false, 'No interactive source is exposed before its preview or an explicit disclosure');
  const declined = timeline.locator('.code-block').filter({ hasText: '无法显示交互界面' });
  const raw = declined.locator('pre');
  await declined.getByRole('button', { name: '展开源码', exact: true }).click();
  await raw.waitFor();
  assert.match(await raw.innerText(), /preview-16/);
  await declined.getByRole('button', { name: '收起源码', exact: true }).click();
  await raw.waitFor({ state: 'hidden' });
});

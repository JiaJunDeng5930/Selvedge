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
  const fence = (id, label) => [
    '```selvedge-ui',
    `<ui id="${id}"><metric id="value" label="${label}" value="3"/></ui>`,
    '```',
  ].join('\n');
  fixture.finish(0, { text: [
    '这份答复包含两个交互章节。',
    '## 1. 指标概览', fence('summary', '访问量'),
    '## 2. 详细检查', fence('detail', '完成项'),
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
      const action = footer.querySelector('button').getBoundingClientRect();
      const controls = footer.getBoundingClientRect();
      return {
        headingSize: parseFloat(getComputedStyle(node).fontSize),
        textSize: parseFloat(getComputedStyle(caption).fontSize),
        precedingGap: title.top - before.bottom,
        contentGap: code.getBoundingClientRect().top - title.bottom,
        rightInset: controls.right - action.right,
        footerFits: controls.left >= 0 && controls.right <= innerWidth + 1,
      };
    });
    assert.ok(geometry.headingSize > geometry.textSize, 'The section heading is larger than the explanation');
    assert.ok(geometry.precedingGap > geometry.contentGap, 'Section boundaries are clearer than gaps inside a section');
    assert.ok(geometry.rightInset <= 2 && geometry.footerFits, 'The source action fits at its own section edge');
  }

  await panels.nth(1).getByRole('button', { name: '展开源码', exact: true }).click();
  await panels.nth(1).locator('pre').waitFor();
  assert.equal(await panels.nth(0).locator('pre').isVisible(), false);
  assert.match(await panels.nth(1).locator('pre').textContent(), /id="detail"/);
});

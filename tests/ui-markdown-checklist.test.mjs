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
  const fence = (id, children) => [
    '```selvedge-ui',
    `<ui id="${id}"><stack id="layout">${children}</stack></ui>`,
    '```',
  ].join('\n');
  const chart = (id, label) =>
    `<bar-chart id="${id}" label="${label}" data={[{id:"a",product:"线轴",count:3}]} row-key="id" x="product" y="count"/>`;
  fixture.finish(0, { text: [
    '这份答复包含四个交互章节。',
    '| 产品 | 数量 |\n| --- | --- |\n| 线轴 | 3 |\n| 织针 | 7 |',
    '## 1. 指标概览', fence('summary', '<metric id="value" label="访问量" value="3"/>'),
    '## 2. 详细检查', fence('detail',
      '<metric id="value" label="完成项" value="3"/><table id="counts" label="产品明细" row-key="id" rows={[{id:"a",product:"线轴",count:3},{id:"b",product:"织针",count:7}]}><column id="product" field="product" label="产品"/><column id="count" field="count" label="数量"/></table><button id="reset" label="重置本区" action="reset"/>'),
    '## 3. 单图', fence('single', chart('single-chart', '单图数据')),
    '## 4. 图表比较', fence('compare', chart('a', '甲') + chart('b', '乙')),
    '```text\nOrdinary code with its own actions.\n```',
  ].join('\n\n') });
  const { task } = await taskIdle(running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const timeline = page.getByRole('main').getByRole('region', { name: 'Conversation', exact: true });
  const heading = timeline.getByRole('heading', { name: '2. 详细检查', exact: true });
  const panels = timeline.locator('.code-block[data-interactive-active="true"]');
  const single = panels.filter({ has: page.getByText('单图数据', { exact: true }) });
  const compare = panels.filter({ has: page.getByText('乙', { exact: true }) });
  await compare.waitFor();

  for (const width of [1280, 390]) {
    await page.setViewportSize({ width, height: 800 });
    if (width === 390) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const geometry = await heading.evaluate(node => {
      const before = node.previousElementSibling.getBoundingClientRect();
      const title = node.getBoundingClientRect();
      const caption = node.parentElement.querySelector(':scope > p');
      const code = node.nextElementSibling;
      const footer = code.querySelector('[data-semantic-key="interactive-markdown/source-controls"]');
      const disclosure = footer.querySelector(':scope > button');
      const action = disclosure.getBoundingClientRect();
      const reset = footer.querySelector('[data-interactive-component="button"] button').getBoundingClientRect();
      const controls = footer.getBoundingClientRect();
      const standalone = node.previousElementSibling
        .querySelector('[data-semantic-key="interactive-markdown/source-controls"] > button')
        .getBoundingClientRect();
      const text = document.createRange();
      text.selectNodeContents(disclosure);
      return {
        headingSize: parseFloat(getComputedStyle(node).fontSize),
        textSize: parseFloat(getComputedStyle(caption).fontSize),
        precedingGap: title.top - before.bottom,
        contentGap: code.getBoundingClientRect().top - title.bottom,
        footerInset: controls.left - code.getBoundingClientRect().left,
        sharesRow: Math.abs(action.top + action.height / 2 - reset.top - reset.height / 2) <= 1 &&
          reset.right < action.left && Math.abs(reset.left - controls.left) <= 2,
        compactFooter: action.left - reset.right <= 8 &&
          Math.abs(standalone.left - controls.left) <= 2,
        quietSource: action.width >= 32 && action.height >= 32 && action.width < reset.width &&
          text.getBoundingClientRect().width <= 1,
        footerFits: controls.left >= 0 && controls.right <= innerWidth + 1,
      };
    });
    assert.ok(geometry.headingSize > geometry.textSize, 'The section heading is larger than the explanation');
    assert.ok(geometry.precedingGap > geometry.contentGap, 'Section boundaries are clearer than gaps inside a section');
    assert.ok(Math.abs(geometry.footerInset) <= 2 && geometry.footerFits, 'The footer fits its own section');
    assert.ok(geometry.sharesRow, 'Reset and source actions share one footer row');
    assert.ok(geometry.compactFooter, 'The source control stays beside its fence actions at the leading edge');
    assert.ok(geometry.quietSource, 'The source control is an icon with a full button target');
    const tableChrome = await timeline.getByRole('table').evaluateAll(tables => tables.map(table => {
      const header = getComputedStyle(table.tHead.rows[0].cells[0]);
      const body = getComputedStyle(table.tBodies[0].rows[1].cells[0]);
      return [header.paddingInlineStart, header.borderBlockEnd, body.borderBlockStart, body.borderInlineEndWidth];
    }));
    assert.equal(tableChrome.length, 2);
    assert.deepEqual(tableChrome[0], tableChrome[1], 'Markdown and authored tables share the same header and row separators');
    assert.equal(tableChrome[0].at(-1), '0px');
    const positions = async panel => {
      const source = panel.getByRole('button', { name: '展开源码', exact: true });
      const actions = await panel.getByText('查看数据', { exact: true }).all();
      return Promise.all([source, ...actions].map(action => action.boundingBox()));
    };
    const [singleSource, singleData] = await positions(single);
    assert.ok(singleSource.x + singleSource.width <= singleData.x &&
      singleData.x - (singleSource.x + singleSource.width) <= 8 &&
      Math.abs(singleSource.y - singleData.y) <= 1, 'One chart presents its source beside its data');
    const [compareSource, firstData, lastData] = await positions(compare);
    assert.ok(firstData.y < lastData.y && lastData.y + lastData.height <= compareSource.y &&
      compareSource.x <= lastData.x, 'Multiple charts have separate data controls and one shared source underneath');
  }

  const chartData = single.getByRole('table', { name: '图表数据', exact: true });
  await single.getByText('查看数据', { exact: true }).press('Enter');
  await chartData.waitFor();
  await single.getByRole('button', { name: '展开源码', exact: true }).press('Enter');
  await single.locator('pre').waitFor();
  assert.equal(await chartData.isVisible(), true);
  await single.getByRole('button', { name: '收起源码', exact: true }).press('Enter');
  await single.locator('pre').waitFor({ state: 'hidden' });
  assert.equal(await chartData.isVisible(), true);

  const detail = panels.nth(1);
  const footer = detail.locator('[data-semantic-key="interactive-markdown/source-controls"]');
  const codeActions = detail.getByRole('toolbar', { name: 'Code actions', exact: true });
  await footer.getByRole('button', { name: '重置本区', exact: true }).waitFor();
  assert.equal(await codeActions.isVisible(), false);
  await timeline.locator('.code-block:has(code[data-language="text"])')
    .getByRole('button', { name: 'Copy code', exact: true }).waitFor();
  const reveal = footer.getByRole('button', { name: '展开源码', exact: true });
  await reveal.hover();
  const help = button => button.evaluate(node => getComputedStyle(node, '::after').content);
  assert.equal(await help(reveal), '"展开源码"');
  assert.equal(await reveal.getAttribute('aria-expanded'), 'false');
  await reveal.press('Enter');
  await detail.locator('pre').waitFor();
  const hide = footer.getByRole('button', { name: '收起源码', exact: true });
  assert.ok(await hide.evaluate(node => node === document.activeElement));
  assert.equal(await hide.getAttribute('aria-expanded'), 'true');
  assert.equal(await help(hide), '"收起源码"');
  const wrap = codeActions.getByRole('button', { name: 'Wrap code', exact: true });
  await wrap.click();
  assert.equal(await codeActions.getByRole('button', { name: 'Unwrap code', exact: true }).getAttribute('aria-pressed'), 'true');
  const sourceAfterPreview = await detail.evaluate(block =>
    block.querySelector('.code-toolbar').getBoundingClientRect().top >=
    block.querySelector('.interactive-markdown-target').getBoundingClientRect().bottom);
  assert.equal(sourceAfterPreview, true);
  assert.equal(await panels.nth(0).locator('pre').isVisible(), false);
  assert.match(await detail.locator('pre').textContent(), /id="detail"/);
  await hide.click();
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
  fixture.finish(0, { text: [...sections, '```selvedge-ui example\nAn ordinary example.\n```', 'Settled reply ends here.'].join('\n\n') });
  const { task } = await taskIdle(running.service, task_id);
  await page.evaluate(() => {
    const probe = { flashing: false, pendingSeen: false, overlappingStatus: false, firstPaint: null, running: true };
    window.fencePaintProbe = probe;
    const painted = node => node.getClientRects().length > 0 && getComputedStyle(node).visibility === 'visible';
    function sample() {
      for (const code of document.querySelectorAll('pre > code')) {
        if (code.textContent.startsWith('<ui id="preview-') && painted(code)) probe.flashing = true;
      }
      const loading = [...document.querySelectorAll('main [role="status"]')].some(status =>
        status.textContent === '正在加载对话…' && painted(status));
      if (loading) probe.pendingSeen = true;
      const reader = document.querySelector('main section[aria-label="Conversation"]');
      const readerVisible = reader && painted(reader) && Number(getComputedStyle(reader).opacity) > 0;
      if (loading && readerVisible) probe.overlappingStatus = true;
      if (probe.firstPaint === null && readerVisible) {
        const tail = [...reader.querySelectorAll('p')].find(node => node.textContent === 'Settled reply ends here.');
        const visible = node => {
          if (!node || !painted(node)) return false;
          const bounds = node.getBoundingClientRect(), viewport = reader.getBoundingClientRect();
          return bounds.top >= viewport.top - 1 && bounds.bottom <= viewport.bottom + 1;
        };
        probe.firstPaint = { tail: visible(tail) };
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
  const probe = await page.evaluate(() => {
    window.fencePaintProbe.running = false;
    return window.fencePaintProbe;
  });
  assert.equal(probe.flashing, false, 'No interactive source is exposed before its preview or an explicit disclosure');
  assert.equal(probe.pendingSeen, true, 'A delayed history gives one visible loading status');
  assert.equal(probe.overlappingStatus, false, 'The conversation loading status never overlays visible content');
  assert.equal(await page.getByText('正在加载对话…', { exact: true }).isVisible(), false);
  assert.deepEqual(probe.firstPaint, { tail: true }, 'The first visible viewport includes the conversation tail');
  await timeline.getByRole('button', { name: '创建对话分支', exact: true }).waitFor();
  const declined = timeline.locator('.code-block').filter({ hasText: '无法显示交互界面' });
  const raw = declined.locator('pre');
  const reveal = declined.getByRole('button', { name: '展开源码', exact: true });
  assert.equal(await reveal.textContent(), '');
  assert.equal(await reveal.getAttribute('aria-expanded'), 'false');
  await reveal.press('Enter');
  await raw.waitFor();
  assert.match(await raw.innerText(), /preview-16/);
  const hide = declined.getByRole('button', { name: '收起源码', exact: true });
  assert.ok(await hide.evaluate(node => node === document.activeElement));
  assert.equal(await hide.getAttribute('aria-expanded'), 'true');
  await hide.press('Enter');
  await raw.waitFor({ state: 'hidden' });
});

test('opening a running conversation lands at the available reply without replaying its history', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile, running } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Prepare a detailed report.' });
  const deadline = Date.now() + 15_000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests[0]);
  const earlier = Array.from({ length: 7 }, (_, index) => [
    `## Report section ${index + 1}`, 'Prior report text. '.repeat(250),
    '```selvedge-ui\n' + `<ui id="report-${index}"><metric id="total" label="Total" value="4"/></ui>` + '\n```',
  ].join('\n\n')).join('\n\n');
  fixture.finish(0, { text: earlier });
  const { task } = await taskIdle(running.service, task_id);
  const question = 'Continue the detailed report.';
  await command({ op: 'send', task_id, message: question });
  const liveDeadline = Date.now() + 15_000;
  while (!fixture.requests[1] && Date.now() < liveDeadline) await delay(10);
  assert.ok(fixture.requests[1]);
  const live = 'Live reply at the end.';
  fixture.emit(1, live + '\n\n```selvedge-ui\n<ui id="new-report">\n');
  await page.evaluate(({ question, live }) => {
    window.firstRunningConversation = new Promise(resolve => {
      const sample = () => {
        const reader = document.querySelector('main section[aria-label="Conversation"]');
        if (!reader || getComputedStyle(reader).opacity === '0' || getComputedStyle(reader).visibility !== 'visible') {
          requestAnimationFrame(sample);
          return;
        }
        const view = reader.getBoundingClientRect();
        const inView = text => [...reader.querySelectorAll('p')].some(node => {
          if (node.textContent !== text) return false;
          const rect = node.getBoundingClientRect();
          return rect.top >= view.top && rect.bottom <= view.bottom;
        });
        resolve({ latestMessage: inView(question), liveReply: inView(live) });
      };
      requestAnimationFrame(sample);
    });
  }, { question, live });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const timeline = page.getByRole('region', { name: 'Conversation', exact: true });
  await timeline.getByText(live, { exact: true }).waitFor();
  assert.deepEqual(await page.evaluate(() => window.firstRunningConversation),
    { latestMessage: true, liveReply: true });
  const more = 'The next part continues below.';
  fixture.emit(1, '<metric id="live" label="Live total" value="5"/></ui>\n```\n\n' + more + '\n\n');
  await timeline.getByText(more, { exact: true }).waitFor();
  assert.equal(await page.getByText('正在加载对话…', { exact: true }).isVisible(), false);
  fixture.finish(1);
});

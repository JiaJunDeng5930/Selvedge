import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function selectTask(fixture, taskId) {
  const { task } = await fixture.command({ op: 'read', task_id: taskId });
  await fixture.page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  await fixture.page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  return task;
}

async function publicCommand(running, command) {
  const response = await fetch(`${running.address}/api/commands`, {
    method: 'POST', headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    body: JSON.stringify(command),
  });
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  assert.equal(body.ok, true, JSON.stringify(body));
  return body.result;
}

function overlapsVertically(a, b) {
  return Math.min(a.y + a.height, b.y + b.height) > Math.max(a.y, b.y);
}

// The observable is the space returned to the conversation, rather than a particular grid or CSS class.
test('conversation navigation releases desktop space and preserves the draft through drawer navigation', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  await page.setViewportSize({ width: 1024, height: 900 });
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  const task = await selectTask(fixture, task_id);
  const main = page.getByRole('main');
  const message = page.getByRole('combobox', { name: 'Message', exact: true });
  assert.equal(await message.getAttribute('placeholder'), 'Write a message…');
  const title = main.getByText(task.title, { exact: true }).first();
  const details = main.getByRole('button', { name: 'Task details', exact: true });
  const [titleBounds, actionBounds, expanded] = await Promise.all([
    title.boundingBox(), details.boundingBox(), main.boundingBox(),
  ]);
  assert.ok(overlapsVertically(titleBounds, actionBounds), 'The conversation title and actions share their heading row');
  await message.fill('Keep this draft while changing navigation capacity.');
  await page.getByRole('button', { name: /Collapse.*(?:Task|sidebar)/ }).click();
  const expand = page.getByRole('button', { name: /Expand.*(?:Task|sidebar)/ });
  await expand.waitFor();
  const collapsed = await main.boundingBox();
  assert.ok(collapsed.width > expanded.width + 100,
    `Collapsing the sidebar must return its column to the conversation (${expanded.width} to ${collapsed.width})`);
  assert.equal(await page.getByRole('navigation', { name: 'Task tree', exact: true }).isVisible(), false);
  await expand.click();
  await page.getByRole('navigation', { name: 'Task tree', exact: true }).waitFor();
  const restored = await main.boundingBox();
  assert.ok(Math.abs(restored.width - expanded.width) <= 2, 'Expanding restores the usable desktop navigation');
  await message.focus();
  await page.setViewportSize({ width: 450, height: 900 });
  assert.equal(await message.evaluate(node => document.activeElement === node), true);
  const launcher = page.getByRole('button', { name: 'Open Task list', exact: true });
  await launcher.focus();
  await launcher.press('Space');
  await page.getByRole('dialog', { name: '对话', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await page.getByRole('dialog', { name: '对话', exact: true }).waitFor({ state: 'hidden' });
  assert.equal(await launcher.evaluate(node => document.activeElement === node), true);
  assert.equal(await message.inputValue(), 'Keep this draft while changing navigation capacity.');
});

test('task and conversation composers keep controls usable as width and height change', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const main = page.getByRole('main');
  const sizes = [
    { width: 320, height: 568 },
    { width: 390, height: 420 },
    { width: 568, height: 320 },
    { width: 700, height: 900 },
    { width: 1280, height: 900 },
  ];

  async function checkComposer(scope, { width, height }, creating = false) {
    await page.setViewportSize({ width, height });
    const message = scope.getByRole('combobox', { name: creating ? 'Task' : 'Message', exact: true });
    await message.waitFor();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    const form = await message.evaluate(node => node.form.getBoundingClientRect().toJSON());
    const messageBox = await message.boundingBox();
    const messageFontSize = await message.evaluate(node => Number.parseFloat(getComputedStyle(node).fontSize));
    const targets = [
      scope.getByLabel('Attach files', { exact: true }), scope.locator('summary[aria-label="Voice"]'),
      scope.getByRole('button', { name: creating ? 'Start task' : 'Send', exact: true }),
      scope.getByRole('button', { name: /^Permissions:/ }), scope.getByRole('button', { name: /^Model:/ }),
      ...(creating ? [] : [scope.getByRole('button', { name: /^Delivery:/ })]),
    ];
    const bounds = await Promise.all(targets.map(target => target.boundingBox()));
    const size = `${width}×${height}`;
    assert.ok(form.top >= 0 && form.bottom <= height + 1, size);
    assert.ok(messageBox && messageBox.width > 0 && messageBox.height > 0 &&
      messageBox.x >= form.left - 1 && messageBox.x + messageBox.width <= form.right + 1,
      `${size}: message input remains visible within the composer`);
    if (width <= 390) {
      assert.ok(messageFontSize >= 16, `${size}: message text must remain readable without mobile input zoom`);
      const documentWidth = await page.evaluate(() => document.documentElement.scrollWidth);
      assert.ok(documentWidth <= width + 1, `${size}: the page must not need horizontal scrolling`);
      const commonActions = bounds.slice(0, 3);
      for (const box of commonActions) {
        assert.ok(box && box.width >= 44 && box.height >= 44,
          `${size}: attachment, voice and send need 44×44 touch targets`);
      }
      const tops = commonActions.map(box => box.y);
      assert.ok(Math.max(...tops) - Math.min(...tops) <= 2,
        `${size}: attachment, voice and send stay in one control row`);
    }
    for (const [index, box] of bounds.entries()) {
      assert.ok(box && box.width >= 32 && box.height >= 32, `${size}: control ${index} has an unusable target`);
      assert.ok(box.x >= form.left - 1 && box.x + box.width <= form.right + 1 &&
        box.y >= form.top - 1 && box.y + box.height <= form.bottom + 1, `${size}: control ${index} exceeds the composer`);
      for (const other of bounds.slice(0, index)) {
        assert.ok(!overlapsVertically(box, other) || box.x + box.width <= other.x + 1 ||
          other.x + other.width <= box.x + 1, `${size}: composer controls overlap`);
      }
    }
  }

  for (const size of sizes.filter(size => size.width <= 390)) await checkComposer(main, size, true);
  await page.setViewportSize({ width: 1280, height: 900 });
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  const task = await selectTask(fixture, task_id);
  await main.getByRole('heading', { name: task.title, exact: true }).waitFor();
  for (const size of sizes) await checkComposer(main, size);
  await main.getByRole('combobox', { name: 'Message', exact: true }).fill('/side');
  await main.getByRole('button', { name: 'Send', exact: true }).click();
  const side = page.getByRole('complementary', { name: 'Side conversation', exact: true })
    .or(page.getByRole('dialog'));
  for (const size of sizes) await checkComposer(side, size);
});

// A public command updates the card between form preparation and its real HTTP submission.
test('a rejected card edit keeps its diagnostic visible as an assertive alert', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const card = await command({ op: 'create_card', title: 'Conflicting card edit', description: 'Original description' });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const cardRegion = page.locator('[data-surface-role="card"][aria-label="Conflicting card edit"]');
  await cardRegion.waitFor();
  await cardRegion.getByRole('button', { name: '卡片操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑卡片', exact: true }).click();
  const dialog = page.getByRole('dialog').last();
  await dialog.getByRole('textbox', { name: '标题', exact: true }).fill('Keep my unsaved title');
  let intercepted = false;
  await page.route('**/api/browser/command', async route => {
    if (intercepted || route.request().postDataJSON()?.command?.op !== 'update_card') return route.continue();
    intercepted = true;
    await publicCommand(fixture.running, { op: 'update_card', card_id: card.card_id, revision: card.revision,
      observed_at: String(Math.floor(Date.now() / 1000)), description: 'A competing public update' });
    await route.continue();
  });
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === 'update_card');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  const { reply } = await (await receipt).json();
  assert.ok(intercepted);
  assert.equal(reply.ok, false, JSON.stringify(reply));
  assert.equal(reply.error.code, 'card_conflict');
  const alert = dialog.getByRole('alert');
  await alert.waitFor();
  assert.equal(await alert.innerText(), `${reply.error.code}: ${reply.error.message}`);
  assert.equal(await dialog.getByRole('textbox', { name: '标题', exact: true }).inputValue(), 'Keep my unsaved title');
});

// Chart accessibility is exercised through the model protocol and ordinary Markdown publication.
test('model charts and range controls keep their values readable', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const source = `<ui id="monthly-report">
<state id="seats" type="integer" initial={8} min={1} max={50} />
<stack id="report">
<line-chart id="monthly" data={[{id:"a",month:"Jan",value:2},{id:"b",month:"Feb",value:3}]}
 row-key="id" x="month" y="value" x-label="Month" y-label="Value" />
<bar-chart id="revenue" label="各产品收入对比"
 data={[{id:"a",product:"产品 A",income:2},{id:"b",product:"产品 B",income:3},{id:"c",product:"产品 C",income:5},
 {id:"d",product:"产品 D",income:6},{id:"e",product:"产品 E",income:7},{id:"f",product:"产品 F",income:8}]}
 row-key="id" x="product" y="income" x-label="产品" y-label="收入（万元）" />
<slider id="seats-slider" bind="seats" label="Seats" />
</stack>
</ui>`;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile: fixture.profile, message: 'Monthly chart accessibility' });
  const deadline = Date.now() + 10000;
  while (fixture.requests.length <= index && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests.length > index, 'The actual service must request its model response');
  fixture.finish(index, { text: '```selvedge-ui\n' + source + '\n```' });
  await taskIdle(fixture.running.service, task_id);
  await selectTask(fixture, task_id);
  const main = page.getByRole('main');
  const line = main.getByRole('img', { name: /^Value \/ Month/ });
  const bars = main.getByRole('img', { name: /^收入（万元） \/ 产品/ });
  await line.getByText('Jan', { exact: true }).waitFor();
  assert.equal(await line.getByText('Feb', { exact: true }).isVisible(), true);
  assert.equal(await line.getByText('0', { exact: true }).isVisible(), true);
  assert.equal(await line.getByText('3', { exact: true }).isVisible(), true);
  await bars.getByText('收入（万元）', { exact: true }).waitFor();
  for (const product of ['产品 A', '产品 B', '产品 C', '产品 D', '产品 E', '产品 F']) {
    assert.equal(await bars.getByText(product, { exact: true }).isVisible(), true);
  }
  const barChart = bars.locator('xpath=../..');
  const geometry = await bars.evaluate(svg => {
    const lines = Array.from(svg.querySelectorAll('line'));
    const yAxis = lines.find(line => line.x1.baseVal.value === line.x2.baseVal.value);
    const baseline = Math.max(...lines.filter(line => line !== yAxis).map(line => line.y1.baseVal.value));
    const path = svg.querySelector('path');
    const plot = path.getBBox();
    const summary = svg.parentElement.parentElement.querySelector('summary');
    return {
      endsAtBaseline: yAxis.y2.baseVal.value === baseline && plot.y + plot.height === baseline,
      quietAxis: Number(getComputedStyle(yAxis).opacity) < 1,
      accent: path.getAttribute('fill'),
      gap: summary.getBoundingClientRect().top - svg.getBoundingClientRect().bottom,
    };
  });
  assert.equal(geometry.endsAtBaseline, true, 'A positive chart ends both the bars and y axis at zero');
  assert.equal(geometry.quietAxis, true);
  assert.equal(geometry.accent, 'var(--color-token-icon-accent)');
  assert.ok(geometry.gap >= 0 && geometry.gap <= 12, 'The chart does not reserve a blank area below the plot');
  const lineChart = line.locator('xpath=../..');
  const disclosure = lineChart.getByText('查看数据', { exact: true });
  assert.equal(await barChart.getByRole('table').isVisible(), false);
  assert.equal(await lineChart.getByRole('table').isVisible(), false);
  await disclosure.focus();
  await page.keyboard.press('Enter');
  const table = lineChart.getByRole('table', { name: '图表数据', exact: true });
  await table.waitFor();
  assert.equal(await table.evaluate(node => node.localName), 'table', 'Passive chart data uses a native accessible table');
  assert.deepEqual(await table.getByRole('columnheader').allTextContents(), ['Month', 'Value']);
  assert.equal(await table.getByRole('row').count(), 3, 'The header and both source data rows remain readable');
  assert.deepEqual(await table.getByRole('cell').allTextContents(), ['Jan', '2', 'Feb', '3']);
  await disclosure.focus();
  await page.keyboard.press('Enter');
  await table.waitFor({ state: 'hidden' });
  await page.setViewportSize({ width: 390, height: 844 });
  await bars.getByText('产品 F', { exact: true }).waitFor();
  const fits = await bars.evaluate(svg => {
    const bounds = svg.getBoundingClientRect();
    return Array.from(svg.querySelectorAll('text')).every(label => {
      const rect = label.getBoundingClientRect();
      return rect.left >= bounds.left && rect.right <= bounds.right;
    });
  });
  assert.equal(fits, true, 'Axis text fits the plotted surface on narrow screens');
  const seats = page.getByRole('slider', { name: 'Seats', exact: true });
  const shownValue = value => seats.locator('..').getByText(value, { exact: true });
  await shownValue('8').waitFor();
  await seats.press('ArrowRight');
  await shownValue('9').waitFor();
});

async function accessibleDescription(control) {
  return control.evaluate(node => (node.getAttribute('aria-describedby') ?? '').split(/\s+/).filter(Boolean)
    .map(id => document.getElementById(id)?.textContent ?? '').filter(Boolean).join(' '));
}

test('keyboard users can read unavailable action reasons, choice context and collapsed activity summaries', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  assert.equal(await start.isDisabled(), true);
  await start.focus();
  assert.equal(await start.evaluate(node => document.activeElement === node), true,
    'An unavailable action must keep its explanation reachable by keyboard');
  assert.match(await accessibleDescription(start), /A task input needs text or an image/);
  assert.equal(await page.getByText('A task input needs text or an image', { exact: true }).first().isVisible(), true);
  await page.getByRole('button', { name: /^Permissions:/ }).click();
  const automatic = page.getByRole('menuitemradio', { name: 'Automatic review', exact: true });
  await automatic.focus();
  assert.match(await accessibleDescription(automatic), /echo/,
    'The reviewer context of a permission choice belongs to its accessible description');
  assert.match(await accessibleDescription(automatic), /Workspace write/);
  await page.keyboard.press('Escape');

  const { task_id } = await command({ op: 'create', profile: 'demo', message: 'A readable activity summary' });
  await taskIdle(fixture.running.service, task_id);
  await selectTask(fixture, task_id);
  const main = page.getByRole('main');
  assert.equal(await main.getByRole('button', { name: /0 operations|Conversation event/ }).count(), 0,
    'Bookkeeping alone does not create an activity disclosure');
  await command({ op: 'compact', task_id, summary: 'This conversation tested the activity summary.' });
  const summary = main.getByRole('button', { name: 'Context compacted', exact: true });
  await summary.waitFor();
  assert.equal(await summary.getAttribute('aria-expanded'), 'false');
  await summary.click();
  await main.getByText('Context compacted; original conversation retained.', { exact: true }).waitFor();
  await summary.click();
  assert.equal(await summary.getAttribute('aria-expanded'), 'false');
});

test('execution controls appear beside active work and stay out of conversation details', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { task_id } = await command({ op: 'create', profile: fixture.profile, message: 'Stop this running reply' });
  await selectTask(fixture, task_id);
  const main = page.getByRole('main');
  const stop = main.getByRole('button', { name: 'Stop current execution', exact: true });
  await stop.waitFor();
  await main.getByRole('button', { name: 'Task details', exact: true }).click();
  const details = page.getByRole('complementary', { name: 'Task details', exact: true });
  await details.waitFor();
  assert.equal(await details.getByRole('button', { name: /Stop current execution|Fork from current history|Pause conversation/ }).count(), 0);
  await main.getByRole('button', { name: 'Task details', exact: true }).click();
  await stop.click();
  await stop.waitFor({ state: 'hidden' });
  assert.equal((await command({ op: 'read', task_id })).task.status, 'stopped');
});

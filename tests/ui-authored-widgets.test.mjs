import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function showWidgetAnswer(fixture, prompt, source) {
  const { page, command, profile } = fixture;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile, message: prompt });
  const deadline = Date.now() + 10000;
  while (!fixture.requests[index] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[index], 'The provider receives the report request');
  fixture.finish(index, { text: `\`\`\`selvedge-ui\n${source}\n\`\`\`` });
  await taskIdle(fixture.running.service, task_id);
  const report = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: report.task.title, exact: true }).click();
  return task_id;
}

test('authored motion, metrics and tables remain readable in the conversation', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page } = fixture;
  const rows = Array.from({ length: 101 }, (_, i) => `{id:"${i}", name:"Product ${i + 1}"}`).join(',');
  const title = '产品明细（可点击列标题排序）';
  const source = `<ui id="widget-report">
  <stack id="report">
    <row-layout id="animations" gap="sm">
      <badge id="pulse" label="Pulse · 呼吸效果" motion="pulse" />
      <badge id="spin" label="Spin · 旋转效果" motion="spin" />
      <badge id="status" label="Transition · 状态过渡" transition="status" />
    </row-layout>
    <metric id="budget" label="总预算" value={9000} format="currency:CNY" />
    <grid id="prices" columns={3} gap="md">
      <metric id="original-price" label="原价" value={299} format="currency:CNY" />
      <metric id="discount" label="优惠比例" value={0.2} format="percent" />
      <metric id="amount-due" label="应付金额" value={219} format="currency:CNY" tone="success" />
    </grid>
    <row-layout id="metric-comparison" gap="sm">
      <card id="counts" label="普通数值">
        <metric id="visits" label="访问量" value={123456} format="number" />
      </card>
      <card id="cny" label="人民币">
        <metric id="sales" label="销售额" value={987654.32} format="currency:CNY" tone="success" />
      </card>
      <card id="usd" label="美元">
        <metric id="contract" label="合同额" value={12345.67} format="currency:USD" />
      </card>
      <card id="percent" label="百分比">
        <metric id="completion" label="完成比例" value={0.72} format="percent" />
      </card>
    </row-layout>
    <card id="products" label="示例数据">
      <table id="details" label="${title}" rows={[{id:"a",name:"007",revenue:2},{id:"b",name:"Beta",revenue:8},{id:"c",name:"Gamma",revenue:3},{id:"d",name:"Delta",revenue:4},{id:"e",name:"Echo",revenue:5},{id:"f",name:"Foxtrot",revenue:6}]} row-key="id" sortable={true}>
        <column id="name" field="name" label="产品" />
        <column id="revenue" field="revenue" label="收入" format="currency:CNY" />
      </table>
    </card>
    <table id="paged" label="产品目录" rows={[${rows}]} row-key="id">
      <column id="product" field="name" label="名称" />
    </table>
  </stack>
</ui>`;
  await showWidgetAnswer(fixture, 'Display a visual widget report', source);

  const main = page.getByRole('main');
  const spin = main.getByText('Spin · 旋转效果', { exact: true });
  const arranged = direction => main.locator(`[data-interactive-component="row-layout"][data-native-row-direction="${direction}"]`)
    .filter({ hasText: 'Spin · 旋转效果' });
  await arranged('row').waitFor();
  const motionGeometry = () => spin.evaluate(label => {
    const cell = label.closest('[data-interactive-motion="spin"]');
    const row = cell.parentElement;
    const icon = cell.querySelector('svg').getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(label);
    const lines = [...range.getClientRects()];
    return {
      cells: [...row.children].map(node => node.getBoundingClientRect().toJSON()),
      readable: lines.length === 1 && icon.right <= lines[0].left && icon.bottom > lines[0].top && icon.top < lines[0].bottom,
      withinViewport: row.getBoundingClientRect().right <= innerWidth && row.scrollWidth <= row.clientWidth + 1,
    };
  });
  const desktop = await motionGeometry();
  assert.equal(desktop.cells.length, 3);
  assert.ok(desktop.cells.every(cell => Math.abs(cell.width - desktop.cells[0].width) <= 1 && cell.y === desktop.cells[0].y),
    'The three animations have equal space in the same row on desktop');
  assert.ok(desktop.readable && desktop.withinViewport, 'The spinner and its whole label share one line');

  const number = main.getByText('123,456', { exact: true });
  const metricName = main.getByText('访问量', { exact: true });
  const formatCue = main.getByText('普通数值', { exact: true });
  const fontSize = locator => locator.evaluate(node => parseFloat(getComputedStyle(node).fontSize));
  const metricOrder = async (label, amount) => {
    const name = main.getByText(label, { exact: true });
    const value = main.getByText(amount, { exact: true });
    const [labelBox, valueBox] = await Promise.all([name.boundingBox(), value.boundingBox()]);
    assert.ok(labelBox.y + labelBox.height <= valueBox.y && await fontSize(value) > await fontSize(name),
      `${label} appears above its larger value`);
    return labelBox;
  };
  await metricOrder('总预算', '¥9,000.00');
  await main.locator('[data-native-row-direction="row"]')
    .filter({ hasText: '应付金额' }).waitFor();
  const originalPrice = await metricOrder('原价', '¥299.00');
  const discount = await metricOrder('优惠比例', '20%');
  const amountDue = await metricOrder('应付金额', '¥219.00');
  assert.ok(originalPrice.x < discount.x && discount.x < amountDue.x &&
    [discount, amountDue].every(label => Math.abs(originalPrice.y - label.y) <= 1),
    'Metrics with different value sizes align their labels at the top of the desktop row');
  assert.ok((await metricName.boundingBox()).y < (await number.boundingBox()).y &&
    (await number.boundingBox()).y < (await formatCue.boundingBox()).y,
    'The metric name precedes its value and the separate card caption follows');
  assert.ok(await fontSize(number) > await fontSize(metricName) && await fontSize(metricName) > await fontSize(formatCue));
  const sales = main.getByText('¥987,654.32', { exact: true });
  const salesName = main.getByText('销售额', { exact: true });
  const currencyCue = main.getByText('人民币', { exact: true });
  assert.ok((await salesName.boundingBox()).y < (await sales.boundingBox()).y &&
    (await sales.boundingBox()).y < (await currencyCue.boundingBox()).y);
  assert.ok(await fontSize(sales) > await fontSize(number),
    'The emphasized currency retains its larger value');
  const amountFits = () => sales.evaluate(node => {
    const text = document.createRange();
    text.selectNodeContents(node);
    return text.getClientRects().length === 1 && node.scrollWidth <= node.clientWidth + 1;
  });
  assert.equal(await amountFits(), true, 'The emphasized amount reads on one line');
  const comparison = () => metricName.evaluate(label => {
    const group = label.closest('[data-interactive-component="row-layout"]');
    const cards = [...group.children].map(card => ({
      box: card.getBoundingClientRect(),
      label: card.querySelector('[data-semantic-key="interactive-markdown/metric-label"]').getBoundingClientRect(),
    }));
    const firstTop = cards[0].box.top;
    return {
      columns: cards.filter(card => Math.abs(card.box.top - firstTop) <= 1).length,
      aligned: cards.every((card, index) => cards.slice(index + 1).every(next =>
        Math.abs(card.box.top - next.box.top) > 1 ||
        Math.abs(card.box.bottom - next.box.bottom) <= 1 && Math.abs(card.label.bottom - next.label.bottom) <= 1)),
      fits: group.scrollWidth <= group.clientWidth + 1 &&
        cards.every(card => card.box.left >= 0 && card.box.right <= innerWidth),
    };
  });
  assert.deepEqual(await comparison(), { columns: 4, aligned: true, fits: true },
    'The desktop comparison aligns card outlines and metric labels');

  const details = main.getByRole('table', { name: title, exact: true });
  const single = details.locator('..');
  await details.waitFor();
  assert.equal(await main.getByText(title, { exact: true }).count(), 1);
  assert.equal(await main.getByText('示例数据', { exact: true }).count(), 1);
  await single.getByText('共 6 行', { exact: true }).waitFor();
  assert.equal(await single.getByRole('button', { name: /上一页|下一页/ }).count(), 0);
  const firstAmount = details.getByRole('cell', { name: '¥2.00', exact: true });
  await firstAmount.waitFor();
  const align = cell => cell.evaluate(node => getComputedStyle(node).textAlign);
  assert.match(await align(firstAmount), /^(end|right)$/);
  assert.match(await align(details.getByRole('columnheader', { name: '收入', exact: true })), /^(end|right)$/);
  assert.match(await align(details.getByRole('cell', { name: '007', exact: true })), /^(start|left)$/,
    'Text that resembles a number retains text alignment');
  const sort = details.getByRole('button', { name: '收入', exact: true });
  const textRight = locator => locator.evaluate(node => {
    const range = document.createRange();
    range.selectNodeContents(node);
    return range.getBoundingClientRect().right;
  });
  assert.ok(Math.abs(await textRight(sort) - await textRight(firstAmount)) <= 1,
    'The sortable column title aligns with its numeric values');
  await sort.click();
  await details.locator('th[aria-sort="ascending"]').waitFor();
  await sort.click();
  await details.locator('th[aria-sort="descending"]').waitFor();
  assert.deepEqual(await details.getByRole('row').nth(1).getByRole('cell').allTextContents(), ['Beta', '¥8.00']);

  const paged = main.getByRole('table', { name: '产品目录', exact: true });
  const pages = paged.locator('..');
  const next = pages.getByRole('button', { name: '下一页', exact: true });
  const previous = pages.getByRole('button', { name: '上一页', exact: true });
  await pages.getByText('第 1 / 2 页，共 101 行', { exact: true }).waitFor();
  await next.click();
  await pages.getByText('第 2 / 2 页，共 101 行', { exact: true }).waitFor();
  await paged.getByRole('cell', { name: 'Product 101', exact: true }).waitFor();
  await previous.click();
  await pages.getByText('第 1 / 2 页，共 101 行', { exact: true }).waitFor();

  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 740 });
    await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    await arranged('column').waitFor();
    const mobile = await motionGeometry();
    assert.ok(mobile.readable && mobile.withinViewport, `${width}px: icon and full label remain on one line`);
    assert.ok(mobile.cells.every(cell => Math.abs(cell.width - mobile.cells[0].width) <= 1), `${width}px: equal motion cells`);
    assert.deepEqual(await comparison(), { columns: width === 390 ? 2 : 1, aligned: true, fits: true },
      `${width}px: metric cards reflow without clipping and align within each row`);
    assert.equal(await amountFits(), true, `${width}px: the emphasized amount still fits on one line`);
    await metricOrder('总预算', '¥9,000.00');
    await metricOrder('应付金额', '¥219.00');
  }
  await main.getByRole('button', { name: '展开源码', exact: true }).click();
  const original = main.locator('pre code').filter({ hasText: 'Spin · 旋转效果' });
  await original.waitFor();
  assert.ok((await original.textContent()).includes(source), 'The authored source remains available verbatim');
});

test('authored checkboxes, result metrics and message actions have distinct visual roles', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page } = fixture;
  const annualLabel = '启用年付优惠（八折）';
  const detailsLabel = '显示计算明细';
  const message = '请继续讨论年付方案。';
  const task_id = await showWidgetAnswer(fixture, 'Show the payment example and its available actions', `<ui id="payment-showcase">
  <state id="annual" type="boolean" initial={false} />
  <state id="showDetails" type="boolean" initial={false} />
  <stack id="sample">
    <card id="checks" label="数字与开关">
      <checkbox id="annual-discount" label="${annualLabel}" bind="annual" />
      <checkbox id="details" label="${detailsLabel}" bind="showDetails" />
    </card>
    <grid id="amounts" columns={3}>
      <metric id="original" label="原价" format="currency:CNY" value={100} />
      <metric id="discount" label="优惠比例" format="percent" value={annual ? 0.2 : 0} />
      <metric id="total" label="应付金额" format="currency:CNY" value={annual ? 80 : 100} tone="success" transition="status" />
    </grid>
    <row-layout id="external-buttons" gap="sm">
      <button id="copy" label="复制文字" action="copy" value="${message}" />
      <button id="draft" label="填入输入框（不发送）" action="draft" message="${message}" />
      <button id="open" label="打开 example.com" action="openUrl" url="https://example.com/" />
    </row-layout>
    <card id="send" label="真实发送操作" tone="warning" gap="sm">
      <text id="send-explanation" label="发送后会继续当前对话。" />
      <button id="submit" label="发送测试消息 / Send" action="submit" message="${message}" />
    </card>
  </stack>
</ui>`);
  const main = page.getByRole('main');
  const checkbox = label => main.getByRole('checkbox', { name: label, exact: true });
  const annual = checkbox(annualLabel);
  const details = checkbox(detailsLabel);
  const action = name => main.getByRole('button', { name, exact: true });
  const copy = action('复制文字');
  const fill = action('填入输入框（不发送）');
  const open = action('打开 example.com');
  const send = action('发送测试消息 / Send');
  const total = main.locator('[data-interactive-component="metric"]').filter({ hasText: '应付金额' });
  const original = main.locator('[data-interactive-component="metric"]').filter({ hasText: '原价' });
  const bounds = input => input.evaluate(node => {
    const wrapper = node.closest('label');
    const target = node.parentElement;
    const caption = [...wrapper.children].find(child => child !== target);
    return { indicator: target.getBoundingClientRect().toJSON(), caption: caption.getBoundingClientRect().toJSON() };
  });
  const paint = value => value.evaluate(node => {
    const style = getComputedStyle(node);
    return { size: parseFloat(style.fontSize), color: style.color, background: style.backgroundColor };
  });
  await main.locator('[data-native-row-direction="row"]').filter({ hasText: '应付金额' }).waitFor();
  for (const width of [1280, 390, 320]) {
    if (width !== 1280) {
      await page.setViewportSize({ width, height: 740 });
      await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    }
    const [first, second] = await Promise.all([bounds(annual), bounds(details)]);
    assert.ok(Math.abs(first.indicator.x - second.indicator.x) <= 1 &&
      [first, second].every(({ indicator, caption }) => indicator.right <= caption.left), `${width}px: leading checkbox column`);
    const [pay, base] = await Promise.all([paint(total.getByText('¥100.00', { exact: true })),
      paint(original.getByText('¥100.00', { exact: true }))]);
    assert.ok(pay.size > base.size && pay.color !== base.color, `${width}px: result amount is emphasized`);
    const [baseName, payName, baseValue, payValue] = await Promise.all([
      original.getByText('原价', { exact: true }), total.getByText('应付金额', { exact: true }),
      original.getByText('¥100.00', { exact: true }), total.getByText('¥100.00', { exact: true }),
    ].map(node => node.boundingBox()));
    assert.ok(baseName.y + baseName.height <= baseValue.y && payName.y + payName.height <= payValue.y,
      `${width}px: price names precede their values`);
    if (width === 1280) assert.ok(Math.abs(baseName.y - payName.y) <= 1,
      'The emphasized total keeps its name aligned with the other price names');
    const utilities = await Promise.all([copy.boundingBox(), fill.boundingBox(), open.boundingBox()]);
    assert.ok(utilities.every(rect => rect && rect.x >= 0 && rect.x + rect.width <= width));
    for (const [index, box] of utilities.entries()) {
      if (!index) continue;
      const previous = utilities[index - 1];
      if (width === 1280) assert.ok(Math.abs(previous.y - box.y) <= 1, 'Desktop has one utility row');
      if (Math.abs(previous.y - box.y) <= 1) assert.ok(box.x - (previous.x + previous.width) <= 12, 'Utilities stay close on a line');
      else assert.ok(Math.abs(box.x - utilities[0].x) <= 1, 'Wrapped utility rows align to the left');
    }
    assert.ok((await send.boundingBox()).y > utilities.at(-1).y + utilities.at(-1).height);
    const sendPaint = await paint(send);
    assert.notEqual(sendPaint.background, 'rgba(0, 0, 0, 0)', 'Send has a visible button surface');
    assert.notEqual(sendPaint.background, (await paint(copy)).background);
  }

  await page.evaluate(() => {
    window.fixtureActionEffects = {};
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
      writeText: async text => { window.fixtureActionEffects.copy = text; },
    } });
    window.open = url => { window.fixtureActionEffects.open = url; };
  });
  await main.getByText(annualLabel, { exact: true }).click();
  assert.equal(await annual.isChecked(), true);
  await total.getByText('¥80.00', { exact: true }).waitFor();
  await details.press('Space');
  assert.equal(await details.isChecked(), true);
  await copy.click();
  await page.waitForFunction(expected => window.fixtureActionEffects.copy === expected, message);
  await open.click();
  await page.waitForFunction(() => window.fixtureActionEffects.open === 'https://example.com/');
  await fill.click();
  const composer = main.getByRole('combobox', { name: 'Message', exact: true });
  assert.equal(await composer.inputValue(), message);
  assert.equal(fixture.requests.length, 1);
  await composer.fill('');
  await send.click();
  const deadline = Date.now() + 10000;
  while (!fixture.requests[1] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[1], 'The separate Send action reaches the provider');
  fixture.finish(1, { text: '已收到。' });
  await taskIdle(fixture.running.service, task_id);
  const conversation = await fixture.command({ op: 'read', task_id });
  assert.deepEqual(conversation.messages.filter(item => item.role === 'user').at(-1)?.content,
    [{ type: 'text', text: message }]);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('authored forms and state adjustments keep related controls together', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const source = `<ui id="compact-controls">
  <state id="nickname" type="string" initial="小岚" />
  <state id="status" type="enum" initial="所有" options={["所有","进行中"]} />
  <state id="notes" type="string" initial=${JSON.stringify('第一行备注\n第二行备注')} />
  <state id="count" type="integer" initial={0} min={0} max={1000} />
  <state id="amount" type="integer" initial={8} min={1} max={50} />
  <state id="price" type="integer" initial={32} min={1} max={100} />
  <state id="discount" type="boolean" initial={false} />
  <state id="details" type="boolean" initial={false} />
  <stack id="main">
    <grid id="forms" columns={2} gap="md">
      <card id="text-fields" label="文本与选择">
        <text-input id="name" label="昵称" bind="nickname" />
        <select id="status-filter" label="状态" bind="status" />
        <textarea id="comment" label="备注" bind="notes" />
      </card>
      <card id="number-fields" label="数字与开关">
        <slider id="amount-slider" label="数量（1—50）" bind="amount" />
        <number-input id="amount-number" label="数量：与滑块同步" bind="amount" />
        <number-input id="price-number" label="单价（元）" bind="price" />
        <checkbox id="annual" label="启用年付优惠" bind="discount" />
        <checkbox id="show-details" label="显示计算明细" bind="details" />
      </card>
    </grid>
    <card id="counter" label="本地状态操作" gap="md">
      <metric id="counter-value" label="点击计数" value={count} />
      <row-layout id="adjustments" gap="sm">
        <button id="increase" label="加一" action="set" target="count" value={min(count + 1, 1000)} />
        <button id="decrease" label="减一" action="set" target="count" value={max(count - 1, 0)} />
        <button id="clear" label="归零" action="set" target="count" value={0} />
      </row-layout>
    </card>
    <card id="send" label="真实发送操作" tone="warning" gap="sm">
      <text id="explanation" label="点击下方按钮，会把上方文字作为新消息发送给助手。" />
      <button id="submit" label="发送测试消息 / Send" action="submit" message="一条新消息" />
    </card>
  </stack>
</ui>`;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile, message: 'Show compact input and adjustment controls' });
  const deadline = Date.now() + 10000;
  while (!fixture.requests[index] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[index]);
  fixture.finish(index, { text: `\`\`\`selvedge-ui\n${source}\n\`\`\`` });
  await taskIdle(fixture.running.service, task_id);
  const { task } = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();

  const main = page.getByRole('main');
  const notes = main.getByRole('textbox', { name: '备注', exact: true });
  const details = main.getByRole('checkbox', { name: '显示计算明细', exact: true });
  const counter = main.locator('[data-interactive-component="card"]').filter({ has: page.getByText('本地状态操作', { exact: true }) });
  const metric = counter.locator('[data-interactive-component="metric"]');
  const action = label => counter.getByRole('button', { name: label, exact: true });
  const send = main.getByRole('button', { name: '发送测试消息 / Send', exact: true });
  await send.waitFor();
  assert.equal(await main.getByText('真实发送操作', { exact: true }).isVisible(), true);
  assert.equal(await main.getByText('点击下方按钮，会把上方文字作为新消息发送给助手。', { exact: true }).isVisible(), true);
  assert.equal(await notes.inputValue(), '第一行备注\n第二行备注');
  assert.equal(await counter.getByText('本地状态操作', { exact: true }).isVisible(), true);
  assert.equal(await metric.getByText('点击计数', { exact: true }).isVisible(), true);
  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 900 });
    if (width < 500) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const note = await notes.evaluate(node => {
      const style = getComputedStyle(node);
      return { height: node.offsetHeight, line: parseFloat(style.lineHeight), resize: style.resize,
        bounds: node.getBoundingClientRect().toJSON() };
    });
    assert.ok(note.height >= 2 * note.line && note.height <= 2 * note.line + 18, `Compact two-line note field at ${width}px`);
    assert.equal(note.resize, 'vertical');
    assert.ok(note.bounds.left >= 0 && note.bounds.right <= width);
    const right = await details.boundingBox();
    assert.ok(right && right.x >= 0 && right.x + right.width <= width);
    const [card, value, ...buttons] = await Promise.all([counter, metric, action('加一'), action('减一'), action('归零')].map(node => node.boundingBox()));
    assert.ok(card && value && card.x >= 0 && card.x + card.width <= width);
    assert.ok(buttons.every(box => box && box.x >= card.x && box.x + box.width <= card.x + card.width));
    if (width === 1280) {
      assert.ok(Math.abs(note.bounds.bottom - (right.y + right.height)) <= 24, 'The two form columns end near the same line');
      assert.ok(value.y < buttons[0].y + buttons[0].height && buttons[0].y < value.y + value.height);
      assert.ok(buttons[0].x - (value.x + value.width) >= -1 && buttons[0].x - (value.x + value.width) <= 16,
        'The first adjustment is next to the metric');
      const trailingInset = card.x + card.width - Math.max(...buttons.map(box => box.x + box.width));
      assert.ok(trailingInset <= 24, 'The counter border ends just beyond its last button');
    }
    for (let i = 1; i < buttons.length; i++) {
      if (Math.abs(buttons[i].y - buttons[i - 1].y) <= 1) {
        assert.ok(buttons[i].x - (buttons[i - 1].x + buttons[i - 1].width) <= 12);
      }
    }
  }
  const ready = button => button.and(counter.locator('button:enabled:not([aria-disabled="true"])'));
  const editedNotes = '第一行备注\n改过的第二行\n第三行';
  await notes.and(main.locator('textarea:not([inert])')).fill(editedNotes);
  await ready(action('加一')).click();
  await metric.getByText('1', { exact: true }).waitFor();
  await ready(action('归零')).click();
  await metric.getByText('0', { exact: true }).waitFor();
  assert.equal(await notes.inputValue(), editedNotes);
});

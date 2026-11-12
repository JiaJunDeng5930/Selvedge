import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('a range and adjacent number editor share one compact view only for the same binding', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const source = `<ui id="range-pair">
  <state id="quantity" type="integer" initial={8} min={1} max={50} />
  <state id="budget" type="integer" initial={17} min={1} max={50} />
  <state id="price" type="integer" initial={32} min={1} max={50} />
  <stack id="controls">
    <card id="numbers" label="数字与开关">
      <slider id="quantity-range" label="数量（1—50）" bind="quantity" />
      <number-input id="quantity-number" label="数量：与上方滑块同步" bind="quantity" />
      <text id="note" label="数量以件为单位。" />
    </card>
    <slider id="budget-range" label="预算" bind="budget" />
    <number-input id="price-number" label="单价（元）" bind="price" />
    <text id="invoice-note" label="预算和单价可分别修改。" />
  </stack>
</ui>`;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile, message: 'Show the linked quantity editors' });
  const deadline = Date.now() + 10000;
  while (!fixture.requests[index] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[index]);
  fixture.finish(index, { text: `\`\`\`selvedge-ui\n${source}\n\`\`\`` });
  await taskIdle(fixture.running.service, task_id);
  const { task } = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();

  const main = page.getByRole('main');
  const numbers = main.locator('[data-interactive-component="card"]').filter({
    has: page.getByText('数字与开关', { exact: true }),
  });
  const range = main.getByRole('slider', { name: '数量（1—50）', exact: true });
  const quantity = main.getByRole('textbox', { name: '数量：与上方滑块同步', exact: true });
  const budget = main.getByRole('slider', { name: '预算', exact: true });
  const price = main.getByRole('textbox', { name: '单价（元）', exact: true });
  await price.waitFor();
  assert.equal(await quantity.inputValue(), '8');
  assert.equal(await range.inputValue(), '8');
  assert.equal(await main.getByText('数量（1—50）', { exact: true }).filter({ visible: true }).count(), 1);
  assert.equal(await main.getByText('数量：与上方滑块同步', { exact: true }).filter({ visible: true }).count(), 1);
  assert.equal(await main.getByText('数量以件为单位。', { exact: true }).isVisible(), true);
  assert.equal(await main.getByText('预算和单价可分别修改。', { exact: true }).isVisible(), true);
  assert.equal(await numbers.getByText('8', { exact: true }).filter({ visible: true }).count(), 0,
    'The number editor replaces the slider’s generated readout');
  assert.equal(await main.getByText('17', { exact: true }).filter({ visible: true }).count(), 1,
    'An unrelated adjacent number editor does not replace a standalone slider’s readout');

  const viewport = page.viewportSize();
  for (const width of [viewport.width, 390, 320]) {
    await page.setViewportSize({ width, height: viewport.height });
    if (width < 500) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const [slider, number, separateSlider, separateNumber] = await Promise.all(
      [range, quantity, budget, price].map(field => field.boundingBox()));
    assert.ok(slider && number && separateSlider && separateNumber);
    const gap = number.x - (slider.x + slider.width);
    assert.ok(gap >= -1 && gap <= 16 && number.x + number.width <= width + 1 &&
      slider.y < number.y + number.height && number.y < slider.y + slider.height,
    `The quantity controls are beside one another at ${width}px, with ${gap}px between them`);
    assert.ok(separateSlider.y + separateSlider.height <= separateNumber.y + 1,
      'Different bindings keep their own rows');
  }

  const waitForValue = async (field, expected) => {
    const id = await field.getAttribute('id');
    await page.waitForFunction(([id, value]) => document.getElementById(id)?.value === value, [id, expected]);
  };
  const waitForFocus = async field => {
    const id = await field.getAttribute('id');
    await page.waitForFunction(id => document.activeElement?.id === id && !document.activeElement.inert, id);
  };
  await range.and(main.locator('input:not([inert])')).focus();
  await waitForFocus(range);
  await page.keyboard.press('ArrowRight');
  await waitForValue(quantity, '9');
  await waitForFocus(range);
  await quantity.and(main.locator('input:not([inert])')).fill('12');
  await waitForValue(range, '12');
  await waitForFocus(quantity);
  assert.equal(await budget.inputValue(), '17');
  assert.equal(await price.inputValue(), '32');
});

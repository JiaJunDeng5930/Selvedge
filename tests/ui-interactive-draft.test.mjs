import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { imageBase64 } from './fixtures/images.mjs';
import { taskIdle } from './support.mjs';

const refusalText = '输入框已有草稿，已保留。清空后可重试。';

async function showActionAnswer(fixture, prompt, text) {
  const { page, command, profile } = fixture;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile, message: prompt });
  const deadline = Date.now() + 10000;
  while (fixture.requests.length === index && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[index], 'The provider must receive the opening prompt');
  fixture.finish(index, { text });
  await taskIdle(fixture.running.service, task_id);
  const before = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: before.task.title, exact: true }).click();
  return { index, task_id, before };
}

test('an interactive fill reports its own refusal, preserves the draft, and can be retried', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const suggestion = '请说明第一个建议。';
  const source = `<ui id="followups">
  <stack id="buttons">
    <button id="first" label="填入输入框（不发送）" action="draft" message="${suggestion}"/>
    <button id="second" label="填写另一条追问" action="draft" message="请说明第二个建议。"/>
  </stack>
</ui>`;
  const { index, task_id, before } = await showActionAnswer(fixture, 'Show two follow-up ideas',
    `可以从两个问题继续。\n\n\`\`\`selvedge-ui\n${source}\n\`\`\``);
  const main = page.getByRole('main');
  const composer = main.getByRole('combobox', { name: 'Message', exact: true });
  const fill = main.getByRole('button', { name: '填入输入框（不发送）', exact: true });
  const sibling = main.getByRole('button', { name: '填写另一条追问', exact: true });
  const refusal = button => button.locator('..').getByRole('status').filter({ hasText: refusalText });

  const existing = '我要保留自己的追问。';
  await composer.fill(existing);
  await fill.press('Enter');
  await refusal(fill).waitFor();
  assert.equal(await main.getByText(refusalText, { exact: true }).count(), 1, 'The refusal appears only at the triggering control');
  assert.equal(await refusal(sibling).count(), 0);
  assert.equal(await composer.inputValue(), existing);
  assert.equal(await fill.evaluate(button => button === document.activeElement), true);

  await composer.fill('');
  const filename = 'unsent-follow-up.png';
  await main.locator('input[type="file"]').setInputFiles({
    name: filename, mimeType: 'image/png', buffer: Buffer.from(imageBase64, 'base64'),
  });
  const image = main.getByRole('img', { name: filename, exact: true });
  await image.waitFor();
  await sibling.press('Enter');
  await refusal(sibling).waitFor();
  await refusal(fill).waitFor();
  assert.equal(await composer.inputValue(), '', 'An attachment alone still occupies the draft');
  assert.equal(await image.isVisible(), true, 'The attachment survives a blocked fill');
  assert.equal(await sibling.evaluate(button => button === document.activeElement), true);
  await main.getByRole('button', { name: 'Remove', exact: true }).click();
  await image.waitFor({ state: 'hidden' });

  await fill.press('Enter');
  await refusal(fill).waitFor({ state: 'hidden' });
  await refusal(sibling).waitFor();
  assert.equal(await composer.inputValue(), suggestion);
  assert.equal(await composer.evaluate(field => field === document.activeElement), true);
  assert.equal(fixture.requests.length, index + 1, 'Filling the composer never calls the provider');
  assert.deepEqual((await command({ op: 'read', task_id })).messages, before.messages,
    'Filling the composer does not append a submitted message');
  assert.deepEqual(fixture.failures, []);
});

test('interactive action feedback fits below the button beside a usable Copy control', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page } = fixture;
  const followup = '请说明这个建议。';
  await showActionAnswer(fixture, 'Show a follow-up beside a copy action', [
    '```selvedge-ui', '<ui id="followup-row">', '<row-layout id="actions">',
    `<button id="fill" label="填入输入框（不发送）" action="draft" message="${followup}"/>`,
    `<button id="copy" label="复制文字" action="copy" value="${followup}"/>`,
    '</row-layout>', '</ui>', '```',
  ].join('\n'));
  await page.evaluate(() => {
    window.fixtureClipboard = '';
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
      writeText: async text => { window.fixtureClipboard = text; },
    } });
  });
  const main = page.getByRole('main');
  const composer = main.getByRole('combobox', { name: 'Message', exact: true });
  const fill = main.getByRole('button', { name: '填入输入框（不发送）', exact: true });
  const copy = main.getByRole('button', { name: '复制文字', exact: true });
  const refusal = fill.locator('..').getByRole('status').filter({ hasText: refusalText });
  const existing = '请保留已经写好的追问。';
  for (const width of [320, 390, 1280]) {
    await page.setViewportSize({ width, height: width === 1280 ? 900 : 670 });
    if (width === 1280) await page.getByRole('navigation', { name: 'Task tree', exact: true }).waitFor();
    else await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    await composer.fill(existing);
    await fill.press('Enter');
    await refusal.waitFor();
    const layout = await fill.evaluate(button => {
      const label = button.querySelector(':scope > span');
      const feedback = button.parentElement.querySelector(':scope > [role="status"]');
      const row = button.closest('[data-interactive-component="row-layout"]');
      const bounds = feedback.getBoundingClientRect();
      return {
        labelWidth: label.clientWidth,
        labelTextWidth: label.scrollWidth,
        labelHeightFits: label.scrollHeight <= label.clientHeight + 1,
        feedbackBelow: bounds.top >= button.getBoundingClientRect().bottom,
        feedbackFits: feedback.scrollWidth <= feedback.clientWidth + 1 && bounds.left >= 0 && bounds.right <= innerWidth,
        rowFits: row.scrollWidth <= row.clientWidth + 1 && row.scrollHeight <= row.clientHeight + 1,
        focused: button === document.activeElement,
      };
    });
    assert.ok(layout.labelTextWidth <= layout.labelWidth + 1 && layout.labelHeightFits, `${width}px: the full action label fits`);
    assert.ok(layout.feedbackBelow && layout.feedbackFits && layout.rowFits, `${width}px: feedback fits below its action`);
    assert.ok(layout.focused, `${width}px: feedback leaves keyboard focus on its action`);
    assert.equal(await main.getByText(refusalText, { exact: true }).count(), 1);
    assert.equal(await copy.isEnabled(), true);
    const copyBounds = await copy.boundingBox();
    assert.ok(copyBounds && copyBounds.x >= 0 && copyBounds.x + copyBounds.width <= width);

    if (width === 320) {
      await copy.press('Enter');
      await page.waitForFunction(expected => window.fixtureClipboard === expected, followup);
      assert.equal(await composer.inputValue(), existing);
    }
    await composer.fill('');
    await fill.press('Enter');
    await refusal.waitFor({ state: 'hidden' });
  }
});

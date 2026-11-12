import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

const authored = `<ui id="status-list">
  <state id="status" type="enum" initial="全部" options={["全部","进行中","已完成"]} />
  <stack id="content">
    <select id="status-filter" label="筛选状态" bind="status" />
    <each id="items" items={status == "全部" ? [{id:"progress",label:"开发组件"},{id:"done",label:"设计首页"}] : status == "进行中" ? [{id:"progress",label:"开发组件"}] : [{id:"done",label:"设计首页"}]} item="item" key="id">
      <card id="item" label={item.label}>
        <text id="detail" label="详细进度" />
      </card>
    </each>
  </stack>
</ui>`;
const passage = n => Array.from({ length: n }, (_, i) =>
  `### 阅读段落 ${i + 1}\n\n这里是一段对话内容，需要保持筛选操作前后的阅读位置。\n\n`).join('');

test('changing an authored status filter twice retains its reading position and focus', { timeout: 60_000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile, message: 'Filter the status list' });
  const deadline = Date.now() + 10_000;
  while (!fixture.requests[index] && Date.now() < deadline) await new Promise(done => setTimeout(done, 20));
  assert.ok(fixture.requests[index]);
  fixture.finish(index, { text: passage(12) + '```selvedge-ui\n' + authored + '\n```\n\n' + passage(24) });
  await taskIdle(fixture.running.service, task_id);
  await page.getByRole('button', { name: 'Filter the status list', exact: true }).click();
  const filter = page.getByRole('combobox', { name: '筛选状态', exact: true });
  await filter.waitFor();
  await page.waitForFunction(() => {
    const field = document.querySelector('select[aria-label="筛选状态"]');
    return field && !field.disabled && !field.closest('[inert]');
  });
  await filter.scrollIntoViewIfNeeded();
  await filter.focus();
  const geometry = () => filter.evaluate(node => {
    const reader = node.closest('[data-reading-root="true"]');
    const bounds = reader.getBoundingClientRect();
    const box = node.getBoundingClientRect();
    const visible = [...reader.querySelectorAll('[data-interactive-component="card"]')].filter(card => {
      const rect = card.getBoundingClientRect();
      return rect.bottom > bounds.top && rect.top < bounds.bottom;
    }).map(card => card.textContent.trim());
    return { top: reader.scrollTop, end: reader.scrollHeight - reader.clientHeight,
      offset: box.top - bounds.top, focused: document.activeElement === node, visible };
  });
  const before = await geometry();
  assert.ok(before.end - before.top > 500, 'The filter is well above the end of the conversation');
  for (const [value, expected, excluded] of [
    ['进行中', '开发组件', '设计首页'],
    ['已完成', '设计首页', '开发组件'],
  ]) {
    await filter.selectOption(value);
    await page.waitForFunction(({ expected, excluded }) => {
      const cards = [...document.querySelectorAll('[data-interactive-component="card"]')];
      return cards.some(card => card.textContent.includes(expected)) &&
        cards.every(card => !card.textContent.includes(excluded));
    }, { expected, excluded });
    const after = await geometry();
    assert.ok(Math.abs(after.offset - before.offset) < 3,
      `The filter keeps its position after selecting ${value}: ${JSON.stringify({ before, after })}`);
    assert.equal(after.focused, true, 'The native control retains focus');
    assert.ok(after.visible.some(card => card.includes(expected)), 'The matching result remains in the reading viewport');
  }
  const latest = page.locator('[data-semantic-key="latest"]');
  await latest.click();
  await page.waitForFunction(() => {
    const reader = document.querySelector('[data-reading-root="true"]');
    return reader && reader.scrollHeight - reader.clientHeight - reader.scrollTop <= 1;
  });
});

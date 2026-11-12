import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('authored task summaries align statuses and values while keeping each item selectable', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const source = `<ui id="task-report">
  <state id="selected" type="string" initial="" max-length={40} />
  <stack id="content" gap="lg">
    <card id="welcome" label="动态文本" gap="sm">
      <text id="greeting" label="你好，小岚 👋" />
      <badge id="plan" label="专业版" tone="accent" />
    </card>
    <each id="tasks" items={[{id:"design",name:"设计首页",status:"已完成",progress:1},{id:"code",name:"开发组件",status:"进行中",progress:0.6},{id:"test",name:"编写测试",status:"未开始",progress:0}]} item="task" key="id">
      <card id="item" label={task.name} tone={selected == task.id ? "accent" : "neutral"} gap="sm">
        <badge id="status" label={task.status} tone={task.status == "已完成" ? "success" : "warning"} />
        <metric id="progress" label="完成比例" value={task.progress} format="percent" />
        <button id="select" label={selected == task.id ? "已选中" : "选中这一项"} action="set" target="selected" value={task.id} />
      </card>
    </each>
    <each id="extras" items={[{id:"custom"}]} item="extra" key="id">
      <card id="custom" label="详情卡片" gap="sm">
        <badge id="status" label="稍后核对" tone="muted" />
        <metric id="progress" label="完成比例" value={0.25} format="percent" />
        <button id="select" label="选择详情" action="set" target="selected" value={extra.id} />
        <text id="description" label="这项任务还有一段说明。" />
      </card>
    </each>
  </stack>
</ui>`;

  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile, message: 'Show the three tasks with their current progress' });
  const deadline = Date.now() + 10000;
  while (!fixture.requests[index] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[index], 'The provider receives the authored list request');
  fixture.finish(index, { text: `\`\`\`selvedge-ui\n${source}\n\`\`\`` });
  await taskIdle(fixture.running.service, task_id);
  const { task } = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();

  const main = page.getByRole('main');
  const byText = value => main.getByText(value, { exact: true });
  const row = name => main.locator('[data-interactive-component="card"]').filter({
    has: page.getByText(name, { exact: true }),
  });
  const completed = row('设计首页');
  const inProgress = row('开发组件');
  const untouched = row('编写测试');
  const plan = byText('专业版');
  const overlapsVertically = (a, b) => a.y < b.y + b.height && b.y < a.y + a.height;
  const textBounds = locator => locator.evaluate(node => {
    const range = document.createRange();
    range.selectNodeContents(node);
    return range.getBoundingClientRect().toJSON();
  });
  const weight = locator => locator.evaluate(node => Number(getComputedStyle(node).fontWeight));
  const fill = locator => locator.evaluate(node => getComputedStyle(node).backgroundColor);
  await completed.getByRole('button', { name: '选中这一项', exact: true }).waitFor();
  const colors = await Promise.all([plan, completed.getByText('已完成', { exact: true }),
    inProgress.getByText('进行中', { exact: true })].map(fill));
  assert.equal(new Set(colors).size, 3, 'Accent, success and warning keep their declared visual tones');
  assert.ok(colors.every(color => color !== 'rgba(0, 0, 0, 0)'));

  await inProgress.getByRole('button', { name: '选中这一项', exact: true }).click();
  await inProgress.getByRole('button', { name: '已选中', exact: true }).waitFor();
  await completed.getByRole('button', { name: '选中这一项', exact: true }).waitFor();

  const viewport = page.viewportSize();
  for (const width of [viewport.width, 390]) {
    await page.setViewportSize({ width, height: viewport.height });
    if (width === 390) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const [welcome, tag] = await Promise.all([byText('你好，小岚 👋').boundingBox(), plan.boundingBox()]);
    assert.ok(welcome && tag && welcome.x + welcome.width <= tag.x + 1 && overlapsVertically(welcome, tag),
      `The short plan status is beside the greeting at ${width}px`);
    assert.ok(tag.width < 90, `The plan status fits its text at ${width}px`);

    const ends = [];
    for (const [item, title, status, percent, choice] of [
      [completed, '设计首页', '已完成', '100%', '选中这一项'],
      [inProgress, '开发组件', '进行中', '60%', '已选中'],
      [untouched, '编写测试', '未开始', '0%', '选中这一项'],
    ]) {
      const heading = item.getByText(title, { exact: true });
      const caption = item.getByText('完成比例', { exact: true });
      const [name, badge, value, action, bounds] = await Promise.all([
        heading.boundingBox(), item.getByText(status, { exact: true }).boundingBox(),
        textBounds(item.getByText(percent, { exact: true })),
        item.getByRole('button', { name: choice, exact: true }).boundingBox(), item.boundingBox(),
      ]);
      assert.ok(name && badge && value && action && bounds);
      assert.ok(name.x + name.width <= badge.x + 1 && badge.x + badge.width <= value.x + 1 &&
        value.x + value.width <= action.x + 1 && action.x + action.width <= bounds.x + bounds.width + 1,
      `The title, status, value and reachable action fit in one ${width}px row`);
      assert.ok(overlapsVertically(name, badge) && overlapsVertically(name, value) && overlapsVertically(name, action));
      assert.ok(await weight(heading) > await weight(caption), 'The title is more prominent than the repeated metric label');
      ends.push(value.x + value.width);
    }
    assert.ok(Math.max(...ends) - Math.min(...ends) <= 1, 'The values align at their trailing edge after selection');
  }

  const detail = row('详情卡片');
  const custom = detail.getByText('这项任务还有一段说明。', { exact: true });
  await custom.waitFor();
  assert.ok((await detail.getByRole('button', { name: '选择详情', exact: true }).boundingBox()).y <
    (await custom.boundingBox()).y, 'A different authored template retains its original content order');
});

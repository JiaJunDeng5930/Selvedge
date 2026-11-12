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
    <each id="estimates" items={[{id:"draft",name:"草稿",metric:"阅读时长"},{id:"recording",name:"录音",metric:"播放时长"},{id:"transcript",name:"逐字稿",metric:"阅读时长"}]} item="entry" key="id">
      <card id="estimate" label={entry.name} gap="sm">
        <badge id="status" label="待核对" tone="muted" />
        <metric id="length" label={entry.metric} value={3} />
        <button id="adjust" label="标记待复查" action="set" target="selected" value="review" />
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
  const choice = (item, label, title) => item.getByRole('button', { name: `${label} · ${title}`, exact: true });
  await choice(completed, '选中这一项', '设计首页').waitFor();
  const colors = await Promise.all([plan, completed.getByText('已完成', { exact: true }),
    inProgress.getByText('进行中', { exact: true })].map(fill));
  assert.equal(new Set(colors).size, 3, 'Accent, success and warning keep their declared visual tones');
  assert.ok(colors.every(color => color !== 'rgba(0, 0, 0, 0)'));

  const unselected = choice(inProgress, '选中这一项', '开发组件');
  assert.equal(await unselected.getAttribute('aria-pressed'), 'false');
  assert.equal(await unselected.getAttribute('title'), '选中这一项 · 开发组件');
  const unselectedFace = (await unselected.innerText()).trim();
  assert.equal(Array.from(unselectedFace).length, 1, 'The selection button presents a visible mark');
  await unselected.focus();
  await inProgress.locator('button:enabled:not([aria-disabled="true"])').waitFor();
  await page.keyboard.press('Enter');
  const selected = choice(inProgress, '已选中', '开发组件');
  await selected.waitFor();
  assert.equal(await selected.getAttribute('aria-pressed'), 'true');
  assert.notEqual((await selected.innerText()).trim(), unselectedFace);
  assert.equal(await selected.evaluate(node => document.activeElement === node), true);
  assert.equal(await choice(completed, '选中这一项', '设计首页').getAttribute('aria-pressed'), 'false');

  const summary = main.locator('[data-semantic-key="interactive-markdown/compact-card-list"]').filter({
    has: page.getByText('设计首页', { exact: true }),
  });
  const sharedCaption = summary.getByText('完成比例', { exact: true });
  assert.equal(await sharedCaption.count(), 1, 'One heading names the shared progress column');
  assert.equal(await summary.getByText('选中这一项', { exact: true }).count(), 0);
  assert.equal(await row('草稿').getByText('阅读时长', { exact: true }).isVisible(), true);
  assert.equal(await row('录音').getByText('播放时长', { exact: true }).isVisible(), true);
  assert.equal(await row('逐字稿').getByText('阅读时长', { exact: true }).isVisible(), true);
  assert.equal(await row('录音').getByRole('button', { name: '标记待复查', exact: true }).innerText(), '标记待复查');

  const viewport = page.viewportSize();
  for (const width of [viewport.width, 390, 320]) {
    await page.setViewportSize({ width, height: viewport.height });
    if (width < 500) await page.getByRole('button', { name: 'Open Task list', exact: true }).waitFor();
    const [welcome, tag] = await Promise.all([byText('你好，小岚 👋').boundingBox(), plan.boundingBox()]);
    assert.ok(welcome && tag && welcome.x + welcome.width <= tag.x + 1 && overlapsVertically(welcome, tag),
      `The short plan status is beside the greeting at ${width}px`);
    assert.ok(tag.width < 90, `The plan status fits its text at ${width}px`);

    const ends = [];
    for (const [item, title, status, percent, label] of [
      [completed, '设计首页', '已完成', '100%', '选中这一项'],
      [inProgress, '开发组件', '进行中', '60%', '已选中'],
      [untouched, '编写测试', '未开始', '0%', '选中这一项'],
    ]) {
      const heading = item.getByText(title, { exact: true });
      const [name, badge, value, action, bounds] = await Promise.all([
        heading.boundingBox(), item.getByText(status, { exact: true }).boundingBox(),
        textBounds(item.getByText(percent, { exact: true })),
        choice(item, label, title).boundingBox(), item.boundingBox(),
      ]);
      assert.ok(name && badge && value && action && bounds);
      assert.ok(name.x + name.width <= badge.x + 1 && badge.x + badge.width <= value.x + 1 &&
        value.x + value.width <= action.x + 1 && action.x + action.width <= bounds.x + bounds.width + 1,
      `The title, status, value and reachable action fit in one ${width}px row`);
      assert.ok(overlapsVertically(name, badge) && overlapsVertically(name, value) && overlapsVertically(name, action));
      assert.ok(await weight(heading) > await weight(sharedCaption), 'The title is more prominent than the shared metric heading');
      ends.push(value.x + value.width);
    }
    assert.ok(Math.max(...ends) - Math.min(...ends) <= 1, 'The values align at their trailing edge after selection');
    const caption = await textBounds(sharedCaption);
    assert.ok(Math.abs(caption.x + caption.width - ends[0]) <= 1, 'The shared heading aligns over the percentage column');
  }

  const detail = row('详情卡片');
  const custom = detail.getByText('这项任务还有一段说明。', { exact: true });
  await custom.waitFor();
  assert.ok((await detail.getByRole('button', { name: '选择详情', exact: true }).boundingBox()).y <
    (await custom.boundingBox()).y, 'A different authored template retains its original content order');
});

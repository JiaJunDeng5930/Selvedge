import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';

async function until(observe, detail) {
  const deadline = Date.now() + 8000;
  do {
    const value = await observe();
    if (value != null && value !== false) return value;
    await delay(25);
  } while (Date.now() < deadline);
  assert.fail(detail);
}

function requestFor(fixture, text, after = -1) {
  return until(() => fixture.requests.find(request => request.index > after && !request.closed &&
    request.input.input.some(item => item.role === 'user' && JSON.stringify(item.content).includes(text))),
  `Expected a model request containing ${text}`);
}

test('a ticket waits for every exit, with a fresh reviewer and a reused implementer', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { command, page, profile } = fixture;
  const { work_id } = await command({ op: 'create_work', name: 'Workflow acceptance' });
  const task = (key, creation) => ({ key, kind: 'task', profile, creation });
  const edge = (key, source, target, description) => ({ key, source, target, ...(description && { description }) });
  await page.getByRole('button', { name: '任务图', exact: true }).click();
  await page.getByRole('button', { name: '创建工作流', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '创建工作流', exact: true });
  const definition = {
    work_id, name: 'Implement and review',
    nodes: [{ key: 'start', kind: 'entrance' }, { key: 'alternative', kind: 'entrance' }, { key: 'finish', kind: 'exit' },
      task('implement', 'once'), task('review', 'each'), task('parallel', 'once')],
    connections: [
      edge('start-implementation', 'start', 'implement'),
      edge('alternative-implementation', 'alternative', 'implement'),
      { ...edge('start-parallel', 'start', 'parallel'), message: { kind: 'literal', value: 'Parallel acceptance work' } },
      edge('submit', 'implement', 'review'),
      edge('changes', 'review', 'implement', 'Changes are required'),
      edge('pass', 'review', 'finish', 'The implementation passes'),
      edge('parallel-done', 'parallel', 'finish'),
    ],
  };
  await editor.getByText('高级选项', { exact: true }).click();
  await editor.getByRole('textbox', { name: 'JSON 定义', exact: true }).fill(JSON.stringify(definition, null, 2));
  await editor.getByRole('button', { name: '创建工作流', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  const { card_id } = await command({ op: 'create_card', title: 'Workflow acceptance ticket' });
  await page.getByRole('button', { name: '卡片看板', exact: true }).click();
  let concurrentChecks = 0;
  let peakChecks = 0;
  let checkedActions = 0;
  let measureChecks = true;
  let failEntranceCheck = true;
  let failLaunchCheckAtRevision;
  await page.route('**/api/assess', async route => {
    const { editor: owner, command: assessed } = route.request().postDataJSON();
    if (measureChecks && owner.kind !== 'candidate') {
      checkedActions++;
      peakChecks = Math.max(peakChecks, ++concurrentChecks);
      await delay(60);
      concurrentChecks--;
    }
    if ((failEntranceCheck && assessed?.op === 'configure_ticket_workflow' && assessed.entrance === 'alternative') ||
        (failLaunchCheckAtRevision !== undefined && assessed?.op === 'start_ticket_workflow' &&
          assessed.revision === failLaunchCheckAtRevision)) {
      if (assessed.op === 'configure_ticket_workflow') failEntranceCheck = false;
      else failLaunchCheckAtRevision = undefined;
      await route.abort();
    } else {
      await route.continue();
    }
  });
  await page.getByRole('button', { name: '打开 Workflow acceptance ticket', exact: true }).click();
  const details = page.getByRole('dialog', { name: '卡片详情', exact: true });
  await details.getByRole('button', { name: '重新检查 · 选择 Implement and review · alternative', exact: true }).click();
  await until(() => checkedActions >= 3, 'Opening a card checks multiple actions');
  assert.equal(peakChecks, 1);
  measureChecks = false;
  await details.getByRole('button', { name: '选择 Implement and review · alternative', exact: true }).click();
  await details.getByText('Implement and review · alternative', { exact: true }).waitFor();
  await page.setViewportSize({ width: 768, height: 1024 });
  failLaunchCheckAtRevision = (await command({ op: 'read_card', card_id })).revision + 1;
  const change = details.getByText('更改工作流入口', { exact: true });
  assert.equal(await change.evaluate(el => el.getBoundingClientRect().bottom <= innerHeight), true);
  await change.click();
  await details.getByRole('button', { name: '选择 Implement and review · start', exact: true }).click();
  await details.getByText('Implement and review · start', { exact: true }).waitFor();
  await details.getByRole('button', { name: '重新检查', exact: true }).click();
  await page.setViewportSize({ width: 360, height: 640 });
  let allowStart;
  const startGate = new Promise(resolve => { allowStart = resolve; });
  t.after(() => allowStart());
  await page.route('**/api/browser/command', async route => {
    if (route.request().postDataJSON()?.command?.op === 'start_ticket_workflow') await startGate;
    await route.continue();
  });
  const launch = details.getByRole('button', { name: '启动工作流实例', exact: true });
  assert.equal(await launch.evaluate(el => el.getBoundingClientRect().bottom <= innerHeight), true);
  await launch.click();
  await details.getByRole('button', { name: '正在提交…', exact: true }).waitFor();
  allowStart();
  const instance_id = await until(async () => {
    const ticket = await command({ op: 'read_card', card_id });
    return Number.isInteger(ticket.workflow_instance_id) ? ticket.workflow_instance_id : null;
  }, 'Starting from the board attaches a workflow instance');
  const read = () => command({ op: 'read_workflow_instance', instance_id });
  const card = () => command({ op: 'read_card', card_id });
  const active = (instance, node) => instance.paths.find(path => path.node === node && path.active);
  const first = await requestFor(fixture, 'Workflow acceptance ticket');
  const parallel = await requestFor(fixture, 'Parallel acceptance work');
  await details.getByRole('button', { name: `实例 #${instance_id} · 进行中`, exact: true }).waitFor();
  await details.locator('[data-semantic-key="activity"]').getByText('进行中', { exact: true }).waitFor();
  await page.setViewportSize({ width: 1280, height: 900 });
  const initial = await read();
  const implementer = active(initial, 'implement').task_id;
  assert.notEqual(implementer, active(initial, 'parallel').task_id);
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: '任务图', exact: true }).click();
  const graph = page.getByRole('region', { name: 'Implement and review', exact: true });
  const dots = graph.locator('[data-semantic-key="workflow-instance-dot"]');
  await until(async () => await dots.count() === 2, 'The active instance appears at both nodes');
  const color = dot => dot.evaluate(el => getComputedStyle(el).backgroundColor);
  assert.notEqual(await color(dots.first()), 'rgba(0, 0, 0, 0)');
  assert.equal(await color(dots.first()), await color(dots.nth(1)));
  const marker = graph.getByRole('button', { name: /实例 #\d+ · 对话/ }).first();
  await marker.focus();
  await page.keyboard.press('Enter');
  const instance = page.getByRole('dialog', { name: `实例 #${instance_id}`, exact: true });
  await instance.getByText('进行中', { exact: true }).waitFor();
  const linkedTask = instance.locator('button[data-semantic-key^="task/"]').first();
  const taskTitle = await linkedTask.innerText();
  await linkedTask.click();
  const conversation = page.locator('dialog[data-semantic-key="side-conversation"]');
  await conversation.waitFor();
  assert.equal(await conversation.locator('h1,h2,h3').first().innerText(), taskTitle);
  await conversation.getByRole('button', { name: /关闭|Close/ }).first().click();
  await instance.getByRole('button', { name: 'Close panel', exact: true }).click();

  fixture.finish(first.index, { text: 'Implementation version one' });
  let review = await requestFor(fixture, 'Implementation version one');
  const reviewer = active(await read(), 'review').task_id;
  assert.match(JSON.stringify(review.input.input), /Changes are required/);
  fixture.finish(review.index, { text: 'Forgot to choose' });
  review = await requestFor(fixture, 'Then send the final answer again', review.index);
  assert.equal(active(await read(), 'review').task_id, reviewer);
  function choose(request, connection) {
    fixture.finish(request.index, { output: [{
      type: 'function_call', name: 'choose_workflow_connection', call_id: `route_${request.index}`,
      arguments: JSON.stringify({ connection }),
    }] });
  }
  choose(review, 'changes');
  review = await until(() => fixture.requests.find(request => request.index > review.index && !request.closed &&
    request.input.input.some(item => item.type === 'function_call_output' && item.call_id === `route_${review.index}`)),
  'The reviewer receives the route tool result');
  fixture.finish(review.index, { text: 'Fix the validation' });
  const fix = await requestFor(fixture, 'Fix the validation');
  assert.equal(active(await read(), 'implement').task_id, implementer);
  fixture.finish(fix.index, { text: 'Implementation version two' });
  review = await requestFor(fixture, 'Implementation version two');
  assert.notEqual(active(await read(), 'review').task_id, reviewer);
  assert.doesNotMatch(JSON.stringify(review.input.input), /Implementation version one/);
  choose(review, 'pass');
  const selected = review.index;
  review = await until(() => fixture.requests.find(request => request.index > selected && !request.closed &&
    request.input.input.some(item => item.type === 'function_call_output' && item.call_id === `route_${selected}`)),
  'The second reviewer receives the route tool result');
  fixture.finish(review.index, { text: 'Approved version two' });
  await until(async () => (await read()).paths.some(path => path.result === 'Approved version two'),
    'The review path reaches its exit');
  assert.equal((await read()).state, 'running');
  assert.equal((await card()).status, 'in_progress');
  fixture.finish(parallel.index, { text: 'Parallel work complete' });
  await until(async () => (await card()).status === 'done', 'The ticket completes after its last path reaches an exit');
  assert.equal((await read()).state, 'completed');
  assert.deepEqual((await read()).paths.map(path => path.result).sort(), ['Approved version two', 'Parallel work complete']);
  await dots.first().waitFor({ state: 'detached' });
  await graph.getByRole('button', { name: `实例 #${instance_id} · 已完成`, exact: true }).click();
  await instance.getByText(/出口结果 · 路径 #\d+ · review → finish/).waitFor();
  await instance.getByText(/出口结果 · 路径 #\d+ · parallel → finish/).waitFor();
  await instance.getByRole('button', { name: 'Close panel', exact: true }).click();

  await page.getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('combobox', { name: '跳到状态列' }).selectOption({ label: '已完成' });
  const openedCard = page.getByRole('button', { name: '打开 Workflow acceptance ticket', exact: true });
  await openedCard.waitFor();
  assert.equal(await openedCard.evaluate(el => {
    const track = el.closest('[data-page-region="board-stages"]').getBoundingClientRect();
    const card = el.getBoundingClientRect();
    return card.left < track.right && card.right > track.left;
  }), true);
});

test('workflows can be authored and started in place from the browser', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page } = fixture;
  await page.getByRole('button', { name: '任务图', exact: true }).click();
  await page.setViewportSize({ width: 588, height: 744 });
  const main = page.getByRole('main');
  await main.getByRole('button', { name: '创建工作流', exact: true }).click();
  const create = page.getByRole('dialog', { name: '创建工作流', exact: true });
  await create.getByRole('textbox', { name: '工作流名称' }).fill('Browser workflow');
  await create.getByRole('button', { name: '创建工作流', exact: true }).click();
  const graph = main.getByRole('region', { name: 'Browser workflow', exact: true });
  await graph.waitFor();
  const canvas = graph.locator('[data-semantic-key="task-graph/viewport"]');
  assert.equal(await canvas.evaluate(el => el.scrollWidth <= el.clientWidth), true);

  const start = async (name, message) => {
    const workflow = main.getByRole('region', { name, exact: true });
    await workflow.getByRole('button', { name: '启动工作流', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: '启动工作流', exact: true });
    await dialog.getByText(name, { exact: true }).waitFor();
    await dialog.getByRole('combobox', { name: '入口', exact: true }).selectOption({ label: 'start' });
    await dialog.getByRole('textbox', { name: '消息', exact: true }).fill(message);
    await dialog.getByRole('button', { name: '启动工作流', exact: true }).click();
    await dialog.waitFor({ state: 'hidden' });
    const instance = page.getByRole('dialog', { name: /^实例 #\d+$/ });
    await instance.waitFor();
    return { workflow, instance };
  };
  const first = 'First line\nSecond line';
  const { instance: firstRun } = await start('Browser workflow', first);
  const receipt = firstRun.getByText(/出口结果 · 路径 #\d+ · start → finish/);
  const receiptTop = await receipt.evaluate(el => el.getBoundingClientRect().top);
  await receipt.click();
  assert.ok(Math.abs(await receipt.evaluate(el => el.getBoundingClientRect().top) - receiptTop) <= 1);
  assert.equal(await firstRun.getByText(first, { exact: true }).innerText(), first);
  await firstRun.getByRole('button', { name: 'Close panel', exact: true }).click();

  await graph.getByRole('button', { name: '编辑工作流', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '编辑工作流', exact: true });
  await editor.getByRole('textbox', { name: '工作流名称' }).fill('Renamed workflow');
  const exit = editor.getByRole('region', { name: '出口 2', exact: true });
  const exitName = exit.getByRole('textbox', { name: '节点名称', exact: true });
  const save = editor.getByRole('button', { name: '保存', exact: true });
  await editor.getByText('高级选项', { exact: true }).click();
  const json = editor.getByRole('textbox', { name: 'JSON 定义', exact: true });
  const definition = await json.inputValue();
  await json.fill('{');
  await editor.getByText('修正 JSON 定义', { exact: true }).waitFor();
  assert.equal(await json.isVisible(), true);
  assert.equal(await save.isEnabled(), false);
  await json.fill(definition);
  await exitName.waitFor();
  assert.deepEqual(await json.evaluate(el => ({
    focused: el === document.activeElement,
    expanded: el.closest('details').open,
  })), { focused: true, expanded: true });
  await editor.getByText('高级选项', { exact: true }).click();
  await exitName.fill('start');
  await exit.getByText('此名称已被其他节点使用。请选择不同的名称。', { exact: true }).waitFor();
  assert.equal(await save.isEnabled(), false);
  const longExit = 'finish-renamed-with-a-long-label-that-wraps-on-a-narrow-screen';
  await exitName.fill(longExit);
  await editor.getByRole('button', { name: '添加任务', exact: true }).click();
  const node = editor.getByRole('region', { name: '任务 3', exact: true });
  const model = node.getByRole('combobox', { name: '模型', exact: true });
  await node.getByText('请选择用于创建对话的模型。', { exact: true }).waitFor();
  assert.equal(await save.isEnabled(), false);
  const modelLabel = await model.getByRole('option', { name: /interactive-fixture/ }).innerText();
  await model.selectOption({ label: modelLabel });
  assert.equal(await editor.getByRole('region', { name: '连线 1', exact: true })
    .getByRole('combobox', { name: '来源节点' }).getByRole('option', { name: longExit }).count(), 0);
  await editor.getByRole('region', { name: '连线 1', exact: true })
    .getByRole('combobox', { name: '接收节点', exact: true }).selectOption({ label: 'task-1' });
  await editor.getByRole('button', { name: '添加连线', exact: true }).click();
  const route = editor.getByRole('region', { name: '连线 2', exact: true });
  await route.getByRole('combobox', { name: '来源节点', exact: true }).selectOption({ label: 'task-1' });
  await route.getByRole('combobox', { name: '接收节点', exact: true }).selectOption({ label: longExit });
  await save.click();
  const renamedGraph = main.getByRole('region', { name: 'Renamed workflow', exact: true });
  const longNode = renamedGraph.locator('[data-semantic-key="workflow-node"]').filter({ hasText: longExit });
  const nodeBounds = () => longNode.evaluate(el => {
    const box = el.getBoundingClientRect();
    const name = el.querySelector('details').getBoundingClientRect();
    const kind = el.querySelector('[data-semantic-key="workflow-node-kind"]').getBoundingClientRect();
    return { nameBottom: name.bottom - box.top, kindTop: kind.top - box.top,
      kindBottom: kind.bottom - box.top, nodeHeight: box.height };
  });
  const verifyNodeBounds = async width => {
    const bounds = await nodeBounds();
    assert.ok(bounds.nameBottom <= bounds.kindTop + 1 && bounds.kindBottom <= bounds.nodeHeight + 1,
      `Node label at ${width}px: ${JSON.stringify(bounds)}`);
  };
  for (const width of [360, 768]) {
    await page.setViewportSize({ width, height: 900 });
    await verifyNodeBounds(width);
    await longNode.getByText(longExit, { exact: true }).click();
    await verifyNodeBounds(width);
    await longNode.getByText(longExit, { exact: true }).click();
  }
  const { workflow: renamed, instance: modelRun } = await start('Renamed workflow', 'Run with the selected model');
  assert.equal(await renamed.locator('[data-semantic-key="task-graph/viewport"]').count(), 1);
  const request = await requestFor(fixture, 'Run with the selected model');
  const answer = 'Model output\nSecond line';
  fixture.finish(request.index, { text: answer });
  await modelRun.getByText(new RegExp(`出口结果 · 路径 #\\d+ · task-1 → ${longExit}`)).click();
  assert.equal(await modelRun.getByText(answer, { exact: true }).innerText(), answer);
});

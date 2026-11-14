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
    nodes: [{ key: 'start', kind: 'entrance' }, { key: 'finish', kind: 'exit' },
      task('implement', 'once'), task('review', 'each'), task('parallel', 'once')],
    connections: [
      edge('start-implementation', 'start', 'implement'),
      { ...edge('start-parallel', 'start', 'parallel'), message: { kind: 'literal', value: 'Parallel acceptance work' } },
      edge('submit', 'implement', 'review'),
      edge('changes', 'review', 'implement', 'Changes are required'),
      edge('pass', 'review', 'finish', 'The implementation passes'),
      edge('parallel-done', 'parallel', 'finish'),
    ],
  };
  await editor.getByRole('textbox', { name: 'JSON 定义', exact: true }).fill(JSON.stringify(definition, null, 2));
  await editor.getByRole('button', { name: '创建工作流', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  const { card_id } = await command({ op: 'create_card', title: 'Workflow acceptance ticket' });
  await page.getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('button', { name: '打开 Workflow acceptance ticket', exact: true }).click();
  const details = page.getByRole('dialog', { name: '卡片详情', exact: true });
  await details.getByRole('button', { name: '选择 Implement and review · start', exact: true }).click();
  await details.getByRole('button', { name: '启动工作流实例', exact: true }).first().click();
  const instance_id = await until(async () => {
    const ticket = await command({ op: 'read_card', card_id });
    return Number.isInteger(ticket.workflow_instance_id) ? ticket.workflow_instance_id : null;
  }, 'Starting from the board attaches a workflow instance');
  const read = () => command({ op: 'read_workflow_instance', instance_id });
  const card = () => command({ op: 'read_card', card_id });
  const active = (instance, node) => instance.paths.find(path => path.node === node && path.active);
  const first = await requestFor(fixture, 'Workflow acceptance ticket');
  const parallel = await requestFor(fixture, 'Parallel acceptance work');
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
  await dots.first().hover();
  assert.equal(await dots.first().evaluate(el => {
    const box = el.getBoundingClientRect();
    return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2) === el;
  }), true, 'The floating dot is visible outside the node and can be hovered');

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
});

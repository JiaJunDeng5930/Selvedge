import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture, openCreationEnvironment } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function submitTask(page) {
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const response = await receipt;
  assert.equal(response.status(), 200);
  const { reply } = await response.json();
  assert.equal(reply.ok, true, JSON.stringify(reply));
  return reply.result.task_id;
}

async function projectTask(page) {
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: 'Acceptance Project', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();
  await page.getByRole('button', { name: 'Start task', exact: true }).waitFor();
}

async function projectWorkspaceFixture(t) {
  const fixture = await browserFixture(t);
  const { command } = fixture;
  const root = path.join(fixture.root, 'Project workspace');
  await mkdir(root);
  await writeFile(path.join(root, 'AGENTS.md'), 'Use the Project acceptance instructions.');
  const { project_id } = await command({ op: 'create_project', name: 'Acceptance Project',
    workspace: { roots: [root], primary_root: root } });
  return { fixture, root, project_id };
}

async function finishModelReply(fixture, prompt, reply) {
  const deadline = Date.now() + 5000;
  let request;
  do {
    request = fixture.requests.find(entry => !entry.closed && entry.input.input.some(item =>
      item.role === 'user' && JSON.stringify(item.content).includes(prompt)));
    if (request) break;
    await delay(10);
  } while (Date.now() < deadline);
  assert.ok(request, `The model did not receive the expected input: ${prompt}`);
  fixture.finish(request.index, { text: reply });
}

test('Work navigation preserves Project grouping and opens the same conversation from the tree, graph and Board', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command, profile } = fixture;
  const project = 'Shared research project';
  const { project_id } = await command({ op: 'create_project', name: project, workspace: { roots: [] } });
  const { work_id: research } = await command({ op: 'create_work', name: 'Research Work' });
  const { work_id: release } = await command({ op: 'create_work', name: 'Release Work' });

  async function conversation(work_id, message) {
    const { task_id } = await command({ op: 'create_work_task', work_id, profile, message, settings: { project_id } });
    await finishModelReply(fixture, message, `Initial reply for ${message}.`);
    const { task } = await taskIdle(fixture.running.service, task_id);
    return task;
  }

  const source = await conversation(research, 'Collect evidence for the audit');
  const destination = await conversation(research, 'Review the collected evidence');
  const { task_id: releaseTask } = await command({ op: 'create_work_task', work_id: release, profile: 'demo',
    message: 'Prepare the release brief', settings: { project_id } });
  const { task: other } = await taskIdle(fixture.running.service, releaseTask);
  const { children: [branch] } = await command({ op: 'fork', task_id: other.id, child_count: 1,
    messages: ['Check the draft release brief.'] });
  const { task: child } = await taskIdle(fixture.running.service, branch);
  await command({ op: 'create_task_graph', work_id: research, name: 'Evidence handoff', nodes: [
    { key: 'collect', task_id: source.id }, { key: 'review', task_id: destination.id },
  ], rules: [
    { key: 'forward-output', source: 'collect', actions: [{ target: 'review', message: { kind: 'output' } }] },
  ] });
  await command({ op: 'create_task_graph', work_id: release, name: 'Release checklist', nodes: [
    { key: 'release', task_id: other.id },
  ], rules: [] });
  const cardTitle = 'Review evidence from the board';
  const { card_id } = await command({ op: 'create_card', title: cardTitle });
  const { revision } = await command({ op: 'read_card', card_id });
  await command({ op: 'link_card', card_id, revision, task_id: destination.id });

  const tree = page.getByRole('navigation', { name: 'Task tree', exact: true });
  const global = page.getByRole('navigation', { name: 'Global navigation', exact: true });
  const center = page.getByRole('main');
  const projectGroup = tree.getByRole('region', { name: project, exact: true });
  const taskEntry = task => projectGroup.locator(`[data-task-id="${task.id}"]`)
    .getByRole('button', { name: task.title, exact: true }).first();
  const branches = projectGroup.getByRole('group', { name: 'Subtasks', exact: true })
    .and(projectGroup.locator(`[data-task-parent="${other.id}"]`));
  const branchEntry = branches.locator(`[data-task-id="${child.id}"]`)
    .getByRole('button', { name: child.title, exact: true });
  const picker = page.getByRole('button', { name: /^对话范围 · / });
  async function selectWork(name) {
    await picker.click();
    const overview = page.getByRole('menu', { name: '对话范围', exact: true });
    await overview.getByRole('menuitemradio', { name, exact: true }).click();
    await page.getByRole('button', { name: `对话范围 · ${name}`, exact: true }).waitFor();
  }

  await taskEntry(destination).waitFor();
  await taskEntry(other).waitFor();
  await branchEntry.waitFor();
  const collapse = projectGroup.getByRole('button', { name: `Collapse branches of ${other.title}`, exact: true });
  assert.equal(await collapse.getAttribute('aria-expanded'), 'true');
  await collapse.click();
  await branches.waitFor({ state: 'hidden' });
  await taskEntry(other).waitFor();
  const expand = projectGroup.getByRole('button', { name: `Expand branches of ${other.title}`, exact: true });
  assert.equal(await expand.getAttribute('aria-expanded'), 'false');
  await expand.click();
  await branchEntry.waitFor();
  await selectWork('Research Work');
  await taskEntry(destination).waitFor();
  await taskEntry(other).waitFor({ state: 'hidden' });
  await branches.waitFor({ state: 'hidden' });
  await taskEntry(source).click();
  const composer = center.getByRole('combobox', { name: 'Message', exact: true });
  const prompt = 'Send the signed audit finding downstream.';
  const delivered = 'Signed audit finding for the destination.';
  async function seeDestination() {
    await center.getByText(destination.title, { exact: true }).first().waitFor();
    await center.getByText(delivered, { exact: true }).waitFor();
  }
  await composer.fill(prompt);
  await composer.press('Enter');
  await finishModelReply(fixture, prompt, delivered);
  await finishModelReply(fixture, delivered, 'The destination reviewed the signed finding.');

  const graphs = page.getByRole('button', { name: '任务图', exact: true });
  await graphs.click();
  const graph = center.getByRole('region', { name: 'Evidence handoff', exact: true });
  await graph.waitFor();
  await center.getByRole('region', { name: 'Release checklist', exact: true }).waitFor({ state: 'hidden' });
  await graph.getByText(project, { exact: true }).first().waitFor();
  await graph.locator('svg[data-semantic-key="task-graph/edges"] path').first().waitFor();
  const rules = graph.getByRole('region', { name: '发送规则', exact: true });
  assert.match(await rules.innerText(), /collect[^\n]*→[^\n]*review/u);
  await graph.getByRole('region', { name: '最近发送结果', exact: true })
    .getByText(/forward-output/).waitFor();
  await graph.getByRole('button', { name: destination.title, exact: true }).click();
  await seeDestination();

  await taskEntry(source).click();
  await center.getByText(source.title, { exact: true }).first().waitFor();
  await taskEntry(destination).click();
  await seeDestination();
  await selectWork('Release Work');
  await taskEntry(other).waitFor();
  await taskEntry(destination).waitFor({ state: 'hidden' });
  await branchEntry.waitFor();
  await graphs.click();
  await center.getByRole('region', { name: 'Release checklist', exact: true }).waitFor();
  await graph.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: '共享 UI', exact: true }).click();
  await center.getByText('Release Work', { exact: true }).waitFor();
  await global.getByRole('button', { name: '项目', exact: true }).click();
  await center.getByRole('region', { name: project, exact: true }).waitFor();
  await global.getByRole('button', { name: '卡片看板', exact: true }).click();
  await center.getByRole('article', { name: cardTitle, exact: true })
    .getByRole('button', { name: '打开对话', exact: true }).click();
  await seeDestination();
});

test('Project task creation restores Project workspace inheritance through the browser', async t => {
  const { fixture, root, project_id } = await projectWorkspaceFixture(t);
  const { page, command } = fixture;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'Acceptance Project', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).waitFor();
  assert.ok((await page.getByRole('main').innerText()).includes(root));
  await page.getByText('Use the Project acceptance instructions.', { exact: true }).waitFor();
  await page.getByRole('main').getByRole('button', { name: '在项目中开始对话', exact: true }).click();
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  await start.waitFor();
  assert.equal(await start.isDisabled(), true, 'An empty Task remains a passive draft');
  assert.equal(await page.locator('button[data-logical-key="composer/workspace"]').isVisible(), false);
  const environment = await openCreationEnvironment(page);
  await environment.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: '工作目录', exact: true });
  await workspace.getByRole('button', { name: '移除目录', exact: true }).click();
  await workspace.getByRole('button', { name: '使用继承的工作目录', exact: true }).click();
  await workspace.getByRole('button', { name: '移除目录', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await environment.waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Use inherited Project workspace');
  const inherited = await submitTask(page);
  const inheritedTask = (await command({ op: 'read', task_id: inherited })).task;
  assert.equal(inheritedTask.settings.project_id, project_id);
  assert.deepEqual(inheritedTask.settings.workspace, { roots: [root], primary_root: root });
});

test('Project task creation preserves explicitly empty workspaces through the browser', async t => {
  const { fixture, root, project_id } = await projectWorkspaceFixture(t);
  const { page, command } = fixture;
  await projectTask(page);
  const environment = await openCreationEnvironment(page);
  await environment.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog', { name: '工作目录', exact: true });
  await workspace.getByRole('button', { name: '移除目录', exact: true }).click();
  await workspace.getByRole('button', { name: '使用继承的工作目录', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await environment.waitFor();
  await page.keyboard.press('Escape');
  await environment.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Use explicitly no workspace roots');
  const empty = await submitTask(page);
  const emptyTask = (await command({ op: 'read', task_id: empty })).task;
  assert.equal(emptyTask.settings.project_id, project_id);
  assert.deepEqual(emptyTask.settings.workspace, { roots: [], primary_root: null },
    'Explicitly removing roots must not silently return to Project inheritance');
  await page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  await page.getByRole('button', { name: '任务详情', exact: true }).click();
  const details = page.getByRole('complementary', { name: '任务详情', exact: true });
  await details.getByText('未设置工作目录', { exact: true }).waitFor();
  assert.equal(await details.getByText(/^主目录/).count(), 0,
    'An empty workspace needs only one absence indicator');
});

test('ordered image content and the active composer survive responsive navigation', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, command } = fixture;
  const asset = await fixture.upload('ordered image.png');
  const image = { type: 'image', image: { id: asset.id, mime: asset.mime, bytes: Number(asset.bytes) }, detail: 'auto' };
  const { task_id } = await command({ op: 'create', profile: fixture.profile, message: [
    { type: 'text', text: 'Before image marker' }, image,
    { type: 'text', text: 'Between images marker' }, image,
    { type: 'text', text: 'After images marker' },
  ] });
  await taskIdle(fixture.running.service, task_id);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: /^Image fixture task/ }).click();
  await page.getByText('Image request accepted.', { exact: true }).waitFor();
  const order = await page.getByRole('main').evaluate((root, id) => {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    const sequence = [];
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (node.nodeType === Node.TEXT_NODE) {
        for (const marker of ['Before image marker', 'Between images marker', 'After images marker']) {
          if (node.textContent.includes(marker)) sequence.push(marker);
        }
      } else if (node.localName === 'img' && node.getAttribute('src').includes(id)) sequence.push('image');
    }
    return sequence;
  }, asset.id);
  assert.deepEqual(order, ['Before image marker', 'image', 'Between images marker', 'image', 'After images marker'],
    'Images remain at their original content positions, including repeated references to the same asset');

  const message = page.getByRole('combobox', { name: 'Message', exact: true });
  await message.fill('Keep this unsent draft while narrowing.');
  await message.focus();
  const narrowWidth = 390;
  await page.setViewportSize({ width: narrowWidth, height: 900 });
  const tasks = page.getByRole('button', { name: 'Open Task list', exact: true });
  await tasks.waitFor();
  assert.equal(await message.evaluate(node => node === document.activeElement), true,
    'A layout change must preserve the user activity instead of opening the Task tree');
  assert.equal(await message.inputValue(), 'Keep this unsent draft while narrowing.');
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), narrowWidth,
    'The narrow workspace stays within the page width');
  await tasks.focus();
  await tasks.press('Space');
  const taskDrawer = page.getByRole('dialog', { name: '对话', exact: true });
  await taskDrawer.waitFor();
  assert.equal(await taskDrawer.getByRole('button', { name: '任务图', exact: true }).count(), 0);
  await page.keyboard.press('Escape');
  await taskDrawer.waitFor({ state: 'hidden' });
  assert.equal(await tasks.evaluate(node => node === document.activeElement), true,
    'Closing the Task tree restores its actual keyboard launcher');
  const launcher = page.getByRole('button', { name: 'Global navigation', exact: true });
  await launcher.press('Enter');
  const navigation = page.getByRole('dialog').getByRole('navigation', { name: 'Global destinations', exact: true });
  await navigation.getByRole('button', { name: '项目', exact: true }).waitFor();
  await navigation.getByRole('button', { name: '任务图', exact: true }).click();
  await page.getByRole('main').getByRole('heading', { name: '任务图', exact: true }).waitFor();
  await launcher.click();
  await navigation.getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
});

test('task graph setup creates its conversations in scope and routes replies', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { work_id: work } = await command({ op: 'create_work', name: 'Graph setup' });
  const { task_id: outsider } = await command({ op: 'create_idle', profile: 'demo' });
  await page.getByRole('button', { name: /^对话范围 · / }).click();
  await page.getByRole('menu', { name: '对话范围', exact: true })
    .getByRole('menuitemradio', { name: 'Graph setup', exact: true }).click();
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: '任务图', exact: true }).click();
  const emptyGraph = page.getByRole('main').locator('[data-semantic-key="task-graph/empty"]');
  const emptyRoute = emptyGraph.getByRole('region', { name: '转发方向', exact: true });
  await emptyRoute.getByText('来源对话', { exact: true }).waitFor();
  await emptyGraph.getByText('接收对话', { exact: true }).waitFor();
  assert.equal(await emptyRoute.getByRole('button').count(), 0);
  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 780 });
    const geometry = await emptyRoute.evaluate(node => {
      const [from, arrow, to] = Array.from(node.children, child => child.getBoundingClientRect());
      const description = node.previousElementSibling.getBoundingClientRect();
      const heading = node.parentElement.querySelector('h3').getBoundingClientRect();
      const create = node.parentElement.querySelector('button').getBoundingClientRect();
      const center = box => box.top + box.height / 2;
      const axis = box => box.left + box.width / 2;
      return { row: from.right < arrow.left && arrow.right < to.left &&
        Math.abs(center(from) - center(arrow)) < 1 && Math.abs(center(arrow) - center(to)) < 1,
      follows: from.top >= description.bottom && create.top >= to.bottom,
      fits: from.left >= 0 && to.right <= innerWidth,
      centered: [heading, description, create].every(box =>
        Math.abs(axis(box) - axis(node.getBoundingClientRect())) < 2) };
    });
    assert.deepEqual(geometry, { row: true, follows: true, fits: true, centered: true }, 'Empty route at ' + width + 'px');
  }
  await page.setViewportSize({ width: 1280, height: 900 });
  await emptyGraph.getByRole('button', { name: '创建对话转发', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: '创建对话转发', exact: true });
  const create = dialog.getByRole('button', { name: '创建对话转发', exact: true });
  await create.waitFor();
  const declaration = dialog.getByRole('textbox', { name: 'JSON 定义', exact: true });
  const advanced = dialog.getByText('高级配置', { exact: true });
  assert.equal(await declaration.isVisible(), false);
  await advanced.click();
  await dialog.getByText('JSON 定义', { exact: true }).waitFor();
  const initialDeclaration = await declaration.inputValue();
  assert.match(initialDeclaration, /^\{\n  "name": "对话转发",\n  "nodes": \[\n    \{/);
  const custom = JSON.parse(initialDeclaration);
  custom.rules[0].key = 'custom';
  await declaration.fill(JSON.stringify(custom, null, 2));
  await dialog.getByText('自定义转发规则在 JSON 定义中编辑。', { exact: true }).waitFor();
  assert.equal(await declaration.isVisible(), true);
  const editedDeclaration = initialDeclaration.replace('"name": "对话转发"', '"name" :  "对话转发"');
  await declaration.fill(editedDeclaration);
  await advanced.click();
  await advanced.click();
  assert.equal(await declaration.inputValue(), editedDeclaration, 'Reopening the editor preserves the author’s draft spacing');
  await advanced.click();
  assert.equal(await dialog.getByRole('alert').count(), 0);
  assert.equal(await create.isDisabled(), true);
  const name = dialog.getByRole('textbox', { name: '转发名称', exact: true });
  assert.equal(await name.inputValue(), '对话转发');
  const newConversation = dialog.getByRole('button', { name: '新建对话', exact: true });
  const returnToGraph = page.getByRole('button', { name: '返回任务图', exact: true });
  const prerequisite = dialog.locator('[data-semantic-key="handoff-needs-conversations"]');
  async function expectBlockedBy(message) {
    await create.and(dialog.locator(`[data-help=${JSON.stringify(message)}]`)).waitFor();
    assert.equal(await create.isDisabled(), true);
    assert.equal(await create.evaluate(button =>
      (button.getAttribute('aria-describedby') ?? '').split(/\s+/)
        .map(id => document.getElementById(id)?.textContent ?? '').join(' ').trim()), message);
  }
  await name.fill('Browser handoff');
  await expectBlockedBy('请在此范围内新建两条对话。');
  assert.equal(await prerequisite.innerText(), '请在此范围内新建两条对话。');
  await newConversation.click();
  assert.equal(await returnToGraph.innerText(), '返回任务图');
  await returnToGraph.click();
  assert.equal(await name.inputValue(), 'Browser handoff');

  async function createEndpoint(message) {
    await newConversation.click();
    await returnToGraph.waitFor();
    const model = page.getByRole('button', { name: /^Model:/ });
    if (!(await model.getAttribute('aria-label')).includes('echo')) {
      await model.click();
      const picker = page.getByRole('dialog', { name: 'Model', exact: true });
      const choose = picker.getByRole('button', { name: /^Choose model:/ });
      const echo = picker.getByRole('menuitemradio', { name: 'echo', exact: true });
      await Promise.any([choose.waitFor(), echo.waitFor()]);
      if (await choose.isVisible()) await choose.click();
      await echo.click();
      if (await picker.isVisible()) await page.keyboard.press('Escape');
    }
    await page.getByRole('combobox', { name: 'Task', exact: true }).fill(message);
    const task = await submitTask(page);
    await dialog.waitFor();
    assert.equal(await name.inputValue(), 'Browser handoff');
    await taskIdle(fixture.running.service, task);
    return task;
  }

  const sourceRequest = 'Collect evidence for the graph';
  const source = await createEndpoint(sourceRequest);
  await expectBlockedBy('请在此范围内再新建一条对话。');
  assert.equal(await prerequisite.innerText(), '请在此范围内再新建一条对话。');
  const receiver = await createEndpoint('Review evidence');
  await expectBlockedBy('请选择来源对话和接收对话。');
  assert.deepEqual((await command({ op: 'read_work', work_id: work })).task_ids, [source, receiver]);
  const sourcePicker = dialog.getByRole('combobox', { name: '来源对话', exact: true });
  const receiverPicker = dialog.getByRole('combobox', { name: '接收对话', exact: true });
  const availableSources = await sourcePicker.locator('option').evaluateAll(options => options.map(option => option.value));
  assert.ok(!availableSources.includes(String(outsider)), 'The picker stays in the graph scope');
  const sourceTitle = (await command({ op: 'read', task_id: source })).task.title;
  const receiverTitle = (await command({ op: 'read', task_id: receiver })).task.title;
  assert.notEqual(sourceTitle, receiverTitle);
  const sourceOption = id => sourcePicker.locator(`option[value="${id}"]`);
  assert.equal(await sourceOption(source).textContent(), sourceTitle);
  assert.equal(await sourceOption(receiver).textContent(), receiverTitle);
  const { task_id: duplicate } = await command({ op: 'create_work_task', work_id: work,
    profile: 'demo', message: sourceRequest });
  await taskIdle(fixture.running.service, duplicate);
  assert.equal((await command({ op: 'read', task_id: duplicate })).task.title, sourceTitle);
  await sourceOption(duplicate).filter({ hasText: `${sourceTitle} · #${duplicate}` }).waitFor({ state: 'attached' });
  assert.equal(await sourceOption(source).textContent(), `${sourceTitle} · #${source}`);
  assert.equal(await sourceOption(receiver).textContent(), receiverTitle);
  await sourcePicker.selectOption(String(source));
  await expectBlockedBy('请选择接收对话。');
  await receiverPicker.selectOption(String(receiver));
  await create.and(dialog.getByRole('button', { disabled: false })).waitFor();

  const direction = dialog.locator('[data-semantic-key="handoff-direction"]');
  const compactHeader = page.locator('[data-surface-role="compact-header"]');
  const desktop = page.viewportSize();
  for (const viewport of [{ width: 1280, height: 720 }, { width: 390, height: 740 }]) {
    await page.setViewportSize(viewport);
    await advanced.click();
    const [from, to, options, json, lineHeight, submit] = await Promise.all([
      sourcePicker.boundingBox(), receiverPicker.boundingBox(), advanced.boundingBox(),
      declaration.boundingBox(), declaration.evaluate(node => parseFloat(getComputedStyle(node).lineHeight)),
      create.boundingBox(),
    ]);
    assert.ok(from && to && options && json && submit);
    assert.ok(from.y >= 0 && to.y + to.height < options.y && options.y + options.height < json.y,
      'Both conversations remain visible above the advanced configuration');
    assert.ok(json.height >= 3 * lineHeight && json.y + json.height < submit.y,
      'The advanced editor shows several lines and leaves room for the transfer action');
    assert.equal(await sourcePicker.inputValue(), String(source));
    assert.equal(await receiverPicker.inputValue(), String(receiver));
    await advanced.click();
  }
  await page.setViewportSize({ width: 844, height: 390 });
  await advanced.click();
  const [landscapeRoute, landscapeJson, landscapeSubmit] = await Promise.all([
    dialog.getByRole('region', { name: '转发方向', exact: true }).boundingBox(),
    declaration.boundingBox(), create.boundingBox(),
  ]);
  assert.ok(landscapeRoute && landscapeJson && landscapeSubmit);
  assert.ok(landscapeRoute.x + landscapeRoute.width < landscapeJson.x
    && landscapeRoute.y + landscapeRoute.height < landscapeSubmit.y
    && landscapeJson.y + landscapeJson.height < landscapeSubmit.y,
    'Landscape shows the route beside the JSON editor with the action below both');
  await advanced.click();
  for (const width of [desktop.width, 390, 320]) {
    await page.setViewportSize({ width, height: desktop.height });
    await compactHeader.waitFor({ state: width === desktop.width ? 'hidden' : 'visible' });
    const [left, arrow, right, sourceLabel, receiverLabel] = await Promise.all([
      sourcePicker.boundingBox(), direction.boundingBox(), receiverPicker.boundingBox(),
      dialog.getByText('来源对话', { exact: true }).boundingBox(),
      dialog.getByText('接收对话', { exact: true }).boundingBox(),
    ]);
    assert.ok(left && arrow && right && sourceLabel && receiverLabel,
      `Both choices, their labels and the direction must be visible at ${width}px`);
    assert.equal(await direction.innerText(), '→');
    assert.ok(Math.abs(sourceLabel.y - receiverLabel.y) <= 2, `Both labels share one row at ${width}px`);
    assert.ok(Math.abs(left.y - right.y) <= 2, `The endpoint controls share one row at ${width}px`);
    const arrowCenter = await direction.evaluate(element => {
      const text = document.createRange();
      text.selectNodeContents(element);
      const { y, height } = text.getBoundingClientRect();
      return y + height / 2;
    });
    for (const picker of [left, right]) {
      const difference = Math.abs(arrowCenter - (picker.y + picker.height / 2));
      assert.ok(difference <= 2, `The direction and select centerlines differ by ${difference}px at ${width}px`);
    }
    assert.ok(left.x + left.width <= arrow.x + 1 && arrow.x + arrow.width <= right.x + 1,
      `Source, arrow and destination are ordered without overlap at ${width}px`);
  }
  await page.setViewportSize(desktop);
  await name.fill('');
  await expectBlockedBy('请输入转发名称。');
  await name.fill('Browser handoff');
  await create.click();
  await dialog.waitFor({ state: 'hidden' });

  await page.getByRole('region', { name: 'Browser handoff', exact: true })
    .getByRole('button', { name: '编辑任务图', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '编辑任务图', exact: true });
  const from = editor.getByRole('combobox', { name: '来源对话', exact: true });
  const to = editor.getByRole('combobox', { name: '接收对话', exact: true });
  assert.equal(await from.inputValue(), String(source));
  assert.equal(await to.inputValue(), String(receiver));
  await editor.getByRole('textbox', { name: '转发名称', exact: true }).fill('Edited handoff');
  await editor.getByRole('button', { name: '保存', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });

  const graph = page.getByRole('region', { name: 'Edited handoff', exact: true });
  await graph.waitFor();
  await command({ op: 'send', task_id: source, message: 'Forward this through the graph' });
  await graph.getByRole('region', { name: '最近发送结果', exact: true })
    .getByText(new RegExp(`对话 #${source} → 对话 #${receiver}`)).waitFor();
  const delivered = await command({ op: 'read', task_id: receiver });
  assert.match(JSON.stringify(delivered), /Forward this through the graph/);
});

test('leaving a graph conversation before its receipt preserves the newer destination', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: '任务图', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '创建对话转发', exact: true }).click();
  const graph = page.getByRole('dialog', { name: '创建对话转发', exact: true });
  const name = graph.getByRole('textbox', { name: '转发名称', exact: true });
  await name.fill('Keep this graph');
  await graph.getByRole('button', { name: '新建对话', exact: true }).click();
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Create while leaving the graph');

  let started, release;
  const pending = new Promise(resolve => { started = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  t.after(() => release());
  await page.route('**/api/browser/command', async route => {
    if (route.request().postDataJSON()?.command?.op !== 'create') return route.continue();
    const response = await route.fetch();
    started();
    await gate;
    await route.fulfill({ response });
  });
  const submission = submitTask(page);
  await pending;
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const board = page.getByRole('main').getByRole('heading', { name: '卡片看板', exact: true });
  await board.waitFor();
  release();
  await submission;
  assert.equal(await board.isVisible(), true);
  assert.equal(await graph.isVisible(), false);

  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: '任务图', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: '创建对话转发', exact: true }).click();
  await graph.locator('[data-semantic-key="handoff-needs-conversations"]')
    .filter({ hasText: '请在此范围内再新建一条对话。' }).waitFor();
  assert.equal(await name.inputValue(), 'Keep this graph');
});

async function graphTemplateFixture(t) {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const alpha = await command({ op: 'create_idle', profile: 'demo' });
  const beta = await command({ op: 'create_idle', profile: 'demo' });
  const graph = await command({ op: 'create_task_graph', name: 'Acceptance workflow',
    nodes: [{ key: 'alpha', task_id: alpha.task_id }, { key: 'beta', task_id: beta.task_id }],
    rules: [{ key: 'flow', source: 'alpha', actions: [{ target: 'beta', message: { kind: 'output' } }] }],
  });
  const source = `<ui id="acceptanceGraph">
<state id="count" type="integer" initial={0} min={0} max={20} />
<state id="note" type="string" initial="" />
<source id="workflow" kind="task-graph" graph-id={${graph.graph_id}} mode="live" />
<stack id="root">
<text id="count-label" label={"Count: " + text(count)} />
<text-input id="note-entry" bind="note" label="Shared note" />
<resource-view id="live" source="workflow" let="graph">
<graph-view id="diagram" nodes={graph.nodes} edges={graph.edges} node-key="identity" layout="stable" label="Acceptance workflow">
<node-template item="node"><stack id="node-body">
<text id="node-name" label={node.key} />
<button id="node-action" label={"Increment " + node.key} action="set" target="count" value={count + 1} />
</stack></node-template>
</graph-view>
</resource-view>
</stack>
</ui>`;
  async function viewer(title) {
    const index = fixture.requests.length;
    const { task_id } = await command({ op: 'create', profile: fixture.profile, message: title });
    const deadline = Date.now() + 5000;
    while (fixture.requests.length <= index && Date.now() < deadline) await delay(10);
    assert.ok(fixture.requests.length > index, 'The complete service must request the viewer reply from its model');
    fixture.finish(index, { text: '```selvedge-ui\n' + source + '\n```' });
    const { task } = await taskIdle(fixture.running.service, task_id);
    const taskEntry = page.getByRole('navigation', { name: 'Task tree', exact: true })
      .getByRole('button').filter({ hasText: task.title });
    await taskEntry.waitFor();
    await taskEntry.click();
    await page.getByRole('main').getByText(task.title, { exact: true }).first().waitFor();
    await page.getByRole('button', { name: 'Increment alpha', exact: true }).waitFor();
    return task.title;
  }
  return { page, viewer };
}

test('live graph node templates remain operable and restore their own state atomically', { timeout: 60000 }, async t => {
  const { page, viewer } = await graphTemplateFixture(t);
  const title = await viewer('Graph interaction acceptance');
  assert.match(await page.getByRole('list', { name: '图节点状态', exact: true }).innerText(), /alpha[\s\S]*beta/);
  assert.match(await page.getByRole('list', { name: '连接规则', exact: true }).innerText(), /flow/);
  await page.getByRole('button', { name: 'Increment alpha', exact: true }).click();
  await page.getByText('Count: 1', { exact: true }).waitFor();
  await page.getByRole('textbox', { name: 'Shared note', exact: true }).fill('One persistent logical note');
  await page.getByRole('button', { name: 'Increment beta', exact: true }).click();
  await page.getByText('Count: 2', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), 'One persistent logical note');
  await page.getByRole('button', { name: '右移', exact: true }).click();
  const panned = await page.getByRole('button', { name: 'Increment alpha', exact: true }).boundingBox();
  await page.getByRole('button', { name: '适应宽度', exact: true }).click();
  await page.waitForFunction(x => {
    const action = [...document.querySelectorAll('button')].find(node => node.textContent === 'Increment alpha');
    return action && action.getBoundingClientRect().x !== x;
  }, panned.x);
  for (let step = 0; step < 3; step++) await page.getByRole('button', { name: '缩小', exact: true }).click();
  const first = await page.getByRole('button', { name: 'Increment alpha', exact: true }).boundingBox();
  const second = await page.getByRole('button', { name: 'Increment beta', exact: true }).boundingBox();
  assert.ok(first.width >= 24 && first.height >= 24 && second.width >= 24 && second.height >= 24,
    'Zoom preserves operable node controls');
  assert.ok(first.x + first.width <= second.x || second.x + second.width <= first.x
    || first.y + first.height <= second.y || second.y + second.height <= first.y,
  'Different node controls must not overlap at low zoom');
  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  await page.getByRole('navigation', { name: 'Task tree', exact: true }).getByRole('button').filter({ hasText: title }).click();
  await page.getByText('Count: 2', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), 'One persistent logical note');
  const invalid = await page.evaluate(() => {
    const [key, raw] = Object.entries(localStorage).find(([key]) => key.startsWith('selvedge-interactive-v1/'));
    const snapshot = JSON.parse(raw);
    snapshot.payload.locals.find(local => local.id === 'count').value = 'invalid integer';
    snapshot.payload.locals.find(local => local.id === 'note').value = 'Must not partially restore';
    return [key, JSON.stringify(snapshot)];
  });
  await page.evaluate(([key, raw]) => localStorage.setItem(key, raw), invalid);
  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  await page.getByRole('navigation', { name: 'Task tree', exact: true }).getByRole('button').filter({ hasText: title }).click();
  await page.getByText('Count: 0', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), '',
    'An invalid persisted field must reject the whole restoration before any other field is applied');
});

test('the same graph definition in another Task keeps an independent local state', { timeout: 60000 }, async t => {
  const { page, viewer } = await graphTemplateFixture(t);
  await viewer('Graph document with saved state');
  await page.getByRole('button', { name: 'Increment alpha', exact: true }).click();
  await page.getByText('Count: 1', { exact: true }).waitFor();
  await page.getByRole('textbox', { name: 'Shared note', exact: true }).fill('This note belongs to the first Task.');
  await viewer('Independent graph document');
  await page.getByText('Count: 0', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), '',
    'The same definition in another Task must not acquire the first Task\'s stored state');
});

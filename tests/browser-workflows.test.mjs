import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
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
    const overview = page.getByRole('dialog', { name: '对话范围', exact: true });
    await overview.getByRole('radio', { name, exact: true }).click();
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

  const graphs = page.getByRole('button', { name: 'Task graphs', exact: true });
  await graphs.click();
  const graph = center.getByRole('region', { name: 'Evidence handoff', exact: true });
  await graph.waitFor();
  await center.getByRole('region', { name: 'Release checklist', exact: true }).waitFor({ state: 'hidden' });
  await graph.getByText(project, { exact: true }).first().waitFor();
  await graph.locator('svg[data-semantic-key="task-graph/edges"] path').first().waitFor();
  const rules = graph.getByRole('region', { name: 'Output rules', exact: true });
  assert.match(await rules.innerText(), /collect[^\n]*→[^\n]*review/u);
  await graph.getByRole('region', { name: 'Last delivery results', exact: true })
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
  await page.getByRole('group', { name: /^Project and run settings · / }).locator('summary').click();
  await page.locator('button[data-logical-key="composer/workspace"]').click();
  let workspace = page.getByRole('dialog');
  await workspace.getByRole('button', { name: 'Remove directory', exact: true }).click();
  await workspace.getByRole('button', { name: 'Use inherited workspace', exact: true }).click();
  await workspace.getByRole('button', { name: 'Remove directory', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
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
  await page.getByRole('group', { name: /^Project and run settings · / }).locator('summary').click();
  await page.locator('button[data-logical-key="composer/workspace"]').click();
  const workspace = page.getByRole('dialog');
  await workspace.getByRole('button', { name: 'Remove directory', exact: true }).click();
  await workspace.getByRole('button', { name: 'Use inherited workspace', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Use explicitly no workspace roots');
  const empty = await submitTask(page);
  const emptyTask = (await command({ op: 'read', task_id: empty })).task;
  assert.equal(emptyTask.settings.project_id, project_id);
  assert.deepEqual(emptyTask.settings.workspace, { roots: [], primary_root: null },
    'Explicitly removing roots must not silently return to Project inheritance');
  await page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Task details', exact: true }).click();
  const details = page.getByRole('complementary', { name: 'Task details', exact: true });
  await details.getByText('No working directory', { exact: true }).waitFor();
  assert.equal(await details.getByText('Primary directory', { exact: true }).count(), 0,
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
  await page.getByRole('dialog', { name: '对话', exact: true }).waitFor();
  await page.getByRole('dialog', { name: '对话', exact: true })
    .getByRole('button', { name: 'Task graphs', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await page.getByRole('dialog', { name: '对话', exact: true }).waitFor({ state: 'hidden' });
  assert.equal(await tasks.evaluate(node => node === document.activeElement), true,
    'Closing the Task tree restores its actual keyboard launcher');
  await tasks.press('Enter');
  await page.getByRole('dialog', { name: '对话', exact: true })
    .getByRole('button', { name: 'Task graphs', exact: true }).click();
  await page.getByRole('main').getByRole('heading', { name: 'Task graphs', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Global navigation', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('main').getByText('卡片看板', { exact: true }).waitFor();
});

test('task graph setup creates its conversations in scope and routes replies', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const { work_id: work } = await command({ op: 'create_work', name: 'Graph setup' });
  const { task_id: outsider } = await command({ op: 'create_idle', profile: 'demo' });
  await page.getByRole('button', { name: /^对话范围 · / }).click();
  await page.getByRole('dialog', { name: '对话范围', exact: true })
    .getByRole('radio', { name: 'Graph setup', exact: true }).click();
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: 'Task graphs', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'New task graph', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: 'New task graph', exact: true });
  const create = dialog.getByRole('button', { name: 'Create task graph', exact: true });
  await create.waitFor();
  assert.equal(await dialog.getByRole('textbox', { name: 'Graph JSON', exact: true }).isVisible(), false);
  assert.equal(await dialog.getByRole('alert').count(), 0);
  assert.equal(await create.isDisabled(), true);
  const name = dialog.getByRole('textbox', { name: 'Graph name', exact: true });
  const newConversation = dialog.getByRole('button', { name: 'New conversation', exact: true });
  const returnToGraph = page.getByRole('button', { name: 'Back to task graph', exact: true });
  const prerequisite = dialog.locator('[data-semantic-key="handoff-needs-conversations"]');
  async function expectBlockedBy(message) {
    await create.and(dialog.locator(`[data-help=${JSON.stringify(message)}]`)).waitFor();
    assert.equal(await create.isDisabled(), true);
    assert.equal(await create.evaluate(button =>
      (button.getAttribute('aria-describedby') ?? '').split(/\s+/)
        .map(id => document.getElementById(id)?.textContent ?? '').join(' ').trim()), message);
  }
  await name.fill('Browser handoff');
  await expectBlockedBy('Create two conversations in this scope.');
  assert.equal(await prerequisite.innerText(), 'Create two conversations in this scope.');
  await newConversation.click();
  assert.equal(await returnToGraph.innerText(), 'Back to task graph');
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

  const source = await createEndpoint('Collect evidence for the graph');
  await expectBlockedBy('Create one more conversation in this scope.');
  assert.equal(await prerequisite.innerText(), 'Create one more conversation in this scope.');
  const receiver = await createEndpoint('Review the routed evidence');
  await expectBlockedBy('Choose a source and a receiving conversation.');
  assert.deepEqual((await command({ op: 'read_work', work_id: work })).task_ids, [source, receiver]);
  const availableSources = await dialog.getByRole('combobox', { name: 'Source conversation', exact: true })
    .locator('option').evaluateAll(options => options.map(option => option.value));
  assert.ok(!availableSources.includes(String(outsider)), 'The picker stays in the graph scope');
  await dialog.getByRole('combobox', { name: 'Source conversation', exact: true }).selectOption(String(source));
  await expectBlockedBy('Choose a receiving conversation.');
  await dialog.getByRole('combobox', { name: 'Receiving conversation', exact: true }).selectOption(String(receiver));
  await dialog.getByRole('button', { name: 'Create task graph', exact: true, disabled: false }).waitFor();
  await name.fill('');
  await expectBlockedBy('Enter a graph name.');
  await name.fill('Browser handoff');
  await create.click();
  await dialog.waitFor({ state: 'hidden' });

  await page.getByRole('region', { name: 'Browser handoff', exact: true })
    .getByRole('button', { name: 'Edit task graph', exact: true }).click();
  const editor = page.getByRole('dialog', { name: 'Edit task graph', exact: true });
  const from = editor.getByRole('combobox', { name: 'Source conversation', exact: true });
  const to = editor.getByRole('combobox', { name: 'Receiving conversation', exact: true });
  assert.equal(await from.inputValue(), String(source));
  assert.equal(await to.inputValue(), String(receiver));
  await editor.getByRole('textbox', { name: 'Graph name', exact: true }).fill('Edited handoff');
  await editor.getByRole('button', { name: 'Save', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });

  const graph = page.getByRole('region', { name: 'Edited handoff', exact: true });
  await graph.waitFor();
  await command({ op: 'send', task_id: source, message: 'Forward this through the graph' });
  await graph.getByRole('region', { name: 'Last delivery results', exact: true })
    .getByText(new RegExp(`Task #${source} → Task #${receiver}`)).waitFor();
  const delivered = await command({ op: 'read', task_id: receiver });
  assert.match(JSON.stringify(delivered), /Forward this through the graph/);
});

test('leaving a graph conversation before its receipt preserves the newer destination', { timeout: 60000 }, async t => {
  const { page } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: 'Task graphs', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'New task graph', exact: true }).click();
  const graph = page.getByRole('dialog', { name: 'New task graph', exact: true });
  const name = graph.getByRole('textbox', { name: 'Graph name', exact: true });
  await name.fill('Keep this graph');
  await graph.getByRole('button', { name: 'New conversation', exact: true }).click();
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
    .getByRole('button', { name: 'Task graphs', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'New task graph', exact: true }).click();
  await graph.locator('[data-semantic-key="handoff-needs-conversations"]')
    .filter({ hasText: 'Create one more conversation in this scope.' }).waitFor();
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

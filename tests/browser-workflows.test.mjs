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

async function projectTask(page, name) {
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name, exact: true }).click();
  await page.getByRole('main').getByRole('list', { name: 'Workspace directories', exact: true }).waitFor();
  await page.getByRole('main').getByRole('button', { name: 'New task', exact: true }).click();
  await page.getByRole('button', { name: 'Start task', exact: true }).waitFor();
}

test('Project task creation preserves restored inheritance and explicitly empty workspaces through the browser', async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const root = path.join(fixture.root, 'Project workspace');
  await mkdir(root);
  await writeFile(path.join(root, 'AGENTS.md'), 'Use the Project acceptance instructions.');
  const { project_id } = await command({ op: 'create_project', name: 'Acceptance Project',
    workspace: { roots: [root], primary_root: root } });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('button', { name: 'Acceptance Project', exact: true }).click();
  await page.getByRole('main').getByRole('list', { name: 'Workspace directories', exact: true }).waitFor();
  assert.equal(await page.getByRole('main').getByRole('list', { name: 'Workspace directories', exact: true }).innerText(), root);
  await page.getByText('Use the Project acceptance instructions.', { exact: true }).waitFor();
  await page.getByRole('main').getByRole('button', { name: 'New task', exact: true }).click();
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  await start.waitFor();
  assert.equal(await start.isDisabled(), true, 'An empty Task remains a passive draft');
  await page.getByRole('button', { name: 'Primary directory', exact: true }).click();
  let workspace = page.getByRole('dialog', { name: 'Primary directory', exact: true });
  await workspace.getByRole('button', { name: 'Remove', exact: true }).click();
  await workspace.getByRole('button', { name: 'Use inherited workspace', exact: true }).click();
  await workspace.getByRole('button', { name: 'Remove', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('Use inherited Project workspace');
  const inherited = await submitTask(page);
  const inheritedTask = (await command({ op: 'read', task_id: inherited })).task;
  assert.equal(inheritedTask.settings.project_id, project_id);
  assert.deepEqual(inheritedTask.settings.workspace, { roots: [root], primary_root: root });

  await projectTask(page, 'Acceptance Project');
  await page.getByRole('button', { name: 'Primary directory', exact: true }).click();
  workspace = page.getByRole('dialog', { name: 'Primary directory', exact: true });
  await workspace.getByRole('button', { name: 'Remove', exact: true }).click();
  await workspace.getByRole('button', { name: 'Use inherited workspace', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await workspace.waitFor({ state: 'hidden' });
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('Use explicitly no workspace roots');
  const empty = await submitTask(page);
  const emptyTask = (await command({ op: 'read', task_id: empty })).task;
  assert.equal(emptyTask.settings.project_id, project_id);
  assert.deepEqual(emptyTask.settings.workspace, { roots: [], primary_root: null },
    'Explicitly removing roots must not silently return to Project inheritance');
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
  await page.getByRole('navigation', { name: 'Tasks', exact: true })
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

  const message = page.getByRole('textbox', { name: 'Message', exact: true });
  await message.fill('Keep this unsent draft while narrowing.');
  await message.focus();
  await page.setViewportSize({ width: 450, height: 900 });
  const tasks = page.getByRole('button', { name: 'Open Task list', exact: true });
  await tasks.waitFor();
  assert.equal(await message.evaluate(node => node === document.activeElement), true,
    'A layout change must preserve the user activity instead of opening the Task tree');
  assert.equal(await message.inputValue(), 'Keep this unsent draft while narrowing.');
  assert.equal(await page.getByRole('banner').count(), 1);
  await tasks.focus();
  await tasks.press('Space');
  await page.getByRole('dialog', { name: 'Tasks', exact: true }).waitFor();
  assert.equal(await page.getByRole('banner').count(), 1);
  await page.keyboard.press('Escape');
  await page.getByRole('dialog', { name: 'Tasks', exact: true }).waitFor({ state: 'hidden' });
  assert.equal(await tasks.evaluate(node => node === document.activeElement), true,
    'Closing the Task tree restores its actual keyboard launcher');
});

test('live graph node templates remain operable and restore state only to their own document', { timeout: 60000 }, async t => {
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
    await page.getByRole('navigation', { name: 'Tasks', exact: true })
      .getByRole('button').filter({ hasText: task.title }).click();
    await page.getByRole('button', { name: 'Increment alpha', exact: true }).waitFor();
    return task.title;
  }
  const title = await viewer('Graph interaction acceptance');
  assert.match(await page.getByRole('list', { name: 'Graph node states', exact: true }).innerText(), /alpha[\s\S]*beta/);
  assert.match(await page.getByRole('list', { name: 'Connection rules', exact: true }).innerText(), /flow/);
  await page.getByRole('button', { name: 'Increment alpha', exact: true }).click();
  await page.getByText('Count: 1', { exact: true }).waitFor();
  await page.getByRole('textbox', { name: 'Shared note', exact: true }).fill('One persistent logical note');
  await page.getByRole('button', { name: 'Increment beta', exact: true }).click();
  await page.getByText('Count: 2', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), 'One persistent logical note');
  await page.getByRole('button', { name: '→', exact: true }).click();
  const panned = await page.getByRole('button', { name: 'Increment alpha', exact: true }).boundingBox();
  await page.getByRole('button', { name: 'Fit width', exact: true }).click();
  await page.waitForFunction(x => {
    const action = [...document.querySelectorAll('button')].find(node => node.textContent === 'Increment alpha');
    return action && action.getBoundingClientRect().x !== x;
  }, panned.x);
  for (let step = 0; step < 3; step++) await page.getByRole('button', { name: '−', exact: true }).click();
  const first = await page.getByRole('button', { name: 'Increment alpha', exact: true }).boundingBox();
  const second = await page.getByRole('button', { name: 'Increment beta', exact: true }).boundingBox();
  assert.ok(first.width >= 24 && first.height >= 24 && second.width >= 24 && second.height >= 24,
    'Zoom preserves operable node controls');
  assert.ok(first.x + first.width <= second.x || second.x + second.width <= first.x
    || first.y + first.height <= second.y || second.y + second.height <= first.y,
  'Different node controls must not overlap at low zoom');
  await page.reload();
  await page.getByRole('navigation', { name: 'Tasks', exact: true }).getByRole('button').filter({ hasText: title }).click();
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
  await page.getByRole('navigation', { name: 'Tasks', exact: true }).getByRole('button').filter({ hasText: title }).click();
  await page.getByText('Count: 0', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), '',
    'An invalid persisted field must reject the whole restoration before any other field is applied');
  await viewer('Independent graph document');
  await page.getByText('Count: 0', { exact: true }).waitFor();
  assert.equal(await page.getByRole('textbox', { name: 'Shared note', exact: true }).inputValue(), '',
    'The same definition in another Task must not acquire the first Task\'s stored state');
});

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { taskIdle } from '../../tests/fixtures/task-idle.mjs';
import { capture, group, setViewport, viewports, withBrowserFixture } from './capture.mjs';

const exact = (root, role, name) => root.getByRole(role, { name, exact: true });
const click = (root, name) => exact(root, 'button', name).click();
const paint = page => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));

async function captureScrolled(page, state, viewport, ready, variant) {
  const handle = await ready.evaluateHandle((node, direction) => {
    if (direction === 'right') {
      const viewport = node.querySelector('[data-page-region="board-stages"], [data-semantic-key="task-graph/viewport"]');
      return viewport && viewport.scrollWidth - viewport.clientWidth > 24 ? viewport : null;
    }
    const regions = [node, ...node.querySelectorAll(':scope > [data-surface-role="dialog-body"]')];
    return regions.find(region => region.scrollHeight - region.clientHeight > 24 &&
      ['auto', 'scroll'].includes(getComputedStyle(region).overflowY)) ?? null;
  }, variant);

  try {
    const scroller = handle.asElement();
    if (!scroller) return;
    const axis = variant === 'right' ? 'scrollLeft' : 'scrollTop';
    const extent = variant === 'right' ? 'scrollWidth' : 'scrollHeight';
    const [start, end] = await scroller.evaluate((node, { axis, extent }) => {
      const start = node[axis];
      node[axis] = node[extent];
      return [start, node[axis]];
    }, { axis, extent });
    try {
      if (end - start > 12) await capture(page, state, viewport, variant);
    } finally {
      await scroller.evaluate((node, { axis, start }) => { node[axis] = start; }, { axis, start });
    }
  } finally {
    await handle.dispose();
  }
}

async function publishSharedView(fixture, workId) {
  const { page, command, requests, finish, running } = fixture;
  const { task_id } = await command({
    op: 'create_work_task', work_id: workId, profile: 'interactive', message: 'Publish a shared view.',
  });
  async function waitForRequest(start, operation) {
    const deadline = Date.now() + 12_000;
    while (Date.now() < deadline) {
      const request = requests.slice(start).find(entry => !entry.closed);
      if (request) return request;
      await paint(page);
    }
    throw new Error(`The shared Work UI fixture timed out while waiting for ${operation}`);
  }
  const readCall = 'read-shared-view';
  const first = await waitForRequest(0, 'the initial model request');
  finish(first.index, { output: [{ type: 'function_call', call_id: readCall, name: 'read_work_ui', arguments: '{}' }] });
  const read = await waitForRequest(first.index + 1, 'the read_work_ui result');
  const reply = read.input.input.find(item => item.type === 'function_call_output' && item.call_id === readCall);
  if (!reply) throw new Error('The model request omitted the read_work_ui result');
  const { revision } = JSON.parse(reply.output).value.result;
  const patch = `*** Begin Patch
*** Add File: work-ui.dsl
+<ui id="work-panel">
+  <metric id="progress" label="Reviewed browser views" value={24} />
+</ui>
*** End Patch`;
  finish(read.index, {
    output: [{
      type: 'function_call',
      call_id: 'publish-shared-view',
      name: 'apply_work_ui_patch',
      arguments: JSON.stringify({ revision, patch }),
    }],
  });
  const done = await waitForRequest(read.index + 1, 'the apply_work_ui_patch result');
  finish(done.index, { text: 'Published a shared Work view.' });
  await taskIdle(running.service, task_id);
}

await withBrowserFixture(async fixture => {
  const { page, command, root, running } = fixture;
  const setupViewport = { id: 'setup', ...page.viewportSize(), textScale: 100 };
  const main = page.getByRole('main');
  const navigation = page.getByRole('navigation', { name: 'Global navigation' });
  const dialog = key => page.locator(`dialog[open][data-semantic-key="${key}"]`).last();
  const activeDialogs = page.locator('dialog[open]:not([inert])');

  async function dismissLayers() {
    // A nested picker can return to its editor before returning to the page.
    for (let remaining = 5; remaining > 0 && await activeDialogs.count(); remaining--) {
      await page.keyboard.press('Escape');
      await paint(page);
    }
    if (await activeDialogs.count()) throw new Error('Escape did not close the active dialogs');
  }

  const failures = [];
  async function captureState(state, ready, open) {
    for (const viewport of viewports) {
      try {
        await setViewport(page, viewport);
        if (open) await open();
        await ready.waitFor({ state: 'visible' });
        await page.mouse.move(0, 0);
        await capture(page, state, viewport);
        await captureScrolled(page, state, viewport, ready, 'bottom');
        if (state === 'board' || state === 'graphs') {
          await captureScrolled(page, state, viewport, ready, 'right');
        }
      } catch (cause) {
        console.error(`${state} at ${viewport.id}:`, cause);
        failures.push(cause);
      } finally {
        if (open) await dismissLayers();
      }
    }
    await setViewport(page, setupViewport);
  }
  const capturePage = state => captureState(state, main);
  const captureLayer = (state, key, open) => captureState(state, dialog(key), open);

  const longLabel = 'a_very_long_unbroken_folder_or_project_label_for_layout_checks';
  const directory = path.join(root, longLabel);
  await mkdir(directory);
  await writeFile(path.join(directory, 'AGENTS.md'), `Follow the project guidance. ${longLabel}`);
  const projectName = 'Selvedge browser workspace';
  const { project_id: project } = await command({
    op: 'create_project', name: projectName, workspace: { roots: [directory], primary_root: directory },
  });
  const { project_id: documentation } = await command({
    op: 'create_project', name: `Documentation ${longLabel}`, workspace: { roots: [] },
  });
  const { task_id: source } = await command({
    op: 'create', profile: 'demo', message: 'uniqueauditterm output', settings: { project_id: project },
  });
  const { task_id: target } = await command({
    op: 'create', profile: 'demo', message: 'Review browser conventions', settings: { project_id: documentation },
  });
  await Promise.all([taskIdle(running.service, source), taskIdle(running.service, target)]);

  if (group === 'projects') {
    await click(navigation, '项目');
    const entry = exact(main, 'region', projectName);
    await entry.waitFor();
    await capturePage('projects');
    const actions = () => click(entry, 'Project actions');
    const edit = () => click(main, 'Edit project');
    await captureLayer('project-new', 'activity', () => click(main, 'New project'));
    await captureLayer('project-list-menu', 'object-actions', actions);
    await actions();
    await click(dialog('object-actions'), 'Project details');
    await exact(main, 'heading', projectName).waitFor();
    await capturePage('project');
    await captureLayer('project-edit', 'activity', edit);
    await captureLayer('project-directory-browser', 'directory-browser', async () => {
      await edit();
      await dialog('activity').getByRole('button', { name: /^Browse/ }).first().click();
    });
    await captureLayer('project-source', 'property-source', async () => {
      await edit();
      await dialog('activity').getByRole('button', { name: /^Configuration source/ }).first().click();
    });
    await captureLayer('project-details-menu', 'object-actions', () => click(main, 'More actions'));
    const disposable = 'Disposable project for confirmation';
    await command({ op: 'create_project', name: disposable, workspace: { roots: [] } });
    await click(navigation, '项目');
    await captureLayer('project-delete', 'confirmation', async () => {
      await click(exact(main, 'region', disposable), 'Project actions');
      await click(dialog('object-actions'), 'Delete project');
    });
    await click(navigation, '搜索对话');
    const search = main.getByRole('searchbox');
    await search.waitFor();
    await capturePage('history-empty');
    await search.fill('uniqueauditterm');
    await click(main, '搜索');
    await main.getByText('命中消息', { exact: true }).first().waitFor();
    await capturePage('history-results');
  }

  if (group === 'board') {
    const title = 'Review browser layout with a long descriptive title';
    const { card_id } = await command({
      op: 'create_card', title, description: longLabel, status: 'backlog', labels: ['readability', 'interaction'],
    });
    const linked = await command({ op: 'create_card', title: 'Verify the linked browser conversation' });
    const archived = await command({ op: 'create_card', title: 'Archived browser task with historical context' });
    const linkedCard = await command({ op: 'read_card', card_id: linked.card_id });
    const archivedCard = await command({ op: 'read_card', card_id: archived.card_id });
    await command({ op: 'link_card', card_id: linked.card_id, revision: linkedCard.revision, task_id: target });
    await command({ op: 'archive_card', card_id: archived.card_id, revision: archivedCard.revision });
    await click(navigation, '任务看板');
    const card = main.locator(`article[data-card-id="${card_id}"]`);
    await card.waitFor();
    await capturePage('board');
    const more = () => click(card, 'More actions');
    await captureLayer('board-new-card', 'object-editor', () => click(main.locator('[data-board-group="primary-action"]'), '新建任务'));
    await captureLayer('board-filters', 'board-filters', () => click(main, '筛选任务'));
    await captureLayer('board-settings', 'board-settings', () => click(main, '看板设置'));
    await captureLayer('board-archive', 'archived-cards', () => click(main, '归档任务'));
    await captureLayer('board-card-details', 'card-details', () => click(card, `打开 ${title}`));
    await captureLayer('board-card-menu', 'object-actions', more);
    const cardActions = [
      ['board-card-edit', 'Edit card', 'object-editor'],
      ['board-card-move', 'Move card', 'card-decision'],
      ['board-card-link', 'Link task', 'card-decision'],
      ['board-card-delete', 'Delete card', 'confirmation'],
    ];
    for (const [state, label, key] of cardActions) {
      await captureLayer(state, key, async () => {
        await more();
        await click(dialog('object-actions'), label);
      });
    }
  }

  if (group === 'graphs') {
    const name = 'Share accessibility findings from product design to documentation';
    await command({
      op: 'create_task_graph',
      name,
      nodes: [{ key: 'source', task_id: source }, { key: 'target', task_id: target }],
      rules: [{
        key: 'delivery-rule', source: 'source',
        actions: [{ target: 'target', message: { kind: 'literal', value: longLabel } }],
      }],
    });
    await command({ op: 'send', task_id: source, message: 'Route an actual delivery for the screenshot.' });
    await taskIdle(running.service, source);
    await taskIdle(running.service, target);
    await click(page.getByRole('navigation', { name: 'Task tree' }), 'Task graphs');
    const graph = exact(main, 'region', name);
    await graph.waitFor();
    await capturePage('graphs');
    await captureLayer('graph-new', 'object-editor', () => click(main, 'New task graph'));
    await captureLayer('graph-edit', 'object-editor', () => click(graph, 'Edit task graph'));
    const more = () => click(graph, 'More actions');
    await captureLayer('graph-menu', 'object-actions', more);
    await captureLayer('graph-delete', 'confirmation', async () => {
      await more();
      await click(dialog('object-actions'), 'Delete task graph');
    });
  }

  if (group === 'shared') {
    const name = 'Workspace audit Work';
    const { work_id } = await command({ op: 'create_work', name });
    await page.getByRole('button', { name: /^Work overview:/ }).click();
    await exact(exact(page, 'dialog', 'Works'), 'radio', name).click();
    await click(page, '共享 UI');
    await capturePage('shared-empty');
    await publishSharedView(fixture, work_id);
    await main.getByText('Reviewed browser views', { exact: true }).waitFor();
    await capturePage('shared-populated');
    await click(main, '展开源码');
    await capturePage('shared-source');
  }
  if (failures.length) throw new AggregateError(failures, `Incomplete ${group} screenshots`);
});

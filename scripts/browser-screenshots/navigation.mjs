import { taskIdle } from '../../tests/fixtures/task-idle.mjs';
import { capture, captureExtra, notApplicable, setViewport, viewports, withBrowserFixture } from './capture.mjs';

const projectName = 'Selvedge browser navigation';
const workName = 'Improve navigation at different viewport sizes';
const lastWork = 'Triage next changes';
const crossingDraft = 'Preserve this draft across the sidebar boundary';

const button = (root, name) => root.getByRole('button', { name, exact: true });
const dialog = (root, name) => root.getByRole('dialog', { name, exact: true });
const taskTree = root => root.getByRole('navigation', { name: 'Task tree', exact: true });
const workPicker = root => root.getByRole('button', { name: /^对话范围 · / });
const published = page => page.locator('#surface[data-display-pending="false"]').waitFor();

async function withPage(fixture, viewport, run) {
  const { width, height } = viewport;
  const page = await fixture.browser.newPage({ viewport: { width, height } });
  const errors = [];
  page.on('pageerror', error => errors.push(error));
  page.setDefaultTimeout(10000);
  try {
    await page.goto(fixture.running.url);
    await page.getByRole('main').waitFor();
    await setViewport(page, viewport);
    await published(page);
    const result = await run(page);
    if (errors.length) throw new AggregateError(errors, 'Navigation page raised browser errors');
    return result;
  } finally {
    await page.close();
  }
}

async function forViewports(fixture, run) {
  const failures = [];
  for (let index = 0; index < viewports.length; index += 3) {
    const batch = viewports.slice(index, index + 3);
    const results = await Promise.allSettled(batch.map(viewport =>
      withPage(fixture, viewport, page => run(page, viewport))));
    for (const [offset, result] of results.entries()) {
      if (result.status === 'fulfilled') continue;
      console.error(`${batch[offset].id}:`, result.reason);
      failures.push(result.reason);
    }
  }
  if (failures.length) throw new AggregateError(failures, 'Incomplete navigation screenshots');
}

async function isCompact(page) {
  const compactMenu = button(page, 'Global navigation');
  const sidebar = taskTree(page);
  await compactMenu.or(sidebar).waitFor();
  return compactMenu.isVisible();
}

async function openTaskTree(page) {
  const launcher = button(page, 'Open Task list');
  if (await launcher.isVisible()) await launcher.click();
  await taskTree(page).waitFor();
}

async function closeDialog(page, layer) {
  await page.keyboard.press('Escape');
  await layer.waitFor({ state: 'hidden' });
  await published(page);
}

async function placePointer(page) {
  await published(page);
  await page.mouse.move(1, page.viewportSize().height - 1);
}

async function captureState(page, state, viewport, variant) {
  await placePointer(page);
  await capture(page, state, viewport, variant);
}

async function captureBreakpointState(page, name) {
  await placePointer(page);
  await captureExtra(page, name);
}

async function seedNavigation({ command, running }) {
  const { project_id: project } = await command({ op: 'create_project', name: projectName, workspace: { roots: [] } });
  const { project_id: docs } = await command({
    op: 'create_project', name: 'Documentation and release verification', workspace: { roots: [] },
  });
  const { work_id: work } = await command({ op: 'create_work', name: workName });
  for (const name of [
    'Documentation', 'Release preparation', 'Run acceptance checks on long captions', 'Review the workspace interface', lastWork,
  ]) {
    await command({ op: 'create_work', name });
  }

  async function createTask(message, projectId = project) {
    const { task_id: id } = await command({
      op: 'create_work_task', work_id: work, profile: 'demo', message, settings: { project_id: projectId },
    });
    await taskIdle(running.service, id);
    return id;
  }

  const [parent] = await Promise.all([
    createTask('Improve conversation reading and navigation'),
    createTask('Verify the documentation navigation labels', docs),
    createTask('Check the sidebar and inspect project settings'),
    createTask('Review the last viewport and accessibility evidence'),
  ]);
  const { children: [branch, sibling] } = await command({
    op: 'fork', task_id: parent, child_count: 2,
    messages: ['Check whether tool output stays anchored', 'Review the second conversation branch'],
  });
  await Promise.all([taskIdle(running.service, branch), taskIdle(running.service, sibling)]);
  const { children: [nested] } = await command({
    op: 'fork', task_id: branch, child_count: 1, messages: ['Check the reading location after expanding again'],
  });
  const { task_id: independent } = await command({
    op: 'create', profile: 'demo', message: 'Review an independent task with no project',
  });
  await Promise.all([taskIdle(running.service, nested), taskIdle(running.service, independent)]);
  return { parent, nested };
}

async function captureCompactNavigation(page, viewport) {
  const global = dialog(page, 'Global navigation');
  const drawer = dialog(page, 'Task tree');
  const works = dialog(page, '对话范围');
  await captureState(page, 'compact-header', viewport);
  await button(page, 'Global navigation').click();
  await global.waitFor();
  await captureState(page, 'global', viewport);
  await closeDialog(page, global);

  await openTaskTree(page);
  await captureState(page, 'drawer-all', viewport);
  await button(drawer, 'Global navigation').click();
  await global.waitFor();
  await captureState(page, 'drawer-global', viewport);
  await closeDialog(page, global);
  await workPicker(drawer).click();
  await works.waitFor();
  await captureState(page, 'drawer-works', viewport);
  await closeDialog(page, works);
  await closeDialog(page, drawer);
}

async function captureNavigation(page, viewport, { parent, nested }) {
  const compact = await isCompact(page);
  const works = dialog(page, '对话范围');
  if (compact) {
    await captureCompactNavigation(page, viewport);
    for (const state of ['desktop-sidebar', 'desktop-collapsed']) {
      await notApplicable(state, viewport, 'This viewport uses the compact header and Task tree drawer.');
    }
  } else {
    await captureState(page, 'desktop-sidebar', viewport);
    for (const state of ['compact-header', 'global', 'drawer-all', 'drawer-global', 'drawer-works']) {
      await notApplicable(state, viewport, 'This viewport shows the Task tree and global destinations in the sidebar.');
    }
  }

  await workPicker(page).click();
  await works.waitFor();
  await captureState(page, 'works-many', viewport);
  const workOptions = works.locator('[data-surface-role="dialog-body"]');
  if (await workOptions.evaluate(body => body.scrollHeight > body.clientHeight)) {
    await works.getByRole('radio', { name: lastWork, exact: true }).scrollIntoViewIfNeeded();
    await captureState(page, 'works-many', viewport, 'bottom');
  }
  await works.getByRole('radio', { name: workName, exact: true }).click();
  await button(page, `对话范围 · ${workName}`).waitFor();
  await openTaskTree(page);
  await captureState(page, 'work-tree', viewport);

  const project = taskTree(page).getByRole('region', { name: projectName, exact: true });
  const projectActions = button(project, '项目操作');
  await project.locator('[data-navigation-owner]').hover();
  await projectActions.focus();
  await captureState(page, 'project-actions-revealed', viewport);
  await projectActions.click();
  const actions = dialog(page, 'Actions');
  await actions.waitFor();
  await captureState(page, 'project-actions', viewport);
  await closeDialog(page, actions);

  const branchRow = project.locator(`[data-task-id="${parent}"] > [data-task-tree-row]`);
  await branchRow.locator('button[aria-expanded="true"]').click();
  await captureState(page, 'branches-collapsed', viewport);
  await branchRow.locator('button[aria-expanded="false"]').click();
  await button(project, '收起项目').click();
  await captureState(page, 'project-collapsed', viewport);
  await button(project, '展开项目').click();

  await project.locator(`[data-task-id="${nested}"] > [data-task-tree-row] [data-semantic-key="open"]`).click();
  await openTaskTree(page);
  await published(page);
  await page.waitForFunction(taskId => {
    const port = document.querySelector('[data-workspace-navigation="collection"]');
    const selected = port?.querySelector(`[data-task-tree-entry][aria-current="true"][data-task-id="${taskId}"] > [data-task-tree-row]`);
    if (!selected) return false;
    const row = selected.getBoundingClientRect();
    const range = port.getBoundingClientRect();
    return row.top >= range.top - 1 && row.bottom <= range.bottom + 1;
  }, nested);
  await captureState(page, 'task-selected', viewport);

  await button(taskTree(page), 'Rename Work').click();
  const editor = dialog(page, 'Rename Work');
  await editor.waitFor();
  await captureState(page, 'rename-work', viewport);
  await editor.getByRole('textbox', { name: 'Name', exact: true }).fill('');
  await editor.locator('[data-semantic-key="property-repair"]').waitFor();
  await captureState(page, 'rename-work-empty', viewport);
  await closeDialog(page, editor);

  if (!compact) {
    await button(page, 'Collapse Task sidebar').click();
    await button(page, 'Expand Task sidebar').waitFor();
    await captureState(page, 'desktop-collapsed', viewport);
  }
}

async function captureWorkCreation(page, viewport) {
  const works = dialog(page, '对话范围');
  await workPicker(page).click();
  await button(works, '新建工作组').click();
  await works.waitFor({ state: 'hidden' });
  await page.getByRole('button', { name: /^对话范围 · Work #/ }).waitFor();
  await page.getByRole('combobox', { name: 'Task', exact: true }).waitFor();
  await captureState(page, 'new-work-created', viewport);

  await openTaskTree(page);
  await button(taskTree(page), 'Rename Work').click();
  const editor = dialog(page, 'Rename Work');
  const renamed = `Navigation audit ${viewport.id}`;
  await editor.getByRole('textbox', { name: 'Name', exact: true }).fill(renamed);
  await button(editor, 'Save').click();
  await editor.waitFor({ state: 'hidden' });
  await button(page, `对话范围 · ${renamed}`).waitFor();
  await captureState(page, 'work-renamed', viewport);
}

async function captureSidebarBreakpoint(fixture) {
  const size = width => ({ width, height: 650, textScale: 100 });
  const probe = width => withPage(fixture, size(width), isCompact);
  let lower = 629;
  let upper = 900;
  const [startsCompact, endsCompact] = await Promise.all([probe(lower), probe(upper)]);
  if (!startsCompact || endsCompact) throw new Error('629–900 px no longer brackets the Task sidebar breakpoint');
  while (upper - lower > 1) {
    const middle = Math.floor((lower + upper) / 2);
    if (await probe(middle)) lower = middle;
    else upper = middle;
  }

  await withPage(fixture, size(lower), async page => {
    await captureBreakpointState(page, `edge-${lower}-base`);
    await openTaskTree(page);
    await captureBreakpointState(page, `edge-${lower}-drawer`);
  });
  await withPage(fixture, size(upper), async page => {
    await captureBreakpointState(page, `edge-${upper}-base`);
    await button(page, 'Collapse Task sidebar').click();
    await button(page, 'Expand Task sidebar').waitFor();
    await captureBreakpointState(page, `edge-${upper}-collapsed`);

    await button(page, 'Expand Task sidebar').click();
    await taskTree(page).waitFor();
    const draft = page.getByRole('combobox', { name: 'Task', exact: true });
    await draft.fill(crossingDraft);
    await button(page, 'Collapse Task sidebar').click();
    await button(page, 'Expand Task sidebar').waitFor();
    await setViewport(page, size(lower));
    const launcher = button(page, 'Open Task list');
    await launcher.click();
    const drawer = dialog(page, 'Task tree');
    await drawer.waitFor();
    await captureBreakpointState(page, `edge-${lower}-crossing-drawer`);
    await closeDialog(page, drawer);
    await launcher.and(page.locator(':focus')).waitFor();

    await setViewport(page, size(upper));
    await button(page, 'Expand Task sidebar').click();
    await taskTree(page).waitFor();
    if (await draft.inputValue() !== crossingDraft) throw new Error('Crossing the Task sidebar breakpoint replaced the draft');
    await captureBreakpointState(page, `edge-${upper}-crossing-restored`);
  });
}

await withBrowserFixture(async fixture => {
  await forViewports(fixture, async (page, viewport) => {
    await workPicker(page).click();
    await dialog(page, '对话范围').waitFor();
    await captureState(page, 'works-single', viewport);
  });
  const tasks = await seedNavigation(fixture);
  await forViewports(fixture, (page, viewport) => captureNavigation(page, viewport, tasks));
  await forViewports(fixture, captureWorkCreation);
  await captureSidebarBreakpoint(fixture);
});

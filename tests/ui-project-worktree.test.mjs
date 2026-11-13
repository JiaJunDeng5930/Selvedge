import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { browserFixture } from './fixtures/browser.mjs';

const execute = promisify(execFile);

test('Project worktree defaults require a committed Git primary only while enabled', async t => {
  const { page, command, root } = await browserFixture(t);
  const ordinary = path.join(root, 'Ordinary directory');
  const repository = path.join(root, 'Git workspace');
  await mkdir(ordinary);
  await mkdir(repository);
  const git = (...args) => execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Project fixture', '-c', 'user.email=project@example.test', '-C', repository, ...args]);
  await git('init', '--initial-branch=main');
  await git('commit', '--allow-empty', '-m', 'Initial commit');

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  const create = page.getByRole('main').getByRole('button', { name: '新建项目', exact: true });
  const project = page.getByRole('dialog', { name: '新建项目', exact: true });
  const submit = project.getByRole('button', { name: '创建项目', exact: true });
  const worktreeName = '新对话默认创建 Git 工作树';
  const worktree = project.getByRole('checkbox', { name: worktreeName, exact: true });
  const reason = message => project.getByRole('status').filter({ hasText: message });
  const name = project.getByRole('textbox', { name: '项目名称', exact: true });
  const add = project.getByRole('button', { name: '添加目录', exact: true });
  const browse = project.getByRole('button', { name: '浏览…', exact: true });
  const pathEntry = project.locator('[data-semantic-key="project-directory-input"]');
  const directory = pathEntry.getByRole('textbox');
  const missingMessage = '请先添加并选择主目录。';
  const notGitMessage = '主目录需要位于包含至少一次提交的 Git 仓库中。';
  const missing = reason(missingMessage);

  async function assertBlockingReason(message) {
    const status = reason(message);
    await status.waitFor();
    const copies = project.getByText(message, { exact: true }).and(project.locator(':not(.visually-hidden)'));
    assert.equal(await copies.count(), 1, 'The form shows one copy of the Git check reason');
    assert.ok(await status.evaluate(node => node.closest('footer') !== null));
    assert.equal(await submit.isDisabled(), true);
    assert.equal(await submit.evaluate(button => (button.getAttribute('aria-describedby') ?? '').split(/\s+/)
      .map(id => document.getElementById(id)?.textContent ?? '').join(' ').trim()), message);
  }
  async function assertDirectoryRow(minimumWidth) {
    const [field, control] = await Promise.all([directory.boundingBox(), browse.boundingBox()]);
    assert.ok(field && control && field.width >= minimumWidth);
    assert.ok(field.x + field.width <= control.x + 1 && field.y < control.y + control.height &&
      control.y < field.y + field.height, 'The directory field and Browse share the same row');
  }

  await create.click();
  await name.fill('默认使用工作树');
  await pathEntry.getByRole('textbox', { name: '目录路径', exact: true }).waitFor();
  await pathEntry.getByRole('button', { name: '浏览…', exact: true }).waitFor();
  assert.equal(await add.isVisible(), false, 'An empty path only offers browsing');
  const [box, caption] = await Promise.all([
    worktree.boundingBox(), project.getByText(worktreeName, { exact: true }).boundingBox(),
  ]);
  assert.ok(box && caption && box.x + box.width <= caption.x &&
    Math.abs(box.y + box.height / 2 - caption.y - caption.height / 2) <= 1,
  'The checkbox sits before and vertically centered with its label');
  await worktree.press('Space');
  await worktree.and(page.locator(':focus')).waitFor();
  assert.equal(await worktree.isChecked(), true);
  await project.getByRole('heading', { name: '工作目录', exact: true }).waitFor();
  await assertBlockingReason(missingMessage);
  assert.ok((await project.boundingBox()).width >= 420, 'The desktop Project form gives its directory row a reading width');
  await assertDirectoryRow(200);

  const narrow = { width: 390, height: 310 };
  const bodySelector = '[data-surface-role="dialog-body"]';
  const dialogId = await project.getAttribute('id');
  await page.setViewportSize(narrow);
  // The viewport changes before the measured dialog constraints are published.
  await page.waitForFunction(({ dialogId, width, height, bodySelector }) => {
    const dialog = document.getElementById(dialogId);
    const body = dialog?.querySelector(bodySelector);
    const bounds = dialog?.getBoundingClientRect();
    return window.innerWidth === width && window.innerHeight === height && bounds
      && bounds.left >= 0 && bounds.right <= width && bounds.top >= 0 && bounds.bottom <= height
      && body && body.scrollHeight > body.clientHeight;
  }, { dialogId, ...narrow, bodySelector });
  await assertBlockingReason(missingMessage);
  await assertDirectoryRow(120);
  const scroll = await missing.evaluate(async (reason, bodySelector) => {
    const body = reason.closest('dialog').querySelector(bodySelector);
    const before = reason.getBoundingClientRect().toJSON();
    const start = body.scrollTop;
    body.scrollTop = start > 0 ? 0 : body.scrollHeight;
    await new Promise(requestAnimationFrame);
    return { before, after: reason.getBoundingClientRect().toJSON(), start, end: body.scrollTop };
  }, bodySelector);
  assert.notEqual(scroll.end, scroll.start, 'The narrow form body scrolled');
  assert.ok(scroll.before.width > 0 && scroll.before.height > 0
    && scroll.before.left >= 0 && scroll.before.right <= narrow.width
    && scroll.before.top >= 0 && scroll.before.bottom <= narrow.height);
  assert.deepEqual(scroll.after, scroll.before, 'The visible footer reason stays in place while the form scrolls');
  await page.setViewportSize({ width: 320, height: 640 });
  await page.waitForFunction(({ dialogId, width }) => {
    const bounds = document.getElementById(dialogId)?.getBoundingClientRect();
    return innerWidth === width && bounds && bounds.left >= 0 && bounds.right <= width;
  }, { dialogId, width: 320 });
  await assertDirectoryRow(100);
  const narrowPath = await pathEntry.boundingBox();
  const narrowBrowse = await browse.boundingBox();
  assert.ok(narrowPath && narrowBrowse && narrowPath.x >= 0 && narrowBrowse.x + narrowBrowse.width <= 320,
    'The grouped directory field and Browse fit a 320px viewport');
  await directory.fill(repository);
  const clear = pathEntry.getByRole('button', { name: '清空', exact: true });
  await clear.waitFor();
  const [addBounds, clearBounds, browseBounds] = await Promise.all([
    add.boundingBox(), clear.boundingBox(), browse.boundingBox(),
  ]);
  assert.ok(addBounds && clearBounds && browseBounds && Math.abs(addBounds.y - browseBounds.y) < 1 &&
    Math.abs(clearBounds.y - addBounds.y) < 1 &&
    clearBounds.x + clearBounds.width <= 320, 'Typing offers Add and Clear on the same line as Browse');
  await clear.click();
  await add.waitFor({ state: 'hidden' });
  await page.setViewportSize({ width: 1280, height: 900 });

  await browse.click();
  const chooser = page.getByRole('dialog', { name: '选择 Selvedge 主机上的目录', exact: true });
  await chooser.waitFor();
  await page.waitForFunction(id => {
    const covered = document.getElementById(id);
    return covered?.open && getComputedStyle(covered).visibility === 'hidden';
  }, dialogId);
  const folder = chooser.getByRole('button', { name: 'Ordinary directory', exact: true });
  const choose = chooser.getByRole('button', { name: '使用此目录', exact: true });
  await folder.click();
  await folder.waitFor({ state: 'hidden' });
  await chooser.getByRole('status').filter({ hasText: '主目录须位于包含提交的 Git 仓库中。' }).waitFor();
  assert.equal(await choose.isDisabled(), true);
  await chooser.getByRole('button', { name: '取消', exact: true }).click();
  await chooser.waitFor({ state: 'hidden' });
  await browse.and(page.locator(':focus')).waitFor();
  assert.equal(await name.inputValue(), '默认使用工作树');
  assert.equal(await project.getByText(ordinary, { exact: true }).count(), 0);
  await directory.fill(ordinary);
  await add.click();
  await assertBlockingReason(notGitMessage);
  await directory.fill(repository);
  await add.click();
  await assertBlockingReason(notGitMessage);
  await pathEntry.getByRole('textbox', { name: '添加另一个目录', exact: true }).waitFor();
  const repositoryRoot = project.getByRole('region', { name: repository, exact: true });
  const heading = repositoryRoot.locator('[data-semantic-key="workspace-member-heading"]');
  const basename = heading.getByText('Git workspace', { exact: true });
  const primaryLabel = heading.getByText('主目录', { exact: true });
  await basename.waitFor();
  const fullPath = repositoryRoot.getByText(repository, { exact: true });
  await fullPath.waitFor();
  await repositoryRoot.getByRole('button', { name: '设为主目录', exact: true }).click();
  await primaryLabel.waitFor();
  await page.setViewportSize({ width: 320, height: 640 });
  await basename.scrollIntoViewIfNeeded();
  const [nameBox, primaryBox, fullPathBox, selectable] = await Promise.all([
    basename.boundingBox(), primaryLabel.boundingBox(), fullPath.boundingBox(),
    fullPath.evaluate(node => getComputedStyle(node).userSelect !== 'none'),
  ]);
  const center = box => box.y + box.height / 2;
  assert.ok(nameBox && primaryBox && fullPathBox &&
    Math.abs(center(nameBox) - center(primaryBox)) <= 1 &&
    nameBox.x + nameBox.width <= primaryBox.x + 1,
    'The directory basename and primary role share a line in a narrow project editor');
  assert.ok(fullPathBox.y >= Math.max(nameBox.y + nameBox.height, primaryBox.y + primaryBox.height) - 1 &&
    selectable,
    'The complete path stays readable and selectable below the short name');
  const [repositoryActionsBox, repositoryBox, appendBox] = await Promise.all([
    repositoryRoot.locator('[data-semantic-key="workspace-member-actions"]').boundingBox(),
    repositoryRoot.boundingBox(),
    pathEntry.boundingBox(),
  ]);
  const ordinaryRoot = project.getByRole('region', { name: ordinary, exact: true });
  const ordinaryActionsBox = await ordinaryRoot.locator('[data-semantic-key="workspace-member-actions"]').boundingBox();
  const ordinaryHeadingBox = await ordinaryRoot.locator('[data-semantic-key="workspace-member-heading"]').boundingBox();
  assert.ok(repositoryActionsBox && nameBox && Math.abs(repositoryActionsBox.y - nameBox.y) <= 1,
    'The primary directory action aligns with its short name');
  assert.ok(repositoryBox && fullPathBox.width >= repositoryBox.width - 20,
    'The full path uses the available row width at a narrow viewport');
  assert.ok(ordinaryActionsBox && ordinaryHeadingBox && Math.abs(ordinaryActionsBox.y - ordinaryHeadingBox.y) <= 1,
    'The secondary directory actions align with their short name');
  assert.ok(repositoryBox && appendBox && appendBox.y >= repositoryBox.y + repositoryBox.height + 6,
    'The add-directory area is separated from the selected directory list');
  assert.equal(await ordinaryRoot.getByRole('button', { name: '设为主目录', exact: true }).count(), 1);
  assert.equal(await ordinaryRoot.getByRole('button', { name: '移除目录', exact: true }).count(), 1);
  await page.setViewportSize({ width: 1280, height: 900 });
  const [desktopRepositoryBox, desktopPathBox] = await Promise.all([
    repositoryRoot.boundingBox(), fullPath.boundingBox(),
  ]);
  assert.ok(desktopRepositoryBox && desktopPathBox && desktopPathBox.width >= desktopRepositoryBox.width - 20,
    'The full path uses the available row width at a desktop viewport');
  await project.getByRole('region', { name: ordinary, exact: true })
    .getByRole('button', { name: '移除目录', exact: true }).click();

  await browse.click();
  await chooser.getByRole('button', { name: '上一级', exact: true }).click();
  await folder.click();
  await folder.waitFor({ state: 'hidden' });
  await chooser.getByRole('status').filter({ hasText: '将作为辅助目录添加。此目录不能用作 Git 工作树的主目录。' }).waitFor();
  await choose.click();
  await chooser.waitFor({ state: 'hidden' });
  await submit.click();
  await project.waitFor({ state: 'hidden' });

  await create.click();
  await name.fill('不配置工作目录');
  await worktree.check();
  await missing.waitFor();
  await worktree.uncheck();
  await project.getByRole('heading', { name: '工作目录（可选）', exact: true }).waitFor();
  await submit.click();
  await project.waitFor({ state: 'hidden' });

  const projects = await command({ op: 'list_projects' });
  const enabled = projects.find(project => project.name === '默认使用工作树');
  assert.equal(enabled.create_worktree, true);
  assert.deepEqual(enabled.workspace, { roots: [repository, ordinary], primary_root: repository });
  const disabled = projects.find(project => project.name === '不配置工作目录');
  assert.equal(disabled.create_worktree, false);
  assert.deepEqual(disabled.workspace, { roots: [], primary_root: null });
});

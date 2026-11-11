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
  const worktree = project.getByRole('checkbox', { name: '新对话默认创建 Git 工作树', exact: true });
  const reason = message => project.getByRole('status').filter({ hasText: message });
  const name = project.getByRole('textbox', { name: '项目名称', exact: true });
  const directory = project.getByRole('textbox', { name: '目录路径', exact: true });
  const add = project.getByRole('button', { name: '添加目录', exact: true });
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

  await create.click();
  await name.fill('默认使用工作树');
  await worktree.check();
  await project.getByRole('heading', { name: '工作目录', exact: true }).waitFor();
  await assertBlockingReason(missingMessage);

  const narrow = { width: 390, height: 370 };
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
  await page.setViewportSize({ width: 1280, height: 900 });

  const browse = project.getByRole('button', { name: '浏览…', exact: true });
  await browse.click();
  const chooser = page.getByRole('dialog', { name: '选择 Selvedge 主机上的目录', exact: true });
  const folder = chooser.getByRole('button', { name: 'Ordinary directory', exact: true });
  const choose = chooser.getByRole('button', { name: '使用此目录', exact: true });
  await folder.click();
  await folder.waitFor({ state: 'hidden' });
  await chooser.getByRole('status').filter({ hasText: '主目录须位于包含提交的 Git 仓库中。' }).waitFor();
  assert.equal(await choose.isDisabled(), true);
  await chooser.getByRole('button', { name: '取消', exact: true }).click();
  await chooser.waitFor({ state: 'hidden' });
  assert.equal(await project.getByText(ordinary, { exact: true }).count(), 0);
  await directory.fill(ordinary);
  await add.click();
  await assertBlockingReason(notGitMessage);
  await directory.fill(repository);
  await add.click();
  await assertBlockingReason(notGitMessage);
  await project.getByRole('region', { name: repository, exact: true })
    .getByRole('button', { name: '设为主目录', exact: true }).click();
  await project.getByRole('region', { name: ordinary, exact: true })
    .getByRole('button', { name: '移除目录', exact: true }).click();

  await browse.click();
  await chooser.getByRole('button', { name: '上一级目录', exact: true }).click();
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

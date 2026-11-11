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
  const reason = message => project.getByRole('alert').filter({ hasText: message });
  const name = project.getByRole('textbox', { name: '项目名称', exact: true });
  const directory = project.getByRole('textbox', { name: '目录路径', exact: true });
  const add = project.getByRole('button', { name: '添加目录', exact: true });
  const missing = reason('请先添加并选择主目录。');
  const notGit = reason('主目录需要位于包含至少一次提交的 Git 仓库中。');

  await create.click();
  await name.fill('默认使用工作树');
  await worktree.check();
  await project.getByRole('heading', { name: '工作目录', exact: true }).waitFor();
  await missing.waitFor();
  assert.equal(await submit.isDisabled(), true);

  await project.getByRole('button', { name: '浏览…', exact: true }).click();
  const chooser = page.getByRole('dialog', { name: '选择 Selvedge 主机上的目录', exact: true });
  const folder = chooser.getByRole('button', { name: 'Ordinary directory', exact: true });
  await folder.click();
  await folder.waitFor({ state: 'hidden' });
  await chooser.getByRole('button', { name: '使用此目录', exact: true }).click();
  await chooser.waitFor({ state: 'hidden' });
  await notGit.waitFor();
  assert.equal(await submit.isDisabled(), true);
  await directory.fill(repository);
  await add.click();
  await notGit.waitFor();
  assert.equal(await submit.isDisabled(), true);
  await project.getByRole('region', { name: repository, exact: true })
    .getByRole('button', { name: '设为主目录', exact: true }).click();
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
  assert.deepEqual(enabled.workspace, { roots: [ordinary, repository], primary_root: repository });
  const disabled = projects.find(project => project.name === '不配置工作目录');
  assert.equal(disabled.create_worktree, false);
  assert.deepEqual(disabled.workspace, { roots: [], primary_root: null });
});

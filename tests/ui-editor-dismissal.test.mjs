import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { browserFixture } from './fixtures/browser.mjs';

test('a canceled card capture gives the next stage a fresh draft, while successful continuous capture retains its settings', async t => {
  const { page, command, requests } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const title = editor.getByRole('textbox', { name: '标题', exact: true });
  const description = editor.getByRole('textbox', { name: '描述', exact: true });
  const more = editor.getByText('更多卡片选项', { exact: true });
  const stage = editor.getByRole('combobox', { name: '状态', exact: true });
  const priority = editor.getByRole('combobox', { name: '优先级', exact: true });
  const assistance = editor.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  const draftingModel = editor.getByRole('combobox', { name: '整理用的模型', exact: true });
  const keepOpen = editor.getByRole('checkbox', { name: '创建后继续添加', exact: true });
  const cancel = editor.getByRole('button', { name: '取消', exact: true });
  const submit = editor.getByRole('button', { name: '创建卡片', exact: true });
  await page.getByRole('button', { name: '新建卡片', exact: true }).click();
  await title.fill('This draft will be discarded');
  await description.fill('Do not inherit any of these choices.');
  await more.click();
  await priority.selectOption('high');
  await assistance.check();
  await draftingModel.selectOption('interactive');
  await keepOpen.check();
  await editor.getByText('保存后先生成卡片内容，暂不启动对话。', { exact: true }).waitFor();
  await cancel.click();
  await editor.waitFor({ state: 'hidden' });

  const todo = page.getByRole('button', { name: '新建卡片 · 待办', exact: true });
  await todo.click();
  assert.equal(await title.inputValue(), '');
  assert.equal(await description.inputValue(), '');
  assert.equal(await assistance.isVisible(), false);
  const savedTitle = 'Saved in the requested stage';
  await title.fill(savedTitle);
  assert.equal(await editor.getByText(/先生成卡片内容/).count(), 0);
  await more.click();
  assert.equal(await stage.inputValue(), 'todo');
  assert.equal(await priority.inputValue(), 'none');
  assert.equal(await assistance.isChecked(), false);
  assert.equal(await keepOpen.isChecked(), false);
  await assistance.check();
  assert.equal(await draftingModel.inputValue(), '');
  await assistance.uncheck();
  await priority.selectOption('low');
  await keepOpen.check();
  await submit.click();
  await page.waitForFunction(id => document.getElementById(id)?.value === '', await title.getAttribute('id'));
  assert.equal(await editor.isVisible(), true);
  assert.equal(await stage.inputValue(), 'todo');
  assert.equal(await priority.inputValue(), 'low');
  assert.equal(await keepOpen.isChecked(), true);
  await cancel.click();
  await editor.waitFor({ state: 'hidden' });
  const [saved] = (await command({ op: 'list_cards' })).cards;
  assert.equal(saved.title, savedTitle);
  assert.equal(saved.status, 'todo');
  assert.equal(saved.priority, 'low');
  assert.equal(requests.length, 0);

  const card = page.getByRole('article', { name: savedTitle, exact: true });
  const edit = page.getByRole('dialog', { name: '编辑卡片', exact: true });
  const editTitle = edit.getByRole('textbox', { name: '标题', exact: true });
  async function editSavedCard() {
    await card.getByRole('button', { name: '卡片操作', exact: true }).click();
    await page.getByRole('button', { name: '编辑卡片', exact: true }).click();
  }
  await editSavedCard();
  await editTitle.fill('Unsaved replacement');
  await page.keyboard.press('Escape');
  await edit.waitFor({ state: 'hidden' });
  await editSavedCard();
  assert.equal(await editTitle.inputValue(), savedTitle);
  assert.equal((await command({ op: 'read_card', card_id: saved.card_id })).title, savedTitle);
});

test('canceling the card editor aborts its pending upload', async t => {
  const { page } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const create = page.getByRole('button', { name: '新建卡片', exact: true });
  await create.click();
  const editor = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const filename = 'discarded-draft.txt';
  const upload = /\/api\/board\/attachments\?name=discarded-draft\.txt$/;
  await page.route(upload, () => {});
  const started = page.waitForRequest(upload);
  const attachment = editor.getByLabel('添加附件', { exact: true }).and(editor.locator('input[type="file"]'));
  assert.equal(await attachment.isVisible(), true);
  assert.equal(await editor.getByRole('textbox', { name: '标签', exact: true }).isVisible(), false);
  await attachment.setInputFiles({
    name: filename, mimeType: 'text/plain', buffer: Buffer.from('Unsaved card attachment.'),
  });
  const request = await started;
  await editor.getByText(filename, { exact: true }).waitFor();
  const aborted = page.waitForEvent('requestfailed', pending => pending === request);
  await editor.getByRole('button', { name: '取消', exact: true }).click();
  await aborted;
  await editor.waitFor({ state: 'hidden' });
  await create.click();
  await editor.getByRole('textbox', { name: '标题', exact: true }).fill('A new card');
  await editor.getByText('更多卡片选项', { exact: true }).click();
  assert.equal(await editor.getByText(filename, { exact: true }).count(), 0);
  await editor.getByRole('button', { name: '创建卡片', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
});

test('canceling Add to board restores the source conversation defaults on reopening', async t => {
  const { page, command } = await browserFixture(t);
  const { project_id } = await command({ op: 'create_project', name: 'Card source project', workspace: { roots: [] } });
  const { task_id } = await command({ op: 'create_idle', profile: 'demo', settings: { project_id } });
  const { task } = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const actions = page.getByRole('main').getByRole('button', { name: '对话操作', exact: true });
  const editor = page.getByRole('dialog', { name: '添加到看板', exact: true });
  const title = editor.getByRole('textbox', { name: '标题', exact: true });
  async function openCardEditor() {
    await actions.click();
    await page.getByRole('button', { name: '添加到看板', exact: true }).click();
  }
  await openCardEditor();
  await title.fill('Discard this draft title');
  await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
  await editor.waitFor({ state: 'hidden' });
  assert.deepEqual((await command({ op: 'list_cards' })).cards, []);
  await openCardEditor();
  assert.equal(await title.inputValue(), task.title);
  await editor.getByText('更多卡片选项', { exact: true }).click();
  const project = editor.getByRole('combobox', { name: '所属项目', exact: true });
  assert.equal(await project.inputValue(), String(project_id));
});

test('a project can start with only a name and save an optional directory later', async t => {
  const { page, command, root } = await browserFixture(t);
  const workspace = path.join(root, '项目默认目录');
  await mkdir(path.join(workspace, '子目录'), { recursive: true });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 620 });
  const main = page.getByRole('main');
  await main.getByRole('button', { name: '新建项目', exact: true }).click();
  const create = page.getByRole('dialog', { name: '新建项目', exact: true });
  const name = create.getByRole('textbox', { name: '项目名称', exact: true });
  const submit = create.getByRole('button', { name: '创建项目', exact: true });
  const optional = create.getByRole('heading', { name: '工作目录（可选）', exact: true });
  const browse = create.getByRole('button', { name: '浏览…', exact: true });
  await optional.waitFor();
  const headingBounds = await optional.boundingBox();
  const browseBounds = await browse.boundingBox();
  assert.ok(headingBounds && browseBounds && headingBounds.x >= 0 && headingBounds.x + headingBounds.width <= 390
    && headingBounds.y >= 0
    && headingBounds.y + headingBounds.height <= browseBounds.y && headingBounds.y + headingBounds.height <= 620);
  assert.equal(await name.getAttribute('placeholder'), '请输入项目名称');
  assert.equal(await name.getAttribute('aria-required'), 'true');
  assert.equal(await submit.isDisabled(), true);
  assert.equal(await submit.getAttribute('title'), '请输入项目名称');
  assert.equal(await create.getByRole('alert').count(), 0);
  await create.locator('[data-semantic-key="editor-commit-reason"]').waitFor({ state: 'hidden' });
  assert.equal(await submit.evaluate(button => (button.getAttribute('aria-describedby') ?? '').split(/\s+/)
    .map(id => document.getElementById(id)?.textContent ?? '').join(' ').trim()), '请输入项目名称');
  await name.fill('\u3000 ');
  assert.equal(await submit.getAttribute('title'), '请输入项目名称');
  assert.equal(await submit.isDisabled(), true);
  assert.equal(await create.getByRole('alert').count(), 0);
  await create.locator('[data-semantic-key="editor-commit-reason"]').waitFor({ state: 'hidden' });
  await name.fill(`${'项'.repeat(85)}ab`);
  assert.equal(await submit.isDisabled(), true);
  assert.equal(await submit.getAttribute('title'), '项目名称不能超过 256 个 UTF-8 字节。');
  await create.getByRole('alert').filter({ hasText: '项目名称不能超过 256 个 UTF-8 字节。' }).waitFor();
  await name.fill(`${'项'.repeat(85)}a`);
  await create.getByRole('button', { name: '创建项目', exact: true, disabled: false }).waitFor();

  const projectName = '先按名称创建的项目';
  await name.fill(projectName);
  await browse.click();
  const chooser = page.getByRole('dialog', { name: '选择 Selvedge 主机上的目录', exact: true });
  await chooser.getByRole('button', { name: '取消', exact: true }).click();
  await chooser.waitFor({ state: 'hidden' });
  await page.waitForFunction(id => document.activeElement?.id === id, await browse.getAttribute('id'));
  assert.equal(await name.inputValue(), projectName);
  assert.equal(await create.getByRole('textbox', { name: '目录路径', exact: true }).inputValue(), '');
  await submit.click();
  await create.waitFor({ state: 'hidden' });
  const [created] = await command({ op: 'list_projects' });
  assert.equal(created.name, projectName);
  assert.deepEqual(created.workspace, { roots: [], primary_root: null });

  await page.setViewportSize({ width: 1280, height: 900 });
  const row = main.getByRole('region', { name: projectName, exact: true });
  await row.hover();
  await row.getByRole('button', { name: '项目操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑项目', exact: true }).click();
  const edit = page.getByRole('dialog', { name: '编辑项目', exact: true });
  assert.equal(await edit.getByRole('textbox', { name: '项目名称', exact: true }).inputValue(), projectName);
  await edit.getByRole('button', { name: '浏览…', exact: true }).click();
  await chooser.getByRole('textbox', { name: '目录路径', exact: true }).fill(workspace);
  await chooser.getByRole('button', { name: '前往', exact: true }).click();
  await chooser.getByRole('button', { name: '子目录', exact: true }).waitFor();
  await chooser.getByRole('button', { name: '使用此目录', exact: true }).click();
  await chooser.waitFor({ state: 'hidden' });
  await edit.getByText(workspace, { exact: true }).waitFor();
  await edit.getByRole('button', { name: '保存', exact: true }).click();
  await edit.waitFor({ state: 'hidden' });
  const saved = await command({ op: 'read_project', project_id: created.project_id });
  assert.equal(saved.name, projectName);
  assert.deepEqual(saved.workspace, { roots: [workspace], primary_root: workspace });
});

test('a typed Project directory shows one instruction and leaves both footer actions together', { timeout: 60000 }, async t => {
  const { page, command, root } = await browserFixture(t);
  const directory = path.join(root, '手动输入的项目目录');
  await mkdir(directory);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  const create = page.getByRole('main').getByRole('button', { name: '新建项目', exact: true });
  const project = page.getByRole('dialog', { name: '新建项目', exact: true });
  const location = project.getByRole('textbox', { name: '目录路径', exact: true });
  const submit = project.getByRole('button', { name: '创建项目', exact: true });
  const cancel = project.getByRole('button', { name: '取消', exact: true });
  const instruction = '请先添加或清空目录路径。';
  const status = project.getByRole('status').filter({ hasText: instruction });
  const copies = project.getByText(instruction, { exact: true }).and(project.locator(':not(.visually-hidden)'));

  const cases = [
    { width: 1280, height: 900, name: '手动添加目录', action: '添加目录', workspace: { roots: [directory], primary_root: directory } },
    { width: 390, height: 620, name: '清空未添加的目录', action: '清空', workspace: { roots: [], primary_root: null } },
  ];
  for (const { width, height, name, action } of cases) {
    await page.setViewportSize({ width, height });
    await create.click();
    await project.getByRole('textbox', { name: '项目名称', exact: true }).fill(name);
    await location.fill(directory);
    await status.waitFor();
    assert.equal(await copies.count(), 1, `One visible instruction at ${width}px`);
    assert.equal(await submit.isDisabled(), true);
    assert.equal(await submit.evaluate(button => (button.getAttribute('aria-describedby') ?? '').split(/\s+/)
      .map(id => document.getElementById(id)?.textContent ?? '').join(' ').trim()), instruction);

    const statusBounds = await status.boundingBox();
    const locationBounds = await location.boundingBox();
    const cancelBounds = await cancel.boundingBox();
    const submitBounds = await submit.boundingBox();
    assert.ok(statusBounds && locationBounds && statusBounds.y + statusBounds.height <= locationBounds.y);
    assert.ok(cancelBounds && submitBounds && cancelBounds.x + cancelBounds.width <= submitBounds.x
      && Math.abs(cancelBounds.y + cancelBounds.height / 2 - submitBounds.y - submitBounds.height / 2) <= 1
      && cancelBounds.x >= 0 && submitBounds.x + submitBounds.width <= width,
    `Cancel and Create share one footer row at ${width}px`);

    await project.getByRole('button', { name: action, exact: true }).click();
    await status.waitFor({ state: 'hidden' });
    assert.equal(await location.inputValue(), '');
    await submit.click();
    await project.waitFor({ state: 'hidden' });
  }
  const saved = await command({ op: 'list_projects' });
  for (const { name, workspace } of cases) {
    assert.deepEqual(saved.find(project => project.name === name)?.workspace, workspace);
  }
});

test('closing Project and title prompt editors discards their unsaved drafts through the browser', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const projectName = 'Editor dismissal project';
  await command({ op: 'create_project', name: projectName,
    workspace: { roots: [], primary_root: null } });

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '项目', exact: true }).click();
  await page.getByRole('main').getByRole('region', { name: projectName, exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: '项目操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑项目', exact: true }).click();
  let dialog = page.getByRole('dialog');
  const projectNameInput = dialog.getByRole('textbox', { name: '项目名称', exact: true });
  await projectNameInput.fill('Unsaved project name');
  await page.keyboard.press('Escape');
  await projectNameInput.waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  await page.getByRole('main').getByRole('region', { name: projectName, exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: '项目操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑项目', exact: true }).click();
  dialog = page.getByRole('dialog');
  assert.equal(await dialog.getByRole('textbox', { name: '项目名称', exact: true }).inputValue(), projectName);
  await page.keyboard.press('Escape');
  await dialog.getByRole('textbox', { name: '项目名称', exact: true }).waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  const settings = page.getByRole('dialog', { name: '设置', exact: true });
  const editTitlePrompts = settings.getByRole('button', { name: '编辑标题设置', exact: true });
  const titlePrompts = page.getByRole('dialog', { name: '对话标题', exact: true });
  async function openTitlePrompts() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: '设置', exact: true }).click();
    await editTitlePrompts.click();
    return titlePrompts;
  }

  dialog = await openTitlePrompts();
  const prompt = dialog.getByRole('textbox', { name: '任务标题提示词', exact: true });
  const savedPrompt = await prompt.inputValue();
  await prompt.fill('Unsaved title prompt');
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
  await editTitlePrompts.waitFor();
  assert.equal(await editTitlePrompts.evaluate(button => document.activeElement === button), true);

  await editTitlePrompts.click();
  assert.equal(await prompt.inputValue(), savedPrompt);

  const titleModel = dialog.getByLabel('对话标题模型', { exact: true });
  const options = await titleModel.locator('option').evaluateAll(nodes => nodes.map(node => ({
    label: node.label, value: node.value,
  })));
  const automatic = options.find(option => option.label === '自动');
  const configured = options.find(option => option.label.includes('interactive') || option.value.includes('interactive'));
  assert.ok(automatic, 'The title model selector exposes automatic selection');
  assert.ok(configured, 'The selector exposes the configured interactive model connection');
  assert.equal(await titleModel.inputValue(), automatic.value, 'Automatic selection is the initial title model');
  await titleModel.selectOption(configured.value);
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });
  await editTitlePrompts.waitFor();

  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  dialog = await openTitlePrompts();
  assert.equal(await dialog.getByLabel('对话标题模型', { exact: true }).inputValue(), configured.value,
    'The selected title model remains saved after the page reloads');
});

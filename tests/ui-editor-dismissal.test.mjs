import test from 'node:test';
import assert from 'node:assert/strict';
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
  await editor.getByText('更多卡片选项', { exact: true }).click();
  const filename = 'discarded-draft.txt';
  const upload = /\/api\/board\/attachments\?name=discarded-draft\.txt$/;
  await page.route(upload, () => {});
  const started = page.waitForRequest(upload);
  await editor.locator('input[type="file"]').setInputFiles({
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
  const actions = page.getByRole('main').getByRole('button', { name: 'More actions', exact: true });
  const editor = page.getByRole('dialog', { name: '添加到看板', exact: true });
  const title = editor.getByRole('textbox', { name: '标题', exact: true });
  async function openCardEditor() {
    await actions.click();
    await page.getByRole('button', { name: 'Add to board', exact: true }).click();
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
  const projectNameInput = dialog.getByRole('textbox', { name: 'Name', exact: true });
  await projectNameInput.fill('Unsaved project name');
  await page.keyboard.press('Escape');
  await projectNameInput.waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  await page.getByRole('main').getByRole('region', { name: projectName, exact: true }).hover();
  await page.getByRole('main').getByRole('button', { name: '项目操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑项目', exact: true }).click();
  dialog = page.getByRole('dialog');
  assert.equal(await dialog.getByRole('textbox', { name: 'Name', exact: true }).inputValue(), projectName);
  await page.keyboard.press('Escape');
  await dialog.getByRole('textbox', { name: 'Name', exact: true }).waitFor({ state: 'hidden' });
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });

  const settings = page.getByRole('dialog', { name: 'Settings', exact: true });
  const editTitlePrompts = settings.getByRole('button', { name: 'Edit title prompts', exact: true });
  const titlePrompts = page.getByRole('dialog', { name: 'Conversation titles', exact: true });
  async function openTitlePrompts() {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: 'Settings', exact: true }).click();
    await editTitlePrompts.click();
    return titlePrompts;
  }

  dialog = await openTitlePrompts();
  const prompt = dialog.getByRole('textbox', { name: 'Task title prompt', exact: true });
  const savedPrompt = await prompt.inputValue();
  await prompt.fill('Unsaved title prompt');
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
  await editTitlePrompts.waitFor();
  assert.equal(await editTitlePrompts.evaluate(button => document.activeElement === button), true);

  await editTitlePrompts.click();
  assert.equal(await prompt.inputValue(), savedPrompt);

  const titleModel = dialog.getByLabel('Conversation title model', { exact: true });
  const options = await titleModel.locator('option').evaluateAll(nodes => nodes.map(node => ({
    label: node.label, value: node.value,
  })));
  const automatic = options.find(option => option.label === 'Automatic');
  const configured = options.find(option => option.label.includes('interactive') || option.value.includes('interactive'));
  assert.ok(automatic, 'The title model selector exposes automatic selection');
  assert.ok(configured, 'The selector exposes the configured interactive model connection');
  assert.equal(await titleModel.inputValue(), automatic.value, 'Automatic selection is the initial title model');
  await titleModel.selectOption(configured.value);
  await dialog.getByRole('button', { name: 'Save', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });
  await editTitlePrompts.waitFor();

  await page.reload();
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor();
  dialog = await openTitlePrompts();
  assert.equal(await dialog.getByLabel('Conversation title model', { exact: true }).inputValue(), configured.value,
    'The selected title model remains saved after the page reloads');
});

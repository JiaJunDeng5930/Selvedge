import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('task board exposes ordinary model and unassigned filter choices', async t => {
  const { page } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('button', { name: '筛选卡片', exact: true }).click();
  const dialog = page.getByRole('dialog').last();
  for (const label of ['interactive-fixture', '未分配', '未分配项目']) {
    const choice = dialog.getByRole('checkbox', { name: label, exact: true });
    await choice.click();
    assert.equal(await choice.getAttribute('aria-checked'), 'true', label);
    await choice.click();
    assert.equal(await choice.getAttribute('aria-checked'), 'false', label);
  }
});

test('card save shows whether a model will start, wait, or remain manual', async t => {
  const { page, command, running, requests, finish } = await browserFixture(t);
  const settings = automatic => command({ op: 'board_settings', automatic, draft_profile: 'interactive' });
  await settings(true);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const newCard = async title => {
    await page.getByRole('button', { name: '新建卡片', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: '新建卡片', exact: true });
    await dialog.getByRole('textbox', { name: '标题', exact: true }).fill(title);
    await dialog.getByText('更多卡片选项', { exact: true }).click();
    await dialog.getByRole('combobox', { name: '负责人', exact: true }).selectOption('profile/interactive');
    return dialog;
  };
  const stage = dialog => dialog.getByRole('combobox', { name: '状态', exact: true });
  const consequence = (dialog, text) => dialog.locator('[data-surface-role="dialog-actions"]')
    .getByText(text, { exact: true }).waitFor();

  const title = 'Review the rollout';
  await page.setViewportSize({ width: 390, height: 844 });
  const first = await newCard(title);
  assert.equal(await stage(first).inputValue(), 'backlog');
  await consequence(first, '只保存卡片。移到「待办」可自动排队。');
  const prediction = await first.getByText('只保存卡片。移到「待办」可自动排队。', { exact: true }).boundingBox();
  const submit = await first.getByRole('button', { name: '创建卡片', exact: true }).boundingBox();
  for (const box of [prediction, submit]) {
    assert.ok(box && box.x >= 0 && box.y >= 0 && box.x + box.width <= 390 && box.y + box.height <= 844);
  }
  assert.ok(prediction.y + prediction.height <= submit.y);
  await page.setViewportSize({ width: 1280, height: 900 });
  const drafting = first.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  await drafting.check();
  await consequence(first, '保存后先生成卡片内容，暂不启动对话。');
  await stage(first).selectOption('todo');
  await consequence(first, '保存后先生成卡片内容，成功后自动排队。');
  assert.deepEqual((await command({ op: 'list_cards' })).cards, []);
  await drafting.uncheck();
  await stage(first).selectOption('backlog');
  await consequence(first, '只保存卡片。移到「待办」可自动排队。');
  await first.getByRole('button', { name: '创建卡片', exact: true }).click();
  await first.waitFor({ state: 'hidden' });
  const [saved] = (await command({ op: 'list_cards' })).cards;
  assert.equal(saved.status, 'backlog');
  assert.equal(saved.task_id, null);

  const card = page.getByRole('article', { name: title, exact: true });
  await card.getByRole('button', { name: '卡片操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑卡片', exact: true }).click();
  const edit = page.getByRole('dialog', { name: '编辑卡片', exact: true });
  await edit.getByText('更多卡片选项', { exact: true }).click();
  await stage(edit).selectOption('todo');
  await consequence(edit, '保存后会尝试启动对话。');
  await settings(false);
  await consequence(edit, '只保存卡片。对话需要手动启动。');
  await settings(true);
  await consequence(edit, '保存后会尝试启动对话。');
  await edit.getByRole('button', { name: '保存', exact: true }).click();
  await edit.waitFor({ state: 'hidden' });
  const active = await command({ op: 'read_card', card_id: saved.card_id });
  assert.equal(active.status, 'in_progress');
  assert.notEqual(active.task_id, null);
  const movedTrigger = page.locator('[data-board-stage="in_progress"]')
    .getByRole('article', { name: title, exact: true }).getByRole('button', { name: '卡片操作', exact: true });
  await movedTrigger.waitFor();
  await page.waitForFunction(key => document.activeElement?.id === key, await movedTrigger.getAttribute('id'));

  const waitingTitle = 'Review the follow-up';
  const second = await newCard(waitingTitle);
  await stage(second).selectOption('todo');
  await consequence(second, '保存后进入队列，等模型空闲再尝试启动对话。');
  await second.getByRole('button', { name: '创建卡片', exact: true }).click();
  await second.waitFor({ state: 'hidden' });
  const waiting = (await command({ op: 'list_cards' })).cards.find(card => card.title === waitingTitle);
  assert.equal(waiting.activity, 'queued');
  assert.equal(waiting.task_id, null);

  const deadline = Date.now() + 5000;
  while (!requests.length && Date.now() < deadline) await delay(10);
  assert.ok(requests[0], 'The first card must reach the fixture model');
  finish(0, { text: 'The rollout is ready.' });
  await taskIdle(running.service, active.task_id);
  await page.locator('[data-board-stage="in_progress"]')
    .getByRole('article', { name: waitingTitle, exact: true }).waitFor();
  const started = await command({ op: 'read_card', card_id: waiting.card_id });
  assert.notEqual(started.task_id, null);
});

test('the board keeps empty stages visible and counts only matching cards linked to executing conversations', async t => {
  const { page, command } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const board = page.locator('[data-page-region="board-stages"]');
  for (const viewport of [{ width: 1280, height: 900 }, { width: 760, height: 500 }]) {
    await page.setViewportSize(viewport);
    await page.waitForFunction(singleRow => {
      const scrollport = document.querySelector('[data-page-region="board-stages"]');
      const stages = [...(scrollport?.querySelectorAll('[data-board-stage]') ?? [])];
      if (stages.length !== 6 || scrollport.scrollWidth > scrollport.clientWidth) return false;
      const bounds = scrollport.getBoundingClientRect();
      return stages.every(stage => {
        const { top, bottom, height } = stage.getBoundingClientRect();
        return top >= bounds.top && bottom <= bounds.bottom + 1 && height <= 80
          && (!singleRow || top <= bounds.top + 1);
      });
    }, viewport.width === 1280);
    await board.getByRole('region', { name: '已完成，0 张卡片', exact: true }).waitFor();
    await board.getByRole('region', { name: '已阻塞，0 张卡片', exact: true }).waitFor();
  }

  await page.setViewportSize({ width: 1280, height: 900 });
  const message = 'Link an executing conversation';
  const { task_id } = await command({ op: 'create', profile: 'interactive', message });
  const { task } = await command({ op: 'read', task_id });
  const nav = page.getByRole('navigation', { name: 'Task tree', exact: true });
  await nav.locator(`[data-task-id="${task_id}"] [data-task-working="true"]`).waitFor();
  await page.getByRole('radio', { name: '执行中的卡片 0', exact: true }).waitFor();

  const title = 'Plan the release';
  const { card_id } = await command({ op: 'create_card', title });
  const card = board.getByRole('article', { name: title, exact: true });
  const completed = board.locator('[data-board-stage="done"]');
  await card.locator('[data-card-grip]').dragTo(completed);
  await completed.getByRole('article', { name: title, exact: true }).waitFor();
  await card.getByRole('button', { name: '卡片操作', exact: true }).click();
  await page.getByRole('dialog', { name: 'Actions', exact: true })
    .getByRole('button', { name: '移动卡片', exact: true }).click();
  const move = page.getByRole('dialog', { name: '移动卡片', exact: true });
  await move.getByRole('button', { name: '移至待规划', exact: true }).click();
  await move.waitFor({ state: 'hidden' });
  await board.locator('[data-board-stage="backlog"]').getByRole('article', { name: title, exact: true }).waitFor();
  await card.getByRole('button', { name: '关联对话', exact: true }).click();
  const link = page.getByRole('dialog', { name: '关联对话', exact: true });
  const choice = link.getByRole('button', { name: `${task.title} · 预计进入 进行中`, exact: true });
  let competing = true;
  await page.route('**/api/browser/command', async route => {
    if (competing && route.request().postDataJSON()?.command?.op === 'link_card') {
      competing = false;
      const { revision } = await command({ op: 'read_card', card_id });
      await command({ op: 'update_card', card_id, revision,
        observed_at: String(Math.floor(Date.now() / 1000)), description: 'An update while the picker is open' });
    }
    await route.continue();
  });
  const rejected = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === 'link_card');
  await choice.click();
  const { reply } = await (await rejected).json();
  assert.equal(reply.ok, false, JSON.stringify(reply));
  assert.equal(reply.error.code, 'card_conflict');
  const failure = link.getByRole('alert');
  await failure.waitFor();
  assert.equal(await failure.innerText(), `${reply.error.code}: ${reply.error.message}`);
  await choice.click();
  await link.waitFor({ state: 'hidden' });

  const working = page.getByRole('radio', { name: '执行中的卡片 1', exact: true });
  await working.click();
  await board.locator('[data-board-stage="in_progress"]').getByRole('article', { name: title, exact: true }).waitFor();
  const search = page.getByPlaceholder('搜索卡片', { exact: true });
  await search.fill('different card title');
  await page.getByRole('radio', { name: '执行中的卡片 0', exact: true }).waitFor();
  await card.waitFor({ state: 'hidden' });
  await search.clear();
  await card.getByRole('button', { name: '打开对话', exact: true }).click();
  await page.getByRole('main').getByRole('article', { name: 'Message', exact: true })
    .getByText(message, { exact: true }).waitFor();
});

test('a conversation can be added to the board without starting another conversation', async t => {
  const { page, command, running, requests, finish } = await browserFixture(t);
  const { project_id } = await command({ op: 'create_project', name: 'Release planning', workspace: { roots: [] } });
  const { task_id } = await command({ op: 'create', profile: 'interactive', message: 'Verify the release checklist',
    settings: { project_id } });
  const { task } = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  const main = page.getByRole('main');
  const actions = main.getByRole('button', { name: 'More actions', exact: true });
  await actions.click();
  await page.getByRole('button', { name: 'Add to board', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: '添加到看板', exact: true });
  const titleField = dialog.getByRole('textbox', { name: '标题', exact: true });
  assert.equal(await titleField.inputValue(), task.title);
  await dialog.getByText('关联对话', { exact: true }).waitFor();
  const destination = dialog.getByText('预计进入', { exact: true }).locator('..');
  await destination.getByText('进行中', { exact: true }).waitFor();
  await dialog.getByText('更多卡片选项', { exact: true }).click();
  await destination.getByText('进行中', { exact: true }).waitFor();
  const deadline = Date.now() + 5000;
  while (!requests.length && Date.now() < deadline) await delay(10);
  assert.ok(requests[0], 'The source conversation must reach the fixture model');
  finish(0, { text: 'The release checklist is ready for review.' });
  await taskIdle(running.service, task_id);
  await destination.getByText('待审核', { exact: true }).waitFor();
  await dialog.getByText('对话当前未运行。', { exact: true }).waitFor();
  const title = 'Release checklist review';
  await titleField.fill(title);
  await dialog.getByRole('button', { name: '添加卡片', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });

  const { cards } = await command({ op: 'list_cards' });
  assert.equal(cards.length, 1);
  assert.equal(cards[0].task_id, task_id);
  assert.equal(cards[0].title, title);
  assert.equal(cards[0].project, String(project_id));
  assert.equal(cards[0].status, 'in_review');
  assert.deepEqual((await command({ op: 'list' })).tasks.map(value => value.id), [task_id]);

  const duplicate = await fetch(`${running.address}/api/commands`, {
    method: 'POST', headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ op: 'create_card', title: 'Duplicate card', task_id }),
  });
  const refused = await duplicate.json();
  assert.equal(refused.ok, false, JSON.stringify(refused));
  assert.equal(refused.error.code, 'conversation_already_linked');
  assert.deepEqual((await command({ op: 'list_cards' })).cards, cards);

  await page.keyboard.press('Escape');
  await actions.click();
  await page.getByRole('button', { name: 'Open board card', exact: true }).click();
  const details = page.getByRole('dialog', { name: '卡片详情', exact: true });
  await details.getByText(title, { exact: true }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Add to board', exact: true }).count(), 0);

  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await main.getByRole('button', { name: '新建卡片', exact: true }).click();
  const ordinary = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const ordinaryTitle = ordinary.getByRole('textbox', { name: '标题', exact: true });
  assert.equal(await ordinaryTitle.inputValue(), '');
  await ordinaryTitle.fill('Independent plan');
  await ordinary.getByRole('button', { name: '创建卡片', exact: true }).click();
  await ordinary.waitFor({ state: 'hidden' });
  const listed = (await command({ op: 'list_cards' })).cards;
  assert.equal(listed.length, 2);
  assert.equal(listed.find(value => value.title === 'Independent plan').task_id, null);
});

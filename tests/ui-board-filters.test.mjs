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

test('assisted card creation keeps model selection truthful when the catalog changes', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, command, upstream, running } = fixture;
  const delegate = upstream.options.respond;
  const requests = [];
  let models = [];
  const complete = (response, text) => {
    const output = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\n\n`);
  };
  upstream.options.respond = async (entry, response) => {
    if (new URL(entry.url, upstream.address).pathname === '/v1/models') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ models }));
      return;
    }
    const schema = entry.body.text?.format?.schema;
    if (schema?.properties?.title && schema?.properties?.description) {
      requests.push(entry.body.model);
      complete(response, JSON.stringify({ title: 'Organized card', description: 'A completed model draft' }));
      return;
    }
    return delegate(entry, response);
  };
  async function refresh(slugs) {
    models = slugs.map(slug => ({ slug, display_name: slug, visibility: 'list', context_window: 128000,
      effective_context_window_percent: 100, default_reasoning_level: 'medium',
      supported_reasoning_levels: [{ effort: 'medium' }] }));
    const response = await fetch(`${running.address}/api/accounts/refresh`, {
      method: 'POST', headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' }, body: '{}',
    });
    assert.equal(response.status, 200, await response.clone().text());
    const reply = await response.json();
    assert.ok(reply.ok, JSON.stringify(reply));
    return reply.result.profiles;
  }
  const configured = await refresh(['image-fixture', 'replacement-fixture']);
  const replacement = configured.find(model => model.name === 'replacement-fixture');
  assert.ok(replacement?.key);
  await command({ op: 'board_settings', automatic: false, draft_profile: fixture.profile });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const create = dialog.getByRole('button', { name: '创建卡片', exact: true });
  const assisted = dialog.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  const profile = dialog.getByRole('combobox', { name: '整理用的模型', exact: true });
  async function openAssistedCard(title) {
    await page.getByRole('button', { name: '新建卡片', exact: true }).click();
    await dialog.getByRole('textbox', { name: '标题', exact: true }).fill(title);
    await dialog.getByText('更多卡片选项', { exact: true }).click();
    await assisted.check();
  }
  const selected = label => profile.locator('option:checked').filter({ hasText: label }).waitFor({ state: 'attached' });
  async function blocked(message) {
    await selected('请选择模型');
    await dialog.getByRole('alert').filter({ hasText: message }).waitFor();
    assert.equal(await create.isEnabled(), false);
  }

  await openAssistedCard('A valid Board default');
  await selected('看板默认模型');
  await create.click();
  await dialog.waitFor({ state: 'hidden' });
  await page.getByRole('article', { name: 'Organized card', exact: true }).waitFor();
  assert.deepEqual(requests, ['image-fixture']);

  await openAssistedCard('Preserve this card draft');
  await selected('看板默认模型');
  await refresh(['replacement-fixture']);
  await blocked('看板默认整理模型不可用，请选择其他模型。');
  assert.ok(!(await profile.locator('option').allTextContents()).includes('看板默认模型'));
  await profile.selectOption(replacement.key);
  await page.waitForFunction(() => {
    const submit = document.querySelector('dialog[open] button[data-semantic-key="submit"]');
    return submit && !submit.disabled && submit.getAttribute('aria-disabled') !== 'true';
  });
  await refresh(['image-fixture']);
  await blocked('所选整理模型不可用，请重新选择。');
  assert.ok((await profile.locator('option').allTextContents()).includes('看板默认模型'));
  await dialog.getByRole('button', { name: '取消', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });

  await refresh(['replacement-fixture']);
  await page.getByRole('button', { name: '看板设置', exact: true }).click();
  const settingsProfile = page.getByRole('combobox', { name: '草稿模型', exact: true });
  await settingsProfile.locator('option:checked').filter({ hasText: '请选择草稿模型' }).waitFor({ state: 'attached' });
});

test('assisted card creation can fall back to manual save when no drafting model exists', async t => {
  const fixture = await browserFixture(t);
  const { page, command, requests } = fixture;
  const { demo } = fixture.running.service.config.profiles;
  await fixture.restart({ profiles: { demo } });
  await page.goto(fixture.running.url);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('button', { name: '新建卡片', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const title = 'Preserve this card draft';
  await dialog.getByRole('textbox', { name: '标题', exact: true }).fill(title);
  await dialog.getByText('更多卡片选项', { exact: true }).click();
  const assisted = dialog.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  await assisted.check();
  await dialog.getByRole('alert').filter({ hasText: '没有可用的整理模型。请配置模型，或关闭模型整理。' }).waitFor();
  const profile = dialog.getByRole('combobox', { name: '整理用的模型', exact: true });
  assert.deepEqual(await profile.locator('option').allTextContents(), ['请选择模型']);
  const create = dialog.getByRole('button', { name: '创建卡片', exact: true });
  assert.equal(await create.isEnabled(), false);
  await assisted.uncheck();
  await create.click();
  await dialog.waitFor({ state: 'hidden' });
  const [saved] = (await command({ op: 'list_cards' })).cards;
  assert.equal(saved.title, title);
  assert.equal(requests.length, 0);
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

test('the blocked card commit keeps its repair visible while the mobile form scrolls', async t => {
  const { page, command, requests, finish } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 500 });
  await page.getByRole('button', { name: '新建卡片', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const title = dialog.getByRole('textbox', { name: '标题', exact: true });
  const description = dialog.getByRole('textbox', { name: '描述', exact: true });
  const body = dialog.locator('[data-surface-role="dialog-body"]');
  const footer = dialog.locator('[data-surface-role="dialog-actions"]');
  const submit = footer.getByRole('button', { name: '创建卡片', exact: true });
  const reasonText = '看板未设置默认整理模型，请选择模型。';
  const reason = footer.locator('[data-semantic-key="editor-commit-reason"]');
  await submit.waitFor();
  assert.equal(await reason.count(), 0);
  await title.fill('A card with a long description');
  await description.fill('Review this step and keep the details in the card.\n'.repeat(18));
  await dialog.getByText('更多卡片选项', { exact: true }).click();
  await dialog.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true }).check();
  const model = dialog.getByRole('combobox', { name: '整理用的模型', exact: true });
  await reason.waitFor();
  assert.equal(await reason.textContent(), reasonText);
  await body.getByRole('alert').filter({ hasText: reasonText }).waitFor();
  assert.equal(await model.locator('option:checked').textContent(), '请选择模型');
  assert.equal(await submit.isDisabled(), true);

  await title.focus();
  await page.keyboard.press('Tab');
  await page.waitForFunction(({ descriptionId, modelId, reasonText }) => {
    const input = document.getElementById(descriptionId);
    const picker = document.getElementById(modelId);
    const panel = input?.closest('dialog');
    const body = panel?.querySelector('[data-surface-role="dialog-body"]');
    const footer = panel?.querySelector('[data-surface-role="dialog-actions"]');
    const reason = [...(footer?.children ?? [])].find(node => node.textContent === reasonText);
    const disabledCommit = footer?.querySelector('button[aria-disabled="true"]');
    if (!body || !picker || document.activeElement !== input || body.scrollHeight <= body.clientHeight) return false;
    const bodyBounds = body.getBoundingClientRect();
    return picker.getBoundingClientRect().top >= bodyBounds.bottom
      && [reason, disabledCommit].every(node => {
        const rect = node?.getBoundingClientRect();
        return rect && rect.top >= bodyBounds.bottom && rect.bottom <= window.innerHeight
          && rect.left >= 0 && rect.right <= window.innerWidth;
      });
  }, { descriptionId: await description.getAttribute('id'), modelId: await model.getAttribute('id'), reasonText });

  const focused = locator => locator.evaluate(element => element === document.activeElement);
  for (let index = 0; index < 12 && !(await focused(model)); index++) await page.keyboard.press('Tab');
  assert.equal(await focused(model), true, 'Tab reaches the field named in the footer');
  await page.keyboard.press('i');
  assert.equal(await model.inputValue(), 'interactive');
  await reason.waitFor({ state: 'hidden' });
  await footer.getByText('保存后先生成卡片内容，暂不启动对话。', { exact: true }).waitFor();
  assert.equal(await submit.isEnabled(), true);
  await page.keyboard.press('Tab');
  await page.keyboard.press('Tab');
  assert.equal(await focused(submit), true);
  await page.keyboard.press('Enter');
  await dialog.waitFor({ state: 'hidden' });

  const generatedTitle = 'Drafted with keyboard';
  const deadline = Date.now() + 5000;
  while (!requests.length && Date.now() < deadline) await delay(10);
  assert.ok(requests[0], 'The keyboard submission reaches the drafting model');
  finish(0, { text: JSON.stringify({ title: generatedTitle, description: 'Review the saved request.' }) });
  await page.getByRole('article', { name: generatedTitle, exact: true }).waitFor();
  assert.equal((await command({ op: 'list_cards' })).cards[0].title, generatedTitle);
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

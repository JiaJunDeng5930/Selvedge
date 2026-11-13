import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function assertConversationActivity(card, caption) {
  const status = card.getByText(caption, { exact: true });
  await status.waitFor();
  const action = status.locator('..').getByRole('button', { name: '打开对话', exact: true });
  await action.waitFor();
  const [button, text] = await Promise.all([action.boundingBox(), status.boundingBox()]);
  assert.ok(button && text);
  const sideBySide = text.x >= button.x + button.width - 1 &&
    text.x - button.x - button.width <= 16 && text.y < button.y + button.height && button.y < text.y + text.height;
  const stacked = text.y >= button.y + button.height - 1 && text.y - button.y - button.height <= 16;
  assert.ok(sideBySide || stacked, 'The conversation status stays next to its action');
}

test('board filters provide a compact keyboard-searchable assignee list', async t => {
  const fixture = await browserFixture(t);
  const { page } = fixture;
  const profiles = fixture.running.service.config.profiles;
  const variants = Object.fromEntries(Array.from({ length: 14 }, (_, index) => {
    const model = `review-worker-${String(index + 1).padStart(2, '0')}-with-a-long-display-name`;
    return [model, { ...profiles.interactive, model }];
  }));
  await fixture.restart({ profiles: { ...profiles, ...variants } });
  await page.goto(fixture.running.url);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('button', { name: '筛选卡片', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: '筛选卡片', exact: true });
  await dialog.waitFor();
  const desktop = await dialog.boundingBox();
  assert.ok(desktop && desktop.width < 600 && desktop.height < 450, 'Collapsed filters fit a compact desktop dialog');
  const assignee = dialog.locator('details').filter({ hasText: '负责人' });
  const summary = assignee.locator('summary');
  const search = dialog.getByRole('searchbox', { name: '搜索负责人', exact: true });
  const options = dialog.getByRole('region', { name: '负责人选项', exact: true });
  async function wholeAssigneeRows() {
    await page.waitForFunction(id => {
      const list = document.getElementById(id);
      if (!list || list.scrollHeight <= list.clientHeight) return false;
      const { top, bottom } = list.getBoundingClientRect();
      const visible = [...list.children].map(option => option.getBoundingClientRect())
        .filter(row => row.bottom > top + 1 && row.top < bottom - 1);
      return visible.length > 1 && visible.every(row => row.top >= top - 1 && row.bottom <= bottom + 1);
    }, await options.getAttribute('id'));
  }
  await search.waitFor({ state: 'hidden' });
  await summary.press('Enter');
  await search.waitFor();
  await wholeAssigneeRows();
  await dialog.evaluate(node => {
    window.fixtureBoardResize = new Promise(resolve => {
      window.addEventListener('resize', () => {
        const { top, bottom, height } = node.getBoundingClientRect();
        const visibleTop = window.visualViewport?.offsetTop ?? 0;
        const visibleBottom = visibleTop + (window.visualViewport?.height ?? innerHeight);
        resolve({ top, bottom, height, visibleTop, visibleBottom });
      }, { once: true });
    });
  });
  await page.setViewportSize({ width: 760, height: 420 });
  const initial = await page.evaluate(() => window.fixtureBoardResize);
  assert.ok(initial.height > 0 && initial.top >= initial.visibleTop && initial.bottom <= initial.visibleBottom,
    `The first resized layout fits the visible viewport: ${JSON.stringify(initial)}`);
  await wholeAssigneeRows();
  const compact = await dialog.boundingBox();
  assert.ok(compact && compact.y >= 0 && compact.y + compact.height <= 420);
  await options.evaluate(list => list.scrollIntoView({ block: 'center' }));
  await options.hover();
  await page.mouse.wheel(0, 95);
  await page.waitForFunction(id => document.getElementById(id)?.scrollTop > 0, await options.getAttribute('id'));
  await wholeAssigneeRows();
  const rows = options.getByRole('checkbox');
  const last = rows.last();
  await search.focus();
  for (let index = 0, count = await rows.count(); index < count; index++) await page.keyboard.press('Tab');
  await page.waitForFunction(({ listId, optionId }) => {
    const list = document.getElementById(listId);
    const option = document.getElementById(optionId);
    if (!list || document.activeElement !== option || list.scrollTop <= 0) return false;
    const row = option.getBoundingClientRect(), bounds = list.getBoundingClientRect();
    const body = list.closest('[data-surface-role="dialog-body"]').getBoundingClientRect();
    return row.top >= Math.max(0, bounds.top, body.top) - 1
      && row.bottom <= Math.min(innerHeight, bounds.bottom, body.bottom) + 1;
  }, { listId: await options.getAttribute('id'), optionId: await last.getAttribute('id') });
  const worker = options.getByRole('checkbox', { name: 'review-worker-14-with-a-long-display-name', exact: true });
  await search.fill('WORKER-14');
  await worker.waitFor();
  assert.equal(await options.getByRole('checkbox').count(), 1);
  await search.press('Tab');
  await page.waitForFunction(id => document.activeElement?.id === id, await worker.getAttribute('id'));
  await page.keyboard.press('Space');
  await worker.and(page.locator('[aria-checked="true"]')).waitFor();
  await search.fill('does not match a model');
  assert.equal(await worker.getAttribute('aria-checked'), 'true');
  await summary.press('Enter');
  assert.equal(await summary.textContent(), '负责人 · 1');
  await summary.press('Enter');
  await worker.waitFor();
  await dialog.getByRole('button', { name: '清除筛选', exact: true }).click();
  await options.getByText('没有匹配的负责人。', { exact: true }).waitFor();
  await search.clear();
  for (const label of ['interactive-fixture', '未分配', '未分配项目']) {
    const choice = dialog.getByRole('checkbox', { name: label, exact: true });
    await choice.click();
    await choice.and(page.locator('[aria-checked="true"]')).waitFor();
    await choice.click();
    await choice.and(page.locator('[aria-checked="false"]')).waitFor();
  }
});

test('enabling board automation includes existing eligible cards and disabling preserves active conversations', async t => {
  const { page, command, running, requests, finish } = await browserFixture(t);
  await command({ op: 'board_settings', automatic: false, draft_profile: '' });
  const title = 'Run the existing priority card';
  const assigned = { assignee: 'profile/interactive' };
  const active = await command({ op: 'create_card', title, status: 'todo', priority: 'urgent', ...assigned });
  const waiting = await command({ op: 'create_card', title: 'Wait for the assigned model', status: 'in_progress', ...assigned });
  const planning = await command({ op: 'create_card', title: 'Keep the card in planning', status: 'backlog', ...assigned });
  const unassigned = await command({ op: 'create_card', title: 'Leave the card unassigned', status: 'todo' });
  const read = ({ card_id }) => command({ op: 'read_card', card_id });
  assert.equal((await read(active)).task_id, null);
  assert.equal(requests.length, 0);

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 620 });
  await page.getByRole('button', { name: '看板设置', exact: true }).click();
  const settings = page.getByRole('dialog', { name: '看板设置', exact: true });
  const guidance = settings.getByText('启用后，符合条件的现有卡片会自动排队。', { exact: true });
  await guidance.waitFor();
  const automation = settings.getByRole('switch', { name: '自动执行', exact: true });
  await automation.and(page.locator('[aria-checked="false"]')).waitFor();
  const noteBox = await guidance.boundingBox();
  const buttonBox = await automation.boundingBox();
  assert.ok(noteBox && buttonBox && noteBox.x >= 0 && noteBox.x + noteBox.width <= 390);
  assert.ok(noteBox.y + noteBox.height <= 620 && noteBox.x + noteBox.width <= buttonBox.x &&
    noteBox.y < buttonBox.y + buttonBox.height && buttonBox.y < noteBox.y + noteBox.height,
    'The guidance sits beside its switch at a compact width');
  assert.ok(buttonBox.width >= 44 && buttonBox.height >= 44, 'The switch has a touch-sized target');
  await automation.click();
  await automation.and(page.locator('[aria-checked="true"]')).waitFor();
  await settings.getByText(/正在运行的对话会继续/).waitFor();
  const deadline = Date.now() + 15000;
  while (!requests.length && Date.now() < deadline) await delay(10);
  assert.ok(JSON.stringify(requests[0]?.input)?.includes(title), 'The existing priority card must reach the model');
  const started = await read(active);
  assert.notEqual(started.task_id, null);
  assert.equal((await read(waiting)).activity, 'queued');
  assert.equal((await read(planning)).task_id, null);
  assert.equal((await read(unassigned)).task_id, null);

  await page.keyboard.press('Escape');
  await settings.waitFor({ state: 'hidden' });
  const queued = page.getByRole('article', { name: 'Wait for the assigned model', exact: true });
  await queued.getByText('排队中', { exact: true }).waitFor();
  await queued.getByRole('button', { name: '关联对话', exact: true }).waitFor();
  assert.equal(await queued.getByRole('button', { name: '打开对话', exact: true }).count(), 0);
  await page.getByRole('button', { name: '看板设置', exact: true }).click();
  await automation.press('Space');
  await automation.and(page.locator('[aria-checked="false"]')).waitFor();
  await guidance.waitFor();
  assert.equal(requests[0].closed, false);
  finish(0, { text: 'The existing card finished normally.' });
  await taskIdle(running.service, started.task_id);
  const after = await read(waiting);
  assert.equal(after.task_id, null);
  assert.equal(after.activity, 'not_started');
  assert.equal(requests.length, 1);
});

test('the archive opens near its desktop trigger and fits a compact viewport with card actions', async t => {
  const { page, command } = await browserFixture(t);
  await command({ op: 'board_settings', automatic: false, draft_profile: '' });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const trigger = page.getByRole('button', { name: '归档卡片', exact: true });
  const archive = page.getByRole('dialog', { name: '归档卡片', exact: true });
  const empty = archive.getByText('没有归档的卡片。', { exact: true });
  const triggerBox = await trigger.boundingBox();
  await trigger.click();
  await empty.waitFor();
  const desktop = await archive.boundingBox();
  assert.ok(triggerBox && desktop && Math.abs(desktop.y - triggerBox.y - triggerBox.height) <= 20 &&
    Math.abs(desktop.x + desktop.width - triggerBox.x - triggerBox.width) <= 20,
    'The empty archive opens immediately below the desktop trigger');
  assert.equal(await archive.evaluate(dialog => getComputedStyle(dialog, '::backdrop').backgroundColor), 'rgba(0, 0, 0, 0)');
  await page.keyboard.press('Escape');
  await archive.waitFor({ state: 'hidden' });
  await page.waitForFunction(id => document.activeElement?.id === id, await trigger.getAttribute('id'));

  const title = 'Archived card for layout';
  const { card_id } = await command({ op: 'create_card', title, status: 'todo' });
  const read = () => command({ op: 'read_card', card_id });
  const { revision } = await read();
  await command({ op: 'archive_card', card_id, revision });
  await trigger.click();
  const card = archive.getByRole('article', { name: title, exact: true });
  await card.waitFor();

  await page.setViewportSize({ width: 390, height: 520 });
  await card.waitFor();
  await page.locator('dialog[data-semantic-key="archived-cards"]:not([data-native-layer])').waitFor();
  const compact = await archive.boundingBox();
  assert.ok(compact && compact.x >= 0 && compact.y >= 0 &&
    compact.x + compact.width <= 390 && compact.y + compact.height <= 520);
  await card.getByRole('button', { name: '卡片操作', exact: true }).click();
  const actions = page.getByRole('menu', { name: '卡片操作', exact: true });
  const restore = actions.getByRole('button', { name: '恢复卡片', exact: true });
  await restore.waitFor();
  assert.deepEqual(await actions.getByRole('button').evaluateAll(buttons =>
    buttons.map(button => button.getAttribute('aria-label'))), ['恢复卡片', '删除卡片']);
  await restore.click();
  await empty.waitFor();
  assert.equal((await read()).archived, false);
});

test('new card text checks guide the relevant field in Chinese', async t => {
  const { page, command } = await browserFixture(t);
  await page.setViewportSize({ width: 1280, height: 720 });
  await command({ op: 'board_settings', automatic: false, draft_profile: 'interactive' });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('button', { name: '新建卡片', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const title = dialog.getByRole('textbox', { name: '标题', exact: true });
  const description = dialog.getByRole('textbox', { name: '描述', exact: true });
  const create = dialog.getByRole('button', { name: '创建卡片', exact: true });
  async function reason(message) {
    const alert = dialog.getByRole('alert').filter({ hasText: message });
    await alert.waitFor();
    await dialog.locator('[data-semantic-key="editor-commit-reason"]').waitFor({ state: 'hidden' });
    assert.equal(await alert.count(), 1);
    assert.equal(await create.isEnabled(), false);
    const [field, help, body] = await Promise.all([
      title.boundingBox(), alert.boundingBox(), dialog.locator('[data-surface-role="dialog-body"]').boundingBox(),
    ]);
    assert.ok(field && help && body && help.y >= field.y + field.height - 1 &&
      help.y - field.y - field.height < 24 && help.y + help.height <= body.y + body.height,
    'The validation appears beside the title, inside the editor body');
  }
  const ready = async () => page.waitForFunction(id => {
    const button = document.getElementById(id);
    return button && !button.disabled && button.getAttribute('aria-disabled') !== 'true';
  }, await create.getAttribute('id'));
  async function missingTitle(prompt) {
    await dialog.getByRole('alert').waitFor({ state: 'hidden' });
    await dialog.locator('[data-semantic-key="editor-commit-reason"]').waitFor({ state: 'hidden' });
    await page.waitForFunction(({ id, prompt }) => document.getElementById(id)?.title === prompt,
      { id: await create.getAttribute('id'), prompt });
    assert.equal(await create.isDisabled(), true);
  }
  await missingTitle('请输入标题。');
  assert.equal(await title.getAttribute('placeholder'), '请输入标题');
  assert.equal(await description.getAttribute('placeholder'), null);
  await title.fill('\u3000 ');
  await missingTitle('请输入标题。');

  await description.fill('Use this description as the source');
  await dialog.getByText('更多卡片选项', { exact: true }).click();
  await missingTitle('请输入标题。');
  await page.waitForFunction(() => {
    const dialog = document.querySelector('dialog[open]');
    const body = dialog?.querySelector('[data-surface-role="dialog-body"]');
    const bounds = dialog?.getBoundingClientRect();
    return body && bounds && bounds.height < innerHeight - 48 && body.scrollHeight <= body.clientHeight + 1;
  });
  const assisted = dialog.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  await assisted.check();
  await ready();
  await description.clear();
  await missingTitle('请输入标题或描述。');

  await assisted.uncheck();
  await title.fill('长'.repeat(667));
  await reason('标题太长，请缩短。');
  await title.clear();
  await missingTitle('请输入标题。');
  await title.fill('Ready to save');
  await ready();
  await create.click();
  await dialog.waitFor({ state: 'hidden' });
  await page.getByRole('article', { name: 'Ready to save', exact: true }).waitFor();
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
    await profile.waitFor({ state: 'hidden' });
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
  for (const state of ['hidden', 'visible']) {
    await assisted.press('Space');
    await profile.waitFor({ state });
    assert.equal(await assisted.evaluate(node => document.activeElement === node), true);
  }
  assert.equal(await profile.inputValue(), replacement.key);
  await page.waitForFunction(() => {
    const submit = document.querySelector('dialog[open] button[data-semantic-key="submit"]');
    return submit && !submit.disabled && submit.getAttribute('aria-disabled') !== 'true';
  });
  await refresh(['image-fixture']);
  await blocked('所选整理模型不可用，请重新选择。');
  assert.ok((await profile.locator('option').allTextContents()).includes('看板默认模型'));
  await assisted.uncheck();
  await profile.waitFor({ state: 'hidden' });
  await create.click();
  await dialog.waitFor({ state: 'hidden' });
  assert.ok((await command({ op: 'list_cards' })).cards.some(card => card.title === 'Preserve this card draft'));
  assert.deepEqual(requests, ['image-fixture']);

  await refresh(['replacement-fixture']);
  await page.getByRole('button', { name: '看板设置', exact: true }).click();
  const settingsProfile = page.getByRole('combobox', { name: '默认整理模型', exact: true });
  await settingsProfile.locator('option:checked').filter({ hasText: '请选择模型' }).waitFor({ state: 'attached' });
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
  const optionFields = ['状态', '优先级', '负责人', '所属项目']
    .map(name => first.getByRole('combobox', { name, exact: true }));
  await page.waitForFunction(ids => {
    const boxes = ids.map(id => document.getElementById(id)?.getBoundingClientRect());
    const beside = (first, second) => first && second && Math.abs(first.y - second.y) <= 1 && first.right <= second.left;
    return beside(boxes[0], boxes[1]) && beside(boxes[2], boxes[3]);
  }, await Promise.all(optionFields.map(field => field.getAttribute('id'))));
  const upload = first.locator('input[type="file"]').and(first.getByLabel('添加附件', { exact: true }));
  const labels = first.getByRole('textbox', { name: '标签', exact: true });
  await labels.fill('发布\n体验走查');
  assert.equal(await labels.inputValue(), '发布\n体验走查');
  assert.ok(await labels.evaluate(input => {
    const style = getComputedStyle(input);
    return input.clientHeight - parseFloat(style.paddingBlockStart) - parseFloat(style.paddingBlockEnd)
      >= 3 * parseFloat(style.lineHeight) - 1;
  }), 'The label editor has three visible lines');
  assert.ok(await upload.evaluate(input => {
    const control = input.closest('label');
    const icon = control.querySelector('svg').getBoundingClientRect();
    const text = Array.from(control.childNodes).find(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim());
    const range = document.createRange();
    range.selectNodeContents(text);
    const label = range.getBoundingClientRect();
    return label.left >= icon.right && label.left - icon.right < 12
      && icon.top < label.bottom && label.top < icon.bottom;
  }), 'The attachment label and paperclip are in one adjacent control');
  assert.ok(await upload.evaluate(input => {
    const dialog = input.closest('dialog');
    const attachment = input.closest('label').getBoundingClientRect();
    const description = dialog.querySelector('textarea[data-semantic-key="description"]').getBoundingClientRect();
    const options = dialog.querySelector('[data-semantic-key="card-options"] > summary').getBoundingClientRect();
    return attachment.top >= description.bottom && attachment.top - description.bottom <= 12 &&
      attachment.bottom <= options.top;
  }), 'Attachments follow the description, above the options');
  const drafting = first.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  const continuous = first.getByRole('checkbox', { name: '创建后继续添加', exact: true });
  const [captureBox, draftingBox] = await Promise.all([continuous, drafting].map(checkbox => checkbox.evaluate(input => {
    const control = input.closest('[data-control-target="checkbox"]').getBoundingClientRect();
    const text = input.closest('label').querySelector(':scope > span:not([data-control-target])').getBoundingClientRect();
    return { left: control.left, beforeLabel: control.right <= text.left && control.top < text.bottom && text.top < control.bottom };
  })));
  assert.ok(captureBox.beforeLabel && draftingBox.beforeLabel && Math.abs(captureBox.left - draftingBox.left) <= 1,
    'Card creation checkbox targets share a left edge before their labels');
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
  assert.deepEqual(saved.labels, ['发布', '体验走查']);

  const card = page.getByRole('article', { name: title, exact: true });
  await card.getByRole('button', { name: '卡片操作', exact: true }).click();
  await page.getByRole('button', { name: '编辑卡片', exact: true }).click();
  const edit = page.getByRole('dialog', { name: '编辑卡片', exact: true });
  await edit.getByText('更多卡片选项', { exact: true }).click();
  const editLabels = edit.getByRole('textbox', { name: '标签', exact: true });
  assert.equal(await editLabels.inputValue(), '发布\n体验走查');
  await editLabels.fill('体验走查\n已复核');
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
  assert.deepEqual(active.labels, ['体验走查', '已复核']);
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

test('the mobile card editor keeps real repairs visible and missing model choice neutral', async t => {
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
  const reasonText = '请选择整理用的模型。';
  const reason = footer.locator('[data-semantic-key="editor-commit-reason"]');
  const titleError = '标题太长，请缩短。';
  const titleReason = body.getByRole('alert').filter({ hasText: titleError });
  await title.fill('长'.repeat(667));
  await titleReason.waitFor();
  await reason.waitFor({ state: 'hidden' });
  const options = dialog.getByText('更多卡片选项', { exact: true });
  await options.click();
  await body.evaluate(node => { node.scrollTop = node.scrollHeight; });
  await reason.filter({ hasText: titleError }).waitFor();
  await titleReason.waitFor({ state: 'hidden' });
  await description.focus();
  await page.keyboard.press('Shift+Tab');
  assert.equal(await title.evaluate(element => element === document.activeElement), true);
  await body.evaluate(node => { node.scrollTop = 0; });
  await titleReason.waitFor();
  await reason.waitFor({ state: 'hidden' });
  await title.fill('A card with a long description');
  await titleReason.waitFor({ state: 'hidden' });

  await options.click();
  const stage = dialog.getByRole('combobox', { name: '状态', exact: true });
  await stage.waitFor({ state: 'hidden' });
  await description.fill('Review this step and keep the details in the card.\n'.repeat(18));
  const assisted = dialog.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true });
  const model = dialog.getByRole('combobox', { name: '整理用的模型', exact: true });
  await model.waitFor({ state: 'hidden' });
  await assisted.check();
  const submitId = await submit.getAttribute('id');
  async function needsModel() {
    await page.waitForFunction(({ submitId, reasonText }) => {
      const button = document.getElementById(submitId);
      return button?.getAttribute('aria-disabled') === 'true' &&
        (button.getAttribute('aria-describedby') ?? '').split(/\s+/)
          .some(id => document.getElementById(id)?.textContent === reasonText);
    }, { submitId, reasonText });
    assert.equal(await dialog.getByRole('alert').count(), 0);
    await reason.waitFor({ state: 'hidden' });
  }
  await model.scrollIntoViewIfNeeded();
  assert.equal(await model.locator('option:checked').textContent(), '请选择模型');
  const [textBox, toggleBox, modelBox, optionsBox] = await Promise.all(
    [description, assisted, model, options].map(control => control.boundingBox()));
  assert.ok(textBox && toggleBox && modelBox && optionsBox &&
    textBox.y + textBox.height <= toggleBox.y &&
    toggleBox.y + toggleBox.height <= modelBox.y && modelBox.y + modelBox.height <= optionsBox.y);
  await needsModel();
  await title.press('Enter');
  await needsModel();
  assert.deepEqual((await command({ op: 'list_cards' })).cards, []);

  await title.focus();
  await page.keyboard.press('Tab');
  const focused = locator => locator.evaluate(element => element === document.activeElement);
  assert.equal(await focused(description), true);
  for (let index = 0; index < 4 && !(await focused(model)); index++) await page.keyboard.press('Tab');
  assert.equal(await focused(model), true, 'Tab reaches the required model selector');
  await page.keyboard.press('i');
  assert.equal(await model.inputValue(), 'interactive');
  await reason.waitFor({ state: 'hidden' });
  await footer.getByText('保存后先生成卡片内容，暂不启动对话。', { exact: true }).waitFor();
  assert.equal(await submit.isEnabled(), true);
  const disclosure = dialog.locator('summary').filter({ hasText: '更多卡片选项' });
  await page.keyboard.press('Tab');
  assert.equal(await focused(disclosure), true, 'Tab reaches the collapsed disclosure heading');
  await page.keyboard.press('Tab');
  assert.equal(await focused(footer.getByRole('button', { name: '取消', exact: true })), true,
    'Tab skips fields in the closed disclosure');
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

test('the card action menu keeps positions while service assessments settle', async t => {
  const { page, command } = await browserFixture(t);
  await command({ op: 'board_settings', automatic: false, draft_profile: '' });
  const title = 'A model-assigned card';
  await command({ op: 'create_card', title, assignee: 'profile/interactive' });
  const archiveCheck = Promise.withResolvers();
  const otherChecks = Promise.withResolvers();
  await page.route('**/api/assess', async route => {
    const owner = route.request().postDataJSON()?.editor;
    if (owner?.kind !== 'menu') return route.continue();
    const response = await route.fetch();
    await (owner.action === 'archive' ? archiveCheck.promise : otherChecks.promise);
    await route.fulfill({ response });
  });
  const menu = page.getByRole('menu', { name: '卡片操作', exact: true });
  const action = name => menu.getByRole('button', { name, exact: true });
  const rows = () => menu.getByRole('button').evaluateAll(buttons => buttons.map(button => {
    const label = button.querySelector('span:not([aria-hidden], .visually-hidden)');
    return { id: button.id, name: button.getAttribute('aria-label'), reason: button.title,
      disabled: button.disabled || button.getAttribute('aria-disabled') === 'true',
      y: button.getBoundingClientRect().y, labelX: label?.getBoundingClientRect().x };
  }));
  const order = ['移动卡片', '编辑卡片', '启动对话', '归档卡片', '置顶卡片', '删除卡片'];
  let opening;
  function assertMenu(current, available) {
    assert.deepEqual(current.map(({ name }) => name), order);
    assert.deepEqual(current.filter(row => !row.disabled).map(({ name }) => name), available);
    assert.deepEqual(current.map(({ id }) => id), opening.map(({ id }) => id));
    assert.ok(current.every((row, index) => Math.abs(row.y - opening[index].y) <= 1),
      'Permission results leave each action at the same screen position');
    assert.ok(current.every(row => row.labelX !== undefined && Math.abs(row.labelX - current[0].labelX) <= 1),
      'The visible card action labels start at the same horizontal position');
  }
  try {
    await page.getByRole('navigation', { name: 'Global navigation', exact: true })
      .getByRole('button', { name: '卡片看板', exact: true }).click();
    await page.getByRole('article', { name: title, exact: true })
      .getByRole('button', { name: '卡片操作', exact: true }).click();
    await action('启动对话').waitFor();
    opening = await rows();
    assertMenu(opening, ['移动卡片', '编辑卡片']);
    assert.ok(opening.every((row, index) => index === 0 || row.y > opening[index - 1].y),
      'Visual order follows the declared action order');
    await action('编辑卡片').focus();
    archiveCheck.resolve();
    await action('归档卡片').and(page.locator(':not([aria-disabled="true"])')).waitFor();
    const partial = await rows();
    assertMenu(partial, ['移动卡片', '编辑卡片', '归档卡片']);
    assert.equal(partial.find(row => row.name === '启动对话').reason, '正在检查');
    assert.equal(await action('编辑卡片').evaluate(button => document.activeElement === button), true);
  } finally {
    archiveCheck.resolve();
    otherChecks.resolve();
  }
  for (const name of ['启动对话', '置顶卡片', '删除卡片'])
    await action(name).and(page.locator(':not([aria-disabled="true"])')).waitFor();
  assertMenu(await rows(), order);
  await action('移动卡片').click();
  await page.getByRole('dialog', { name: '移动卡片', exact: true }).waitFor();
});

test('the board keeps empty stages visible and counts only matching cards linked to executing conversations', async t => {
  const { page, browser, command } = await browserFixture(t);
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const board = page.locator('[data-page-region="board-stages"]');
  for (const viewport of [{ width: 1280, height: 900 }, { width: 760, height: 500 }, { width: 390, height: 620 }]) {
    await page.setViewportSize(viewport);
    await page.waitForFunction(() => {
      const scrollport = document.querySelector('[data-page-region="board-stages"]');
      const stages = [...(scrollport?.querySelectorAll('[data-board-stage]') ?? [])];
      if (stages.length !== 6 || scrollport.scrollWidth > scrollport.clientWidth) return false;
      const bounds = scrollport.getBoundingClientRect();
      return stages.every(stage => {
        const { top, height, width } = stage.getBoundingClientRect();
        return top >= bounds.top - 1 && height <= 80 && width >= Math.min(200, scrollport.clientWidth) - 1;
      });
    });
    await board.getByRole('region', { name: '已完成，0 张卡片', exact: true }).waitFor();
    await board.getByRole('region', { name: '已阻塞，0 张卡片', exact: true }).waitFor();
  }

  await page.setViewportSize({ width: 1280, height: 900 });
  const message = 'Link an executing conversation';
  const { task_id } = await command({ op: 'create', profile: 'interactive', message });
  const { task } = await command({ op: 'read', task_id });
  const nav = page.getByRole('navigation', { name: 'Task tree', exact: true });
  await nav.locator(`[data-task-id="${task_id}"]`).getByRole('img', { name: '运行中', exact: true }).waitFor();
  await page.getByRole('radio', { name: '执行中的卡片 0', exact: true }).waitFor();

  const title = 'Plan the release';
  const { card_id } = await command({ op: 'create_card', title });
  const card = board.getByRole('article', { name: title, exact: true });
  await card.waitFor();
  const tracks = await board.locator('[data-board-stage]').evaluateAll(stages =>
    stages.map(stage => ({ top: stage.getBoundingClientRect().top, bottom: stage.getBoundingClientRect().bottom })));
  const firstRow = tracks.filter(track => Math.abs(track.top - tracks[0].top) < 1);
  assert.ok(firstRow.length > 1 && tracks[0].bottom - tracks[0].top > 80
    && firstRow.every(track => Math.abs(track.bottom - tracks[0].bottom) < 1),
    'Empty stages have the same track extent as a populated neighbor');
  const completed = board.locator('[data-board-stage="done"]');
  await card.locator('[data-card-grip]').dragTo(completed);
  await completed.getByRole('article', { name: title, exact: true }).waitFor();
  await card.getByRole('button', { name: '卡片操作', exact: true }).click();
  await page.getByRole('dialog', { name: '卡片操作', exact: true })
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

  await assertConversationActivity(card, '工作中');
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

  // The card can still reference a conversation omitted by the current
  // observation. Keep the disabled link without a stale running label.
  const limitedObservation = await browser.newPage({ viewport: page.viewportSize() });
  limitedObservation.setDefaultTimeout(10000);
  await limitedObservation.route('**/api/browser/state', async route => {
    const response = await route.fetch();
    const snapshot = await response.json();
    snapshot.program.tasks = snapshot.program.tasks.filter(task => String(task.id) !== String(task_id));
    await route.fulfill({ response, json: snapshot });
  });
  await limitedObservation.goto(page.url());
  await limitedObservation.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await limitedObservation.getByRole('radio', { name: '全部卡片', exact: true }).click();
  const observedCard = limitedObservation.getByRole('article', { name: title, exact: true });
  const unavailable = observedCard.getByRole('button', { name: '打开对话', exact: true });
  await unavailable.and(limitedObservation.locator('[aria-disabled="true"]')).waitFor();
  assert.equal(await unavailable.getAttribute('title'), '关联的对话不可用');
  assert.equal(await observedCard.getByText('工作中', { exact: true }).count(), 0);
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
  const actions = main.getByRole('button', { name: '对话操作', exact: true });
  await actions.click();
  await page.getByRole('button', { name: '添加到看板', exact: true }).click();

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
  const linkedCard = page.getByRole('menu', { name: '对话操作', exact: true })
    .getByRole('button', { name: '打开关联卡片', exact: true });
  await linkedCard.waitFor();
  assert.equal(await linkedCard.locator('svg').count(), 1);
  await linkedCard.click();
  const details = page.getByRole('dialog', { name: '卡片详情', exact: true });
  await details.getByText(title, { exact: true }).waitFor();
  assert.equal(await page.getByRole('button', { name: '添加到看板', exact: true }).count(), 0);

  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  const review = main.locator('[data-board-stage="in_review"]');
  const reviewCard = review.getByRole('article', { name: title, exact: true });
  const completed = reviewCard.getByText('对话已完成', { exact: true });
  await assertConversationActivity(reviewCard, '对话已完成');
  const heading = reviewCard.getByText(title, { exact: true });
  const reference = reviewCard.getByText(cards[0].identifier, { exact: true });
  const updated = reviewCard.getByText(/^(刚刚|\d+分钟前)$/u);
  const [headingBounds, referenceBounds, activityBounds, updateBounds] = await Promise.all(
    [heading, reference, completed, updated].map(element => element.boundingBox()));
  assert.ok(headingBounds && referenceBounds && activityBounds && updateBounds);
  assert.ok(headingBounds.y < referenceBounds.y && headingBounds.y < activityBounds.y,
    'The card title is above the secondary ID and the separate conversation status');
  assert.ok(Math.abs(referenceBounds.y - updateBounds.y) <= 1 && updateBounds.x > referenceBounds.x,
    'The card reference and update time share one metadata line');
  for (const absent of ['无', '未分配']) {
    assert.equal(await reviewCard.getByText(absent, { exact: true }).count(), 0);
  }
  await reviewCard.locator('[data-card-grip]').waitFor();
  await reviewCard.getByRole('button', { name: '卡片操作', exact: true }).waitFor();
  await reviewCard.getByRole('button', { name: '卡片操作', exact: true }).click();
  const cardActions = page.getByRole('menu', { name: '卡片操作', exact: true });
  await cardActions.getByRole('button', { name: '编辑卡片', exact: true }).waitFor();
  assert.equal(await cardActions.getByRole('button', { name: '启动对话', exact: true }).count(), 0);
  await page.keyboard.press('Escape');
  await cardActions.waitFor({ state: 'hidden' });
  const titleAction = reviewCard.getByRole('button', { name: `打开 ${title}`, exact: true });
  await titleAction.press('Enter');
  await details.getByText(title, { exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await details.waitFor({ state: 'hidden' });
  assert.equal(await titleAction.evaluate(button => button === document.activeElement), true);
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

  const { task_id: idle } = await command({ op: 'create_idle', profile: 'demo' });
  const idleTitle = 'Prepared conversation';
  await command({ op: 'create_card', title: idleTitle, task_id: idle, assignee: 'self', priority: 'high' });
  const idleCard = review.getByRole('article', { name: idleTitle, exact: true });
  await assertConversationActivity(idleCard, '对话已就绪');
  await idleCard.getByText('我', { exact: true }).waitFor();
  await idleCard.getByText('高', { exact: true }).waitFor();
  assert.equal(await idleCard.getByText('对话已完成', { exact: true }).count(), 0);
  await page.setViewportSize({ width: 390, height: 620 });
  await assertConversationActivity(reviewCard, '对话已完成');
});

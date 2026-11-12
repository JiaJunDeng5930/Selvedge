import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';

async function observed(predicate, explanation) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const value = predicate();
    if (value) return value;
    await delay(10);
  }
  throw new Error(explanation);
}

test('new Task permissions remain reachable with ordinary pointer clicks', async t => {
  for (const viewport of [{ width: 1280, height: 900 }, { width: 390, height: 700 }]) {
    await t.test(`${viewport.width} by ${viewport.height}`, async t => {
      const { page } = await browserFixture(t);
      await page.setViewportSize(viewport);
      await page.getByRole('button', { name: /^权限:/ }).click();
      const permissions = page.getByRole('dialog', { name: '权限', exact: true });
      await permissions.getByRole('button', { name: '自定义权限…', exact: true }).click();
      for (const name of ['审批方式', '文件系统权限', '联网权限']) {
        await permissions.getByRole('button', { name, exact: true }).click({ trial: true });
      }
      await permissions.getByRole('button', { name: '返回', exact: true }).click();
      for (const name of ['询问审批', '自动审批', '完全访问']) {
        await permissions.getByRole('menuitemradio', { name, exact: true }).click({ trial: true });
      }

    });
  }
});

test('conversation and board controls distinguish same-name configurations and exclude the review-only model', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, upstream, command } = fixture;
  const delegate = upstream.options.respond;
  const requests = [];
  const fixedAstra = 'gpt-6-astra · Fixed effort';
  const adaptiveAstra = 'gpt-6-astra · Adaptive effort';
  const models = ['image-fixture', 'gpt-6-astra', 'codex-auto-review'].map(slug => ({
    slug, display_name: slug, visibility: 'list', context_window: 128000,
    effective_context_window_percent: 100, default_reasoning_level: 'medium',
    supported_reasoning_levels: [{ effort: 'medium' }],
  }));
  upstream.options.respond = async (entry, response) => {
    if (new URL(entry.url, upstream.address).pathname === '/v1/models') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ models }));
      return;
    }
    if (!entry.url.endsWith('/input_tokens') && entry.body.text?.format?.name !== 'task_title') requests.push(entry.body);
    const schema = entry.body.text?.format?.schema;
    if (schema?.properties?.title && schema?.properties?.description) {
      const output = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text',
        text: JSON.stringify({ title: 'A readable assisted card', description: 'Plan the reviewed workflow.' }) }] }];
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\n\n`);
      return;
    }
    return delegate(entry, response);
  };
  const refresh = await fetch(`${fixture.running.address}/api/accounts/refresh`, {
    method: 'POST', headers: { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' }, body: '{}',
  });
  assert.equal(refresh.status, 200);
  const catalog = await refresh.json();
  assert.equal(catalog.ok, true, JSON.stringify(catalog));
  assert.ok(catalog.result.profiles.some(profile => profile.name === 'codex-auto-review'),
    'The connected catalog must contain the dedicated profile before testing its exclusion');
  const astraProfiles = catalog.result.profiles.filter(profile => profile.name === 'gpt-6-astra');
  assert.equal(astraProfiles.length, 2);
  const fixed = astraProfiles.find(profile => !profile.adaptive_reasoning);
  const adaptive = astraProfiles.find(profile => profile.adaptive_reasoning);
  assert.ok(fixed?.key);
  assert.ok(adaptive?.key);
  await page.reload();
  await page.getByRole('button', { name: /^Model:/ }).click();
  const picker = page.getByRole('dialog', { name: 'Model', exact: true });
  const summary = picker.getByRole('button', { name: /^Choose model:/ });
  const ordinaryModel = picker.getByRole('menuitemradio', { name: 'image-fixture', exact: true });
  await Promise.any([summary.waitFor(), ordinaryModel.waitFor()]);
  if (await summary.isVisible()) await summary.click();
  await ordinaryModel.waitFor();
  for (const label of [fixedAstra, adaptiveAstra]) {
    assert.equal(await picker.getByRole('menuitemradio', { name: label, exact: true }).count(), 1, label);
  }
  for (const label of ['gpt-6-astra', 'codex-auto-review']) {
    assert.equal(await picker.getByRole('menuitemradio', { name: label, exact: true }).count(), 0, label);
  }
  await ordinaryModel.click();
  await page.keyboard.press('Escape');
  await picker.waitFor({ state: 'hidden' });
  await page.getByRole('combobox', { name: 'Task', exact: true }).fill('Run the ordinary reviewed task.');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const ordinary = await observed(() => requests.find(request => JSON.stringify(request.input).includes('Run the ordinary reviewed task.')),
    'The ordinary Task must reach the actual provider HTTP boundary');
  assert.equal(ordinary.model, 'image-fixture');

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();
  await page.getByRole('button', { name: '看板设置', exact: true }).click();
  const draftModels = page.getByRole('combobox', { name: '草稿模型', exact: true });
  const draftNames = await draftModels.locator('option').allTextContents();
  for (const label of ['image-fixture', 'gpt-6-astra']) assert.ok(draftNames.includes(label), label);
  for (const label of [fixedAstra, adaptiveAstra, 'codex-auto-review']) assert.ok(!draftNames.includes(label), label);
  assert.equal(await draftModels.locator('option').filter({ hasText: 'gpt-6-astra' }).getAttribute('value'), fixed.key);
  await page.keyboard.press('Escape');
  await page.getByRole('main').getByRole('button', { name: '新建卡片', exact: true }).first().click();
  const card = page.getByRole('dialog');
  await card.getByRole('textbox', { name: '标题', exact: true }).waitFor();
  const assistance = card.getByRole('combobox', { name: '整理用的模型', exact: true });
  assert.equal(await assistance.isVisible(), false);
  await card.getByText('更多卡片选项', { exact: true }).click();
  const assistanceNames = await assistance.locator('option').allTextContents();
  for (const label of ['image-fixture', 'gpt-6-astra']) assert.ok(assistanceNames.includes(label), label);
  for (const label of [fixedAstra, adaptiveAstra, 'codex-auto-review']) assert.ok(!assistanceNames.includes(label), label);
  assert.equal(await assistance.locator('option').filter({ hasText: 'gpt-6-astra' }).getAttribute('value'), fixed.key);
  const assignee = card.getByRole('combobox', { name: '负责人', exact: true });
  const assigneeNames = await assignee.locator('option').allTextContents();
  for (const label of ['image-fixture', fixedAstra, adaptiveAstra]) assert.ok(assigneeNames.includes(label), label);
  await assignee.selectOption({ label: adaptiveAstra });
  await card.getByRole('textbox', { name: '描述', exact: true }).fill('Plan the reviewed workflow.');
  await card.getByRole('checkbox', { name: '用模型整理标题和描述', exact: true }).check();
  await assistance.selectOption({ label: 'image-fixture' });
  const creation = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === 'create_card');
  await card.getByRole('button', { name: '创建卡片', exact: true }).click();
  const { reply } = await (await creation).json();
  assert.ok(reply.ok, JSON.stringify(reply));
  const persisted = await command({ op: 'read_card', card_id: reply.result.card_id });
  assert.equal(persisted.assignee, `profile/${adaptive.key}`);
  const created = page.getByRole('article', { name: 'A readable assisted card', exact: true });
  await created.getByText(adaptiveAstra, { exact: true }).waitFor();
  const assisted = await observed(() => requests.find(request => request.text?.format?.schema?.properties?.description),
    'Card assistance must reach its ordinary provider');
  assert.equal(assisted.model, 'image-fixture');
  assert.ok(requests.every(request => request.model !== 'codex-auto-review'));
  await page.getByRole('button', { name: '筛选卡片', exact: true }).click();
  const filters = page.getByRole('dialog').last();
  const adaptiveFilter = filters.getByRole('checkbox', { name: adaptiveAstra, exact: true });
  const fixedFilter = filters.getByRole('checkbox', { name: fixedAstra, exact: true });
  await adaptiveFilter.click();
  assert.equal(await adaptiveFilter.getAttribute('aria-checked'), 'true');
  await created.waitFor();
  await adaptiveFilter.click();
  await fixedFilter.click();
  assert.equal(await fixedFilter.getAttribute('aria-checked'), 'true');
  await created.waitFor({ state: 'hidden' });
});

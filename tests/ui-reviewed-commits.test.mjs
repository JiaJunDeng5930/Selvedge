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
      await page.getByRole('button', { name: 'Permissions', exact: true }).click();
      const permissions = page.getByRole('dialog', { name: 'Permissions', exact: true });
      await permissions.getByRole('button', { name: 'Custom permissions…', exact: true }).click();
      for (const name of ['Execution policy', 'Filesystem access', 'Network access']) {
        await permissions.getByRole('button', { name, exact: true }).click({ trial: true });
      }
      await permissions.getByRole('button', { name: 'Back', exact: true }).click();
      for (const name of ['Ask for approval', 'Automatic review', 'Unrestricted']) {
        await permissions.getByRole('radio', { name, exact: true }).click({ trial: true });
      }

    });
  }
});

test('ordinary Task and Board assistance choices exclude the auto-review-only profile', async t => {
  const fixture = await browserFixture(t, { images: true });
  const { page, upstream } = fixture;
  const delegate = upstream.options.respond;
  const requests = [];
  const models = ['image-fixture', 'codex-auto-review'].map(slug => ({
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
  await page.reload();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  assert.equal(await page.getByRole('radio', { name: 'codex-auto-review', exact: true }).count(), 0);
  await page.getByRole('radio', { name: 'image-fixture', exact: true }).click();
  await page.getByRole('textbox', { name: 'Task', exact: true }).fill('Run the ordinary reviewed task.');
  await page.getByRole('button', { name: 'Start task', exact: true }).click();
  const ordinary = await observed(() => requests.find(request => JSON.stringify(request.input).includes('Run the ordinary reviewed task.')),
    'The ordinary Task must reach the actual provider HTTP boundary');
  assert.equal(ordinary.model, 'image-fixture');

  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '任务看板', exact: true }).click();
  await page.getByRole('button', { name: '看板设置', exact: true }).click();
  const draftModels = page.getByRole('combobox', { name: '草稿模型', exact: true });
  const draftNames = await draftModels.locator('option').allTextContents();
  assert.ok(draftNames.includes('image-fixture'));
  assert.ok(!draftNames.includes('codex-auto-review'));
  await page.keyboard.press('Escape');
  await page.getByRole('main').getByRole('button', { name: '新建任务', exact: true }).first().click();
  const card = page.getByRole('dialog');
  const assistance = card.getByRole('combobox', { name: 'Assistance model', exact: true });
  const assistanceNames = await assistance.locator('option').allTextContents();
  assert.ok(assistanceNames.includes('image-fixture'));
  assert.ok(!assistanceNames.includes('codex-auto-review'));
  await card.getByRole('textbox', { name: 'Description', exact: true }).fill('Plan the reviewed workflow.');
  await card.getByRole('checkbox', { name: 'Assist with title and description', exact: true }).check();
  await assistance.selectOption({ label: 'image-fixture' });
  await card.getByRole('button', { name: 'Create card', exact: true }).click();
  await page.getByText('A readable assisted card', { exact: true }).waitFor();
  const assisted = await observed(() => requests.find(request => request.text?.format?.schema?.properties?.description),
    'Card assistance must reach its ordinary provider');
  assert.equal(assisted.model, 'image-fixture');
  assert.ok(requests.every(request => request.model !== 'codex-auto-review'));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function selectTask(fixture, taskId) {
  const { task } = await fixture.command({ op: 'read', task_id: taskId });
  await fixture.page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  await fixture.page.getByRole('combobox', { name: 'Message', exact: true }).waitFor();
  return task;
}

async function publicCommand(running, command) {
  const response = await fetch(`${running.address}/api/commands`, {
    method: 'POST', headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    body: JSON.stringify(command),
  });
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  assert.equal(body.ok, true, JSON.stringify(body));
  return body.result;
}

function overlapsVertically(a, b) {
  return Math.min(a.y + a.height, b.y + b.height) > Math.max(a.y, b.y);
}

// The observable is the space returned to the conversation, rather than a particular grid or CSS class.
test('conversation navigation releases desktop space and preserves the draft through drawer navigation', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  await page.setViewportSize({ width: 1024, height: 900 });
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  const task = await selectTask(fixture, task_id);
  const main = page.getByRole('main');
  const message = page.getByRole('combobox', { name: 'Message', exact: true });
  assert.equal(await message.getAttribute('placeholder'), 'Ask anything, or describe a task');
  const title = main.getByText(task.title, { exact: true }).first();
  const details = main.getByRole('button', { name: 'Task details', exact: true });
  const [titleBounds, actionBounds, expanded] = await Promise.all([
    title.boundingBox(), details.boundingBox(), main.boundingBox(),
  ]);
  assert.ok(overlapsVertically(titleBounds, actionBounds), 'The conversation title and actions share their heading row');
  await message.fill('Keep this draft while changing navigation capacity.');
  await page.getByRole('button', { name: /Collapse.*(?:Task|sidebar)/ }).click();
  const expand = page.getByRole('button', { name: /Expand.*(?:Task|sidebar)/ });
  await expand.waitFor();
  const collapsed = await main.boundingBox();
  assert.ok(collapsed.width > expanded.width + 100,
    `Collapsing the sidebar must return its column to the conversation (${expanded.width} to ${collapsed.width})`);
  assert.equal(await page.getByRole('navigation', { name: 'Task tree', exact: true }).isVisible(), false);
  await expand.click();
  await page.getByRole('navigation', { name: 'Task tree', exact: true }).waitFor();
  const restored = await main.boundingBox();
  assert.ok(Math.abs(restored.width - expanded.width) <= 2, 'Expanding restores the usable desktop navigation');
  await message.focus();
  await page.setViewportSize({ width: 450, height: 900 });
  assert.equal(await message.evaluate(node => document.activeElement === node), true);
  const launcher = page.getByRole('button', { name: 'Open Task list', exact: true });
  await launcher.focus();
  await launcher.press('Space');
  await page.getByRole('dialog', { name: 'Task tree', exact: true }).waitFor();
  await page.keyboard.press('Escape');
  await page.getByRole('dialog', { name: 'Task tree', exact: true }).waitFor({ state: 'hidden' });
  assert.equal(await launcher.evaluate(node => document.activeElement === node), true);
  assert.equal(await message.inputValue(), 'Keep this draft while changing navigation capacity.');
});

// A public command updates the card between form preparation and its real HTTP submission.
test('a rejected card edit keeps its diagnostic visible as an assertive alert', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const card = await command({ op: 'create_card', title: 'Conflicting card edit', description: 'Original description' });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '任务看板', exact: true }).click();
  const cardRegion = page.locator('[data-surface-role="card"][aria-label="Conflicting card edit"]');
  await cardRegion.waitFor();
  await cardRegion.getByRole('button', { name: 'More actions', exact: true }).click();
  await page.getByRole('button', { name: 'Edit card', exact: true }).click();
  const dialog = page.getByRole('dialog').last();
  await dialog.getByRole('textbox', { name: 'Title', exact: true }).fill('Keep my unsaved title');
  let intercepted = false;
  await page.route('**/api/browser/command', async route => {
    if (intercepted || route.request().postDataJSON()?.command?.op !== 'update_card') return route.continue();
    intercepted = true;
    await publicCommand(fixture.running, { op: 'update_card', card_id: card.card_id, revision: card.revision,
      observed_at: String(Math.floor(Date.now() / 1000)), description: 'A competing public update' });
    await route.continue();
  });
  const receipt = page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === 'update_card');
  await dialog.getByRole('button', { name: 'Save', exact: true }).click();
  const { reply } = await (await receipt).json();
  assert.ok(intercepted);
  assert.equal(reply.ok, false, JSON.stringify(reply));
  assert.equal(reply.error.code, 'card_conflict');
  const alert = dialog.getByRole('alert');
  await alert.waitFor();
  assert.equal(await alert.innerText(), `${reply.error.code}: ${reply.error.message}`);
  assert.equal(await dialog.getByRole('textbox', { name: 'Title', exact: true }).inputValue(), 'Keep my unsaved title');
});

// Chart accessibility is exercised through the model protocol and ordinary Markdown publication.
test('model chart data remains a readable table with labelled columns in source order', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const source = `<ui id="monthly-report">
<line-chart id="monthly" data={[{id:"a",month:"Jan",value:2},{id:"b",month:"Feb",value:3}]}
 row-key="id" x="month" y="value" x-label="Month" y-label="Value" />
</ui>`;
  const index = fixture.requests.length;
  const { task_id } = await command({ op: 'create', profile: fixture.profile, message: 'Monthly chart accessibility' });
  const deadline = Date.now() + 10000;
  while (fixture.requests.length <= index && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests.length > index, 'The actual service must request its model response');
  fixture.finish(index, { text: '```selvedge-ui\n' + source + '\n```' });
  await taskIdle(fixture.running.service, task_id);
  await selectTask(fixture, task_id);
  const table = page.getByRole('main').getByRole('table');
  await table.waitFor();
  assert.equal(await table.evaluate(node => node.localName), 'table', 'Passive chart data uses a native accessible table');
  assert.deepEqual(await table.getByRole('columnheader').allTextContents(), ['Month', 'Value']);
  assert.equal(await table.getByRole('row').count(), 3, 'The header and both source data rows remain readable');
  assert.deepEqual(await table.getByRole('cell').allTextContents(), ['Jan', '2', 'Feb', '3']);
});

async function accessibleDescription(control) {
  return control.evaluate(node => (node.getAttribute('aria-describedby') ?? '').split(/\s+/).filter(Boolean)
    .map(id => document.getElementById(id)?.textContent ?? '').filter(Boolean).join(' '));
}

test('keyboard users can read unavailable action reasons, choice context and collapsed activity summaries', { timeout: 60000 }, async t => {
  const fixture = await browserFixture(t);
  const { page, command } = fixture;
  const start = page.getByRole('button', { name: 'Start task', exact: true });
  assert.equal(await start.isDisabled(), true);
  await start.focus();
  assert.equal(await start.evaluate(node => document.activeElement === node), true,
    'An unavailable action must keep its explanation reachable by keyboard');
  assert.match(await accessibleDescription(start), /A task input needs text or an image/);
  assert.equal(await page.getByText('A task input needs text or an image', { exact: true }).first().isVisible(), true);
  await page.getByRole('button', { name: /^Permissions:/ }).click();
  const automatic = page.getByRole('menuitemradio', { name: 'Automatic review', exact: true });
  await automatic.focus();
  assert.match(await accessibleDescription(automatic), /echo/,
    'The reviewer context of a permission choice belongs to its accessible description');
  assert.match(await accessibleDescription(automatic), /Workspace write/);
  await page.keyboard.press('Escape');

  const { task_id } = await command({ op: 'create', profile: 'demo', message: 'A readable activity summary' });
  await taskIdle(fixture.running.service, task_id);
  await selectTask(fixture, task_id);
  const main = page.getByRole('main');
  const summary = main.getByText('Conversation event · 0 operations', { exact: true }).first();
  await summary.waitFor();
  assert.equal(await summary.isVisible(), true, 'Collapsed activity has visible summary text');
  await main.getByRole('button', { name: 'Expand activity', exact: true }).first().click();
  await main.getByRole('button', { name: 'Collapse activity', exact: true }).first().click();
  assert.equal(await summary.isVisible(), true, 'Collapsing details keeps the readable summary');
});

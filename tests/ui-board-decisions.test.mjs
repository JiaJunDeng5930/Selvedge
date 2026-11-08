import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';

test('a card action opens a searchable selector for a move or a task link', async t => {
  const { page, command } = await browserFixture(t);
  const source = await command({ op: 'create_card', title: 'Card to organize' });
  const destination = await command({ op: 'create_card', title: 'Destination card', status: 'todo' });
  const { task_id } = await command({ op: 'create_idle', profile: 'demo' });
  const { task } = await command({ op: 'read', task_id });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '任务看板', exact: true }).click();

  const card = page.locator('[data-surface-role="card"][aria-label="Card to organize"]');
  const openActions = () => card.getByRole('button', { name: 'More actions', exact: true }).click();
  const actionButton = name => page.getByRole('button', { name, exact: true });
  const receipt = op => page.waitForResponse(response => response.url().endsWith('/api/browser/command')
    && response.request().postDataJSON()?.command?.op === op);

  await openActions();
  await actionButton('Move card').waitFor();
  assert.equal(await actionButton('Move before Destination card').count(), 0);
  assert.equal(await actionButton(`Link ${task.title}`).count(), 0);

  await actionButton('Move card').click();
  const move = page.getByRole('dialog', { name: 'Move card', exact: true });
  const search = move.getByPlaceholder('Search choices');
  await search.fill('no such card');
  await move.getByText('No matching choices.').waitFor();
  await search.fill('Destination card');
  const moved = receipt('move_card');
  await move.getByRole('button', { name: 'Move before Destination card', exact: true }).click();
  assert.equal((await (await moved).json()).reply.ok, true);
  const board = await command({ op: 'list_cards' });
  const ordered = board.cards.filter(card => card.status === 'todo').map(card => card.card_id);
  assert.deepEqual(ordered, [source.card_id, destination.card_id]);

  await page.keyboard.press('Escape');
  await actionButton('Link task').click();
  const link = page.getByRole('dialog', { name: 'Link task', exact: true });
  await link.getByPlaceholder('Search choices').fill(String(task_id));
  const linked = receipt('link_card');
  await link.getByRole('button', { name: `Link ${task.title}`, exact: true }).click();
  assert.equal((await (await linked).json()).reply.ok, true);
  assert.equal((await command({ op: 'read_card', card_id: source.card_id })).task_id, task_id);
});

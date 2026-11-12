import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

test('conversation search excerpts show rendered text around a match and label source-only matches', { timeout: 60000 }, async t => {
  const title = 'History excerpt fixture';
  const fixture = await browserFixture(t, { taskTitle: () => title });
  const { page, command, profile } = fixture;
  const { task_id } = await command({ op: 'create', profile, message: 'Explain the archive review.' });
  const deadline = Date.now() + 10000;
  while (!fixture.requests[0] && Date.now() < deadline) await delay(20);
  assert.ok(fixture.requests[0], 'The provider receives the source task');
  fixture.finish(0, { text: [
    'Earlier context stays outside the excerpt.',
    '',
    '```selvedge-ui',
    '<ui id="hidden-source-token">',
    '<text id="internal-label" label="Review-only marker" />',
    '</ui>',
    '```',
    '',
    '### Confirm the archive',
    '',
    'Before release, check the **Review-only marker** in [the audit notes](https://example.test/audit).',
    '',
    'The next paragraph describes a different step.',
  ].join('\n') });
  await taskIdle(fixture.running.service, task_id);
  await page.getByRole('button', { name: '搜索对话', exact: true }).click();
  const query = page.getByRole('searchbox', { name: '标题或消息关键词', exact: true });
  const result = page.locator('[data-semantic-key="result"]').filter({
    has: page.getByRole('button', { name: new RegExp('^' + title + ' · 消息 #') }),
  });
  const search = async text => { await query.fill(text); await query.press('Enter'); };

  await search('  review-only marker  ');
  await result.getByText('Before release, check the Review-only marker in the audit notes.', { exact: true }).waitFor();
  const readable = await result.innerText();
  assert.doesNotMatch(readable, /<ui|internal-label|selvedge-ui|\*\*|example\.test|Earlier context|next paragraph|上一条|下一条/);

  await search('hidden-source-token');
  await result.getByText('在消息原文中找到匹配', { exact: true }).waitFor();
  assert.doesNotMatch(await result.innerText(), /<ui|hidden-source-token|selvedge-ui/);
  await result.getByRole('button').click();
  const original = page.locator('[data-reading-root] [data-history-match]');
  await original.getByText('Confirm the archive', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => CSS.highlights?.has('selvedge-history-match')), false);
  assert.equal(fixture.requests.length, 1, 'Search only reads committed history');
});

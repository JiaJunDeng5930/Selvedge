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
  const assistantHit = page.getByRole('button', { name: `${title} · 助手`, exact: true });
  const result = page.locator('[data-semantic-key="result"]').filter({
    has: assistantHit,
  });
  const search = async text => { await query.fill(text); await query.press('Enter'); };

  await search('  review-only marker  ');
  await result.getByText('Before release, check the Review-only marker in the audit notes.', { exact: true }).waitFor();
  assert.equal(await result.locator('mark').textContent(), 'Review-only marker');
  const emphasis = await result.evaluate(card => {
    const excerpt = card.querySelector('[data-semantic-key="result-excerpt"]');
    const speaker = card.querySelector('[data-semantic-key="result-speaker"]');
    return { excerpt: parseFloat(getComputedStyle(excerpt).fontSize),
      speaker: parseFloat(getComputedStyle(speaker).fontSize),
      speakerFirst: speaker.getBoundingClientRect().bottom <= excerpt.getBoundingClientRect().top };
  });
  assert.ok(emphasis.speakerFirst && emphasis.excerpt > emphasis.speaker);
  const readable = await result.innerText();
  assert.doesNotMatch(readable, /<ui|internal-label|selvedge-ui|\*\*|example\.test|Earlier context|next paragraph|上一条|下一条/);

  await search('no-matching-release-note');
  await page.getByText('没有找到匹配的标题或消息。试试其他关键词。', { exact: true }).waitFor();

  await search('hidden-source-token');
  await result.getByText('在消息原文中找到匹配', { exact: true }).waitFor();
  assert.doesNotMatch(await result.innerText(), /<ui|hidden-source-token|selvedge-ui/);
  await assistantHit.getByText('助手', { exact: true }).waitFor();
  await assistantHit.click();
  const original = page.locator('[data-reading-root] [data-history-match]');
  await original.getByText('Confirm the archive', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => CSS.highlights?.has('selvedge-history-match')), false);
  assert.equal(fixture.requests.length, 1, 'Search only reads committed history');
});

test('Search groups an interleaved title and message hits and returns to each selected hit', { timeout: 60000 }, async t => {
  const firstTitle = '发布前检查清单';
  const secondTitle = '后续复核记录';
  const firstPrompt = '发布前要检查哪些项目？';
  const firstReply = '请在发布前确认构建通过。';
  const secondReply = '请在发布前记录复核结果。';
  const fixture = await browserFixture(t, { taskTitle: prompt => prompt === firstPrompt ? firstTitle : secondTitle });
  const { page, command, profile } = fixture;
  const complete = async (message, text) => {
    const index = fixture.requests.length;
    const { task_id } = await command({ op: 'create', profile, message });
    const deadline = Date.now() + 10000;
    while (!fixture.requests[index] && Date.now() < deadline) await delay(20);
    assert.ok(fixture.requests[index], 'The provider receives each source task');
    fixture.finish(index, { text });
    await taskIdle(fixture.running.service, task_id);
  };
  await complete(firstPrompt, firstReply);
  await complete('列出复核要求。', secondReply);

  await page.getByRole('button', { name: '搜索对话', exact: true }).click();
  const query = page.getByRole('searchbox', { name: '标题或消息关键词', exact: true });
  await query.fill('发布前');
  await query.press('Enter');
  const main = page.getByRole('main');
  const cards = main.locator('[data-semantic-key="result"]');
  const first = cards.nth(0);
  const second = cards.nth(1);
  const titleHit = first.getByRole('button', { name: firstTitle, exact: true });
  const excerpts = card => card.locator('[data-semantic-key="result-excerpt"]');
  await second.getByRole('heading', { name: secondTitle, exact: true }).waitFor();
  assert.equal(await cards.count(), 2);
  assert.equal(await titleHit.locator('mark').textContent(), '发布前');
  assert.deepEqual(await excerpts(first).allTextContents(), [firstReply, firstPrompt]);
  assert.deepEqual(await excerpts(second).allTextContents(), [secondReply]);
  assert.deepEqual(await main.locator('[data-semantic-key="result-speaker"]').allTextContents(), ['助手', '用户', '助手']);
  assert.doesNotMatch(await main.innerText(), /消息\s*#\d+/u);
  assert.deepEqual(await main.locator('[data-semantic-key="result-excerpt"] mark').allTextContents(), ['发布前', '发布前', '发布前']);
  assert.equal((await first.innerText()).split(firstTitle).length - 1, 1);
  assert.equal((await second.innerText()).split(secondTitle).length - 1, 1);

  const checkIndent = card => card.evaluate(node => {
    const title = node.querySelector('[data-semantic-key="result-title"]').getBoundingClientRect();
    return [...node.querySelectorAll('[data-semantic-key="result-excerpt"]')]
      .every(excerpt => excerpt.getBoundingClientRect().left >= title.left + 8);
  });
  for (const card of [first, second]) assert.ok(await checkIndent(card));

  const openAndReturn = async (hit, located) => {
    await hit.press('Enter');
    await located();
    await main.getByRole('button', { name: '返回搜索结果', exact: true }).click();
    await hit.and(page.locator(':focus')).waitFor();
    assert.equal(await query.inputValue(), '发布前');
  };
  await openAndReturn(titleHit, () => main.getByText(firstReply, { exact: true }).waitFor());
  await page.setViewportSize({ width: 320, height: 740 });
  await page.locator('[data-semantic-key="compact-header"]').waitFor();
  for (const card of [first, second]) assert.ok(await checkIndent(card));
  for (const [card, text] of [[first, firstReply], [first, firstPrompt], [second, secondReply]]) {
    const hit = card.getByRole('button').filter({ hasText: text });
    await openAndReturn(hit, () => page.waitForFunction(text => {
      const [range] = CSS.highlights?.get('selvedge-history-match') ?? [];
      if (range) return range.toString() === '发布前' &&
        range.startContainer.parentElement.closest('[data-reading-anchor]')?.textContent.includes(text);
      return Array.from(document.querySelectorAll('[data-reading-root] [data-history-match]'))
        .some(article => article.textContent.includes(text));
    }, text));
  }
  assert.equal(await main.evaluate(node => node.scrollWidth <= node.clientWidth), true);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { interactiveMarkdownFixture } from './fixtures/interactive-markdown.mjs';
import { browserFixture } from './fixtures/browser.mjs';
import { taskIdle } from './support.mjs';

async function until(observe, description) {
  const deadline = Date.now() + 10_000;
  do {
    const value = observe();
    if (value) return value;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Timed out waiting for ${description}`);
}

test('HTTP and native agent search retain scoped original message locations across a restart', async t => {
  const fixture = await interactiveMarkdownFixture();
  t.after(() => fixture.close());
  const raw = async (command, status = 200) => {
    const response = await fetch(`${fixture.running.address}/api/commands`, {
      method: 'POST', headers: { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(command),
    });
    assert.equal(response.status, status);
    return response.json();
  };
  const command = async input => {
    const reply = await raw(input);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const requestFor = marker => until(() => fixture.requests.find(request => !request.closed
    && JSON.stringify(request.input.input).includes(marker)), `model request containing ${marker}`);
  const complete = async (task, marker, text) => {
    const request = await requestFor(marker);
    fixture.finish(request.index, { text });
    return taskIdle(fixture.running.service, task);
  };
  const project = async name => {
    const root = path.join(fixture.root, name);
    await mkdir(root);
    return (await command({ op: 'create_project', name, workspace: { roots: [root] } })).project_id;
  };
  const projectA = await project('Alpha Project');
  const projectB = await project('Beta Project');
  const workA = (await command({ op: 'create_work', name: 'First Work' })).work_id;
  const workB = (await command({ op: 'create_work', name: 'Second Work' })).work_id;
  const records = [];
  const readable = item => {
    if (item.role === 'user') return { role: 'user',
      text: item.content.filter(part => part.type === 'text').map(part => part.text).join('') };
    assert.equal(item.role, 'model_context');
    assert.equal(item.content.type, 'provider_receipt');
    assert.equal(item.content.item.type, 'message');
    assert.equal(item.content.item.role, 'assistant');
    return { role: 'assistant', text: item.content.item.content.map(part => part.text).join('') };
  };
  const create = async (label, project_id, work_id) => {
    const message = `${label} user context before. 星河 NeEdLe user match. Context after.`;
    const { task_id } = await command({ op: 'create_work_task', work_id, profile: 'interactive',
      settings: { project_id }, message });
    const assistant = `${label} assistant context before. 星河 nEeDlE assistant match. Context after.`;
    const page = await complete(task_id, message, assistant);
    for (const [message_index, item] of page.messages.entries()) {
      if ((item.role === 'user' && readable(item).text === message) || (item.role === 'model_context' && item.content.type === 'provider_receipt'
          && item.content.item.type === 'message' && item.content.item.content[0].text === assistant)) {
        records.push({ task_id, message_index, ...readable(item), wire_role: item.role, project_id, work_id });
      }
    }
    return task_id;
  };
  const first = await create('First conversation', projectA, workA);
  await create('Second conversation', projectB, workA);
  await create('Third conversation', projectA, workB);
  assert.equal(records.length, 6, 'The real model transport must record each user and assistant message');
  await command({ op: 'send', task_id: first, message: 'Continue the oldest conversation without the keyword.' });
  await complete(first, 'Continue the oldest conversation', 'Later response without the keyword.');

  const expected = records.toSorted((left, right) => right.task_id - left.task_id || right.message_index - left.message_index);
  const identify = hits => hits.map(hit => [hit.task.id, hit.message_index, hit.role]);
  const rows = list => list.map(item => [item.task_id, item.message_index, item.role]);
  const search = args => command({ op: 'search_history', query: 'needle', ...args });
  const all = await search({});
  assert.deepEqual(identify(all.hits), rows(expected));
  assert.equal(all.has_more, false);
  assert.equal(all.next_after, null);
  for (const hit of all.hits) {
    const source = expected.find(item => item.task_id === hit.task.id && item.message_index === hit.message_index);
    assert.equal(hit.task.settings.project_id, source.project_id);
    assert.equal(hit.task.work_id, source.work_id);
    assert.equal(typeof hit.task.title, 'string');
    assert.match(hit.snippet, /needle/i);
    assert.equal(typeof hit.before, 'string');
    assert.equal(typeof hit.after, 'string');
    const original = await command({ op: 'read', task_id: hit.task.id, after: hit.message_index, limit: 1 });
    assert.equal(original.messages.length, 1);
    assert.equal(original.messages[0].role, source.wire_role);
    assert.deepEqual(readable(original.messages[0]), { role: hit.role, text: source.text });
  }
  const firstAssistant = all.hits.find(hit => hit.task.id === first && hit.role === 'assistant');
  assert.match(firstAssistant.before, /First conversation user/);
  assert.match(firstAssistant.after, /Continue the oldest conversation/);
  assert.deepEqual(identify((await search({ project_id: projectA })).hits), rows(expected.filter(item => item.project_id === projectA)));
  assert.deepEqual(identify((await search({ work_id: workA })).hits), rows(expected.filter(item => item.work_id === workA)));
  const intersection = await search({ project_id: projectA, work_id: workA });
  assert.deepEqual(identify(intersection.hits), rows(expected.filter(item => item.task_id === first)));
  assert.deepEqual(identify((await search({ query: '  星河  ' })).hits), rows(expected));
  const pageOne = await search({ limit: 3 });
  assert.equal(pageOne.has_more, true);
  assert.equal(typeof pageOne.next_after, 'number');
  const pageTwo = await search({ after: pageOne.next_after, limit: 3 });
  assert.deepEqual(identify([...pageOne.hits, ...pageTwo.hits]), rows(expected));
  assert.equal(pageTwo.next_after, null);
  for (const input of [{ query: ' \n ' }, { project_id: 999999 }, { work_id: 999999 }]) {
    const rejected = await raw({ op: 'search_history', query: 'needle', ...input }, 400);
    assert.equal(rejected.ok, false, JSON.stringify(rejected));
  }

  await fixture.restart();
  assert.deepEqual(await search({ project_id: projectA, work_id: workA }), intersection,
    'Reopening SQLite preserves searchable original message offsets and task metadata');
  const marker = 'Find the earlier discussion using the native search tool.';
  const { task_id: agent } = await command({ op: 'create', profile: 'interactive', message: marker });
  const request = await requestFor(marker);
  const tool = request.input.tools.find(tool => tool.name === 'search_history');
  assert.ok(tool, 'The actual provider request advertises the native search_history tool');
  assert.ok(tool.parameters.required.includes('query'));
  assert.ok(tool.parameters.properties.project_id);
  assert.ok(tool.parameters.properties.work_id);
  fixture.finish(request.index, { output: [{ type: 'function_call', call_id: 'search-original-history',
    name: 'search_history', arguments: JSON.stringify({ query: 'needle', project_id: projectA, work_id: workA }) }] });
  const continuation = await until(() => fixture.requests.find(item => !item.closed
    && item.input.input.some(input => input.type === 'function_call_output' && input.call_id === 'search-original-history')),
  'the native tool result delivered to the model');
  const output = continuation.input.input.find(item => item.type === 'function_call_output' && item.call_id === 'search-original-history');
  const result = JSON.parse(output.output);
  assert.equal(result.is_error, false, JSON.stringify(result));
  assert.equal(result.value.ok, true, JSON.stringify(result.value));
  assert.deepEqual(result.value.result, intersection, 'The UI command and agent tool return the same search result');
  fixture.finish(continuation.index, { text: 'Located the earlier conversation.' });
  await taskIdle(fixture.running.service, agent);
  assert.deepEqual(fixture.failures, []);
});

test('Search finds the displayed conversation title and lets the user retry a lost reply', async t => {
  const title = '极光排班计划';
  const fixture = await browserFixture(t, { taskTitle: () => title });
  const { page, command } = fixture;
  const prompt = 'Summarize last week’s availability.';
  const { task_id } = await command({ op: 'create', profile: fixture.profile, message: prompt });
  const modelRequest = await until(() => fixture.requests.find(entry => !entry.closed
    && JSON.stringify(entry.input.input).includes(prompt)), 'the conversation model request');
  fixture.finish(modelRequest.index, { text: 'The team is available Monday morning.' });
  await taskIdle(fixture.running.service, task_id);
  const tree = page.getByRole('navigation', { name: 'Task tree', exact: true });
  await tree.getByRole('button', { name: title, exact: true }).waitFor();
  await page.getByRole('button', { name: '搜索对话', exact: true }).click();
  const query = page.getByRole('searchbox', { name: '标题或消息关键词', exact: true });
  const submit = page.getByRole('button', { name: '搜索', exact: true });
  assert.equal(await submit.isDisabled(), true, 'A blank query cannot be submitted');
  const endpoint = '**/api/browser/command';
  let requests = 0;
  let finishReply;
  const untilReply = new Promise(resolve => { finishReply = resolve; });
  const dropReply = async route => {
    if (route.request().postDataJSON()?.command?.op !== 'search_history') return route.continue();
    requests++;
    await route.fetch();
    await untilReply;
    return route.abort('failed');
  };
  await page.route(endpoint, dropReply);
  try {
    await query.fill(title);
    await query.press('Enter');
    await page.getByRole('status').filter({ hasText: /^正在搜索…$/u }).waitFor();
    assert.equal(await submit.isDisabled(), true, 'A pending search disables repeated submission');
    await query.press('Enter');
    await until(() => requests, 'the search request');
  } finally { finishReply(); }
  await page.getByRole('status').filter({ hasText: '未能完成搜索，请重试。' }).waitFor();
  await page.unroute(endpoint, dropReply);
  assert.equal(requests, 1, 'Repeated Enter did not send another search');
  await submit.click();
  const match = page.getByRole('main').getByRole('button', { name: title, exact: true });
  await match.click();
  await page.getByRole('main').getByText('The team is available Monday morning.', { exact: true }).waitFor();
  const back = page.getByRole('button', { name: '返回搜索结果', exact: true });
  await back.click();
  await match.and(page.locator(':focus')).waitFor();
  assert.equal(await query.inputValue(), title);
  await tree.getByRole('button', { name: title, exact: true }).click();
  await page.getByRole('main').getByText('The team is available Monday morning.', { exact: true }).waitFor();
  assert.equal(await back.count(), 0, 'An ordinary sidebar visit has no return to search');
  await page.getByRole('button', { name: '新建对话', exact: true }).click();
  await page.getByRole('main').getByRole('combobox', { name: 'Task', exact: true }).waitFor();
  assert.equal(await page.getByText('This command is already pending.', { exact: true }).count(), 0);
});

test('Returning from a search hit restores its filtered results page and reading position', { timeout: 60000 }, async t => {
  const title = 'Archive reading fixture';
  const fixture = await browserFixture(t, { taskTitle: () => title });
  const { page, command } = fixture;
  const projectName = 'Archive project';
  const resultWork = 'Archive group';
  const sourceWork = 'Source group';
  const marker = '档案检索';
  const directory = path.join(fixture.root, 'archive');
  await mkdir(directory);
  const { project_id } = await command({ op: 'create_project', name: projectName, workspace: { roots: [directory] } });
  await command({ op: 'create_work', name: sourceWork });
  const { work_id } = await command({ op: 'create_work', name: resultWork });
  const prompt = 'Gather notes in the archive.';
  const { task_id } = await command({ op: 'create_work_task', work_id, profile: fixture.profile,
    settings: { project_id }, message: prompt });
  const request = await until(() => fixture.requests.find(entry => !entry.closed
    && JSON.stringify(entry.input.input).includes(prompt)), 'the archive model request');
  fixture.finish(request.index, { output: Array.from({ length: 45 }, (_, index) => ({
    type: 'message', role: 'assistant', content: [{ type: 'output_text',
      text: `${marker} ${index + 1}. ${'Searchable notes for the project archive. '.repeat(4)}` }],
  })) });
  await taskIdle(fixture.running.service, task_id);

  const main = page.getByRole('main');
  const query = main.getByRole('searchbox', { name: '标题或消息关键词', exact: true });
  const project = main.getByRole('combobox', { name: '项目', exact: true });
  const work = main.getByRole('combobox', { name: '工作组', exact: true });
  const previous = main.getByRole('button', { name: '上一页', exact: true });
  const back = main.getByRole('button', { name: '返回搜索结果', exact: true });
  const hit = main.getByRole('button', { name: /^Archive reading fixture · 消息 #/ }).nth(16);
  const picker = page.getByRole('button', { name: /^对话范围 · / });
  const scope = page.getByRole('menu', { name: '对话范围', exact: true });
  await picker.click();
  await scope.getByRole('menuitemradio', { name: sourceWork, exact: true }).click();
  await page.getByRole('button', { name: `对话范围 · ${sourceWork}`, exact: true }).waitFor();
  const search = page.getByRole('button', { name: '搜索对话', exact: true });
  const enterSearch = async () => {
    if (!(await search.isVisible()))
      await page.getByRole('button', { name: 'Global navigation', exact: true }).click();
    await search.click();
  };
  await enterSearch();
  await project.selectOption({ label: projectName });
  await work.selectOption({ label: resultWork });
  await query.fill(marker);
  await query.press('Enter');
  await main.getByRole('button', { name: '更多结果', exact: true }).click();
  await previous.waitFor();
  const hitName = await hit.textContent();
  const checkSearch = async offset => {
    await hit.waitFor();
    await previous.waitFor();
    assert.equal(await query.inputValue(), marker);
    assert.equal(await project.inputValue(), String(project_id));
    assert.equal(await work.inputValue(), String(work_id));
    assert.equal(await hit.textContent(), hitName);
    assert.ok(Math.abs((await main.evaluate(node => node.scrollTop)) - offset) <= 2,
      'The search list returns to its previous scroll position');
  };
  const readPosition = async () => {
    await hit.scrollIntoViewIfNeeded();
    return hit.evaluate(node => {
      node.scrollIntoView({ block: 'center', behavior: 'instant' });
      return node.closest('main').scrollTop;
    });
  };

  for (const viewport of [{ width: 1280, height: 900 }, { width: 390, height: 844 }, { width: 844, height: 390 }]) {
    await page.setViewportSize(viewport);
    const offset = await readPosition();
    assert.ok(offset > 100, 'The selected result is well below the first visible results');
    await hit.click();
    if (viewport.width === 1280)
      await page.getByRole('button', { name: `对话范围 · ${resultWork}`, exact: true }).waitFor();
    await back.click();
    await hit.and(page.locator(':focus')).waitFor();
    await checkSearch(offset);
    if (viewport.width === 1280)
      await page.getByRole('button', { name: `对话范围 · ${sourceWork}`, exact: true }).waitFor();
  }

  const offset = await readPosition();
  await hit.click();
  await back.waitFor();
  await enterSearch();
  await checkSearch(offset);

  await query.fill('档案');
  await query.press('Enter');
  await main.getByRole('button', { name: '更多结果', exact: true }).waitFor();
  assert.equal(await previous.count(), 0);
  assert.equal(await main.evaluate(node => node.scrollTop), 0);
});

test('A search result opens and highlights a deep visible match while later replies render', { timeout: 60000 }, async t => {
  const title = 'Conversation reading fixture';
  const fixture = await browserFixture(t, { taskTitle: () => title });
  const { page, command } = fixture;
  const marker = '追加式数据集';
  const enteredQuery = `　${marker}　`;
  const firstPrompt = 'Start a conversation with a long introduction.';
  const { task_id } = await command({ op: 'create', profile: fixture.profile, message: firstPrompt });
  const requestFor = prompt => until(() => fixture.requests.find(entry => !entry.closed
    && JSON.stringify(entry.input.input).includes(prompt)), `the model request for ${prompt}`);
  const longText = (prefix, count) => Array.from({ length: count }, (_, index) =>
    `${prefix} ${index + 1}. ${'Text with enough detail to wrap across multiple lines. '.repeat(8)}`).join('\n\n');
  const calculator = [
    '```selvedge-ui',
    '<ui id="budget">',
    '<state id="seats" type="integer" initial={5} min={1} max={20} />',
    '<slider id="seat-slider" bind="seats" label="Budget seats" />',
    `<button id="follow-up" label="Prepare a question" action="draft" message="${marker}" />`,
    '</ui>',
    '```',
  ].join('\n');
  const visibleMatch = `The audit record uses **${marker}** to keep the earlier entries readable.`;
  fixture.finish((await requestFor(firstPrompt)).index, { text: [calculator, longText('Introduction', 48),
    '## Audit record', visibleMatch, longText('Audit details', 24)].join('\n\n') });
  const history = await taskIdle(fixture.running.service, task_id);
  const index = history.messages.findIndex(message => JSON.stringify(message).includes(visibleMatch));
  assert.ok(index >= 0, 'The real conversation contains the selected message');
  const livePrompt = 'Add a long follow-up to the budget.';
  await command({ op: 'send', task_id, message: livePrompt });
  const live = await requestFor(livePrompt);
  fixture.emit(live.index, longText('Live follow-up', 25));

  const timelineSelector = `[data-reading-root][data-task-id="${task_id}"]`;
  const timeline = page.locator(timelineSelector);
  const atLatest = () => page.waitForFunction(selector => {
    const root = document.querySelector(selector);
    return root && root.scrollHeight - root.clientHeight - root.scrollTop <= 2;
  }, timelineSelector);
  const tree = page.getByRole('navigation', { name: 'Task tree', exact: true });
  await tree.getByRole('button', { name: title, exact: true }).click();
  await timeline.getByRole('slider', { name: 'Budget seats', exact: true }).waitFor();
  await timeline.getByText(/Live follow-up 25/).waitFor();
  await atLatest();

  await page.getByRole('button', { name: '搜索对话', exact: true }).click();
  const query = page.getByRole('searchbox', { name: '标题或消息关键词', exact: true });
  await query.fill(enteredQuery);
  await query.press('Enter');
  const hit = page.getByRole('main').getByRole('button', { name: `${title} · 消息 #${index + 1}`, exact: true });
  await hit.press('Enter');
  const keyword = timeline.getByText(marker, { exact: true });
  await keyword.waitFor();
  const highlighted = () => page.waitForFunction(({ task, marker }) => {
    const root = document.querySelector(`[data-reading-root][data-task-id="${task}"]`);
    const highlight = CSS.highlights.get('selvedge-history-match');
    const [range] = highlight ?? [];
    if (!root || highlight?.size !== 1 || range?.toString() !== marker ||
        !range.startContainer.parentElement.closest('p')?.textContent.startsWith('The audit record uses')) return false;
    const viewport = root.getBoundingClientRect(), bounds = range.getBoundingClientRect();
    const article = range.startContainer.parentElement.closest('article').getBoundingClientRect();
    return bounds.top >= viewport.top - 1 && bounds.bottom <= viewport.bottom + 1 && article.top < viewport.top - 1000;
  }, { task: task_id, marker });
  const checkFocusFrame = async () => {
    await timeline.and(page.locator(':focus-visible')).waitFor();
    const frame = await keyword.evaluate(node => {
      const root = node.closest('[data-reading-root]');
      const bounds = root.getBoundingClientRect();
      const style = getComputedStyle(root);
      const text = document.createRange();
      text.selectNodeContents(node);
      const ringInside = Math.max(0, -parseFloat(style.outlineOffset));
      return { style: style.outlineStyle, width: parseFloat(style.outlineWidth),
        leftClearance: text.getBoundingClientRect().left - bounds.left - ringInside };
    });
    assert.equal(frame.style, 'solid');
    assert.ok(frame.width >= 2);
    assert.ok(frame.leftClearance >= 4,
      `The timeline focus ring clears the assistant text by ${frame.leftClearance}px`);
  };
  const offset = () => keyword.evaluate(node => new Promise(resolve => {
    requestAnimationFrame(() => setTimeout(() => {
      const viewport = node.closest('[data-reading-root]').getBoundingClientRect();
      resolve(node.getBoundingClientRect().top - viewport.top);
    }, 0));
  }));
  await highlighted();
  await checkFocusFrame();
  const arrived = await offset();
  const previousWidth = await timeline.evaluate(root => root.clientWidth);
  await keyword.evaluate(node => {
    window.firstResizedMessageOffset = new Promise(resolve => {
      window.addEventListener('resize', () => setTimeout(() => {
        const viewport = node.closest('[data-reading-root]')?.getBoundingClientRect();
        resolve(viewport ? node.getBoundingClientRect().top - viewport.top : null);
      }, 0), { once: true });
    });
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(({ selector, previousWidth }) =>
    document.querySelector(selector)?.clientWidth < previousWidth, { selector: timelineSelector, previousWidth });
  const resized = await page.evaluate(() => window.firstResizedMessageOffset);
  assert.ok(resized !== null && Math.abs(resized - arrived) <= 2,
    `The first resized frame retains the selected keyword (before ${arrived}px, after ${resized}px)`);
  await checkFocusFrame();
  const completion = longText('Finished follow-up', 30);
  fixture.emit(live.index, '\n\n' + completion);
  fixture.finish(live.index, {});
  await taskIdle(fixture.running.service, task_id);
  await timeline.getByText(/Finished follow-up 30/).waitFor();
  const completed = await offset();
  assert.ok(Math.abs(completed - arrived) <= 2,
    `The selected keyword stays at its reading position as the reply completes (before ${arrived}px, after ${completed}px)`);
  await page.waitForFunction(() => !CSS.highlights.has('selvedge-history-match'));

  const scrolledPast = previous => page.waitForFunction(({ selector, previous, marker }) => {
    const root = document.querySelector(selector);
    const keyword = [...root.querySelectorAll('strong')].find(text => text.textContent === marker);
    return keyword && previous > keyword.getBoundingClientRect().top - root.getBoundingClientRect().top + 50;
  }, { selector: timelineSelector, previous, marker });
  await page.keyboard.press('PageDown');
  await scrolledPast(arrived);
  const afterPaging = await offset();
  await timeline.hover();
  await page.mouse.wheel(0, 180);
  await scrolledPast(afterPaging);

  await page.getByRole('button', { name: '返回搜索结果', exact: true }).click();
  await hit.and(page.locator(':focus')).waitFor();
  assert.equal(await query.inputValue(), enteredQuery);
  await hit.press('Enter');
  await highlighted();
  await checkFocusFrame();
  await page.getByRole('button', { name: 'Return to latest', exact: true }).click();
  await atLatest();
});

test('A stalled first connection is visible and the user can reconnect', async t => {
  const { browser, running } = await browserFixture(t);
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  t.after(() => page.close());
  let first = true;
  await page.route('**/api/browser/state', route => {
    if (!first) return route.continue();
    first = false;
    // Leave the first state request unanswered so the browser's own deadline fires.
  });
  await page.goto(running.url);
  await page.getByRole('status').filter({ hasText: /^正在连接 Selvedge…$/u }).waitFor();
  const retry = page.getByRole('button', { name: '重新连接', exact: true });
  await retry.click({ timeout: 25000 });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true }).waitFor({ timeout: 10000 });
});

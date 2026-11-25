import test from 'node:test';
import assert from 'node:assert/strict';
import { browserFixture } from './fixtures/browser.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { events } from '../host/network.mjs';
import { startServer } from '../host/server.mjs';
import { home, taskIdle } from './support.mjs';

test('opening the browser reads a conversation history only when that conversation becomes visible', async t => {
  const { page, command, running } = await browserFixture(t);
  const message = 'Selected conversation before the browser opened';
  const { task_id: selected } = await command({ op: 'create', profile: 'demo', message });
  const { task_id: unrelated } = await command({ op: 'create', profile: 'demo',
    message: 'Unrelated conversation history '.repeat(400) });
  const [{ task }] = await Promise.all([taskIdle(running.service, selected), taskIdle(running.service, unrelated)]);
  const snapshotPath = '/api/browser/state';
  const historyReads = [];
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.pathname === snapshotPath && url.searchParams.has('history')) historyReads.push(url.searchParams.get('history'));
  });
  const opened = page.waitForResponse(response => new URL(response.url()).pathname === snapshotPath);
  await page.reload();
  const { program } = await (await opened).json();
  assert.equal(Object.hasOwn(program.tasks[selected], 'history'), false);
  assert.equal(Object.hasOwn(program.tasks[unrelated], 'history'), false);
  assert.equal(Object.hasOwn(program.tasks[unrelated], 'tools'), false);
  assert.deepEqual(historyReads, []);

  const captured = Promise.withResolvers();
  const release = Promise.withResolvers();
  t.after(() => release.resolve());
  const scope = url => url.pathname === snapshotPath && url.searchParams.get('history') === String(selected);
  let first = true;
  await page.route(scope, async route => {
    if (!first) return route.continue();
    first = false;
    const response = await route.fetch();
    captured.resolve();
    await release.promise;
    await route.fulfill({ response });
  });
  await page.getByRole('navigation', { name: 'Task tree', exact: true })
    .getByRole('button', { name: task.title, exact: true }).click();
  await captured.promise;
  await page.getByText('正在加载对话…', { exact: true }).waitFor();
  const appended = 'Arrived while the selected history was in flight';
  await command({ op: 'send', task_id: selected, message: appended });
  await taskIdle(running.service, selected);
  release.resolve();
  const timeline = page.getByRole('region', { name: 'Conversation', exact: true });
  await timeline.getByText(message, { exact: true }).first().waitFor();
  await timeline.getByText(appended, { exact: true }).first().waitFor();
  assert.ok(historyReads.length >= 1);
  assert.deepEqual([...new Set(historyReads)], [String(selected)]);
});

test('the board follows other commits and recovers an acknowledged write when its HTTP receipt is lost or stalled', async t => {
  const { page, command } = await browserFixture(t);
  await command({ op: 'board_settings', automatic: false, draft_profile: '' });
  await page.getByRole('navigation', { name: 'Global navigation', exact: true })
    .getByRole('button', { name: '卡片看板', exact: true }).click();

  const dialog = page.getByRole('dialog', { name: '新建卡片', exact: true });
  const card = title => page.getByRole('article', { name: title, exact: true });
  async function submit(title) {
    await page.getByRole('button', { name: '新建卡片', exact: true }).click();
    await dialog.getByRole('textbox', { name: '标题', exact: true }).fill(title);
    await dialog.getByRole('button', { name: '创建卡片', exact: true }).click();
  }
  const initial = 'Initial card from another client';
  await command({ op: 'create_card', title: initial });
  await card(initial).waitFor();

  let stateReads = 0;
  page.on('request', request => {
    if (new URL(request.url()).pathname === '/api/browser/state') stateReads++;
  });
  const received = 'Card with a matching receipt';
  await submit(received);
  await card(received).waitFor();
  assert.equal(stateReads, 0, 'The matching command receipt already carries its committed state');

  const unrelated = 'Unrelated committed card';
  await command({ op: 'create_card', title: unrelated });
  await card(unrelated).waitFor();
  assert.ok(stateReads > 0, 'The browser still reads the state for a commit from another client');

  for (const outcome of ['stalled', 'lost']) {
    const title = `Committed card with a ${outcome} receipt`;
    const release = Promise.withResolvers();
    const delivered = Promise.withResolvers();
    t.after(() => release.resolve());
    const url = '**/api/browser/command';
    const holdReceipt = async route => {
      if (route.request().postDataJSON()?.command?.title !== title) return route.continue();
      try {
        const response = await route.fetch();
        assert.equal((await response.json()).reply.ok, true);
        if (outcome === 'lost') await route.abort('failed');
        else {
          await release.promise;
          await route.fulfill({ response });
        }
      } finally {
        delivered.resolve();
      }
    };
    await page.route(url, holdReceipt);
    const recovered = page.waitForResponse(async response =>
      new URL(response.url()).pathname === '/api/browser/state' && response.ok() && (await response.text()).includes(title));
    await submit(title);
    await recovered;
    release.resolve();
    await delivered.promise;
    await page.unroute(url, holdReceipt);
    if (outcome === 'lost') {
      await page.keyboard.press('Escape');
    }
    await dialog.waitFor({ state: 'hidden' });
    await card(title).waitFor();
  }
});

test('a browser command marker identifies just its own durable commit', async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const running = await startServer({ home: directory, cwd: directory, config });
  t.after(() => running.close());
  const page = await fetch(running.url);
  const headers = { cookie: page.headers.get('set-cookie').split(';')[0], origin: running.address };
  const controller = new AbortController();
  const stream = await fetch(`${running.address}/api/events`, { headers, signal: controller.signal });
  const reader = events(stream.body, running.service.limits.frame_bytes);
  const next = async () => JSON.parse((await reader.next()).value);
  try {
    assert.equal((await next()).type, 'stream-state');
    const initial = await next();
    assert.equal(initial.type, 'commit');
    assert.equal(initial.browser_request_id, undefined);

    const id = '9ef97a10c037693a26e17b3ec523f9a9';
    const response = await fetch(`${running.address}/api/browser/command`, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json', 'x-selvedge-browser-request-id': id },
      body: JSON.stringify({ command: { op: 'create_card', title: 'Browser request' } }),
    });
    const body = await response.json();
    assert.equal(body.reply.ok, true, JSON.stringify(body.reply));
    const owned = await next();
    assert.equal(owned.type, 'commit');
    assert.equal(owned.sequence, body.sequence);
    assert.equal(owned.browser_request_id, id);

    const unrelated = await running.service.command({ op: 'create_card', title: 'Other request' });
    assert.equal(unrelated.reply.ok, true);
    const other = await next();
    assert.equal(other.type, 'commit');
    assert.equal(other.sequence, unrelated.sequence);
    assert.equal(other.browser_request_id, undefined);
  } finally {
    controller.abort();
    await reader.return().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
});

test('a local browser command publishes the changed task without unrelated conversation history', async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider: 'echo', model: 'fixture' } } });
  const running = await startServer({ home: directory, cwd: directory, config });
  t.after(() => running.close());
  const { service } = running;
  const selected = await service.command({ op: 'create_idle', profile: 'fixture' });
  assert.equal(selected.reply.ok, true);
  const taskId = Number(selected.reply.result.task_id);
  const cookie = (await fetch(running.url)).headers.get('set-cookie').split(';')[0];
  const headers = { cookie, origin: running.address };
  const state = async () => (await fetch(`${running.address}/api/browser/state`, { headers })).json();

  async function submit(command, sequence) {
    const response = await fetch(`${running.address}/api/browser/command`, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json',
        'x-selvedge-browser-sequence': String(sequence) },
      body: JSON.stringify({ command }),
    });
    const text = await response.text();
    const receipt = JSON.parse(text);
    assert.equal(receipt.reply.ok, true, text);
    assert.equal(receipt.after, sequence);
    return { text, receipt };
  }

  async function freezeAtCurrentSequence() {
    const snapshot = await state();
    const { text, receipt } = await submit({ op: 'freeze', task_id: taskId }, snapshot.sequence);
    const tasks = receipt.updates.flatMap(update => update.tasks);
    assert.deepEqual(tasks.map(task => task.id), [taskId]);
    assert.equal(tasks[0].value.status, 'frozen');
    assert.equal((await state()).program.tasks[taskId].status, 'frozen');
    return text.length;
  }

  const small = await freezeAtCurrentSequence();
  assert.equal((await service.command({ op: 'unfreeze', task_id: taskId })).reply.ok, true);
  const message = 'UNRELATED CONVERSATION HISTORY '.repeat(500);
  const unrelated = await service.command({ op: 'create', profile: 'fixture', message });
  assert.equal(unrelated.reply.ok, true);
  await taskIdle(service, unrelated.reply.result.task_id);
  assert.ok(JSON.stringify((await state()).program.tasks[1].history).includes(message));
  const large = await freezeAtCurrentSequence();
  assert.ok(large - small < message.length, 'The receipt must not copy even one copy of the unrelated message');

  assert.equal((await service.command({ op: 'unfreeze', task_id: taskId })).reply.ok, true);
  const old = 'Earlier selected conversation message '.repeat(120);
  assert.equal((await service.command({ op: 'send', task_id: taskId, message: old })).reply.ok, true);
  await taskIdle(service, taskId);
  const settled = await state();
  assert.ok(JSON.stringify(settled.program.tasks[taskId].history).includes(old));
  const current = 'New selected conversation message';
  const { text, receipt } = await submit({ op: 'send', task_id: taskId, message: current }, settled.sequence);
  assert.ok(!text.includes(old));
  assert.ok(receipt.updates.some(update => update.tasks.some(row =>
    row.id === taskId && JSON.stringify(row.appended).includes(current))));

  await taskIdle(service, taskId);
  const firstFork = await service.command({ op: 'fork', task_id: taskId, child_count: 1 });
  assert.equal(firstFork.reply.ok, true, JSON.stringify(firstFork.reply));
  const firstChild = Number(firstFork.reply.result.children[0]);
  await Promise.all([taskIdle(service, taskId), taskIdle(service, firstChild)]);
  const beforeSibling = await state();
  const priorCapacity = beforeSibling.program.tasks[firstChild].fork.capacities[1];
  const { receipt: nextFork } = await submit({ op: 'fork', task_id: taskId, child_count: 1 },
    beforeSibling.sequence);
  const notices = nextFork.updates.flatMap(update => update.references).filter(row => row.id === firstChild);
  assert.equal(notices.at(-1)?.value.fork.capacities[1].descendants, priorCapacity.descendants + 1,
    'A new sibling updates the shared ancestor capacity of an existing child');
});

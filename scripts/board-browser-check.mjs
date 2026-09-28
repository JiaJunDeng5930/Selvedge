import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from '../tests-bend/support.mjs';
import { browser } from '../tests-bend/fixtures/browser.mjs';

// Browser -> authenticated HTTP -> native Bend -> SQLite -> provider/file I/O.
// All accounts, model responses, directories and Chrome profiles are fixtures.
const cleanups = [], t = { after: cleanup => cleanups.push(cleanup) };
const output = path.resolve('.workpad/board-webui');
await mkdir(output, { recursive: true });
const checks = [];
let site, ui;
const checked = label => { checks.push(label); console.log(`PASS ${label}`); };
const okay = result => { assert.equal(result.reply.ok, true, JSON.stringify(result.reply)); return result.reply.result; };
try {
  const previous = process.env.SELVEDGE_BOARD_BROWSER_KEY;
  process.env.SELVEDGE_BOARD_BROWSER_KEY = 'loopback-browser-fixture';
  t.after(() => { if (previous === undefined) delete process.env.SELVEDGE_BOARD_BROWSER_KEY; else process.env.SELVEDGE_BOARD_BROWSER_KEY = previous; });
  const upstream = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: '{"title":"整理后的任务标题","description":"整理后的任务描述，仍保留原始意图。"}' }] }]);
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    ...defaultConfig.profiles,
    draft: { provider: 'responses', model: 'board-browser-fixture', endpoint: upstream.endpoint, api_key_env: 'SELVEDGE_BOARD_BROWSER_KEY' },
  } });
  site = await startServer({ home: directory, cwd: directory, config });
  t.after(() => site.close());
  const stages = ['backlog', 'todo', 'in_progress', 'in_review', 'done', 'blocked'];
  const titles = ['探索新的协作方式', '保留清晰的执行边界', '改进工具执行反馈', '检查完整的任务流程', '整理已经完成的工作', '等待外部接口确认'];
  for (let index = 0; index < stages.length; index++) okay(await site.service.command({ op: 'create_card',
    title: titles[index], description: '从任务卡片进入工作。描述、优先级、负责人和标签在同一处管理。',
    status: stages[index], priority: ['none', 'high', 'medium', 'low', 'none', 'urgent'][index], labels: ['Selvedge', '看板'],
  }));
  ui = await browser(await home(t)); t.after(() => ui.close());
  await ui.call('Emulation.setDeviceMetricsOverride', { width: 1720, height: 1000, deviceScaleFactor: 1, mobile: false });
  await ui.call('Page.navigate', { url: site.url });
  await ui.wait('document.querySelector("#connection")?.dataset.status === "connected"');
  async function click(selector) {
    await ui.wait(`document.querySelector(${JSON.stringify(selector)})?.getClientRects().length`);
    const point = await ui.evaluate(`(() => {
      const node = document.querySelector(${JSON.stringify(selector)}); node.scrollIntoView({block:'nearest',inline:'nearest'});
      const r = node.getBoundingClientRect(); const x = r.left+r.width/2, y = r.top+r.height/2;
      if (!node.contains(document.elementFromPoint(x,y))) throw new Error('Control is covered: ' + ${JSON.stringify(selector)});
      return {x,y}; })()`);
    await ui.call('Input.dispatchMouseEvent', { type: 'mousePressed', button: 'left', buttons: 1, clickCount: 1, ...point });
    await ui.call('Input.dispatchMouseEvent', { type: 'mouseReleased', button: 'left', buttons: 0, clickCount: 1, ...point });
  }
  async function fill(selector, value) {
    await ui.wait(`document.querySelector(${JSON.stringify(selector)}) && !document.querySelector(${JSON.stringify(selector)}).disabled`);
    await ui.evaluate(`(() => { const input = document.querySelector(${JSON.stringify(selector)});
      if (!input || input.disabled) throw new Error('Editable field missing: ' + ${JSON.stringify(selector)});
      input.focus(); input.value = ${JSON.stringify(value)}; input.dispatchEvent(new Event('input',{bubbles:true})); })()`);
  }
  const readCard = async id => okay(await site.service.command({ op: 'read_card', card_id: id }));
  await click('[data-action="nav/board"]');
  await ui.wait('document.querySelectorAll(".board-column").length === 7 && document.querySelectorAll(".board-card").length === 6');
  assert.equal(await ui.evaluate('document.querySelectorAll(".board-tabs > button").length'), 3);
  await ui.screenshot(path.join(output, 'board-light.png'));
  checked('Native six-column board, archive target and navigation render in an actual browser');

  const sequence = site.service.journal.sequence;
  await click('[data-action="view/assigned"]');
  await ui.wait('document.querySelectorAll(".board-card").length === 0');
  await click('[data-action="view/all"]');
  await ui.wait('document.querySelectorAll(".board-card").length === 6');
  await fill('.board-search', '协作');
  await ui.wait('document.querySelectorAll(".board-card").length === 1');
  await fill('.board-search', '');
  await ui.wait('document.querySelectorAll(".board-card").length === 6');
  assert.equal(site.service.journal.sequence, sequence, 'Search and tab changes must not create journal writes');
  checked('Native tab/search filtering is read-only and does not create task records');

  await click('[data-action="new-card"]');
  await ui.wait('document.querySelector(".board-dialog[open]")?.dataset.kind === "create"');
  await fill('.board-dialog input[name="title"]', '浏览器创建的任务');
  await fill('.board-dialog textarea[name="description"]', '这段内容在原生刷新之后不能丢失。');
  await ui.evaluate('window.boardDraftField = document.querySelector(".board-dialog textarea[name=description]"); boardDraftField.setSelectionRange(3,7)');
  okay(await site.service.command({ op: 'board_settings', automatic: false, draft_profile: 'draft' }));
  await ui.wait('document.querySelector(".board-dialog textarea[name=description]") === window.boardDraftField');
  assert.equal(await ui.evaluate('window.boardDraftField.value'), '这段内容在原生刷新之后不能丢失。');
  await ui.screenshot(path.join(output, 'create-dialog.png'));
  await click('.board-dialog .widget-form button[type="submit"]');
  await ui.wait('!document.querySelector(".board-dialog[open]")');
  const created = await readCard(6);
  assert.equal(created.title, '浏览器创建的任务'); assert.equal(created.description, '这段内容在原生刷新之后不能丢失。');
  checked('Real create form submits native bindings and retains an unsent draft across SSE refresh');

  await click('[data-card="card/6"]');
  await ui.wait('document.querySelector(".board-dialog[open]")?.dataset.kind === "card"');
  await fill('.board-dialog input[name="title"]', '浏览器编辑后的任务');
  await click('.board-dialog .widget-form button[type="submit"]');
  await ui.wait(`document.querySelector('.board-card[data-card="card/6"] .board-card-title')?.textContent === '浏览器编辑后的任务'`);
  assert.equal((await readCard(6)).title, '浏览器编辑后的任务');
  await ui.wait('!document.querySelector(".board-dialog[open]")');
  checked('The detail form fills declared optional patch fields without altering command identity');

  const points = await ui.evaluate(`(() => {
    const source = document.querySelector('[data-card="card/0"]'); const target = document.querySelector('[data-status="todo"] .board-cards');
    source.scrollIntoView({block:'nearest',inline:'nearest'});
    const a=source.getBoundingClientRect(),b=target.getBoundingClientRect();
    return {from:{x:a.left+80,y:a.top+55},to:{x:b.left+b.width/2,y:b.top+20}}; })()`);
  await ui.call('Input.dispatchMouseEvent', { type: 'mousePressed', button: 'left', buttons: 1, clickCount: 1, ...points.from });
  for (let step = 1; step <= 12; step++) await ui.call('Input.dispatchMouseEvent', { type: 'mouseMoved', button: 'left', buttons: 1,
    x: points.from.x + (points.to.x - points.from.x) * step / 12, y: points.from.y + (points.to.y - points.from.y) * step / 12 });
  await ui.call('Input.dispatchMouseEvent', { type: 'mouseReleased', button: 'left', buttons: 0, clickCount: 1, ...points.to });
  await ui.wait(`document.querySelector('[data-card="card/0"]')?.closest('.board-column')?.dataset.status === 'todo'`);
  assert.equal((await readCard(0)).status, 'todo');
  assert.equal(await ui.evaluate('document.querySelectorAll(".board-drag-ghost").length'), 0);
  checked('Actual pointer drag submits the revision-bound native move and cleans its ghost');

  const reorder = await ui.evaluate(`(() => {
    const from=document.querySelector('[data-card="card/6"]').getBoundingClientRect();
    const to=document.querySelector('[data-card="card/1"]').getBoundingClientRect();
    return {from:{x:from.left+70,y:from.top+50},to:{x:to.left+90,y:to.top+5}};
  })()`);
  await ui.call('Input.dispatchMouseEvent', { type: 'mousePressed', button: 'left', buttons: 1, clickCount: 1, ...reorder.from });
  for (let step=1;step<=12;step++) await ui.call('Input.dispatchMouseEvent', { type:'mouseMoved',button:'left',buttons:1,
    x:reorder.from.x+(reorder.to.x-reorder.from.x)*step/12,y:reorder.from.y+(reorder.to.y-reorder.from.y)*step/12 });
  await ui.call('Input.dispatchMouseEvent', { type:'mouseReleased',button:'left',buttons:0,clickCount:1,...reorder.to });
  await ui.wait(`Array.from(document.querySelectorAll('[data-status="todo"] .board-card')).map(n=>n.dataset.card).join(',')==='card/0,card/6,card/1'`);
  assert.equal(await ui.evaluate('document.querySelectorAll(".board-drag-ghost,.is-drop-before").length'), 0);
  checked('Same-column pointer reordering uses an authoritative native insertion target');

  await new Promise(resolve => setTimeout(resolve, 400)); // The drag gesture suppresses its synthetic click.
  await click('[data-card="card/6"]');
  await ui.wait('document.querySelector(".board-dialog[open] textarea[name=description]")');
  const blockedDuringUpload = await ui.evaluate(`(() => {
    const data=new DataTransfer(); data.items.add(new File(['browser attachment'], 'browser-note.txt', {type:'text/plain'}));
    document.querySelector('.board-dialog textarea[name="description"]').dispatchEvent(new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData:data}));
    return document.querySelector('.board-dialog button[type="submit"]').disabled;
  })()`);
  assert.equal(blockedDuringUpload, true);
  await ui.wait(`document.querySelector('.board-dialog .collection-values')?.innerText.includes('browser-note.txt') || Array.from(document.querySelectorAll('.board-dialog .collection-values')).some(n=>n.innerText.includes('browser-note.txt'))`);
  await click('.board-dialog .collection-attachments .collection-values button');
  await ui.wait('document.querySelector(".attachment-preview[open] .attachment-download")');
  assert.equal(await ui.evaluate('document.querySelectorAll(".attachment-preview img").length'), 0);
  await click('.attachment-preview > button');
  await click('.board-dialog .widget-form button[type="submit"]');
  await ui.wait('!document.querySelector(".board-dialog[open]")');
  assert.equal((await readCard(6)).attachments[0].name, 'browser-note.txt');
  checked('Pasted files use authenticated storage, block incomplete submission, preview safely and persist');

  await click('[data-action="new-card"]');
  await click('.board-dialog [data-desktop-menu-trigger][aria-label="优先级"]');
  await ui.evaluate('document.querySelector(\'[data-desktop-menu="choice"] input\').focus()');
  await ui.call('Input.insertText', { text: '高' });
  await ui.wait('document.querySelectorAll(\'[data-desktop-menu="choice"] [role="menuitemradio"]\').length === 1');
  await ui.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowDown', code: 'ArrowDown', windowsVirtualKeyCode: 40 });
  await ui.wait('document.activeElement.dataset.value === "high"');
  await ui.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 });
  await ui.wait('!document.querySelector(\'[data-desktop-menu="choice"]\')');
  await click('[data-action="create/keep"]');
  await ui.wait(`document.querySelector('[data-action="create/keep"]')?.getAttribute('aria-checked') === 'true'`);
  await fill('.board-dialog input[name="title"]', '连续创建一');
  await click('.board-dialog button[type="submit"]');
  await ui.wait('document.querySelector(".board-dialog[open] input[name=title]")?.value === ""');
  assert.equal(await ui.evaluate('document.querySelector(".board-dialog select[name=priority]").value'), 'high');
  assert.equal((await readCard(7)).priority, 'high');
  await fill('.board-dialog input[name="title"]', '连续创建二');
  await click('[data-action="create/keep"]');
  await click('.board-dialog button[type="submit"]');
  await ui.wait('!document.querySelector(".board-dialog[open]")');
  assert.equal((await readCard(8)).priority, 'high');
  checked('Searchable property pickers and continuous creation retain parameters while clearing submitted content');

  await click('[data-action="nav/agents"]');
  await click('[data-action="agents/new"]');
  await fill('.board-dialog input[name="name"]', '实现助手');
  await fill('.board-dialog textarea[name="instructions"]', '先验证需求，再实现变更。');
  await click('.board-dialog .widget-form button[type="submit"]');
  await ui.wait('document.querySelector(".board-entity h2")?.textContent === "实现助手"');
  await ui.screenshot(path.join(output, 'agents.png'));
  checked('Agent configuration is created through the browser rather than a browser-side task scheduler');

  await click('[data-action="nav/board"]');
  await click('[data-action="new-card"]');
  await click('[data-action="create/assisted"]');
  await ui.wait('!document.querySelector(".board-dialog input[name=title]") && document.querySelector(".board-dialog select[name=draft_profile]")');
  await fill('.board-dialog textarea[name="description"]', '请保留我的原意，帮助整理标题。');
  await click('.board-dialog .widget-form button[type="submit"]');
  await ui.wait('Array.from(document.querySelectorAll(".board-card-title")).some(node => node.textContent === "整理后的任务标题")');
  assert.equal(upstream.requests.length, 1); assert.deepEqual(upstream.requests[0].tools, []);
  checked('Assisted capture reaches the independent real SSE drafting adapter and updates the saved card');

  await ui.evaluate('document.documentElement.dataset.theme="dark"');
  await ui.screenshot(path.join(output, 'board-dark.png'));
  await ui.call('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await ui.wait('document.body.dataset.sidebar === "closed"');
  assert.equal(await ui.evaluate('document.documentElement.scrollWidth <= innerWidth'), true);
  await click('[data-action="new-card"]');
  await ui.wait('document.querySelector(".board-dialog[open]")?.dataset.kind === "create"');
  assert.equal(await ui.evaluate('document.querySelector(".board-dialog").getBoundingClientRect().width <= innerWidth'), true);
  await ui.screenshot(path.join(output, 'board-mobile-dialog.png'));
  await ui.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
  await ui.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
  await ui.wait('!document.querySelector(".board-dialog[open]")');
  checked('Dark/narrow layouts stay within the viewport and Escape closes the native dialog');
  assert.deepEqual(ui.errors, []); assert.deepEqual(upstream.failures, []);
  await writeFile(path.join(output, 'checks.json'), JSON.stringify({ checks, browserErrors: ui.errors, endpointFailures: upstream.failures }, null, 2) + '\n');
} catch (error) {
  if (ui) {
    await ui.screenshot(path.join(output, 'failure.png')).catch(() => {});
    await writeFile(path.join(output, 'failure.json'), JSON.stringify({ message: error.stack, checks, browserErrors: ui.errors,
      page: await ui.evaluate('document.body.innerText').catch(() => '') }, null, 2) + '\n');
  }
  throw error;
} finally {
  for (const cleanup of cleanups.reverse()) await cleanup();
}

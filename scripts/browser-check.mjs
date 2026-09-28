import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { chatgptFixture, jsonResponse, modelResponse } from '../tests-bend/fixtures/chatgpt.mjs';
import { taskIdle, shellQuote } from '../tests-bend/support.mjs';
import { browser } from '../tests-bend/fixtures/browser.mjs';

// A real browser + HTTP/SSE provider + native kernel + SQLite. No user account,
// external model request, personal browser profile, or installed npm UI framework.
const cleanups = [];
const t = { after: cleanup => cleanups.push(cleanup) };
const output = path.resolve('.workpad/chatgpt-webui');
await mkdir(output, { recursive: true });
const checks = [];
let browserUI;
let site;
let pending;
let calls = 0;
let nextToolCall;
let performanceResult;
const first = '## A smoother conversation\n\nThe renderer keeps **stable content** in place while new text arrives.\n\n```javascript\nconst message = "hello';
const rest = ' world";\nconsole.log(message);\n```\n\n### Three independent layers\n\n- **Target text** absorbs incoming bursts.\n- **Visible text** advances at a controlled pace.\n- **Stable blocks** retain their DOM identity.\n\n| Work | When it runs |\n| --- | --- |\n| Parse new text | Display batch |\n| Highlight code | Code block closes |\n\nThe update cost depends on the new suffix: $T(n) = O(n)$.\n\n> Keep the conversation readable, even while the model is working.\n\n[OpenAI](https://openai.com) · [Unsafe link](javascript:alert(1))\n\n<img src=x onerror=alert(1)>\n\n![Image preview](https://example.com/tracking.png)\n';
const reply = text => ({ type: 'message', role: 'assistant', phase: 'final_answer', content: [{ type: 'output_text', text }] });
try {
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.method === 'GET') return jsonResponse(response, { models: [{ slug: 'gui-fixture', display_name: 'GUI fixture', visibility: 'list',
      priority: 0, default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium' }] }] });
    if (request.body.input.at(-1)?.type === 'compaction_trigger') return modelResponse(response, [{ type: 'compaction', encrypted_content: 'fixture-checkpoint' }]);
    if (nextToolCall) {
      const call = nextToolCall; nextToolCall = undefined;
      return modelResponse(response, [call]);
    }
    if (++calls !== 1) return modelResponse(response, [reply('Follow-up accepted. Your workspace is ready.')]);
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.write(`data: ${JSON.stringify({ type: 'response.output_text.delta', output_index: 0, delta: first })}\r\n\r\n`);
    pending = {
      finish() {
        response.write(`data: ${JSON.stringify({ type: 'response.output_text.delta', output_index: 0, delta: rest })}\n\n`);
        response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [reply(first + rest)] } })}\n\n`);
      },
    };
  });
  const config = validateConfig({ ...defaultConfig, port: 0, profiles: {}, chatgpt: { ...upstream.profile, timeout_ms: 30000 } });
  site = await startServer({ home: upstream.directory, config, cwd: upstream.directory });
  browserUI = await browser(upstream.directory);
  const { evaluate, wait, call } = browserUI;
  const click = async selector => {
    const point = await evaluate(`(() => { const element = document.querySelector(${JSON.stringify(selector)}); const rect = element.getBoundingClientRect();
      const x = rect.x + rect.width / 2, y = rect.y + rect.height / 2;
      return { x, y, visible: rect.width > 0 && rect.height > 0, hit: element.contains(document.elementFromPoint(x, y)) }; })()`);
    assert.ok(point.visible && point.hit, `${selector} must be reachable by a pointer`);
    await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: point.x, y: point.y, button: 'left', clickCount: 1 });
    await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: point.x, y: point.y, button: 'left', clickCount: 1 });
  };
  await call('Emulation.setDeviceMetricsOverride', { width: 1360, height: 940, deviceScaleFactor: 1, mobile: false });
  await call('Page.navigate', { url: site.url });
  await wait('document.querySelector("select[name=profile]")?.options.length === 1 && document.querySelector("#connection").dataset.status === "connected"');
  assert.equal(await evaluate('document.querySelector("textarea[name=settings]").checkVisibility()'), false);
  await click('.form-options > summary');
  assert.ok(await evaluate('document.querySelector("textarea[name=settings]").checkVisibility()'));
  await call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
  await wait('!document.querySelector(".form-options").open');
  assert.equal(await evaluate('document.querySelector(".brand-mark")'), null);
  await browserUI.screenshot(path.join(output, 'webui-new-task.png'));
  await evaluate(`{ const form = document.querySelector('form[data-key$="/create"]');
    const input = form.querySelector('textarea'); input.value = 'Explain how the streaming renderer works and show an implementation.';
    input.dispatchEvent(new Event('input')); form.requestSubmit(); }`);
  await wait('document.querySelector(".live-preview .code-block code")?.textContent.includes("hell")');
  assert.ok(pending);
  await evaluate(`window.stableHeading = document.querySelector('.live-preview h2'); window.stableCode = document.querySelector('.live-preview pre code');
    window.stableComposer = document.querySelector('form[data-key$="/send/0"] textarea');
    window.stableComposer.value = 'An unsent draft survives unrelated work.'; window.stableComposer.dispatchEvent(new Event('input'));
    window.stableComposer.focus(); window.stableComposer.setSelectionRange(5, 9);`);
  const profile = Object.keys(site.service.config.profiles)[0];
  await site.service.command({ op: 'create', profile, message: 'Background boundary probe.' });
  await taskIdle(site.service, 1);
  await wait('document.querySelectorAll("nav button[aria-current]").length >= 5');
  assert.deepEqual(await evaluate(`({ same: stableComposer === document.querySelector('form[data-key$="/send/0"] textarea'),
    focused: document.activeElement === stableComposer, text: stableComposer.value, start: stableComposer.selectionStart,
    heading: stableHeading === document.querySelector('.live-preview h2'), code: stableCode === document.querySelector('.live-preview pre code') })`),
  { same: true, focused: true, text: 'An unsent draft survives unrelated work.', start: 5, heading: true, code: true });
  checks.push('live SSE preview, native refresh, stable code/heading/editor identity, focus and draft');
  pending.finish();
  await taskIdle(site.service);
  await wait('document.querySelector("[data-role=assistant] .markdown h2") && !document.querySelector(".live-preview")');
  await wait('document.querySelector("[data-decorated=code]") && document.querySelector("math")');
  const markup = await evaluate(`({ heading: stableHeading === document.querySelector('[data-role=assistant] h2'),
    code: stableCode === document.querySelector('[data-role=assistant] pre code'),
    scripts: document.querySelectorAll('.markdown script, .markdown img, .markdown [onerror]').length,
    badLinks: [...document.querySelectorAll('.markdown a[href]')].filter(a => !/^(https?:|mailto:|#)/.test(a.getAttribute('href'))).length,
    table: document.querySelectorAll('.markdown table').length, rawHtml: document.querySelector('.markdown').textContent.includes('<img src=x onerror=alert(1)>') })`);
  assert.deepEqual(markup, { heading: true, code: true, scripts: 0, badLinks: 0, table: 1, rawHtml: true });
  checks.push('checkpointed preview adoption without rebuilding the stable prefix; worker code/math; safe HTML/links/images');

  // Scroll-up readers must not be yanked back down by another task's commit.
  await evaluate(`document.querySelector('.thread-scroll').scrollTop = 0`);
  await delay(80);
  await site.service.command({ op: 'send', task_id: 1, message: 'Background refresh.' });
  await taskIdle(site.service, 1);
  await delay(150);
  assert.equal(await evaluate('document.querySelector(".thread-scroll").scrollTop'), 0);
  checks.push('scroll anchoring while reading previous output');
  await browserUI.screenshot(path.join(output, 'webui-desktop.png'));
  await evaluate('document.getElementById("theme-toggle").click()');
  await browserUI.screenshot(path.join(output, 'webui-dark.png'));
  await evaluate('document.getElementById("theme-toggle").click()');
  await call('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await wait('document.body.dataset.sidebar === "closed"');
  assert.ok(await evaluate('document.documentElement.scrollWidth <= innerWidth'));
  await browserUI.screenshot(path.join(output, 'webui-mobile.png'));
  await click('#sidebar-toggle');
  assert.ok(await evaluate('!document.getElementById("sidebar-dismiss").hidden && document.querySelector(".workspace").inert'));
  await browserUI.screenshot(path.join(output, 'webui-mobile-navigation.png'));
  await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: 370, y: 160, button: 'left', clickCount: 1 });
  await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 370, y: 160, button: 'left', clickCount: 1 });
  await wait('document.body.dataset.sidebar === "closed" && !document.querySelector(".workspace").inert');
  await call('Emulation.setDeviceMetricsOverride', { width: 1360, height: 940, deviceScaleFactor: 1, mobile: false });
  await wait('document.body.dataset.sidebar === "open"');
  await click('#access-toggle');
  assert.ok(await evaluate('document.getElementById("access").open && document.activeElement.id === "token"'));
  await click('#access-close');
  assert.ok(await evaluate('!document.getElementById("access").open'));
  checks.push('desktop/mobile overflow, light/dark presentation, reachable settings, mobile scrim/inert background, access dialog focus');

  const before = calls;
  await evaluate(`stableComposer.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', ctrlKey: true, isComposing: true, bubbles: true }));`);
  await evaluate(`stableComposer.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', shiftKey: true, bubbles: true }));`);
  await delay(80); assert.equal(calls, before);
  await evaluate(`stableComposer.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));`);
  await wait('document.querySelector("[data-role=transcript]").textContent.includes("Follow-up accepted")');
  assert.equal(await evaluate(`document.querySelector('form[data-key$="/send/0"] textarea').value`), '');
  await click('.compose-mode > summary');
  await click('.compose-tab:nth-child(2)');
  assert.equal(await evaluate(`document.querySelector('form[data-key$="/steer/0"]').hidden`), false);
  assert.equal(await evaluate(`document.querySelectorAll('.compose-tab')[1].getAttribute('aria-checked')`), 'true');
  await click('.compose-mode > summary');
  await click('.compose-tab:first-child');
  await click('.thread-header [aria-label="Task details"]');
  const command = async key => {
    await wait(`document.querySelector('[data-key$="/${key}"]') && !document.querySelector('[data-key$="/${key}"]').disabled`);
    await evaluate(`document.querySelector('[data-key$="/${key}"]').click()`);
  };
  await command('controls/freeze');
  await wait('document.querySelector(".thread-header h2").textContent.includes("frozen")');
  await command('controls/unfreeze');
  await wait('!document.querySelector(".thread-header h2").textContent.includes("frozen")');
  await evaluate(`document.querySelector('[data-key$="/advanced"]').open = true;`);
  await command('compact/0');
  await wait('document.querySelector("[data-role=transcript]").textContent.includes("Provider context retained")');
  await browserUI.screenshot(path.join(output, 'webui-details.png'));
  checks.push('IME-safe Enter-to-send and Shift-Enter, pointer-driven send/steer menu, native action binding, manual account compaction');

  // Exercise native permission requests through actual browser clicks. The
  // provider only proposes the command; no test driver supplies an approval.
  for (const decision of ['allow', 'deny']) {
    const marker = path.join(upstream.directory, `browser-${decision}.txt`);
    const bash = `printf approved >> ${shellQuote(marker)}`;
    nextToolCall = { type: 'function_call', call_id: `browser-${decision}`, name: 'bash', arguments: JSON.stringify({
      command: bash, sandbox_permissions: 'require_escalated', justification: 'Write only the specific file requested by the user.',
    }) };
    const created = await site.service.command({ op: 'create', profile, message: `Write only ${marker}.`,
      settings: { workspace: { roots: [] }, approval: { mode: 'ask-for-approval' } } });
    assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
    const id = created.reply.result.task_id;
    await command(`select/${id}`);
    await wait('document.querySelector("[data-role=approval]")');
    const page = (await site.service.command({ op: 'read', task_id: id })).reply.result;
    const operation = page.task.operations.find(operation => operation.status === 'awaiting_approval');
    assert.ok(operation);
    assert.equal(await evaluate('document.querySelector("[data-role=command] .message-body").textContent'), bash);
    assert.equal(await evaluate(`document.querySelector('[data-role="approval"] [data-key$="/review/cwd"] .message-body').textContent`), '/');
    await assert.rejects(readFile(marker), { code: 'ENOENT' });
    await call('Emulation.setDeviceMetricsOverride', decision === 'deny'
      ? { width: 390, height: 844, deviceScaleFactor: 1, mobile: true }
      : { width: 1360, height: 940, deviceScaleFactor: 1, mobile: false });
    await wait(`document.body.dataset.sidebar === ${JSON.stringify(decision === 'deny' ? 'closed' : 'open')}`);
    await evaluate(`document.querySelector('[data-role=approval]').scrollIntoView({block:'center'});`);
    assert.ok(await evaluate('document.documentElement.scrollWidth <= innerWidth'));
    const selector = `[data-key$="/approval/${decision}/${operation.operation_id}"]`;
    await wait(`document.querySelector(${JSON.stringify(selector)}) && !document.querySelector(${JSON.stringify(selector)}).disabled`);
    const point = await evaluate(`(() => { const button = document.querySelector(${JSON.stringify(selector)});
      const box = button.getBoundingClientRect(); const x = box.x + box.width / 2, y = box.y + box.height / 2;
      return { x, y, visible: box.width > 0 && box.height >= 40 && box.top >= 0 && box.bottom <= innerHeight,
        unobscured: button.contains(document.elementFromPoint(x, y)) }; })()`);
    assert.equal(point.visible, true);
    assert.equal(point.unobscured, true, 'Review controls must not be covered by floating UI');
    await browserUI.screenshot(path.join(output, decision === 'allow' ? 'webui-approval-desktop.png' : 'webui-approval-mobile.png'));
    await call('Input.dispatchMouseEvent', { type: 'mousePressed', x: point.x, y: point.y, button: 'left', clickCount: 1 });
    await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: point.x, y: point.y, button: 'left', clickCount: 1 });
    const settled = await taskIdle(site.service, id);
    await wait('!document.querySelector("[data-role=approval]")');
    assert.equal(settled.messages.find(message => message.role === 'approval_record').content.decision, decision);
    if (decision === 'allow') assert.equal(await readFile(marker, 'utf8'), 'approved');
    else await assert.rejects(readFile(marker), { code: 'ENOENT' });
  }
  await call('Emulation.setDeviceMetricsOverride', { width: 1360, height: 940, deviceScaleFactor: 1, mobile: false });
  await wait('document.body.dataset.sidebar === "open"');
  checks.push('visible desktop/mobile permission requests, exact command/cwd, browser approve-once and deny, no preapproval execution');

  const syntax = 'Before **bold** and *emphasis*.\n\n- first\n- second with [a link](https://example.com)\n\n```js\nconst x = "<tag>";\n```\n\nAfter 😃.\n';
  const syntaxResult = await evaluate(`(async () => {
    const { Markdown } = await import('/markdown.mjs');
    const source = ${JSON.stringify(syntax)};
    function render(chunks) {
      const root = document.createElement('div'); let now = 0; const queued = [];
      const markdown = new Markdown(root, { frame: callback => queued.push(callback), cancel() {}, smooth: false });
      const flush = () => { while (queued.length) queued.shift()(now += 32); };
      for (const chunk of chunks) { markdown.append(chunk); flush(); }
      markdown.finish(); flush(); markdown.dispose(); return root;
    }
    const whole = render([source]); const split = render([...source]);
    return { same: whole.innerHTML === split.innerHTML, strong: split.querySelector('strong')?.textContent,
      emphasis: split.querySelector('em')?.textContent, items: split.querySelectorAll('li').length,
      link: split.querySelector('a')?.getAttribute('href'), code: split.querySelector('pre code')?.textContent.trimEnd() };
  })()`);
  assert.deepEqual(syntaxResult, { same: true, strong: 'bold', emphasis: 'emphasis', items: 2,
    link: 'https://example.com/', code: 'const x = "<tag>";' });
  checks.push('chunk-invariant emphasis, links, lists, fences and Unicode through the actual DOM sink');

  // No entire-document reparse when an append-only answer grows. The timing
  // measurement is reported with this environment, not asserted as a theorem.
  performanceResult = await evaluate(`(async () => {
    const { Markdown } = await import('/markdown.mjs');
    const root = document.createElement('div'); root.className = 'markdown'; document.getElementById('surface').replaceChildren(root);
    const text = '## Stable prefix\\n\\n' + 'A bounded display update preserves the stable structure and selection.\\n\\n'.repeat(2400);
    const longTasks = [];
    const observer = new PerformanceObserver(list => longTasks.push(...list.getEntries()));
    observer.observe({ type: 'longtask' });
    const markdown = new Markdown(root, { smooth: false });
    const start = performance.now();
    for (let i = 0; i < text.length; i += 17) markdown.append(text.slice(i, i + 17));
    if (root.childNodes.length) throw new Error('Arrival unexpectedly rendered synchronously');
    markdown.finish();
    await new Promise(resolve => requestAnimationFrame(resolve));
    const heading = root.querySelector('h2');
    await new Promise((resolve, reject) => { const deadline = Date.now() + 10000; const check = () => {
      if (markdown.buffer.stopped) resolve(); else if (Date.now() > deadline) reject(new Error('Markdown did not settle')); else setTimeout(check, 20);
    }; check(); });
    await new Promise(resolve => setTimeout(resolve, 80));
    observer.disconnect();
    const observed = longTasks.filter(entry => entry.startTime >= start);
    const result = { characters: text.length, ...markdown.buffer.metrics, sameHeading: heading === root.querySelector('h2'),
      stableBlocks: markdown.stableBlocks, elapsedMs: Math.round(performance.now() - start),
      longTasks: observed.length, maxLongTaskMs: Math.max(0, ...observed.map(entry => entry.duration)) };
    markdown.dispose(); return result;
  })()`);
  assert.equal(performanceResult.sameHeading, true);
  assert.ok(performanceResult.largestBatch <= 4096);
  assert.ok(performanceResult.stableBlocks >= 2400);
  assert.ok(performanceResult.batches < 100);
  checks.push('long-answer bounded batches and stable DOM prefix');
  assert.deepEqual(upstream.failures, []);
  assert.deepEqual(browserUI.errors, []);
  const result = { checks, performance: performanceResult, browserErrors: browserUI.errors };
  await writeFile(path.join(output, 'browser-results.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  if (browserUI) {
    await browserUI.screenshot(path.join(output, 'webui-failure.png')).catch(() => {});
    console.error('Browser errors:', browserUI.errors);
  }
  throw error;
} finally {
  await browserUI?.close();
  await site?.close();
  for (const cleanup of cleanups.reverse()) await cleanup();
}

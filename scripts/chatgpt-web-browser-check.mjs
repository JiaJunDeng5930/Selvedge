import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { validateConfig, defaultConfig } from '../host/config.mjs';
import { home, taskIdle } from '../tests-bend/support.mjs';
import { webServer, answer } from '../tests-bend/fixtures/chatgpt-web.mjs';
import { browser } from '../tests-bend/fixtures/browser.mjs';

// Real Chrome, the native kernel and both HTTP/SSE boundaries. The upstream is
// a strict local v1 fixture; no personal browser profile or model account is used.
const cleanups = [];
const t = { after: cleanup => cleanups.push(cleanup) };
const env = 'SELVEDGE_WEB_BROWSER_FIXTURE';
const old = process.env[env]; process.env[env] = 'local-web-fixture';
const artifacts = path.resolve('.workpad/chatgpt-web-backend');
let site;
let ui;
let pending;
try {
  await mkdir(artifacts, { recursive: true });
  const directory = await home(t);
  const upstream = await webServer(t, async (_, index, transport) => {
    assert.equal(index, 0);
    const { response, id, makeResource, resources, event } = transport;
    resources.set(id, makeResource([], 'in_progress'));
    response.writeHead(200, { 'content-type': 'text/event-stream', 'x-response-id': id, 'x-web-protocol': 'chatgpt-web.v1' });
    event('response.in_progress', { response_id: id, previous_response_id: null });
    pending = {
      snapshot(text) { event('response.output_text.snapshot', { response_id: id, text, provisional: true }); },
      finish() {
        const resource = makeResource(answer('Final authoritative answer.'));
        resources.set(id, resource);
        event('response.completed', { response: resource });
        response.end('data: [DONE]\n\n');
      },
    };
    pending.snapshot('## First provisional heading\n\nA longer answer before revision.');
  });
  const config = validateConfig({ ...defaultConfig, port: 0, chatgpt: false, profiles: {
    web: { provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: upstream.endpoint, api_key_env: env },
  } });
  site = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  ui = await browser(directory);
  const { call, evaluate, wait } = ui;
  await call('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  await call('Page.navigate', { url: site.url });
  await wait('document.querySelector("select[name=profile]")?.options.length === 1 && document.querySelector("#connection").dataset.status === "connected"');
  await evaluate(`{ const form = document.querySelector('form[data-key$="/create"]');
    const input = form.querySelector('textarea'); input.value = 'Check snapshot rendering.';
    input.dispatchEvent(new Event('input')); form.requestSubmit(); }`);
  await wait('document.querySelector(".live-preview h2")?.textContent === "First provisional heading"');
  await evaluate(`window.savedComposer = document.querySelector('form[data-key$="/send/0"] textarea');
    savedComposer.value = 'Keep this unsubmitted draft.'; savedComposer.dispatchEvent(new Event('input'));
    savedComposer.focus(); savedComposer.setSelectionRange(2, 8);`);
  pending.snapshot('Tiny **revision**.\n\n');
  await wait('document.querySelector(".live-preview .markdown")?.textContent === "Tiny revision."');
  assert.equal(await evaluate('document.querySelector(".live-preview h2")'), null);
  pending.snapshot('Tiny **revision**.\n\nPlus 😀.\n\n<img src=x onerror=alert(1)>\n\n');
  await wait('document.querySelector(".live-preview .markdown")?.textContent.includes("Plus 😀.")');
  assert.deepEqual(await evaluate(`({ same: savedComposer === document.querySelector('form[data-key$="/send/0"] textarea'),
    focused: document.activeElement === savedComposer, text: savedComposer.value,
    start: savedComposer.selectionStart, end: savedComposer.selectionEnd,
    unsafe: document.querySelectorAll('.live-preview img, .live-preview [onerror], .live-preview script').length })`),
  { same: true, focused: true, text: 'Keep this unsubmitted draft.', start: 2, end: 8, unsafe: 0 });
  await ui.screenshot(path.join(artifacts, 'revised-preview.png'));
  pending.finish();
  const page = await taskIdle(site.service);
  await wait('!document.querySelector(".live-preview") && document.querySelector("[data-role=assistant] .markdown")?.textContent.includes("Final authoritative answer.")');
  const durable = page.messages.filter(message => message.role === 'assistant');
  assert.deepEqual(durable.map(message => message.content), ['Final authoritative answer.']);
  assert.deepEqual(upstream.failures, []);
  assert.deepEqual(ui.errors, []);
  const result = { checks: [
    'Named API SSE → native service → browser snapshot',
    'Shrinking/revised preview replaces its parser; extension appends',
    'Composer identity, draft, focus and selection survive revisions',
    'Revised text retains safe Markdown behavior',
    'Only the authoritative terminal answer is committed and displayed',
  ] };
  await writeFile(path.join(artifacts, 'result.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  if (ui) {
    await ui.screenshot(path.join(artifacts, 'failure.png')).catch(() => {});
    const view = await ui.evaluate('({ preview: document.querySelector(".live-preview")?.outerHTML, text: document.body.innerText })').catch(() => null);
    await writeFile(path.join(artifacts, 'failure.json'), JSON.stringify({ error: error.message, view }, null, 2) + '\n');
  }
  throw error;
} finally {
  await ui?.close();
  await site?.close();
  for (const cleanup of cleanups.reverse()) await cleanup();
  if (old === undefined) delete process.env[env]; else process.env[env] = old;
}

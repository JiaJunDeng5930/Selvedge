import test from 'node:test';
import assert from 'node:assert/strict';
import { access, readFile, mkdtemp, mkdir, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { observeConnection } from '../host/public/connection.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

test('snapshot HTTP 503 releases its SSE stream and a new connection observes the current snapshot', async t => {
  let snapshots = 0; let subscriptions = 0;
  let firstClosed; let recovered;
  const released = new Promise(resolve => { firstClosed = resolve; });
  const complete = new Promise(resolve => { recovered = resolve; });
  const streams = new Set();
  const server = http.createServer((request, response) => {
    if (request.url === '/api/browser/state') {
      snapshots++;
      response.setHeader('content-type', 'application/json');
      if (snapshots === 2) { response.writeHead(503); response.end('{}'); }
      else response.end(JSON.stringify({ sequence: snapshots === 1 ? 0 : 1 }));
    } else if (request.url.startsWith('/api/events?after=')) {
      const subscription = ++subscriptions;
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.write('data: {"type":"commit","sequence":1}\n\n');
      streams.add(response);
      response.once('close', () => { streams.delete(response); if (subscription === 1) firstClosed(); });
    } else { response.writeHead(404); response.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = `http://127.0.0.1:${server.address().port}`;
  const controller = new AbortController();
  t.after(async () => {
    controller.abort();
    for (const stream of streams) stream.end();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  let sequence = 0;
  const connect = () => observeConnection({
    signal: controller.signal, sequence: () => sequence,
    request: async (url, signal) => {
      const response = await fetch(address + url, { signal });
      if (!response.ok) throw new Error(`snapshot HTTP ${response.status}`);
      return response.json();
    },
    fetchEvents: (url, signal) => fetch(address + url, { signal }),
    snapshot: body => { sequence = body.sequence; if (sequence === 1 && subscriptions === 2) recovered(); },
    ready() {}, notice() {},
  });
  await assert.rejects(connect(), /snapshot HTTP 503/);
  await released;
  const resumed = connect();
  try {
    await Promise.race([complete, resumed.then(() => { throw new Error('Connection ended before recovery'); })]);
  } finally {
    controller.abort();
    // DEFENSE: Stopping the live SSE observation rejects its pending read with AbortError.
    await resumed.catch(error => { if (error.name !== 'AbortError') throw error; });
  }
  assert.equal(sequence, 1);
  assert.equal(subscriptions, 2);
});

async function browserExecutable() {
  const candidates = [process.env.SELVEDGE_BROWSER, '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].filter(Boolean);
  for (const candidate of candidates) {
    try { await access(candidate, constants.X_OK); return candidate; }
    // DEFENSE: The supported Linux/macOS browser paths can be absent or non-executable; disk failures must not be mistaken for an uninstalled browser.
    catch (error) { if (!['ENOENT', 'EACCES', 'ENOTDIR'].includes(error.code)) throw error; }
  }
  throw new Error('Native browser checks require Chromium/Chrome; set SELVEDGE_BROWSER to its executable');
}

test('the native browser preserves IME confirmation and accepts ordinary long streamed output', async t => {
  const executable = await browserExecutable();
  const profile = await mkdtemp(path.join(tmpdir(), 'selvedge-browser-'));
  t.after(() => rm(profile, { recursive: true, force: true }));
  for (const name of ['config', 'cache', 'data', 'runtime']) await mkdir(path.join(profile, name), { mode: 0o700 });
  let report;
  const reported = new Promise(resolve => { report = resolve; });
  const server = http.createServer((request, response) => {
    const url = new URL(request.url, 'http://localhost');
    const pathname = url.pathname;
    if (pathname === '/result') {
      response.writeHead(204); response.end();
      report({ preserved: url.searchParams.get('preserved') === '1',
        streamed: url.searchParams.get('streamed') === '1', unicode: url.searchParams.get('unicode') === '1',
        linked: url.searchParams.get('linked') === '1', error: url.searchParams.get('error') });
      return;
    }
    if (pathname === '/') {
      response.setHeader('content-type', 'text/html; charset=utf-8');
      response.end(`<!doctype html><textarea id="editor"></textarea><script type="module">
import * as Bend from '/public/generated/browser-model.mjs';
import {editorKeyboard,scalarSelection,applyScalarSelection} from '/public/keyboard.mjs';
import {boundary} from '/public/model-boundary.mjs';
import {Markdown} from '/public/markdown.mjs';
const editor=document.getElementById('editor'); let submitted=0;
editor.addEventListener('keydown', event=>editorKeyboard(event,Bend.native_editor_key,()=>submitted++));
editor.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true}));
const confirmation=new KeyboardEvent('keydown',{key:'Enter',keyCode:229,isComposing:false,bubbles:true,cancelable:true});
editor.dispatchEvent(confirmation);
editor.value='中😀@abc后'; editor.setSelectionRange(3,6);
const selection=scalarSelection(editor);
applyScalarSelection(editor,{start:5n,end:5n,direction:'none'});
const unicode=selection.start===2n&&selection.end===5n&&editor.selectionStart===6&&document.activeElement===editor;
let streamed=false; let linked=true; let error='';
try {
  const source='[$skill](/path/SKILL.md) [x](/path) [energy $x$](/math) $x$';
  for (const split of [source.length,source.indexOf('(')]) {
    const target=document.createElement('div'); document.body.append(target);
    const markdown=new Markdown(target,{smooth:false});
    markdown.append(source.slice(0,split)); await markdown.whenCaughtUp();
    markdown.append(source.slice(split)); markdown.finish(); await markdown.whenSettled();
    const links=[...target.querySelectorAll('a')];
    linked=linked&&links.length===3&&links[0].textContent==='$skill'&&links[1].textContent==='x'
      &&Boolean(links[2].querySelector('math'))&&target.querySelectorAll('math').length===2
      &&!target.textContent.includes('/path');
    markdown.dispose(); target.remove();
  }
  const text='x'.repeat(16*1024);
  const entry=value=>({task_id:17,ticket:3,parts:[{output_index:5,text:value}]});
  const result=boundary('browser.stream_step',{state:[entry('prefix:')],
    notice:{type:'delta',task_id:17,ticket:3,output_index:5,text}});
  streamed=result.publish&&result.state[0].parts[0].text==='prefix:'+text;
} catch (failure) {linked=false; error=String(failure);}
fetch('/result?'+new URLSearchParams({
  preserved:Number(confirmation.keyCode===229&&submitted===0&&!confirmation.defaultPrevented),
  streamed:Number(streamed),unicode:Number(unicode),linked:Number(linked),error}));
</script>`); return;
    }
    let filename;
    if (pathname.startsWith('/public/')) {
      const base = path.join(repository, 'host/public');
      filename = path.resolve(base, pathname.slice('/public/'.length));
      if (!filename.startsWith(base + path.sep)) { response.writeHead(400); response.end(); return; }
    } else { response.writeHead(404); response.end(); return; }
    void readFile(filename).then(body => {
      response.setHeader('content-type', 'text/javascript'); response.end(body);
    }).catch(error => { response.writeHead(500); response.end(error.message); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const address = `http://127.0.0.1:${server.address().port}`;
  const browser = spawn(executable, ['--headless', '--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu',
    '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update',
    '--disable-sync', '--disable-breakpad', '--disable-crash-reporter', '--password-store=basic',
    `--user-data-dir=${path.join(profile, 'browser')}`, address], {
    detached: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, XDG_CONFIG_HOME: path.join(profile, 'config'), XDG_CACHE_HOME: path.join(profile, 'cache'),
      XDG_DATA_HOME: path.join(profile, 'data'), XDG_RUNTIME_DIR: path.join(profile, 'runtime'), GSETTINGS_BACKEND: 'memory' },
  });
  const browserClosed = new Promise((resolve, reject) => { browser.once('error', reject); browser.once('close', resolve); });
  let stdout = ''; let stderr = '';
  browser.stdout.on('data', data => { stdout += data; }); browser.stderr.on('data', data => { stderr += data; });
  const stopBrowser = () => {
    // DEFENSE: A failed spawn has no PID; an exited browser may already have released its process group before cleanup.
    if (browser.pid === undefined) return;
    try { process.kill(-browser.pid, 'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
  };
  try {
    const result = await Promise.race([reported,
      browserClosed.then(code => { throw new Error(`Native browser exited before its result: ${browser.signalCode ?? code}`); }),
    ]);
    assert.equal(result.preserved, true, 'The native IME confirmation was intercepted as submission');
    assert.equal(result.streamed, true, result.error || 'The native browser rejected ordinary streamed output');
    assert.equal(result.unicode, true, 'Native UTF-16 selection did not preserve Bend scalar positions');
    assert.equal(result.linked, true, result.error || 'Dollar-prefixed links lost their label or consumed the destination as math');
  } catch (error) { assert.fail(`${error.stack ?? error}\nstdout:\n${stdout}\nstderr:\n${stderr}`); }
  finally { stopBrowser(); await browserClosed; }
});

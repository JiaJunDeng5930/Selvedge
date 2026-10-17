import test from 'node:test';
import assert from 'node:assert/strict';
import { access, readFile, mkdtemp, mkdir, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { browserBoundaryModel } from './browser-model-support.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

async function browserExecutable() {
  const candidates = [process.env.SELVEDGE_BROWSER, '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].filter(Boolean);
  for (const candidate of candidates) {
    try { await access(candidate, constants.X_OK); return candidate; } catch {}
  }
  throw new Error('Native browser checks require Chromium/Chrome; set SELVEDGE_BROWSER to its executable');
}

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function devToolsEndpoint(directory, browser, deadline) {
  while (Date.now() < deadline) {
    if (browser.pid === undefined) throw new Error('Native browser could not be started');
    if (browser.exitCode !== null || browser.signalCode !== null) throw new Error('Native browser exited before opening DevTools');
    try {
      const [port, endpoint] = (await readFile(path.join(directory, 'DevToolsActivePort'), 'utf8')).trim().split('\n');
      if (port && endpoint) return `ws://127.0.0.1:${port}${endpoint}`;
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await delay(50);
  }
  throw new Error('Native browser did not open DevTools before its deadline');
}

async function connectDevTools(endpoint, diagnostics) {
  const socket = new WebSocket(endpoint);
  const pending = new Map();
  const requests = new Map();
  let sequence = 0;
  socket.addEventListener('message', event => {
    const message = JSON.parse(String(event.data));
    if (message.id) {
      const request = pending.get(message.id);
      if (!request) return;
      pending.delete(message.id); clearTimeout(request.timeout);
      if (message.error) request.reject(new Error(`CDP ${request.method}: ${JSON.stringify(message.error)}`));
      else request.resolve(message.result);
      return;
    }
    const { method, params } = message;
    if (method === 'Runtime.consoleAPICalled') diagnostics.push(`console.${params.type}: ${params.args.map(argument => argument.value ?? argument.description ?? argument.type).join(' ')}`);
    else if (method === 'Runtime.exceptionThrown') diagnostics.push(`runtime: ${params.exceptionDetails.exception?.description ?? params.exceptionDetails.text}`);
    else if (method === 'Network.requestWillBeSent') requests.set(params.requestId, params.request.url);
    else if (method === 'Network.loadingFailed') diagnostics.push(`network: ${requests.get(params.requestId)}: ${params.errorText}`);
    else if (method === 'Network.responseReceived' && params.response.status >= 400) diagnostics.push(`HTTP ${params.response.status}: ${params.response.url}`);
  });
  socket.addEventListener('close', () => {
    for (const request of pending.values()) { clearTimeout(request.timeout); request.reject(new Error(`DevTools closed during ${request.method}`)); }
    pending.clear();
  });
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { reject(new Error('Native browser DevTools connection timed out')); socket.close(); }, 10_000);
    socket.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, { once: true });
    socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('Native browser DevTools connection failed')); }, { once: true });
  });
  return {
    send(method, params = {}, sessionId) {
      const id = ++sequence;
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`CDP ${method} timed out`)); }, 10_000);
        pending.set(id, { resolve, reject, timeout, method });
        try { socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) })); }
        catch (error) { pending.delete(id); clearTimeout(timeout); reject(error); }
      });
    },
    close() { socket.close(); },
  };
}

async function browserResult(devTools, address, deadline) {
  const { targetId } = await devTools.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await devTools.send('Target.attachToTarget', { targetId, flatten: true });
  await devTools.send('Page.enable', {}, sessionId);
  await devTools.send('Runtime.enable', {}, sessionId);
  await devTools.send('Network.enable', {}, sessionId);
  const navigation = await devTools.send('Page.navigate', { url: address }, sessionId);
  if (navigation.errorText) throw new Error(`Native browser navigation failed: ${navigation.errorText}`);
  while (Date.now() < deadline) {
    let observation;
    try { observation = await devTools.send('Runtime.evaluate', { expression: 'document.getElementById("result")?.textContent ?? null', returnByValue: true }, sessionId); }
    catch (error) {
      if (!/Execution context was destroyed|Cannot find (default execution )?context/.test(error.message)) throw error;
      await delay(50); continue;
    }
    if (observation.exceptionDetails) throw new Error(observation.exceptionDetails.exception?.description ?? observation.exceptionDetails.text);
    const text = observation.result.value;
    if (typeof text === 'string' && text !== 'pending') return JSON.parse(text);
    await delay(50);
  }
  throw new Error('Native browser did not complete its fixture before its deadline');
}

test('production browser interpreters preserve actual DOM, IME, CSSOM, focus, measurement and stored appearance', { timeout: 180_000 }, async t => {
  const executable = await browserExecutable();
  const { output } = await browserBoundaryModel(t);
  const profile = await mkdtemp(path.join(tmpdir(), 'selvedge-browser-'));
  t.after(() => rm(profile, { recursive: true, force: true }));
  for (const name of ['config', 'cache', 'data', 'runtime']) await mkdir(path.join(profile, name), { mode: 0o700 });
  const fixture = await readFile(new URL('./fixtures/browser-dom.mjs', import.meta.url));
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (pathname === '/') {
      response.setHeader('content-type', 'text/html');
      response.end('<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/public/vendor/desktop-tokens.css"><link rel="stylesheet" href="/public/style.css"><link rel="stylesheet" href="/public/physical-markdown.css"><div id="surface"></div><pre id="result">pending</pre><script type="module" src="/fixture.mjs"></script>'); return;
    }
    if (pathname === '/storage') {
      response.setHeader('content-type', 'text/html');
      response.end('<!doctype html><script type="module">import * as Model from "/boundary.mjs";import {appearanceObservation} from "/public/appearance.mjs";const observation=appearanceObservation(localStorage);const state=Model.service_step({...observation,$:"interaction/services/MODEL.AppearanceRestored"},Model.service_initial()).state;parent.postMessage({kind:"restored-appearance",appearance:state.appearance.$.split(".").at(-1)},location.origin);</script>'); return;
    }
    if (pathname === '/fixture.mjs') { response.setHeader('content-type', 'text/javascript'); response.end(fixture); return; }
    let filename;
    if (pathname === '/boundary.mjs') filename = output;
    else if (pathname.startsWith('/public/')) {
      const base = path.join(repository, 'host/public');
      filename = path.resolve(base, pathname.slice('/public/'.length));
      if (!filename.startsWith(base + path.sep)) { response.writeHead(400); response.end(); return; }
    } else { response.writeHead(404); response.end(); return; }
    void readFile(filename).then(body => {
      response.setHeader('content-type', filename.endsWith('.css') ? 'text/css' : 'text/javascript'); response.end(body);
    }).catch(error => { response.writeHead(500); response.end(error.message); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const address = `http://127.0.0.1:${server.address().port}`;
  const deadline = Date.now() + 90_000;
  const browser = spawn(executable, ['--headless', '--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu',
    '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update',
    '--disable-sync', '--disable-breakpad', '--disable-crash-reporter', '--password-store=basic',
    `--user-data-dir=${path.join(profile, 'browser')}`, '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0', 'about:blank'], {
    detached: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, XDG_CONFIG_HOME: path.join(profile, 'config'), XDG_CACHE_HOME: path.join(profile, 'cache'),
      XDG_DATA_HOME: path.join(profile, 'data'), XDG_RUNTIME_DIR: path.join(profile, 'runtime'), GSETTINGS_BACKEND: 'memory' },
  });
  const browserClosed = new Promise(resolve => browser.once('close', resolve));
  let stdout = ''; let stderr = '';
  let startupError;
  browser.once('error', error => { startupError = error; });
  browser.stdout.on('data', data => { stdout += data; }); browser.stderr.on('data', data => { stderr += data; });
  const stopBrowser = () => {
    if (browser.pid === undefined) return;
    try { process.kill(-browser.pid, 'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
  };
  const timeout = setTimeout(stopBrowser, 90_000);
  t.after(() => { clearTimeout(timeout); stopBrowser(); });
  const diagnostics = [];
  let result;
  try {
    const endpoint = await devToolsEndpoint(path.join(profile, 'browser'), browser, deadline);
    if (startupError) throw startupError;
    const devTools = await connectDevTools(endpoint, diagnostics);
    t.after(() => devTools.close());
    result = await browserResult(devTools, address, deadline);
  } catch (error) {
    assert.fail(`${startupError?.stack ?? error.stack ?? error}\n${diagnostics.join('\n')}\nstdout:\n${stdout}\nstderr:\n${stderr}`);
  } finally { clearTimeout(timeout); stopBrowser(); await browserClosed; }
  assert.equal(result.ok, true, result.error);
  assert.deepEqual(result.result, { renderer: true, composition: true, keyboard: true, focus: true, geometry: true, measurement: true, storage: true });
});

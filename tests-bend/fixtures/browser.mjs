import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { access, readFile, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';

export async function browser(directory) {
  const candidates = [process.env.CHROME_BIN, '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome'].filter(Boolean);
  let binary;
  for (const candidate of candidates) { try { await access(candidate); binary = candidate; break; } catch {} }
  if (!binary) throw new Error('A Chrome/Chromium installation is required; set CHROME_BIN to its executable.');
  const chrome = spawn(binary, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--remote-debugging-port=0', `--user-data-dir=${directory}/chrome`, 'about:blank'],
  { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  const errors = [];
  const pending = new Map();
  let socket;
  chrome.stderr.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(-8000); });
  const close = async () => {
    for (const job of pending.values()) { clearTimeout(job.timer); job.reject(new Error('Browser closed')); }
    pending.clear(); socket?.close();
    if (chrome.exitCode === null && chrome.signalCode === null) {
      chrome.kill('SIGTERM');
      await Promise.race([new Promise(resolve => chrome.once('close', resolve)), delay(2000)]);
      if (chrome.exitCode === null && chrome.signalCode === null) chrome.kill('SIGKILL');
    }
  };
  try {
    let port;
    for (let attempt = 0; attempt < 120; attempt++) {
      if (chrome.exitCode !== null || chrome.signalCode !== null) throw new Error(`Chrome exited: ${stderr}`);
      try { port = (await readFile(`${directory}/chrome/DevToolsActivePort`, 'utf8')).split('\n')[0]; break; }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      await delay(50);
    }
    assert.ok(port, 'Chrome must expose an isolated debugging port');
    const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
    let nextId = 0;
    socket.addEventListener('message', event => {
      const result = JSON.parse(event.data);
      if (result.method === 'Runtime.exceptionThrown') errors.push(result.params.exceptionDetails.exception?.description ?? result.params.exceptionDetails.text);
      const job = pending.get(result.id);
      if (job) { pending.delete(result.id); clearTimeout(job.timer); result.error ? job.reject(new Error(JSON.stringify(result.error))) : job.resolve(result.result); }
    });
    const call = (method, params = {}) => new Promise((resolve, reject) => {
      const id = ++nextId;
      pending.set(id, { resolve, reject, timer: setTimeout(() => { pending.delete(id); reject(new Error(`CDP timed out: ${method}`)); }, 15000) });
      socket.send(JSON.stringify({ id, method, params }));
    });
    const evaluate = async expression => {
      const result = await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
      return result.result.value;
    };
    const wait = async predicate => {
      try {
        return await evaluate(`new Promise((resolve, reject) => { const end = Date.now() + 10000; const poll = () => {
          if (${predicate}) resolve(true); else if (Date.now() > end) reject(new Error('UI condition timed out')); else setTimeout(poll, 20);
        }; poll(); })`);
      } catch (error) { throw new Error(`${predicate}: ${error.message}`); }
    };
    await call('Runtime.enable'); await call('Page.enable');
    return { call, evaluate, wait, errors, close,
      screenshot: async file => { const shot = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }); await writeFile(file, Buffer.from(shot.data, 'base64')); },
    };
  } catch (error) { await close(); throw error; }
}

import assert from 'node:assert/strict';
import { fork } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../../host/server.mjs';
import { defaultConfig, validateConfig } from '../../host/config.mjs';
import { home, responsesServer } from '../support.mjs';

export const answer = text => [{ type: 'message', role: 'assistant',
  content: [{ type: 'output_text', text }] }];

export async function filesystemChild(t, options, env = process.env) {
  const filename = fileURLToPath(new URL('./filesystem-boundaries-child.mjs', import.meta.url));
  const child = fork(filename, [JSON.stringify(options)], { env, silent: true });
  let stopped = false, stderr = '';
  child.stdout.resume();
  child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-4096); });
  const exited = new Promise(resolve => child.once('exit', () => { stopped = true; resolve(); }));
  const close = async (signal = 'SIGTERM') => {
    if (stopped) return;
    child.kill(signal);
    let forced = false;
    // DEFENSE: A regressed server shutdown must not leave its fixture running after a failed test.
    const timer = setTimeout(() => { forced = true; child.kill('SIGKILL'); }, 5000);
    await exited;
    clearTimeout(timer);
    assert.equal(forced, false, 'The filesystem fixture must shut down within five seconds');
  };
  t.after(() => close());
  let timer;
  const ready = await new Promise((resolve, reject) => {
    child.once('message', resolve);
    child.once('error', reject);
    child.once('exit', (code, signal) => reject(new Error(`Filesystem server exited before startup (${code ?? signal}): ${stderr}`)));
    timer = setTimeout(() => reject(new Error(`Filesystem server did not start: ${stderr}`)), 15000);
  }).finally(() => clearTimeout(timer));
  async function command(command) {
    const response = await fetch(`${ready.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${ready.token}`, 'content-type': 'application/json' }, body: JSON.stringify(command) });
    const reply = await response.json();
    assert.equal(response.status, 200, JSON.stringify(reply));
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  return { command, close, child };
}

export async function filesystemServer(t, { directory, state, cwd, respond, config: overrides = {} } = {}) {
  directory ??= await home(t);
  state ??= path.join(directory, 'state');
  cwd ??= directory;
  await mkdir(state, { recursive: true });
  const upstream = respond && await responsesServer(t, respond, { measure: () => 128 });
  const key = `SELVEDGE_FILESYSTEM_FIXTURE_${process.pid}_${Math.random().toString(16).slice(2)}`;
  if (upstream) {
    process.env[key] = 'loopback-fixture';
    t.after(() => { delete process.env[key]; });
  }
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    ...(upstream ? { profiles: { ...defaultConfig.profiles, fixture: { provider: 'responses', model: 'filesystem-fixture',
      endpoint: upstream.endpoint, api_key_env: key, timeout_ms: 5000 } } } : {}), ...overrides });
  const running = await startServer({ home: state, cwd, config });
  t.after(() => running.close());
  const headers = { authorization: `Bearer ${running.token}` };
  async function command(command) {
    const response = await fetch(`${running.address}/api/commands`, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify(command),
    });
    const reply = await response.json();
    assert.equal(response.status, 200, JSON.stringify(reply));
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  async function idle(taskId, { timeout = 10_000, completed = () => true } = {}) {
    const deadline = Date.now() + timeout;
    let page;
    do {
      page = await command({ op: 'read', task_id: taskId });
      if (page.task.phase === 'idle' && page.task.operations.length === 0 && completed()) {
        if (upstream) assert.deepEqual(upstream.failures, []);
        return page;
      }
      await delay(20);
    } while (Date.now() < deadline);
    throw new Error(`Filesystem scenario did not settle: ${JSON.stringify(page)}`);
  }
  return { directory, state, running, headers, command, idle, upstream,
    profile: upstream ? 'fixture' : 'demo' };
}

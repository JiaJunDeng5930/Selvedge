import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { events } from '../host/network.mjs';
import { home } from './support.mjs';

test('the physical server issues a working cookie, delivers committed SSE and serves the discovered CLI', async t => {
  const directory = await home(t);
  const running = await startServer({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0 }) });
  t.after(() => running.close());
  assert.equal((await fetch(`${running.address}/api/health`)).status, 401);
  const page = await fetch(running.url);
  assert.equal(page.status, 200);
  const headers = { cookie: page.headers.get('set-cookie').split(';')[0], origin: running.address };
  assert.equal((await fetch(`${running.address}/api/health`, { headers })).status, 200);
  const controller = new AbortController();
  const stream = await fetch(`${running.address}/api/events?after=0`, { headers, signal: controller.signal });
  const iterator = events(stream.body, running.service.limits.frame_bytes);
  try {
    assert.equal(JSON.parse((await iterator.next()).value).type, 'stream-state');
    assert.deepEqual(JSON.parse((await iterator.next()).value),
      { type: 'commit', namespace: running.service.journal.namespace, sequence: running.service.journal.sequence });
  } finally {
    controller.abort();
    // DEFENSE: Aborting the live SSE read can reject iterator cleanup with AbortError.
    await iterator.return().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
  const cli = fileURLToPath(new URL('../host/cli.mjs', import.meta.url));
  const described = await promisify(execFile)(process.execPath, [cli, '--home', directory, 'describe']);
  assert.deepEqual(JSON.parse(described.stdout), running.service.description);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, loadConfig } from '../host/config.mjs';
import { events } from '../host/network.mjs';
import { home } from './support.mjs';

test('the physical server authenticates observations, discovers skills before any task, and serves committed SSE and the CLI', async t => {
  const directory = await realpath(await home(t));
  const skill = path.join(directory, 'skills', 'fixture (space)#%', 'SKILL.md');
  await mkdir(path.dirname(skill), { recursive: true });
  await writeFile(skill, '---\nname: fixture\ndescription: Current skill metadata\n---\nPRIVATE-SKILL-BODY');
  const filename = path.join(directory, 'config.json');
  await writeFile(filename, JSON.stringify({ ...defaultConfig, chatgpt: false, port: 0, skills: [skill] }));
  const { config } = await loadConfig({ home: directory });
  const running = await startServer({ home: directory, cwd: directory, config });
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
  const observe = async () => {
    const response = await fetch(`${running.address}/api/browser/observation`, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'skill-catalog', workspace: { roots: [directory], primary_root: directory } }),
    });
    assert.equal(response.status, 200);
    return response.json();
  };
  const catalog = await observe();
  assert.equal(catalog.kind, 'skill-catalog');
  assert.equal(catalog.ok, true, JSON.stringify(catalog));
  assert.deepEqual(catalog.skills, [{ name: 'fixture', description: 'Current skill metadata', path: skill }]);
  assert.equal(JSON.stringify(catalog).includes('PRIVATE-SKILL-BODY'), false);
  await writeFile(filename, '{invalid');
  const failed = await observe();
  assert.equal(failed.ok, false);
  assert.match(failed.error, /configuration.*not valid JSON/i);
  assert.equal(Object.hasOwn(failed, 'skills'), false);
});

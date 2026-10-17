import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, stat } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import { home } from './support.mjs';

const execute = promisify(execFile);
const cliUrl = new URL('../host/cli.mjs', import.meta.url);
const cli = fileURLToPath(cliUrl);
const relayUrl = 'https://example.workers.dev';

test('remote init keeps configuration fields and private credentials out of CLI output', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'config.json');
  const original = { ...structuredClone(defaultConfig), instructions: 'Keep the original configuration.', port: 0 };
  await writeFile(filename, JSON.stringify(original));
  const enrollmentToken = randomBytes(32).toString('base64url');
  // NOTE: This isolated child replaces only HTTPS delivery; native configuration
  // admission, identity persistence and CLI configuration writes are production.
  const script = `
    const { main } = await import(${JSON.stringify(cliUrl.href)});
    let registration;
    globalThis.fetch = async (url, options) => {
      if (url !== ${JSON.stringify(`${relayUrl}/v1/hosts/register`)} || options.method !== 'POST'
        || options.headers.authorization !== 'Bearer ' + process.env.SELVEDGE_RELAY_ENROLLMENT_TOKEN) {
        throw new Error('Unexpected CLI registration request');
      }
      registration = JSON.parse(options.body);
      return Response.json({ host_id: registration.host_id }, { status: 201 });
    };
    await main(['--home', ${JSON.stringify(directory)}, 'remote', 'init', '--relay-url', ${JSON.stringify(`${relayUrl}/`)}]);
    if (!registration || typeof registration.host_token !== 'string') throw new Error('Missing host registration');
  `;
  const result = await execute(process.execPath, ['--eval', script], {
    timeout: 15_000, env: { ...process.env, SELVEDGE_RELAY_ENROLLMENT_TOKEN: enrollmentToken },
  });
  const output = JSON.parse(result.stdout);
  assert.equal(output.ok, true);
  assert.equal(output.restart_required, true);
  assert.equal(output.result.relay_url, relayUrl);
  const saved = JSON.parse(await readFile(filename, 'utf8'));
  assert.deepEqual(saved, { ...original, remote: { relay_url: relayUrl } });
  const identityFile = path.join(directory, 'remote-identity.json');
  const identity = JSON.parse(await readFile(identityFile, 'utf8'));
  assert.equal(output.result.host_id, identity.host_id);
  assert.equal((await stat(identityFile)).mode & 0o777, 0o600);
  assert.equal((await stat(filename)).mode & 0o777, 0o600);
  for (const secret of [enrollmentToken, identity.host_token]) {
    assert.ok(!result.stdout.includes(secret));
    assert.ok(!result.stderr.includes(secret));
    assert.ok(!JSON.stringify(saved).includes(secret));
  }
});

test('remote CLI uses local server discovery and rejects missing enrollment without writing identity', async t => {
  const directory = await home(t);
  const server = await startServer({ home: directory, cwd: directory, config: validateConfig({ ...defaultConfig, port: 0 }) });
  t.after(() => server.close());
  const result = await execute(process.execPath, [cli, '--home', directory, 'remote', 'status'], { timeout: 10_000 });
  const output = JSON.parse(result.stdout);
  assert.equal(output.ok, true);
  assert.equal(output.result.configured, false);
  assert.equal(output.result.enabled, false);
  const pending = await execute(process.execPath, [cli, '--home', directory, 'remote', 'pending'], { timeout: 10_000 });
  assert.deepEqual(JSON.parse(pending.stdout), { ok: true, result: [] });
  const disabled = await execute(process.execPath, [cli, '--home', directory, 'remote', 'disable'], { timeout: 10_000 });
  assert.equal(JSON.parse(disabled.stdout).result.enabled, false);
  const env = { ...process.env };
  delete env.SELVEDGE_RELAY_ENROLLMENT_TOKEN;
  await assert.rejects(execute(process.execPath, [cli, '--home', directory, 'remote', 'init', '--relay-url', relayUrl], { timeout: 10_000, env }),
    error => error.code === 1 && error.stderr.includes('Set SELVEDGE_RELAY_ENROLLMENT_TOKEN'));
  await assert.rejects(readFile(path.join(directory, 'remote-identity.json')), { code: 'ENOENT' });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, readFile, symlink, writeFile, stat, access } from 'node:fs/promises';
import path from 'node:path';
import { saveConnection, packageConnection } from '../plugins/selvedge-chatgpt/bin/setup.mjs';
import { loadSettings } from '../plugins/selvedge-chatgpt/src/client.mjs';
import { home } from './support.mjs';

test('installed connection secrets require private owned files and never leak through parse diagnostics', async t => {
  const base = await home(t);
  const env = { SELVEDGE_URL: 'http://127.0.0.1:7421', SELVEDGE_CONNECTION_ID: '0', SELVEDGE_CONNECTION_TOKEN: 'a'.repeat(43) };
  const filename = await saveConnection(path.join(base, 'data'), env);
  assert.equal((await stat(filename)).mode & 0o777, 0o600);
  const selected = { SELVEDGE_CONNECTION_FILE: filename };
  assert.equal((await loadSettings(selected)).connection, '0');
  await assert.rejects(saveConnection(path.join(base, 'data'), env), { code: 'EEXIST' });
  await chmod(filename, 0o644);
  await assert.rejects(loadSettings(selected), /private, owned/);
  await chmod(filename, 0o600);
  const alias = path.join(base, 'alias');
  await symlink(filename, alias);
  await assert.rejects(loadSettings({ SELVEDGE_CONNECTION_FILE: alias }), { code: 'ELOOP' });
  await writeFile(filename, `{"SELVEDGE_CONNECTION_TOKEN":"${env.SELVEDGE_CONNECTION_TOKEN}" trailing`);
  await assert.rejects(loadSettings(selected), error => error.message === 'Invalid connection file JSON');
});

test('deployment packaging binds a registered connection without credentials or duplicate local tools', async t => {
  const base = await home(t), output = path.join(base, 'package');
  const id = 'plugin_asdk_app_fixture';
  await packageConnection(id, output);
  const manifest = JSON.parse(await readFile(path.join(output, 'plugin.json'), 'utf8'));
  const apps = JSON.parse(await readFile(path.join(output, manifest.extensions['com.openai'].apps), 'utf8'));
  assert.equal(apps.apps.selvedge.id, id);
  assert.equal(apps.apps.selvedge.required, true);
  await access(path.join(output, 'skills/local-projects/SKILL.md'));
  await assert.rejects(access(path.join(output, 'mcp.json')), { code: 'ENOENT' });
  await assert.rejects(access(path.join(output, 'connection.json')), { code: 'ENOENT' });
  await assert.rejects(packageConnection(id, output), { code: 'EEXIST' });
  await assert.rejects(packageConnection('tunnel_fixture', path.join(base, 'invalid')), /registered/);
});

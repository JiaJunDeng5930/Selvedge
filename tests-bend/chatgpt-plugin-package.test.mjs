import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, readFile, symlink, writeFile, stat, access, cp, mkdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { saveConnection } from '../plugins/selvedge-chatgpt/bin/setup.mjs';
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
  await writeFile(filename, Buffer.concat([Buffer.from('{"unexpected":"'), Buffer.from([0xff]), Buffer.from('"}')]));
  await assert.rejects(loadSettings(selected), error => error.message === 'Invalid connection file JSON');
});

test('deployment copies only shipped files from a source directory containing private local data', async t => {
  const base = await home(t), source = path.join(base, 'source'), output = path.join(base, 'deployment');
  const root = fileURLToPath(new URL('../plugins/selvedge-chatgpt/', import.meta.url));
  await cp(root, source, { recursive: true, filter: filename =>
    !['node_modules', 'MODEL.bend'].includes(path.basename(filename)) });
  const setup = await import(pathToFileURL(path.join(source, 'bin/setup.mjs')).href);
  await setup.saveConnection(source, { SELVEDGE_URL: 'http://127.0.0.1:7421', SELVEDGE_CONNECTION_ID: '0',
    SELVEDGE_CONNECTION_TOKEN: 'a'.repeat(43) });
  await writeFile(path.join(source, '.env'), 'PRIVATE_LOCAL_CONFIGURATION');
  await mkdir(path.join(source, 'private'));
  await writeFile(path.join(source, 'private', 'secret'), 'PRIVATE_LOCAL_DATA');
  await writeFile(path.join(source, 'src', 'connection.json'), '{"secret":"PRIVATE_NESTED_CONFIGURATION"}');
  const id = 'plugin_asdk_app_fixture';
  await setup.packageConnection(id, output);
  const manifest = JSON.parse(await readFile(path.join(output, 'plugin.json'), 'utf8'));
  const apps = JSON.parse(await readFile(path.join(output, manifest.extensions['com.openai'].apps), 'utf8'));
  assert.equal(apps.apps.selvedge.id, id);
  for (const filename of ['connection.json', '.env', 'private', 'src/connection.json', 'mcp.json', 'MODEL.bend']) {
    await assert.rejects(access(path.join(output, filename)), { code: 'ENOENT' });
  }
  await access(path.join(output, 'generated/model.mjs'));
  await access(path.join(output, 'src/server.mjs'));
});

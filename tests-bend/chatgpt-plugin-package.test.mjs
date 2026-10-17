import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, readFile, symlink, writeFile, stat, access, cp, mkdir } from 'node:fs/promises';
import http from 'node:http';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { saveConnection, packageConnection } from '../plugins/selvedge-chatgpt/bin/setup.mjs';
import { loadSettings, callTool } from '../plugins/selvedge-chatgpt/src/client.mjs';
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

test('deployment packaging binds the registered connection and refuses invalid or existing destinations', async t => {
  const base = await home(t), output = path.join(base, 'package');
  const id = 'plugin_asdk_app_fixture';
  await packageConnection(id, output);
  const manifest = JSON.parse(await readFile(path.join(output, 'plugin.json'), 'utf8'));
  const apps = JSON.parse(await readFile(path.join(output, manifest.extensions['com.openai'].apps), 'utf8'));
  assert.equal(apps.apps.selvedge.id, id);
  assert.equal(apps.apps.selvedge.required, true);
  await access(path.join(output, 'skills/local-projects/SKILL.md'));
  await assert.rejects(packageConnection(id, output), { code: 'EEXIST' });
  await assert.rejects(packageConnection('tunnel_fixture', path.join(base, 'invalid')), /registered/);
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
  await setup.packageConnection('plugin_asdk_app_fixture', output);
  for (const filename of ['connection.json', '.env', 'private', 'src/connection.json', 'mcp.json', 'MODEL.bend']) {
    await assert.rejects(access(path.join(output, filename)), { code: 'ENOENT' });
  }
  await access(path.join(output, 'generated/model.mjs'));
  await access(path.join(output, 'src/server.mjs'));
});

test('the loopback plugin client preserves bytewise Unicode HTTP replies and rejects corrupt UTF-8 bytes', async t => {
  let corrupt = false;
  const server = http.createServer((request, response) => {
    request.resume();
    response.writeHead(200, { 'content-type': 'application/json' });
    const bytes = corrupt
      ? Buffer.concat([Buffer.from('{"ok":true,"result":[{"name":"'), Buffer.from([0xff]), Buffer.from('"}]}')])
      : Buffer.from(JSON.stringify({ ok: true, result: [{ name: '共享 😀' }] }));
    for (const byte of bytes) response.write(Buffer.from([byte]));
    response.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const config = { endpoint: `http://127.0.0.1:${server.address().port}`, connection: '0', token: 'a'.repeat(43) };
  const result = await callTool(config, 'list_projects', {});
  assert.equal(result.structuredContent.result[0].name, '共享 😀');
  assert.equal(result.isError, false);
  corrupt = true;
  await assert.rejects(callTool(config, 'list_projects', {}), /encoded|UTF-8|valid/i);
});

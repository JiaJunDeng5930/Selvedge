import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { Service } from '../host/service.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { saveConnection } from '../plugins/selvedge-chatgpt/bin/setup.mjs';

test('the official MCP SDK launches the installed stdio manifest and calls its HTTP-backed tool', async t => {
  const base = await home(t);
  const state = path.join(base, 'state');
  const initial = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const seed = await Service.open({ home: state, cwd: base, config: initial });
  let project;
  try {
    const created = await seed.command({ op: 'create_project', name: 'Shared fixture', workspace: { roots: [base] } });
    assert.equal(created.reply.ok, true);
    project = created.reply.result.project_id;
  } finally { await seed.close(); }
  const token = randomBytes(32).toString('base64url');
  const key = `SELVEDGE_SDK_${randomBytes(8).toString('hex')}`;
  process.env[key] = token;
  const config = validateConfig({ ...initial, chatgpt_plugin: { connections: {
    0: { token_env: key, project_ids: [project], sandbox: { mode: 'workspace-write', network_access: false } },
  } } });
  let server;
  t.after(async () => { await server?.close(); delete process.env[key]; });
  server = await startServer({ home: state, cwd: base, config });
  const root = fileURLToPath(new URL('../plugins/selvedge-chatgpt/', import.meta.url));
  const data = path.join(base, 'plugin-data');
  const connection = { SELVEDGE_URL: server.address, SELVEDGE_CONNECTION_ID: '0', SELVEDGE_CONNECTION_TOKEN: token };
  await saveConnection(data, connection);
  const manifest = JSON.parse(await readFile(path.join(root, 'mcp.json'), 'utf8')).mcpServers.selvedge;
  const expand = value => value.replaceAll('${PLUGIN_ROOT}', root).replaceAll('${PLUGIN_DATA}', data);
  const open = async () => {
    const client = new Client({ name: 'tunnel-contract-fixture', version: '1' });
    const transport = new StdioClientTransport({
      command: manifest.command, args: manifest.args.map(expand), cwd: expand(manifest.cwd),
      env: Object.fromEntries(Object.entries(manifest.env).map(([key, value]) => [key, expand(value)])), stderr: 'pipe',
    });
    t.after(() => client.close());
    await client.connect(transport);
    return client;
  };
  const client = await open();
  const tools = (await client.listTools()).tools;
  assert.ok(tools.some(tool => tool.name === 'selvedge_list_projects'));
  const listed = await client.callTool({ name: 'selvedge_list_projects', arguments: {} });
  assert.equal(listed.isError, false);
  assert.deepEqual(listed.structuredContent.result.map(project => project.project_id), [project]);
  await client.close();
});

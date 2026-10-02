import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { connectionConfig, connectionCredentials, connectionCommand } from '../host/chatgpt-plugin.mjs';
import { settings } from '../plugins/selvedge-chatgpt/src/client.mjs';
import { tunnelArguments } from '../plugins/selvedge-chatgpt/bin/tunnel.mjs';
import { saveConnection } from '../plugins/selvedge-chatgpt/bin/setup.mjs';
import { pluginFixture } from './chatgpt-plugin-support.mjs';
import { shellQuote } from './support.mjs';

function journal(state) {
  const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
  try { return db.prepare('SELECT seq, input, decision FROM journal ORDER BY seq').all().map(row => ({
    sequence: row.seq, input: JSON.parse(row.input), decision: JSON.parse(row.decision),
  })); } finally { db.close(); }
}

test('plugin configuration has separate identities, credentials and no scope override', () => {
  assert.deepEqual(connectionConfig(), { connections: {} });
  const valid = { connections: { 0: { token_env: 'TOKEN', project_ids: [1] } } };
  assert.equal(connectionConfig(valid).connections[0].sandbox.network_access, false);
  assert.throws(() => connectionConfig({ connections: { '00': valid.connections[0] } }), /ID/);
  assert.throws(() => connectionConfig({ connections: { 0: { ...valid.connections[0], project_ids: [1, 1] } } }), /project_ids/);
  assert.throws(() => connectionConfig({ connections: { 0: { ...valid.connections[0], sandbox: { mode: 'unrestricted', network_access: true } } } }), /restricted/);
  assert.throws(() => connectionCredentials(connectionConfig(valid), { TOKEN: 'too-short' }), /credential|token/i);
  assert.throws(() => connectionCredentials(connectionConfig({ connections: { 0: valid.connections[0], 1: valid.connections[0] } }), { TOKEN: 'a'.repeat(43) }), /distinct/);
  assert.throws(() => connectionCommand(0, { tool: 'exec', arguments: { connection_id: 1 } }), /arguments/);
  assert.throws(() => connectionCommand(0, { tool: 'configure_chatgpt_connections', arguments: {} }), /Unknown/);
  assert.throws(() => settings({ SELVEDGE_URL: 'https://example.com', SELVEDGE_CONNECTION_ID: '0', SELVEDGE_CONNECTION_TOKEN: 'a'.repeat(43) }), /loopback/);
  assert.throws(() => settings({ SELVEDGE_URL: 'http://127.0.0.1:7421/path', SELVEDGE_CONNECTION_ID: '0', SELVEDGE_CONNECTION_TOKEN: 'a'.repeat(43) }), /loopback/);
  const args = tunnelArguments(['init', '--profile', 'test', '--tunnel-id', 'tunnel_test'], { node: '/node bin/node', server: "/root/it's/server.mjs" });
  assert.deepEqual(args.slice(0, 7), ['init', '--sample', 'sample_mcp_stdio_local', '--profile', 'test', '--tunnel-id', 'tunnel_test']);
  assert.equal(args[8], "'/node bin/node' '/root/it'\\''s/server.mjs'");
  assert.deepEqual(tunnelArguments(['doctor']), ['doctor', '--profile', 'selvedge', '--explain']);
  assert.throws(() => tunnelArguments(['run', '--mcp-command', 'evil']), /Invalid/);
});

test('authenticated HTTP, native journal and real shell preserve project scope and deduplicate concurrent retries', { timeout: 40_000 }, async t => {
  const f = await pluginFixture(t);
  const listed = await f.call(0, 'list_projects', {});
  assert.equal(listed.body.ok, true, JSON.stringify(listed));
  assert.deepEqual(listed.body.result.map(project => project.project_id), [f.a]);
  assert.ok(!JSON.stringify(listed).includes('Private B'));
  assert.equal((await f.call(0, 'get_project', { project_id: f.b })).body.error.code, 'project_forbidden');
  assert.equal((await f.request(0, { tool: 'list_projects', arguments: {} }, { authorization: `Bearer ${f.tokens[1]}` })).status, 401);
  assert.equal((await f.request(0, { tool: 'list_projects', arguments: {} }, { origin: f.server.address })).status, 403);
  assert.equal((await fetch(`${f.server.address}/api/commands`, { method: 'POST', headers: {
    authorization: `Bearer ${f.tokens[0]}`, 'content-type': 'application/json',
  }, body: JSON.stringify({ op: 'projects' }) })).status, 401);
  assert.equal((await f.call(0, 'exec', { project_id: f.a, request_id: 'invalid', command: 'true', workspace: { roots: ['/'] } })).status, 400);
  const filename = path.join(f.roots[1], 'once');
  let committedBeforeDispatch = false;
  f.server.service.on('notice', event => {
    if (event.type !== 'commit') return;
    const row = journal(f.state).find(row => row.sequence === event.sequence);
    if (row?.decision.effects.some(effect => effect.kind === 'chatgpt_exec')) committedBeforeDispatch = !existsSync(filename);
  });
  const arguments_ = { project_id: f.a, request_id: randomUUID(), command: 'printf once >> once; printf "Unicode ✓\\n"; pwd' };
  const [first, second] = await Promise.all([f.call(0, 'exec', arguments_), f.call(0, 'exec', arguments_)]);
  assert.equal(first.body.ok, true, JSON.stringify(first));
  assert.equal(second.body.result.operation_id, first.body.result.operation_id);
  const id = first.body.result.operation_id;
  const result = await f.settled(0, id);
  assert.equal(result.error, false, JSON.stringify(result));
  assert.match(result.value.stdout, /Unicode ✓/);
  assert.ok(result.value.stdout.includes(f.roots[1]));
  assert.equal(await readFile(filename, 'utf8'), 'once');
  assert.equal(committedBeforeDispatch, true, 'The native intent must exist before the process can write');
  assert.equal((await f.call(0, 'exec', { ...arguments_, command: 'printf twice >> once' })).body.error.code, 'request_conflict');
  assert.equal((await f.call(3, 'get_operation', { project_id: f.a, operation_id: id })).body.error.code, 'operation_not_found');
  assert.equal((await f.call(1, 'get_operation', { project_id: f.a, operation_id: id })).body.error.code, 'project_forbidden');
  const rows = journal(f.state);
  const effects = rows.flatMap(row => row.decision.effects).filter(effect => effect.kind === 'chatgpt_exec');
  assert.equal(effects.length, 1);
  assert.deepEqual(effects[0].execution.workspace, { roots: f.roots.slice(0, 2), primary_root: f.roots[1] });
  assert.equal(effects[0].execution.scope, 'project');
  assert.equal(effects[0].execution.access, 'sandboxed');
  for (const token of f.tokens) assert.ok(!JSON.stringify(rows).includes(token));
  const sequence = f.server.service.journal.sequence;
  assert.equal((await f.call(0, 'list_operations', { project_id: f.a })).body.result[0].operation_id, id);
  assert.equal(f.server.service.journal.sequence, sequence, 'Reading receipts must not commit or dispatch');
  assert.equal((await f.call(0, 'forget_operation', { project_id: f.a, operation_id: id })).body.ok, true);
  assert.equal((await f.call(0, 'get_operation', { project_id: f.a, operation_id: id })).body.error.code, 'operation_not_found');
});

test('official MCP SDK discovers and calls the standalone stdio package across conversations', { timeout: 40_000 }, async t => {
  const f = await pluginFixture(t);
  const root = fileURLToPath(new URL('../plugins/selvedge-chatgpt/', import.meta.url));
  const data = path.join(f.base, 'plugin-data');
  const connection = { SELVEDGE_URL: f.server.address, SELVEDGE_CONNECTION_ID: '0', SELVEDGE_CONNECTION_TOKEN: f.tokens[0] };
  await saveConnection(data, connection);
  const manifest = JSON.parse(await readFile(path.join(root, 'mcp.json'), 'utf8')).mcpServers.selvedge;
  const expand = value => value.replaceAll('${PLUGIN_ROOT}', root).replaceAll('${PLUGIN_DATA}', data);
  const open = async (installed = true) => {
    const client = new Client({ name: 'tunnel-contract-fixture', version: '1' });
    const transport = new StdioClientTransport(installed ? {
      command: manifest.command, args: manifest.args.map(expand), cwd: expand(manifest.cwd),
      env: Object.fromEntries(Object.entries(manifest.env).map(([key, value]) => [key, expand(value)])), stderr: 'pipe',
    } : { command: process.execPath, args: [path.join(root, 'bin/server.mjs')], env: connection, stderr: 'pipe' });
    t.after(() => client.close());
    await client.connect(transport);
    return client;
  };
  let client = await open();
  const tools = (await client.listTools()).tools;
  assert.equal(tools.length, 7);
  assert.equal(tools.find(tool => tool.name === 'selvedge_exec').annotations.destructiveHint, true);
  assert.equal(tools.find(tool => tool.name === 'selvedge_exec').inputSchema.additionalProperties, false);
  const listed = await client.callTool({ name: 'selvedge_list_projects', arguments: {} });
  assert.equal(listed.isError, false);
  assert.deepEqual(listed.structuredContent.result.map(project => project.project_id), [f.a]);
  const args = { project_id: f.a, request_id: randomUUID(), command: 'printf mcp > mcp-result; cat mcp-result' };
  const started = await client.callTool({ name: 'selvedge_exec', arguments: args });
  assert.equal(started.isError, false, JSON.stringify(started));
  const id = started.structuredContent.result.operation_id;
  await f.settled(0, id);
  await client.close();
  client = await open(false);
  const retry = await client.callTool({ name: 'selvedge_exec', arguments: args });
  assert.equal(retry.structuredContent.result.operation_id, id);
  const read = await client.callTool({ name: 'selvedge_get_operation', arguments: { project_id: f.a, operation_id: id } });
  assert.equal(read.structuredContent.result.value.stdout, 'mcp');
  const rejected = await client.callTool({ name: 'selvedge_exec', arguments: { ...args, workspace: { roots: ['/'] } } });
  assert.equal(rejected.isError, true);
  assert.equal(await readFile(path.join(f.roots[1], 'mcp-result'), 'utf8'), 'mcp');
});

test('shutdown recovery never replays unknown work, and revocation closes the same connection in every chat', { timeout: 40_000 }, async t => {
  const f = await pluginFixture(t);
  const args = { project_id: f.a, request_id: randomUUID(), command: 'printf once >> recovering; sleep 30' };
  const started = await f.call(0, 'exec', args);
  assert.equal(started.body.ok, true, JSON.stringify(started));
  const id = started.body.result.operation_id;
  const filename = path.join(f.roots[1], 'recovering');
  for (let attempt = 0; !existsSync(filename) && attempt < 200; attempt++) await delay(10);
  assert.equal(await readFile(filename, 'utf8'), 'once');
  await f.restart();
  const recovered = await f.settled(0, id);
  assert.equal(recovered.status, 'interrupted');
  assert.equal(recovered.value.error.code, 'outcome_unknown');
  assert.equal((await f.call(0, 'exec', args)).body.result.operation_id, id);
  assert.equal(await readFile(filename, 'utf8'), 'once');
  assert.equal(journal(f.state).flatMap(row => row.decision.effects).filter(effect => effect.kind === 'chatgpt_exec').length, 1);
  const revoked = await f.server.service.command({ op: 'configure_chatgpt_connections', connections: [] });
  assert.equal(revoked.reply.ok, true);
  assert.equal((await f.call(0, 'list_projects', {})).body.error.code, 'project_forbidden');
  assert.equal((await f.call(0, 'get_operation', { project_id: f.a, operation_id: id })).body.error.code, 'project_forbidden');
});

test('cancellation, read-only grants and current Workspace selection cross the real execution boundary', { timeout: 40_000 }, async t => {
  const f = await pluginFixture(t);
  const args = { project_id: f.a, request_id: randomUUID(), command: 'printf started > cancelled; sleep 30; printf late >> cancelled' };
  const started = await f.call(0, 'exec', args);
  assert.equal(started.body.ok, true, JSON.stringify(started));
  const id = started.body.result.operation_id;
  const filename = path.join(f.roots[1], 'cancelled');
  for (let attempt = 0; !existsSync(filename) && attempt < 200; attempt++) await delay(10);
  assert.equal((await f.call(3, 'cancel_operation', { project_id: f.a, operation_id: id })).body.error.code, 'operation_not_found');
  assert.equal((await f.call(0, 'forget_operation', { project_id: f.a, operation_id: id })).body.error.code, 'operation_running');
  assert.equal((await f.call(0, 'cancel_operation', { project_id: f.a, operation_id: id })).body.result.status, 'interrupted');
  await delay(100);
  assert.equal(await readFile(filename, 'utf8'), 'started');
  const readOnly = await f.call(2, 'exec', { project_id: f.a, request_id: randomUUID(), command: 'printf forbidden > readonly-result' });
  assert.equal((await f.settled(2, readOnly.body.result.operation_id)).error, true);
  assert.equal(existsSync(path.join(f.roots[1], 'readonly-result')), false);
  const updated = path.join(f.base, 'updated');
  await mkdir(updated);
  await writeFile(path.join(updated, 'AGENTS.md'), 'New workspace.');
  const changed = await f.server.service.command({ op: 'update_project', project_id: f.a,
    name: 'Shared A', workspace: { roots: [updated] } });
  assert.equal(changed.reply.ok, true, JSON.stringify(changed.reply));
  const next = await f.call(0, 'exec', { project_id: f.a, request_id: randomUUID(),
    command: `pwd; printf current > current; if cat ${shellQuote(filename)}; then exit 77; fi` });
  const done = await f.settled(0, next.body.result.operation_id);
  assert.equal(done.error, false, JSON.stringify(done));
  assert.ok(done.value.stdout.includes(updated));
  assert.equal(await readFile(path.join(updated, 'current'), 'utf8'), 'current');
});

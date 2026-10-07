import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtemp, mkdir, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';

export async function pluginFixture(t) {
  const base = await realpath(await mkdtemp(path.join(tmpdir(), 'selvedge-chatgpt-')));
  const state = path.join(base, 'state');
  const roots = [path.join(base, 'first "root"'), path.join(base, 'primary'), path.join(base, 'other')];
  await Promise.all([state, ...roots].map(root => mkdir(root)));
  await writeFile(path.join(roots[1], 'AGENTS.md'), 'Project-only fixture guidance.');
  let server;
  const variables = [];
  t.after(async () => {
    await server?.close();
    for (const [name, previous] of variables) {
      if (previous === undefined) delete process.env[name]; else process.env[name] = previous;
    }
    await rm(base, { recursive: true, force: true });
  });
  const initial = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const seed = await Service.open({ home: state, cwd: roots[0], config: initial });
  let a, b;
  try {
    const first = await seed.command({ op: 'create_project', name: 'Shared A', workspace: { roots: roots.slice(0, 2), primary_root: roots[1] } });
    const second = await seed.command({ op: 'create_project', name: 'Private B', workspace: { roots: [roots[2]] } });
    assert.equal(first.reply.ok, true, JSON.stringify(first.reply));
    assert.equal(second.reply.ok, true, JSON.stringify(second.reply));
    a = first.reply.result.project_id; b = second.reply.result.project_id;
  } finally { await seed.close(); }
  const tokens = Array.from({ length: 4 }, () => randomBytes(32).toString('base64url'));
  const connections = Object.fromEntries(tokens.map((token, id) => {
    const name = `SELVEDGE_TEST_${randomBytes(8).toString('hex')}`;
    variables.push([name, process.env[name]]);
    process.env[name] = token;
    return [id, { token_env: name, project_ids: [id === 1 ? b : a],
      sandbox: { mode: id === 2 ? 'read-only' : 'workspace-write', network_access: false } }];
  }));
  const config = validateConfig({ ...initial, chatgpt_plugin: { connections } });
  const restart = async () => {
    await server?.close();
    server = await startServer({ home: state, cwd: roots[0], config });
    return server;
  };
  await restart();
  const request = async (connection, body, headers = {}) => {
    const response = await fetch(`${server.address}/api/chatgpt/${connection}`, { method: 'POST',
      headers: { authorization: `Bearer ${tokens[connection]}`, 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  };
  const call = async (connection, tool, arguments_) => request(connection, { tool, arguments: arguments_ });
  const settled = async (connection, operation, project = a) => {
    const deadline = Date.now() + 10_000;
    let reply;
    do {
      reply = await call(connection, 'get_operation', { project_id: project, operation_id: operation });
      assert.equal(reply.body.ok, true, JSON.stringify(reply));
      if (reply.body.result.status !== 'running') return reply.body.result;
      await delay(15);
    } while (Date.now() < deadline);
    throw new Error(`Operation did not settle: ${JSON.stringify(reply)}`);
  };
  return { base, state, roots, a, b, tokens, config, request, call, settled, restart, get server() { return server; } };
}

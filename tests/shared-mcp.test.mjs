import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, loadConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const picture = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAD0lEQVR4nGNgYPgPRmAKABf2A/1+6zfzAAAAAElFTkSuQmCC';
const mcpProgram = String.raw`
  const { appendFileSync } = require('node:fs');
  const { createInterface } = require('node:readline');
  const [log, picture] = process.argv.slice(-2);
  const send = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');
  const tool = name => ({ name, description: 'Capture a fixture image.', inputSchema: { type: 'object' } });
  let alternate = false;
  createInterface({ input: process.stdin }).on('line', line => {
    const { id, method, params } = JSON.parse(line);
    if (method === 'initialize') send(id, { protocolVersion: params.protocolVersion,
      capabilities: { tools: {} }, serverInfo: { name: 'shared-mcp-fixture', version: '1' } });
    if (method === 'tools/list') send(id, params.cursor
      ? { tools: alternate ? [tool('picture'), tool('alternate')] : [tool('picture')] }
      : { tools: [tool('first_page')], nextCursor: 'second-page' });
    if (method === 'tools/call') {
      appendFileSync(log, JSON.stringify({ pid: process.pid, tag: params.arguments.tag }) + '\n');
      if (params.arguments.tag === 'local Mac') {
        alternate = true;
        process.stdout.write('{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}\n');
      }
      setTimeout(() => send(id, { content: [{ type: 'text', text: 'Picture from ' + params.arguments.tag },
        { type: 'image', mimeType: 'image/png', data: picture }] }), 75);
    }
  });
`;

async function cli(location, ...args) {
  const child = Bun.spawn([process.execPath, 'host/cli.mjs', '--home', location, 'mcp', ...args],
    { stdout: 'pipe', stderr: 'pipe' });
  const [out, err, exit] = await Promise.all([new Response(child.stdout).text(),
    new Response(child.stderr).text(), child.exited]);
  assert.equal(exit, 0, err);
  return out;
}

test('a receiver shares its existing MCP process with global tools and durable calls', async t => {
  const directory = await home(t);
  const mac = path.join(directory, 'mac');
  const vps = path.join(directory, 'vps');
  const workspace = path.join(directory, 'workspace');
  await Promise.all([mac, vps, workspace].map(folder => mkdir(folder)));
  const cert = path.join(directory, 'receiver.pem');
  const key = path.join(directory, 'receiver-key.pem');
  const token = path.join(directory, 'receiver-token');
  const calls = path.join(mac, 'calls.jsonl');
  const privateCalls = path.join(mac, 'private.jsonl');
  const secret = randomBytes(32).toString('base64url');
  await writeFile(token, secret, { mode: 0o600 });
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1', '-keyout', key, '-out', cert], { stdio: 'pipe' });
  const keyEnv = 'SELVEDGE_SHARED_MCP_TEST_API_KEY';
  process.env[keyEnv] = 'shared-mcp-test';
  t.after(() => { delete process.env[keyEnv]; });
  let next;
  const provider = await responsesServer(t, body => {
    if (next) {
      const { tool, tag } = next;
      next = undefined;
      assert.ok(body.tools.some(definition => definition.name === tool), tool);
      return [{ type: 'function_call', name: tool, call_id: tag, arguments: JSON.stringify({ tag }) }];
    }
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];
  });
  const config = { ...defaultConfig, chatgpt: false, port: 0,
    profiles: { fixture: { provider: 'responses', model: 'shared-mcp-fixture', endpoint: provider.endpoint, api_key_env: keyEnv } } };
  const program = filename => ({ command: process.execPath, args: ['-e', mcpProgram, filename, picture] });
  const configFile = (location, value) => writeFile(path.join(location, 'config.json'), JSON.stringify(value));
  await configFile(mac, { ...config, mcp: { cua: program(calls), private: program(privateCalls) },
    execution_receiver: { host: '127.0.0.1', port: 0, cert_file: cert, key_file: key, token_file: token, mcp_servers: [] } });
  assert.match(await cli(mac, 'export', '--server', 'cua'), /configuration saved/);
  const receiver = await startServer({ ...await loadConfig({ home: mac }), cwd: workspace });
  t.after(() => receiver.close());
  const url = 'wss://127.0.0.1:' + receiver.service.executionReceiver.address.port + '/execution';
  await configFile(vps, { ...config, execution_environments: [{ id: 'mac', url, ca_file: cert, token_file: token }] });
  assert.deepEqual(JSON.parse(await cli(vps, 'list', '--environment', 'mac')), ['cua']);
  assert.match(await cli(vps, 'import', '--environment', 'mac', '--server', 'cua', '--name', 'mac_cua'), /configuration saved/);
  const caller = await startServer({ ...await loadConfig({ home: vps }), cwd: workspace });
  t.after(() => caller.close());

  async function runTool(running, tool, tag, settings = {}) {
    const { service, address, token } = running;
    next = { tool, tag };
    const created = await service.command({ op: 'create', profile: 'fixture', message: tag, settings });
    assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
    const page = await taskIdle(service, created.reply.result.task_id);
    assert.match(JSON.stringify(page.messages), new RegExp('Picture from ' + tag));
    const image = page.messages.flatMap(message => message.content?.content ?? [])
      .find(part => part.type === 'image');
    assert.ok(image, tag);
    const attachment = await fetch(address + '/api/board/attachments/' + image.image.id,
      { headers: { authorization: 'Bearer ' + token } });
    assert.equal(attachment.status, 200);
    assert.equal(attachment.headers.get('content-type'), 'image/png');
    assert.equal(Buffer.from(await attachment.arrayBuffer()).toString('base64'), picture);
    return page;
  }
  await runTool(receiver, 'mcp__cua__picture', 'local Mac');
  const alternate = 'mcp__shared-mac_cua__alternate';
  const deadline = Date.now() + 5000;
  let published = false;
  do {
    const state = await fetch(caller.address + '/api/browser/state', {
      headers: { authorization: 'Bearer ' + caller.token },
    });
    assert.equal(state.status, 200);
    published = (await state.json()).program.tools.some(tool => tool.name === alternate);
    if (!published) await delay(20);
  } while (!published && Date.now() < deadline);
  assert.ok(published, 'The remote catalog publishes tool changes from the local MCP process');
  const local = await runTool(caller, alternate, 'local workspace');
  assert.equal(local.task.settings.workspace.environment, undefined);
  const remote = await runTool(caller, 'mcp__shared-mac_cua__picture', 'shared workspace',
    { workspace: { roots: [workspace], environment: 'mac' } });
  assert.equal(remote.task.settings.workspace.environment, 'mac');
  assert.deepEqual(provider.failures, []);

  const tls = { ca: await readFile(cert), rejectUnauthorized: true };
  const connect = async () => {
    const socket = new WebSocket(url, { tls, protocols: ['selvedge-execution-v1'],
      headers: { Authorization: 'Bearer ' + secret } });
    t.after(() => socket.terminate());
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
    return socket;
  };
  const rpc = (socket, id, method, params) => new Promise(resolve => {
    function receive({ data }) {
      const reply = JSON.parse(data);
      if (reply.id !== id) return;
      socket.removeEventListener('message', receive);
      resolve(reply);
    }
    socket.addEventListener('message', receive);
    socket.send(JSON.stringify({ id, method, params }));
  });
  const first = await connect();
  const request = { operation_id: 'lost-mcp-reply', tool: 'mcp', server: 'cua', name: 'picture', arguments: { tag: 'replay' } };
  assert.equal((await rpc(first, 'start', 'execution.start', request)).result.accepted, true);
  first.terminate();
  const reconnected = await connect();
  assert.equal((await rpc(reconnected, 'retry', 'execution.start', request)).result.accepted, true);
  const recovered = await rpc(reconnected, 'wait', 'execution.wait', { operation_id: request.operation_id });
  assert.equal(recovered.result.value.content[0].text, 'Picture from replay');
  const forbidden = { ...request, operation_id: 'private-mcp', server: 'private' };
  await rpc(reconnected, 'private', 'execution.start', forbidden);
  const rejection = await rpc(reconnected, 'denied', 'execution.wait', { operation_id: forbidden.operation_id });
  assert.equal(rejection.result.error.code, 'mcp_unavailable');
  await assert.rejects(readFile(privateCalls), { code: 'ENOENT' });
  const executed = (await readFile(calls, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(executed.map(entry => entry.tag), ['local Mac', 'local workspace', 'shared workspace', 'replay']);
  assert.equal(new Set(executed.map(entry => entry.pid)).size, 1);
});

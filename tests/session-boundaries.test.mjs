import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes, randomUUID } from 'node:crypto';
import { access, chmod, cp, mkdir, readFile, stat, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { Service } from '../host/service.mjs';
import { RemoteConnector } from '../host/remote-connector.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { generateKeyPair } from 'jose';
import { DatabaseSync } from 'node:sqlite';
import { chatgptFixture } from './fixtures/chatgpt.mjs';
import { loginThroughCli } from './fixtures/session-boundaries-oauth.mjs';
import { webPeer } from './fixtures/session-boundaries-web.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const execute = promisify(execFile);
const pluginRoot = fileURLToPath(new URL('../plugins/selvedge-chatgpt/', import.meta.url));
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

async function eventually(observe, message) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const value = await observe();
    if (value) return value;
    await delay(10);
  }
  throw new Error(message);
}

test('a relay reconnect cannot receive an old in-flight reply or replay its command', async t => {
  const directory = await home(t), hostId = randomUUID(), token = randomBytes(32).toString('base64url');
  const service = await Service.open({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'remote_enable' })).reply.ok, true);
  const controller_id = 'a'.repeat(64);
  const granted = await service.command({ op: 'remote_grant', controller_id,
    permissions: { read: true, control: true, configure: false, approve: false } });
  assert.equal(granted.reply.ok, true, JSON.stringify(granted.reply));
  const grant = { controller_id, grant_epoch: granted.reply.result.grant_epoch };
  assert.equal(typeof grant.grant_epoch, 'number');
  const sockets = [], frames = [], authorizations = [];
  const relay = Bun.serve({ hostname: '127.0.0.1', port: 0,
    fetch(request, server) {
      authorizations.push(request.headers.get('authorization'));
      assert.equal(new URL(request.url).pathname, `/v1/hosts/${hostId}/host`);
      assert.equal(request.headers.get('authorization'), `Bearer ${token}`);
      if (server.upgrade(request)) return;
      return new Response(null, { status: 426 });
    },
    websocket: {
      open(socket) { sockets.push(socket); socket.send(JSON.stringify({ type: 'ready', version: 1 })); },
      message(socket, data) {
        const frame = JSON.parse(data); frames.push({ socket, frame });
        if (frame.type === 'ping') socket.send(JSON.stringify({ type: 'pong' }));
      },
    },
  });
  t.after(() => relay.stop(true));
  const release = Promise.withResolvers();
  let committed, invocations = 0;
  // Delay delivery of the real public Service result. This changes transport
  // scheduling only: admission, task creation and the receipt still run normally.
  const delayedTransport = new Proxy(service, { get(target, property) {
    if (property === 'remoteCommand') return async (...args) => {
      invocations++;
      const result = await target.remoteCommand(...args);
      committed = result;
      await release.promise;
      return result;
    };
    const value = Reflect.get(target, property);
    return typeof value === 'function' ? value.bind(target) : value;
  } });
  const connector = new RemoteConnector({ relayUrl: relay.url.origin, hostId, hostToken: token,
    service: delayedTransport, getGrants: async () => [grant], allowLoopback: true, retryBaseMs: 5, retryMaxMs: 10 });
  t.after(() => { release.resolve(); connector.close(); });
  connector.start();
  const ready = index => sockets[index] && connector.status().connected &&
    frames.some(entry => entry.socket === sockets[index] && entry.frame.type === 'grants');
  const send = (socket, frame) => socket.send(JSON.stringify(frame));
  const connection = { connection_id: 'reused-connection', ...grant };
  await eventually(() => ready(0), 'The first real connector session did not become ready');
  send(sockets[0], { type: 'controller_open', ...connection });
  send(sockets[0], { type: 'request', ...connection, request: { id: 'old-rpc', method: 'command', params: {
    request_id: randomUUID(), command: { op: 'create_idle', profile: 'demo' },
  } } });
  await eventually(() => committed, 'The remote command did not reach the actual Service');
  assert.equal(committed.reply.ok, true, JSON.stringify(committed.reply));
  assert.equal(committed.reply.result.task_id, 0);
  sockets[0].close(1012, 'Lose delivery while the admitted command reply is pending');
  await eventually(() => ready(1), 'The connector did not establish a fresh session');
  send(sockets[1], { type: 'controller_open', ...connection });
  release.resolve();
  send(sockets[1], { type: 'request', ...connection,
    request: { id: 'new-rpc', method: 'snapshot', params: {} } });
  await eventually(() => frames.some(entry => entry.socket === sockets[1] && entry.frame.response?.id === 'new-rpc'),
    'The new connection did not receive its own response');
  assert.equal(frames.some(entry => entry.frame.response?.id === 'old-rpc'), false,
    'An old transport response must never be routed to a replacement connection');
  assert.equal(invocations, 1, 'Reconnect must not re-admit the old command');
  const next = await service.command({ op: 'create_idle', profile: 'demo' });
  assert.equal(next.reply.ok, true);
  assert.equal(next.reply.result.task_id, 1, 'Only the original remote task may have been created');
  assert.ok(authorizations.length >= 2);
});

test('manual portable compaction keeps its metered consumer across external credential rotation', async t => {
  const directory = await home(t), meters = [], sent = [];
  const key = `SELVEDGE_COMPACTION_BOUNDARY_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'original';
  t.after(() => { delete process.env[key]; });
  let compacting = false;
  const upstream = await responsesServer(t, (body, _, request) => {
    sent.push({ body, authorization: request.headers.authorization, key: process.env[key], compacting });
    return answer(compacting ? 'Preserve the verified Unicode edit 😀 in the continuation note.' : 'The Unicode edit 😀 is verified.');
  }, { measure: (body, request) => {
    if (compacting) {
      meters.push({ body, authorization: request.headers.authorization, key: process.env[key] });
      // Context budget probes share this route; rotate after the actual tool-free summary is metered.
      if (body.tools.length === 0) process.env[key] = 'rotated';
    }
    return 100;
  } });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false,
    profiles: { fixture: { provider: 'responses', model: 'fixture', endpoint: upstream.endpoint, api_key_env: key } },
    compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 60000,
      targets: [{ profile: 'fixture', window_tokens: 8192, output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'summary' }] },
  }) });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'fixture', message: 'Verify the Unicode edit 😀.' });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const task_id = created.reply.result.task_id;
  await taskIdle(service, task_id);
  compacting = true;
  const compact = await service.command({ op: 'compact', task_id });
  assert.equal(compact.reply.ok, true, JSON.stringify(compact.reply));
  await eventually(() => sent.some(value => value.compacting), 'The accepted manual compaction did not issue its summary request');
  await taskIdle(service, task_id);
  assert.deepEqual(upstream.failures, []);
  const summary = sent.filter(value => value.compacting);
  assert.equal(summary.length, 1, 'Manual compaction must send one summary request');
  assert.equal(summary[0].key, 'rotated', 'The external meter must rotate the credential before execution');
  assert.equal(summary[0].authorization, 'Bearer original');
  const { model, input, instructions, tools, tool_choice, parallel_tool_calls } = summary[0].body;
  const metered = { model, input, tools, tool_choice, parallel_tool_calls,
    ...(Object.hasOwn(summary[0].body, 'instructions') ? { instructions } : {}) };
  const portableMeter = meters.find(value => value.body.tools.length === 0);
  assert.ok(portableMeter, 'Portable compaction must meter its tool-free summary request');
  assert.equal(portableMeter.authorization, 'Bearer original');
  assert.deepEqual(portableMeter.body, metered,
    'Execution must use the exact request measured for its original authenticated consumer');
  assert.equal(summary[0].body.max_output_tokens, 1024);
});

test('Web board drafting and model approval use independent text roots', async t => {
  const directory = await home(t), reviews = [];
  const key = `SELVEDGE_WEB_BOUNDARY_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-web'; t.after(() => { delete process.env[key]; });
  const web = await webPeer(t, ({ body }) => {
    assert.deepEqual(body.tools, []);
    assert.equal(body.previous_response_id, undefined);
    assert.equal(body.input.length, 1);
    const text = body.input[0].content;
    const structured = text.startsWith('{') ? JSON.parse(text) : undefined;
    if (structured?.command) {
      reviews.push(structured);
      return answer('{"decision":"deny","reason":"Inspection only 😀."}');
    }
    return answer('{"title":"Unicode board 😀","description":"Generated Web description."}');
  });
  const worker = await responsesServer(t, (_, index) => index === 0 ? [{ type: 'function_call',
    call_id: 'review-web', name: 'bash', arguments: JSON.stringify({ command: 'pwd',
      sandbox_permissions: 'require_escalated', justification: 'Inspect the current directory.' }) }] : answer('The review refused execution.'));
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, profiles: {
      web: { provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: web.endpoint, api_key_env: key },
      worker: { provider: 'responses', model: 'worker', endpoint: worker.endpoint, api_key_env: key },
    },
  }) });
  t.after(() => service.close());
  const created = await service.command({ op: 'create_card', description: 'Draft a useful Unicode board card.',
    assisted: true, draft_profile: 'web' });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const card_id = created.reply.result.card_id;
  const card = await eventually(async () => {
    const value = (await service.command({ op: 'read_card', card_id })).reply.result;
    return value.title === 'Unicode board 😀' && value;
  }, 'The real Web board draft did not become visible');
  assert.equal(card.description, 'Generated Web description.');
  const task = await service.command({ op: 'create', profile: 'worker', message: 'Inspection only 😀.', settings: {
    approval: { mode: 'approval-for-me', reviewer_profile: 'web' },
  } });
  assert.equal(task.reply.ok, true, JSON.stringify(task.reply));
  const page = await taskIdle(service, task.reply.result.task_id);
  assert.equal(reviews.length, 1);
  assert.equal(reviews[0].command.arguments.command, 'pwd');
  assert.equal(reviews[0].recent_user_requests_newest_first[0], 'Inspection only 😀.');
  assert.ok(JSON.stringify(page.messages).includes('Inspection only 😀.'));
  assert.deepEqual(web.failures, []);
  assert.deepEqual(worker.failures, []);
});

test('Web shutdown detaches a durable original request and restart does not repost it', async t => {
  const directory = await home(t);
  const key = `SELVEDGE_WEB_RETAINED_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-web'; t.after(() => { delete process.env[key]; });
  const web = await webPeer(t, (entry, peer) => {
    if (entry.body.text?.format?.name === 'task_title') return answer('{"title":"Retain original work"}');
    const db = new DatabaseSync(path.join(directory, 'providers/chatgpt-web/requests.sqlite'), { readOnly: true });
    try {
      const row = db.prepare('SELECT body FROM requests WHERE request_key=?').get(entry.key);
      assert.equal(row.body, entry.raw, 'HTTP must observe only an already durable original request');
    } finally { db.close(); }
    peer.start();
    peer.event('response.in_progress', { response_id: peer.id, previous_response_id: null });
    peer.event('response.output_text.snapshot', { response_id: peer.id, text: 'Provisional 😀', provisional: true });
  });
  const options = { home: directory, cwd: directory, config: validateConfig({ ...defaultConfig, chatgpt: false,
    profiles: { web: { provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: web.endpoint, api_key_env: key } },
  }) };
  let service = await Service.open(options);
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'web', message: 'Retain this original request.' });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const original = await eventually(() => web.requests.find(entry => entry.body.tools.length > 0),
    'The original Web request did not arrive');
  const db = new DatabaseSync(path.join(directory, 'providers/chatgpt-web/requests.sqlite'), { readOnly: true });
  try {
    await eventually(() => db.prepare('SELECT response_id FROM requests WHERE request_key=?').get(original.key)?.response_id,
      'The observed external response identity was not persisted');
  } finally { db.close(); }
  await service.close();
  assert.deepEqual(web.controls, [], 'Shutdown detaches observation without issuing explicit remote Stop');
  service = await Service.open(options);
  await service.command({ op: 'read', task_id: created.reply.result.task_id });
  const sent = await service.command({ op: 'send', task_id: created.reply.result.task_id, message: 'A replacement must not duplicate uncertain work.' });
  assert.equal(sent.reply.ok, true, JSON.stringify(sent.reply));
  const snapshot = await taskIdle(service, created.reply.result.task_id);
  assert.ok(snapshot.messages.some(message => message.role === 'error' &&
    message.content.includes('retained') && message.content.includes(original.key)),
  'The successor must explain which unresolved external request blocks it');
  assert.equal(web.requests.filter(entry => entry.body.tools.length > 0).length, 1,
    'Neither journal replay nor a successor ticket may repost an uncertain original');
  assert.deepEqual(web.controls, []);
  assert.deepEqual(web.failures, []);
});

test('explicit Web Interrupt cancels its durable remote request without reposting it', async t => {
  const directory = await home(t);
  const key = `SELVEDGE_WEB_INTERRUPT_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-web'; t.after(() => { delete process.env[key]; });
  const web = await webPeer(t, (entry, peer) => {
    if (entry.body.text?.format?.name === 'task_title') return answer('{"title":"Interrupt original work"}');
    peer.start();
    peer.event('response.in_progress', { response_id: peer.id, previous_response_id: null });
  });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, profiles: {
      web: { provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: web.endpoint, api_key_env: key },
    },
  }) });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'web', message: 'Interrupt this original request.' });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const original = await eventually(() => web.requests.find(entry => entry.body.tools.length > 0),
    'The original Web request did not arrive');
  const db = new DatabaseSync(path.join(directory, 'providers/chatgpt-web/requests.sqlite'), { readOnly: true });
  let responseId;
  try {
    responseId = await eventually(() => db.prepare('SELECT response_id FROM requests WHERE request_key=?').get(original.key)?.response_id,
      'The remote response identity was not persisted before explicit Interrupt');
  } finally { db.close(); }
  const stopped = await service.command({ op: 'interrupt', task_id: created.reply.result.task_id });
  assert.equal(stopped.reply.ok, true, JSON.stringify(stopped.reply));
  await service.close();
  assert.ok(web.controls.includes(`${new URL(web.endpoint).pathname}/${responseId}/cancel`),
    `Explicit Interrupt must issue the provider cancellation request; observed ${JSON.stringify(web.controls)}`);
  assert.equal(web.requests.filter(entry => entry.body.tools.length > 0).length, 1);
  assert.deepEqual(web.failures, []);
});

test('one browser owns one live voice session and can reconnect after disconnect', async t => {
  const directory = await home(t), requests = [], stopped = [];
  const service = await Service.open({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }),
    audioFactory: () => ({
      async createSession(request) { requests.push(request); return { session_id: request.id, answer_sdp: 'fixture answer' }; },
      async appendContext() {},
      async stopSession(id) { stopped.push(id); },
      async close() {},
    }),
  });
  t.after(() => service.close());
  const created = await service.command({ op: 'create_idle', profile: 'demo' });
  assert.equal(created.reply.ok, true);
  const input = { browser_id: 'one-browser', connection: 'loopback-audio',
    task_id: created.reply.result.task_id, sdp: 'v=0' };
  const first = await service.audioCreate(input);
  assert.equal(typeof first.session_id, 'string');
  await assert.rejects(service.audioCreate(input), error => {
    assert.equal(typeof error.message, 'string');
    assert.ok(error.message.trim(), 'Resource refusal must explain why no session was opened');
    assert.match(error.message, /browser|voice|audio|session|already/i);
    return true;
  });
  assert.equal(requests.length, 1, 'Refusal must not open a second external session');
  await service.audioDisconnect(first.session_id, input.browser_id);
  const second = await service.audioCreate(input);
  assert.notEqual(second.session_id, first.session_id);
  assert.equal(requests.length, 2);
  assert.ok(stopped.includes(first.session_id));
});

test('closing the full service aborts an unanswered extension hook and reaps its peer', async t => {
  const directory = await home(t), marker = path.join(directory, 'hook-started.json');
  const model = await responsesServer(t, () => [{ type: 'function_call',
    call_id: 'inspect-projects', name: 'plugin__hung__probe', arguments: '{}' }]);
  const key = `SELVEDGE_SESSION_BOUNDARY_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-only';
  t.after(() => { delete process.env[key]; });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false,
    profiles: { fixture: { provider: 'responses', model: 'fixture', endpoint: model.endpoint,
      api_key_env: key, timeout_ms: 5000 } },
    plugins: { hung: { command: process.execPath,
      args: [fileURLToPath(new URL('./fixtures/session-boundaries-plugin.mjs', import.meta.url))],
      env: { SELVEDGE_SESSION_BOUNDARY_MARKER: marker }, timeout_ms: 60000 } },
  }) });
  let pid;
  t.after(async () => {
    if (pid) {
      try { process.kill(pid, 'SIGKILL'); }
      catch (error) {
        // DEFENSE: Successful service shutdown has already reaped this deliberately hung peer.
        if (error.code !== 'ESRCH') throw error;
      }
    }
    await service.close();
  });
  const created = await service.command({ op: 'create', profile: 'fixture', message: 'Inspect the project list.' });
  assert.equal(created.reply.ok, true);
  const started = await eventually(async () => {
    try { return JSON.parse(await readFile(marker, 'utf8')); }
    catch (error) {
      // DEFENSE: The external peer has not yet received and recorded its first hook request.
      if (error.code === 'ENOENT') return null;
      throw error;
    }
  }, 'The real extension never received its hook');
  pid = started.pid;
  assert.equal(started.method, 'beforeTool');
  await Promise.race([service.close(), delay(3000).then(() => { throw new Error('Service shutdown waited for the 60-second hook deadline'); })]);
  await eventually(() => {
    try { process.kill(pid, 0); return false; }
    catch (error) {
      // DEFENSE: A terminated and reaped process is absent from the operating system.
      if (error.code === 'ESRCH') return true;
      throw error;
    }
  }, 'Closing the service left the extension process alive');
  assert.deepEqual(model.failures, []);
});

test('CLI login preserves private credentials on bad signatures and service refresh is bounded', async t => {
  const upstream = await chatgptFixture(t);
  const catalog = { models: [{ slug: 'session-fixture', display_name: 'Session fixture', visibility: 'list',
    context_window: 128000, default_reasoning_level: 'medium',
    supported_reasoning_levels: [{ effort: 'medium' }] }] };
  const reply = (response, value, status = 200) => {
    response.writeHead(status, { 'content-type': 'application/json' });
    response.end(JSON.stringify(value));
  };
  upstream.options.respond = (entry, response) => reply(response, catalog);
  const config = validateConfig({ ...defaultConfig, chatgpt: upstream.profile, profiles: {}, port: 0 });
  await writeFile(path.join(upstream.directory, 'config.json'), JSON.stringify(config));
  const login = await loginThroughCli(upstream.directory, upstream.address);
  assert.equal(login.opened, true);
  assert.equal(login.code, 0, login.stderr);
  const filename = path.join(upstream.directory, upstream.profile.auth_file);
  const saved = await readFile(filename, 'utf8');
  for (const name of [filename, `${filename}.registration.json`, path.join(upstream.directory, 'auth/chatgpt-host.json')]) {
    assert.equal((await stat(name)).mode & 0o777, 0o600);
  }
  upstream.options.privateKey = (await generateKeyPair('RS256')).privateKey;
  const refused = await loginThroughCli(upstream.directory, upstream.address);
  assert.equal(refused.opened, true);
  assert.notEqual(refused.code, 0);
  assert.match(refused.stderr, /signature|JWT|verif/i);
  assert.equal(await readFile(filename, 'utf8'), saved);
  const attempts = upstream.oauthRequests.filter(entry => entry.url.startsWith('/authorize?'));
  assert.deepEqual(attempts.map(entry => new URL(entry.url, upstream.address).searchParams.get('client_id')),
    ['dynamic_agent_client', 'fixture-issued-client']);
  const hostIds = attempts.map(entry => new URL(entry.url, upstream.address).searchParams.get('ext_agent_host_id'));
  assert.equal(hostIds[0], hostIds[1]);
  delete upstream.options.privateKey;
  const running = await startServer({ home: upstream.directory, cwd: upstream.directory, config });
  t.after(() => running.close());
  await upstream.seedExpiredCredential();
  const grants = () => upstream.oauthRequests.filter(entry => entry.url === '/oauth/token');
  const beforeRefresh = grants().length;
  const headers = { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' };
  const catalogs = await Promise.all([1, 2, 3].map(async () => {
    const response = await fetch(`${running.address}/api/accounts/refresh`, { method: 'POST', headers, body: '{}' });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.ok, true, JSON.stringify(body));
    return body.result;
  }));
  assert.equal(grants().length - beforeRefresh, 1);
  const profile = catalogs[0].profiles.find(value => value.provider === 'chatgpt' && value.name === 'session-fixture');
  assert.ok(profile);
  const firstAuthorization = `Bearer ${JSON.parse(await readFile(filename, 'utf8')).access_token}`;
  const rejectedRequests = [];
  upstream.options.respond = (entry, response) => {
    if (entry.url.endsWith('/models')) return reply(response, catalog);
    if (entry.body?.text?.format?.name === 'task_title') {
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      return response.end(`data: ${JSON.stringify({ type: 'response.completed', response: {
        status: 'completed', output: answer('{"title":"Rejected request"}') } })}\n\n`);
    }
    rejectedRequests.push(entry);
    return reply(response, { error: 'Repeated fixture HTTP rejection' }, 401);
  };
  const beforeRejection = grants().length;
  const createResponse = await fetch(`${running.address}/api/commands`, { method: 'POST', headers,
    body: JSON.stringify({ op: 'create', profile: profile.key, message: 'Observe a repeated HTTP rejection.' }) });
  assert.equal(createResponse.status, 200);
  const created = await createResponse.json();
  assert.equal(created.ok, true, JSON.stringify(created));
  await eventually(async () => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST', headers,
      body: JSON.stringify({ op: 'read', task_id: created.result.task_id }) });
    const body = await response.json();
    return body.ok && body.result.task.phase === 'idle' && body.result.task.operations.length === 0;
  }, 'Repeated HTTP rejection never settled the task');
  assert.equal(rejectedRequests.length, 2);
  assert.equal(rejectedRequests[0].headers.authorization, firstAuthorization);
  assert.notEqual(rejectedRequests[1].headers.authorization, firstAuthorization);
  assert.equal(grants().length - beforeRejection, 1);
  assert.deepEqual(upstream.failures, []);
});

test('installed MCP credentials are private, reject unsafe files and never expose malformed bytes', async t => {
  const base = await home(t), state = path.join(base, 'state'), workspace = path.join(base, 'workspace');
  await mkdir(workspace);
  const initial = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const seed = await Service.open({ home: state, cwd: workspace, config: initial });
  let project;
  try {
    const created = await seed.command({ op: 'create_project', name: 'Shared private fixture', workspace: { roots: [workspace] } });
    assert.equal(created.reply.ok, true);
    project = created.reply.result.project_id;
  } finally { await seed.close(); }
  const key = `SELVEDGE_SESSION_TOKEN_${randomBytes(8).toString('hex')}`, token = randomBytes(32).toString('base64url');
  process.env[key] = token;
  t.after(() => { delete process.env[key]; });
  const running = await startServer({ home: state, cwd: workspace, config: validateConfig({ ...initial,
    chatgpt_plugin: { connections: { 0: { token_env: key, project_ids: [project],
      sandbox: { mode: 'workspace-write', network_access: false } } } },
  }) });
  t.after(() => running.close());
  const data = path.join(base, 'plugin-data');
  const connection = { SELVEDGE_URL: running.address, SELVEDGE_CONNECTION_ID: '0', SELVEDGE_CONNECTION_TOKEN: token };
  const setup = path.join(pluginRoot, 'bin/setup.mjs');
  await execute(process.execPath, [setup, 'connection', data], { env: { ...process.env, ...connection }, timeout: 10000 });
  const filename = path.join(data, 'connection.json');
  assert.equal((await stat(filename)).mode & 0o777, 0o600);
  await assert.rejects(execute(process.execPath, [setup, 'connection', data], { env: { ...process.env, ...connection }, timeout: 10000 }), /exist|EEXIST/i);
  const manifest = JSON.parse(await readFile(path.join(pluginRoot, 'mcp.json'), 'utf8')).mcpServers.selvedge;
  async function list(selected) {
    const client = new Client({ name: 'private-file-contract', version: '1' });
    const expand = value => value.replaceAll('${PLUGIN_ROOT}', pluginRoot).replaceAll('${PLUGIN_DATA}', data);
    const transport = new StdioClientTransport({ command: manifest.command, args: manifest.args.map(expand),
      cwd: expand(manifest.cwd), env: { SELVEDGE_CONNECTION_FILE: selected }, stderr: 'pipe' });
    let stderr = '';
    transport.stderr?.on('data', chunk => { stderr += chunk; });
    try {
      await client.connect(transport);
      return { result: await client.callTool({ name: 'selvedge_list_projects', arguments: {} }), stderr };
    } catch (error) {
      return { error, stderr };
    } finally { await client.close(); }
  }
  const valid = await list(filename);
  assert.equal(valid.result?.isError, false, valid.stderr);
  assert.deepEqual(valid.result.structuredContent.result.map(value => value.project_id), [project]);
  await chmod(filename, 0o644);
  const readable = await list(filename);
  assert.match(JSON.stringify(readable.result ?? readable.error?.message) + readable.stderr, /private|owned/i);
  assert.notEqual(readable.result?.isError, false);
  await chmod(filename, 0o600);
  const alias = path.join(base, 'alias.json');
  await symlink(filename, alias);
  const linked = await list(alias);
  assert.match(JSON.stringify(linked.result ?? linked.error?.message) + linked.stderr, /ELOOP|symbolic/i);
  const secret = 'DO_NOT_PRINT_MALFORMED_CONNECTION_BYTES';
  for (const bytes of [Buffer.from(`{"SELVEDGE_CONNECTION_TOKEN":"${secret}" trailing`),
    Buffer.concat([Buffer.from(`{"${secret}":"`), Buffer.from([0xff]), Buffer.from('"}')])]) {
    await writeFile(filename, bytes);
    const invalid = await list(filename);
    const diagnostic = JSON.stringify(invalid.result ?? invalid.error?.message) + invalid.stderr;
    assert.match(diagnostic, /Invalid connection file JSON/);
    assert.equal(diagnostic.includes(secret), false);
  }
});

test('deployment ships the package without private source-directory data', async t => {
  const base = await home(t), source = path.join(base, 'source'), output = path.join(base, 'deployment');
  await cp(pluginRoot, source, { recursive: true, filter: filename =>
    !['node_modules', 'connection.json', '.env', 'private'].includes(path.basename(filename)) });
  await symlink(path.join(pluginRoot, 'node_modules'), path.join(source, 'node_modules'), 'dir');
  await writeFile(path.join(source, 'connection.json'), '{"private":"LOCAL_CONNECTION_DATA"}');
  await writeFile(path.join(source, '.env'), 'LOCAL_ENVIRONMENT_DATA');
  await mkdir(path.join(source, 'private'));
  await writeFile(path.join(source, 'private/secret'), 'LOCAL_PRIVATE_DATA');
  await writeFile(path.join(source, 'src/connection.json'), '{"private":"NESTED_CONNECTION_DATA"}');
  await execute(process.execPath, [path.join(source, 'bin/setup.mjs'), 'package', 'plugin_asdk_app_session_fixture', output], { timeout: 10000 });
  const manifest = JSON.parse(await readFile(path.join(output, 'plugin.json'), 'utf8'));
  const apps = JSON.parse(await readFile(path.join(output, manifest.extensions['com.openai'].apps), 'utf8'));
  assert.equal(apps.apps.selvedge.id, 'plugin_asdk_app_session_fixture');
  for (const filename of ['connection.json', '.env', 'private', 'src/connection.json', 'mcp.json', 'node_modules']) {
    await assert.rejects(access(path.join(output, filename)), { code: 'ENOENT' });
  }
  await symlink(path.join(pluginRoot, 'node_modules'), path.join(output, 'node_modules'), 'dir');
  const client = new Client({ name: 'deployed-package-contract', version: '1' });
  const transport = new StdioClientTransport({ command: 'node', args: [path.join(output, 'bin/server.mjs')],
    cwd: output, env: { SELVEDGE_URL: 'http://127.0.0.1:7421', SELVEDGE_CONNECTION_ID: '0',
      SELVEDGE_CONNECTION_TOKEN: 'a'.repeat(43) }, stderr: 'pipe' });
  t.after(() => client.close());
  await client.connect(transport);
  const tools = (await client.listTools()).tools;
  assert.ok(tools.some(tool => tool.name === 'selvedge_list_projects'));
});

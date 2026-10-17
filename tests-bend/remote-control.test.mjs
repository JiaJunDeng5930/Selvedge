import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { bendTag, decodeBendValue, encodeBendValue } from '../host/public/bend-value.mjs';
import { validateConfig, defaultConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import { MAX_REMOTE_FRAME_BYTES } from '../remote/protocol.mjs';
import { browserUI, home, surfaceNodes, taskIdle, responsesServer } from './support.mjs';
import { controlPermission, readPermission, eventually, relayPost, remoteFixture } from './remote-support.mjs';

function journal(directory) {
  const db = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
  try { return db.prepare('SELECT seq, input, decision FROM journal ORDER BY seq').all().map(row => ({
    sequence: row.seq, input: JSON.parse(row.input), decision: JSON.parse(row.decision),
  })); } finally { db.close(); }
}

function business(response) {
  assert.equal(response.error, undefined, JSON.stringify(response));
  assert.equal(response.result.reply.ok, true, JSON.stringify(response));
  return response.result.reply.result;
}

test('relay pairing requires local approval; native control, snapshot and subscription use the same committed service', { timeout: 40_000 }, async t => {
  const f = await remoteFixture(t);
  const identityFile = path.join(f.directory, 'remote-identity.json');
  const privateIdentity = JSON.parse(await readFile(identityFile, 'utf8'));
  assert.equal((await stat(identityFile)).mode & 0o077, 0);
  assert.equal(privateIdentity.host_id, f.identity.host_id);
  const pairing = await f.service.remote.pair();
  const token = randomBytes(32).toString('base64url');
  const url = `${f.relay.url}/v1/hosts/${f.identity.host_id}`;
  assert.equal((await relayPost(`${url}/pair`, 'wrong-code', { controller_token: token, label: 'Unapproved' })).status, 401);
  const response = await relayPost(`${url}/pair`, pairing.code, { controller_token: token, label: 'My phone 手机' });
  assert.equal(response.status, 200, await response.clone().text());
  const pending = await response.json();
  assert.equal(pending.status, 'pending');
  assert.equal(pending.controller_id, createHash('sha256').update(token).digest('hex'));
  assert.equal((await relayPost(`${url}/tickets`, token, {})).status, 401);
  assert.equal((await relayPost(`${url}/pair`, pairing.code, { controller_token: token, label: 'Replay' })).status, 401);
  await eventually('the local approval request', async () => (await f.service.remote.pending()).some(item => item.request_id === pending.request_id));
  const before = await f.service.remote.status();
  assert.equal(before.grants.length, 0);
  assert.ok(!JSON.stringify(before).includes(pairing.code));
  const grant = await f.service.remote.approve(pending.request_id, controlPermission);
  assert.deepEqual(grant.permissions, controlPermission);
  const client = await f.connect(token);
  const created = business(await client.command({ op: 'create', profile: 'demo', message: 'Remote 世界 😀' }));
  const settled = await taskIdle(f.service, created.task_id);
  const readRequestId = randomUUID();
  const page = business(await client.command({ op: 'read', task_id: created.task_id }, readRequestId));
  assert.deepEqual(page.messages, settled.messages);
  assert.deepEqual(page.messages.filter(item => ['user', 'assistant'].includes(item.role)).map(item => item.content),
    ['Remote 世界 😀', '[Offline demo] Remote 世界 😀']);
  await f.relay.hibernate(f.identity.host_id);
  assert.deepEqual(business(await client.command({ op: 'read', task_id: created.task_id })).messages, settled.messages,
    'Durable Object hibernation reconstructs existing host and controller socket authority');
  const snapshot = await client.request('snapshot');
  assert.equal(snapshot.error, undefined, JSON.stringify(snapshot));
  assert.equal(snapshot.result.sequence, f.service.journal.sequence);
  assert.deepEqual(snapshot.result.program, encodeBendValue(f.service.journal.program));
  assert.deepEqual(snapshot.result.streams, f.service.browserStreams());
  assert.equal(typeof snapshot.result.incarnation, 'string');
  assert.ok(!JSON.stringify(snapshot.result).includes(privateIdentity.host_token));
  assert.ok(Number.isSafeInteger(snapshot.result.notice_sequence));
  const subscribed = await client.request('subscribe');
  assert.equal(subscribed.error, undefined, JSON.stringify(subscribed));
  assert.equal(subscribed.result.sequence, f.service.journal.sequence);
  assert.deepEqual(subscribed.result.streams, []);
  await f.service.command({ op: 'send', task_id: created.task_id, message: 'Also sent locally' });
  const notice = await client.next(message => message.type === 'event' && message.event.notice.type === 'commit');
  assert.ok(notice.event.notice.sequence > subscribed.result.sequence);
  assert.ok(notice.event.notice_sequence > subscribed.result.notice_sequence);
  assert.equal(notice.event.incarnation, subscribed.result.incarnation);
  const updated = await taskIdle(f.service, created.task_id);
  const beforeRead = f.service.journal.sequence;
  assert.deepEqual(business(await client.command({ op: 'read', task_id: created.task_id }, readRequestId)).messages, updated.messages,
    'Read retries observe current state instead of replaying a mutation receipt');
  assert.equal(f.service.journal.sequence, beforeRead);
  await client.request('unsubscribe');
  const text = JSON.stringify(journal(f.directory));
  for (const secret of [token, pairing.code, privateIdentity.host_token]) {
    assert.ok(!text.includes(secret), 'Network credentials stay outside the task journal');
  }
});

test('lost command replies and host restart retain the same receipt without repeating creates or sends', { timeout: 45_000 }, async t => {
  const f = await remoteFixture(t);
  const controller = await f.pair();
  const remoteAdmin = await controller.client.command({ op: 'remote_enable' });
  assert.equal(remoteAdmin.result?.reply.ok ?? false, false, 'Task control never grants local remote-administration authority');
  let client = controller.client;
  const request_id = randomUUID();
  const command = { op: 'create', profile: 'demo', message: 'Create exactly once' };
  const committed = new Promise(resolve => {
    const observe = decision => {
      if (decision.input.kind !== 'remote_command' || decision.input.request_id !== request_id) return;
      f.service.journal.off('commit', observe);
      void client.close();
      resolve(decision);
    };
    f.service.journal.on('commit', observe);
    t.after(() => f.service.journal.off('commit', observe));
  });
  client.send({ id: randomUUID(), method: 'command', params: { request_id, command } });
  const first = await committed;
  await client.closed;
  const firstPage = await taskIdle(f.service, first.reply.result.task_id);
  client = await f.connect(controller.token);
  const before = f.service.journal.sequence;
  const retried = await client.command(command, request_id);
  assert.deepEqual(retried.result.reply, first.reply);
  const reordered = await client.command({ message: command.message, profile: command.profile, op: command.op }, request_id);
  assert.deepEqual(reordered.result.reply, first.reply, 'JSON object key order does not create another command intent');
  assert.equal(f.service.journal.sequence, before, 'An acknowledged retry must not append another decision');
  const conflict = await client.command({ ...command, message: 'Different intent' }, request_id);
  assert.equal(conflict.result?.reply.error?.code ?? conflict.error?.code, 'remote_request_conflict');
  const send_id = randomUUID();
  const send = { op: 'send', task_id: firstPage.task.id, message: 'Send exactly once' };
  const [sent, simultaneous] = await Promise.all([client.command(send, send_id), client.command(send, send_id)]);
  business(sent);
  assert.deepEqual(simultaneous.result.reply, sent.result.reply);
  const completed = await taskIdle(f.service, firstPage.task.id);
  const oldSnapshot = await client.request('snapshot');
  await f.restart();
  await client.closed;
  client = await f.connect(controller.token);
  const restarted = await client.command(command, request_id);
  assert.deepEqual(restarted.result.reply, first.reply);
  assert.deepEqual((await client.command(send, send_id)).result.reply, sent.result.reply);
  const restored = business(await client.command({ op: 'read', task_id: firstPage.task.id }));
  assert.deepEqual(restored.messages, completed.messages);
  const newSnapshot = await client.request('snapshot');
  assert.notEqual(newSnapshot.result.incarnation, oldSnapshot.result.incarnation);
  assert.equal(newSnapshot.result.sequence, f.service.journal.sequence);
  assert.equal(restored.messages.filter(message => message.role === 'user' && message.content === send.message).length, 1);
  const committedRemote = journal(f.directory).filter(row => row.input.kind === 'remote_command');
  assert.equal(committedRemote.filter(row => row.input.request_id === request_id).length, 1);
  assert.equal(committedRemote.filter(row => row.input.request_id === send_id).length, 1);
});

test('relay snapshots preserve project task trees and executable descendant navigation', { timeout: 240_000 }, async t => {
  const f = await remoteFixture(t);
  const { client } = await f.pair({ ...controlPermission, configure: true });
  const command = async value => business(await client.command(value));
  const alpha = (await command({ op: 'create_project', name: 'Remote Alpha', workspace: { roots: [] } })).project_id;
  const beta = (await command({ op: 'create_project', name: 'Remote Beta', workspace: { roots: [] } })).project_id;
  const root = (await command({ op: 'create', profile: 'demo', message: 'Remote project root 世界', settings: { project_id: alpha } })).task_id;
  await taskIdle(f.service, root);
  const fork = async (task_id, message, project_id) => {
    const { children } = await command({ op: 'fork', task_id, child_count: 1, messages: [message],
      ...(project_id === undefined ? {} : { settings: { project_id } }) });
    await Promise.all([task_id, ...children].map(id => taskIdle(f.service, id)));
    return children[0];
  };
  const child = await fork(root, 'Remote child');
  const descendant = await fork(child, 'Remote grandchild');
  const crossProject = await fork(root, 'Fork into Beta', beta);
  const betaChild = await fork(crossProject, 'Child within Beta');
  const response = await client.request('snapshot');
  assert.equal(response.error, undefined, JSON.stringify(response));
  const ui = await browserUI(t);
  const authenticated = ui.authenticated(decodeBendValue(response.result.program), BigInt(root));
  assert.equal(bendTag(authenticated), 'Done');
  let state = authenticated.value;
  const nodes = () => surfaceNodes(ui.surface_state(state));
  const children = node => {
    const values = [];
    for (let list = node.children; bendTag(list) === 'Con'; list = list.tail) values.push(list.head);
    return values;
  };
  const hierarchy = [];
  const visit = (node, project = null, parent = null) => {
    const tag = bendTag(node.meaning);
    if (tag === 'ProjectGroup') project = Number(node.meaning.project);
    if (tag === 'TaskRow') hierarchy.push({ task: Number(node.meaning.task), project, parent });
    if (tag === 'TaskChildren') parent = Number(node.meaning.task);
    for (const child of children(node)) visit(child, project, parent);
  };
  visit(nodes().find(node => bendTag(node.role) === 'Navigation'));
  assert.deepEqual(hierarchy, [
    { task: root, project: alpha, parent: null }, { task: child, project: alpha, parent: root },
    { task: descendant, project: alpha, parent: child },
    { task: crossProject, project: beta, parent: null }, { task: betaChild, project: beta, parent: crossProject },
  ], 'Every remote-created task appears once; same-project forks nest and a cross-project fork starts its destination tree');
  const navigate = value => {
    if (!value || typeof value !== 'object') return undefined;
    if (bendTag(value) === 'Navigate') return value;
    return Object.values(value).map(navigate).find(Boolean);
  };
  const subtree = node => [node, ...children(node).flatMap(subtree)];
  const row = nodes().find(node => bendTag(node.meaning) === 'TaskRow' && node.meaning.task === BigInt(descendant));
  const open = subtree(row).find(node => navigate(node.meaning.input)?.route.task === BigInt(descendant));
  assert.ok(open, 'The remote descendant retains its actual navigation input');
  state = ui.activate_state(state, ui.key(open));
  assert.deepEqual(nodes().filter(node => bendTag(node.meaning) === 'TaskRow' && node.meaning.selected)
    .map(node => Number(node.meaning.task)), [descendant]);
});

test('native scope and current grants protect established sockets, reads, receipts and local administration', { timeout: 40_000 }, async t => {
  const f = await remoteFixture(t);
  const reader = await f.pair(readPermission);
  const snapshot = await reader.client.request('snapshot');
  assert.ok(snapshot.result.program);
  const denied = await reader.client.command({ op: 'create', profile: 'demo', message: 'Must not execute' });
  assert.equal(denied.result?.reply.ok ?? false, false);
  assert.equal(denied.result?.reply.error?.code ?? denied.error?.code, 'remote_permission_denied');
  const admin = await reader.client.command({ op: 'remote_enable' });
  assert.equal(admin.result?.reply.ok ?? false, false);
  const controller = await f.pair();
  const command = { op: 'create', profile: 'demo', message: 'One authorized task' };
  const request_id = randomUUID();
  const original = await controller.client.command(command, request_id);
  const task = business(original);
  await taskIdle(f.service, task.task_id);
  await f.service.remote.revoke(controller.pending.controller_id);
  await controller.client.closed;
  const hostUrl = `${f.relay.url}/v1/hosts/${f.identity.host_id}`;
  assert.equal((await relayPost(`${hostUrl}/tickets`, controller.token, {})).status, 401);
  const direct = await f.service.remoteCommand(controller.pending.controller_id,
    controller.grant.grant_epoch, { request_id, command });
  assert.equal(direct.reply.ok, false, 'A revoked device cannot use a saved receipt to bypass current authority');
  assert.equal(direct.reply.error.code, 'remote_controller_revoked');
  assert.equal((await reader.client.request('snapshot')).error, undefined);
  await f.service.remote.disable();
  await reader.client.closed;
  assert.equal((await f.service.remote.status()).enabled, false);
  await f.service.remote.enable();
  await f.online();
  const reconnected = await f.connect(reader.token);
  assert.equal((await reconnected.request('snapshot')).error, undefined);
});

test('a controller disconnect leaves active model work running and reconnect observes current stream state', { timeout: 40_000 }, async t => {
  const started = Promise.withResolvers();
  const released = Promise.withResolvers();
  const directory = await home(t);
  const api_key_env = `SELVEDGE_REMOTE_FIXTURE_${randomBytes(8).toString('hex')}`;
  process.env[api_key_env] = 'fixture-key';
  t.after(() => { delete process.env[api_key_env]; released.resolve(); });
  const model = await responsesServer(t, async () => {
    started.resolve();
    await released.promise;
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Completed after disconnect' }] }];
  });
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env,
  } } });
  const f = await remoteFixture(t, { config, directory });
  const controller = await f.pair();
  const created = business(await controller.client.command({ op: 'create', profile: 'fixture', message: 'Keep running' }));
  await started.promise;
  await controller.client.close();
  const active = await f.service.command({ op: 'read', task_id: created.task_id });
  assert.notEqual(active.reply.result.task.phase, 'idle');
  const client = await f.connect(controller.token);
  const subscribed = await client.request('subscribe');
  assert.equal(subscribed.error, undefined, JSON.stringify(subscribed));
  assert.deepEqual(subscribed.result.streams, f.service.browserStreams());
  released.resolve();
  const settled = await taskIdle(f.service, created.task_id);
  assert.equal(model.requests.length, 1);
  assert.equal(settled.messages.at(-1).content.item.content[0].text, 'Completed after disconnect');
  assert.deepEqual(model.failures, []);
  await client.next(message => message.type === 'event' && message.event.notice.type === 'stream_end');
});

test('relay rejects oversized or authority-injecting controller frames before native submission', { timeout: 40_000 }, async t => {
  const f = await remoteFixture(t);
  const controller = await f.pair();
  const before = f.service.journal.sequence;
  controller.client.send({ id: randomUUID(), method: 'snapshot', params: {}, controller_id: 'forged', grant_epoch: 999 });
  await controller.client.closed;
  assert.equal(f.service.journal.sequence, before);
  const oversized = await f.connect(controller.token);
  oversized.socket.send('x'.repeat(MAX_REMOTE_FRAME_BYTES + 1));
  await oversized.closed;
  assert.equal(f.service.journal.sequence, before);
  const healthy = await f.connect(controller.token);
  assert.equal((await healthy.request('snapshot')).error, undefined);
});

test('remote configuration and local management retain the existing authentication and origin boundary', { timeout: 20_000 }, async t => {
  assert.equal(validateConfig(defaultConfig).remote, false);
  const valid = { relay_url: 'https://selvedge-relay.example.workers.dev' };
  assert.deepEqual(validateConfig({ ...defaultConfig, remote: valid }).remote, valid);
  for (const remote of [null, true, { ...valid, surprise: true }, { relay_url: 'http://relay.example' },
    { relay_url: 'https://relay.example:8443' }, { relay_url: 'https://user:password@relay.example' },
    { relay_url: 'https://relay.example/path' }, { relay_url: 'https://relay.example?token=private' },
    { relay_url: 'https://relay.example#fragment' }]) {
    assert.throws(() => validateConfig({ ...defaultConfig, remote }), /remote|relay/i);
  }
  const directory = await home(t);
  const running = await startServer({ home: directory, config: validateConfig({ ...defaultConfig, port: 0 }), cwd: directory });
  t.after(() => running.close());
  const endpoint = `${running.address}/api/remote`;
  const headers = { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' };
  assert.equal((await fetch(`${endpoint}/status`)).status, 401);
  const status = await fetch(`${endpoint}/status`, { headers });
  assert.equal(status.status, 200);
  assert.equal((await status.json()).result.configured, false);
  assert.equal((await fetch(`${endpoint}/status`, { headers: { ...headers, origin: 'https://untrusted.example' } })).status, 403);
  assert.equal((await fetch(`${endpoint}/status?unexpected=1`, { headers })).status, 400);
  assert.equal((await fetch(`${endpoint}/pair`, { headers })).status, 405);
  for (const [route, body] of [['pair', { code: 'injected' }], ['enable', { enabled: true }],
    ['approve', { request_id: 'missing', permissions: { ...controlPermission, admin: true } }],
    ['revoke', { controller_id: 'a'.repeat(64), grant_epoch: 1 }]]) {
    const response = await fetch(`${endpoint}/${route}`, { method: 'POST', headers, body: JSON.stringify(body) });
    assert.equal(response.status, 400, `${route}: ${await response.text()}`);
  }
  assert.equal((await fetch(`${running.address}/api/browser/state`, { headers })).status, 200);
});

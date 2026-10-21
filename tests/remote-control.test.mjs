import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, realpath, stat, symlink, unlink, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { Service } from '../host/service.mjs';
import { provisionRemote } from '../host/remote-control.mjs';
import { home, taskIdle } from './support.mjs';

async function until(condition) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const result = await condition();
    if (result) return result;
    await delay(10);
  }
  throw new Error('Remote fixture did not reach its physical boundary');
}

function remoteRows(directory, request_id) {
  const database = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
  try {
    return database.prepare('SELECT input, decision FROM journal ORDER BY seq').all()
      .map(row => ({ input: JSON.parse(row.input), decision: JSON.parse(row.decision) }))
      .filter(row => row.input.kind === 'remote_command' && row.input.request_id === request_id);
  } finally { database.close(); }
}

test('private identity publication and lost remote command receipts survive restart', async t => {
  const base = await realpath(await home(t));
  const directory = path.join(base, 'state');
  const workspace = path.join(base, 'project');
  await mkdir(workspace);
  const guidance = path.join(workspace, 'AGENTS.override.md');
  await writeFile(guidance, 'Observe the remote task workspace.');
  const enrollmentToken = randomBytes(32).toString('base64url');
  const controller_id = 'a'.repeat(64);
  const pairing_id = randomUUID();
  const registrations = [];
  let socket;
  let publishedGrants = [];
  // This peer only delivers wire messages; grants and receipts come from the
  // production service and its actual SQLite journal.
  const relay = Bun.serve({ hostname: '127.0.0.1', port: 0,
    async fetch(request, server) {
      if (new URL(request.url).pathname === '/v1/hosts/register') {
        assert.equal(request.headers.get('authorization'), `Bearer ${enrollmentToken}`);
        const identity = await request.json();
        registrations.push(identity);
        return Response.json({ host_id: identity.host_id }, { status: 201 });
      }
      if (server.upgrade(request)) return;
      return new Response(null, { status: 426 });
    },
    websocket: {
      open(peer) { socket = peer; },
      message(peer, text) {
        const frame = JSON.parse(text);
        if (frame.type === 'hello') peer.send(JSON.stringify({ type: 'ready', version: 1 }));
        if (frame.type === 'grants') publishedGrants = frame.grants;
        if (frame.type === 'pairing') peer.send(JSON.stringify({ type: 'pair_request',
          request_id: pairing_id, controller_id, label: 'Local owner approved device' }));
        if (frame.type === 'ping') peer.send(JSON.stringify({ type: 'pong' }));
      },
    },
  });
  let service;
  t.after(async () => { await service?.close(); await relay.stop(true); });
  const relayUrl = `http://127.0.0.1:${relay.port}`;
  const provision = { home: directory, relayUrl, enrollmentToken, allowLoopback: true };
  const [firstIdentity, secondIdentity] = await Promise.all([provisionRemote(provision), provisionRemote(provision)]);
  assert.deepEqual(firstIdentity, secondIdentity);
  assert.deepEqual(registrations[0], registrations[1], 'Concurrent initializers register the same completed private identity');
  const filename = path.join(directory, 'remote-identity.json');
  assert.equal((await stat(filename)).mode & 0o777, 0o600);
  const identity = JSON.parse(await readFile(filename, 'utf8'));
  assert.equal(identity.host_id, firstIdentity.host_id);
  const config = { ...validateConfig({ ...defaultConfig, chatgpt: false }), remote: { relay_url: relayUrl } };
  const options = { home: directory, cwd: workspace, config, remoteOptions: { allowLoopback: true } };
  service = await Service.open(options);
  await service.remote.enable();
  await until(async () => (await service.remote.status()).connection.connected);
  await service.remote.pair();
  await until(() => service.remote.pending().some(request => request.request_id === pairing_id));
  assert.deepEqual(publishedGrants, []);
  const grant = await service.remote.approve(pairing_id, { read: true, control: true, configure: true, approve: false });
  await until(() => publishedGrants.some(item => item.controller_id === controller_id && item.grant_epoch === grant.grant_epoch));

  const request_id = randomUUID();
  const command = { op: 'create', profile: 'demo', message: 'Retain this remote command after reply loss.',
    settings: { workspace: { roots: [workspace], primary_root: workspace } } };
  const committed = new Promise(resolve => {
    const observe = decision => {
      if (decision.input.kind !== 'remote_command' || decision.input.request_id !== request_id) return;
      service.journal.off('commit', observe);
      socket.terminate(); // Lose delivery after the actual command and receipt commit.
      resolve(decision.reply);
    };
    service.journal.on('commit', observe);
    t.after(() => service.journal.off('commit', observe));
  });
  const connection = { connection_id: 'lost-reply', controller_id, grant_epoch: grant.grant_epoch };
  socket.send(JSON.stringify({ type: 'controller_open', ...connection }));
  socket.send(JSON.stringify({ type: 'request', ...connection,
    request: { id: 'lost', method: 'command', params: { request_id, command } } }));
  const reply = await committed;
  assert.equal(reply.ok, true, JSON.stringify(reply));
  await taskIdle(service, reply.result.task_id);
  await service.close();
  service = await Service.open(options);
  // Retrying a receipt must precede new filesystem observations, including a
  // source that became unreadable after this service finished opening.
  await unlink(guidance);
  await symlink(filename, guidance);
  const retried = await service.remoteCommand(controller_id, grant.grant_epoch, { request_id, command });
  assert.deepEqual(retried.reply, reply);
  const saved = remoteRows(directory, request_id);
  assert.equal(saved.length, 1);
  assert.deepEqual(saved[0].decision.reply, reply);
  await service.close();
  await unlink(filename);
  await promisify(execFile)('mkfifo', ['-m', '600', filename]);
  await assert.rejects(provisionRemote(provision), { code: 'remote_identity_permissions' });
});

import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { provisionRemote } from '../host/remote-control.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { startRelay } from '../relay/test/runtime.mjs';
import { home } from './support.mjs';

export const readPermission = { read: true, control: false, configure: false, approve: false };
export const controlPermission = { ...readPermission, control: true };

export async function remoteGitRepository(t) {
  const base = await realpath(await home(t));
  const source = path.join(base, 'source repository');
  await mkdir(source);
  const execute = promisify(execFile);
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const git = (...args) => execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Remote fixture', '-c', 'user.email=remote@example.test', '-C', source, ...args], { env });
  await git('init', '--initial-branch=main');
  await writeFile(path.join(source, 'tracked.txt'), 'Source repository contents');
  await git('add', '.');
  await git('commit', '-m', 'Initial remote worktree fixture');
  return { source, directory: path.join(base, 'state') };
}

export async function eventually(label, condition, timeout = 10_000) {
  const deadline = Date.now() + timeout;
  do {
    const value = await condition();
    if (value) return value;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Did not observe ${label}`);
}

export function relayPost(url, token, body) {
  return fetch(url, { method: 'POST', headers: {
    authorization: `Bearer ${token}`, 'content-type': 'application/json',
  }, body: JSON.stringify(body) });
}

export class RemoteClient {
  #messages = [];
  #waiters = new Set();
  #ended = false;

  constructor(url) {
    this.socket = new WebSocket(url);
    this.closed = new Promise(resolve => this.socket.addEventListener('close', event => {
      this.#ended = true;
      this.closeEvent = event;
      for (const wake of this.#waiters) wake();
      resolve(event);
    }, { once: true }));
    this.socket.addEventListener('message', event => {
      this.#messages.push(JSON.parse(event.data));
      for (const wake of this.#waiters) wake();
    });
    this.socket.addEventListener('error', () => {});
  }

  async next(predicate = () => true, timeout = 10_000) {
    const deadline = Date.now() + timeout;
    for (;;) {
      const index = this.#messages.findIndex(predicate);
      if (index !== -1) return this.#messages.splice(index, 1)[0];
      if (this.#ended) throw new Error(`Remote socket closed (${this.closeEvent.code}) before the expected message`);
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new Error('Timed out waiting for a remote message');
      await new Promise(resolve => {
        const wake = () => { clearTimeout(timer); this.#waiters.delete(wake); resolve(); };
        const timer = setTimeout(wake, remaining);
        this.#waiters.add(wake);
      });
    }
  }

  send(message) { this.socket.send(JSON.stringify(message)); }

  async request(method, params = {}) {
    const id = randomUUID();
    this.send({ id, method, params });
    return this.next(message => message.id === id);
  }

  command(command, request_id = randomUUID()) {
    return this.request('command', { request_id, command });
  }

  close() {
    if (this.socket.readyState < WebSocket.CLOSING) this.socket.close();
    return this.closed;
  }
}

export async function connectController(t, { relayUrl, hostId, token }) {
  const response = await eventually('a current controller ticket', async () => {
    const result = await relayPost(`${relayUrl}/v1/hosts/${hostId}/tickets`, token, {});
    if ([401, 403, 409, 503].includes(result.status)) return false;
    assert.equal(result.status, 200, await result.clone().text());
    return result;
  });
  const { ticket } = await response.json();
  const client = new RemoteClient(`${relayUrl.replace(/^http/, 'ws')}/v1/hosts/${hostId}/control?ticket=${encodeURIComponent(ticket)}`);
  t.after(() => client.close());
  client.ready = await client.next(message => message.type === 'ready');
  assert.equal(client.ready.version, 1);
  return client;
}

export async function remoteFixture(t, { config = validateConfig(defaultConfig), directory } = {}) {
  directory ??= await home(t);
  const enrollmentToken = randomBytes(32).toString('base64url');
  const relay = await startRelay({ enrollmentToken });
  let service;
  const clients = new Set();
  t.after(async () => {
    for (const client of clients) await client.close();
    await service?.close();
    await relay.close();
  });
  const identity = await provisionRemote({ home: directory, relayUrl: relay.url, enrollmentToken, allowLoopback: true });
  config = { ...config, remote: { relay_url: relay.url } };
  const options = { home: directory, cwd: directory, config, remoteOptions: { allowLoopback: true } };
  service = await Service.open(options);
  await service.remote.enable();
  const online = () => eventually('the host relay connection', async () => (await service.remote.status()).connection.connected);
  await online();
  const f = {
    directory, relay, identity, config,
    get service() { return service; },
    online,
    async restart() {
      await service.close();
      service = await Service.open(options);
      await online();
    },
    async connect(token) {
      const client = await connectController(t, { relayUrl: relay.url, hostId: identity.host_id, token });
      clients.add(client);
      return client;
    },
    async pair(permissions = controlPermission) {
      const token = randomBytes(32).toString('base64url');
      const pairing = await service.remote.pair();
      const response = await relayPost(`${relay.url}/v1/hosts/${identity.host_id}/pair`, pairing.code,
        { controller_token: token, label: 'Test controller 手机' });
      assert.equal(response.status, 200, await response.clone().text());
      const pending = await response.json();
      const requests = await eventually('the local pairing request', async () => {
        const current = await service.remote.pending();
        return current.some(request => request.request_id === pending.request_id) && current;
      });
      assert.equal(requests.find(request => request.request_id === pending.request_id).controller_id, pending.controller_id);
      const grant = await service.remote.approve(pending.request_id, permissions);
      const client = await f.connect(token);
      assert.equal(client.ready.controller_id, pending.controller_id);
      assert.equal(client.ready.grant_epoch, grant.grant_epoch);
      return { token, pairing, pending, grant, client };
    },
  };
  return f;
}

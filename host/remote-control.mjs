import { remoteControl } from '../remote/control-model.mjs';
import { constants } from 'node:fs';
import { link, mkdir, open, unlink } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import path from 'node:path';
import { requestJson } from './network.mjs';
import { RemoteConnector } from './remote-connector.mjs';
import { assertRelayUrl, REMOTE_PAIRING_TTL_MS } from '../remote/protocol.mjs';

const identityFormat = 'selvedge-remote-identity-1';
const identityName = 'remote-identity.json';
const tokenShape = /^[A-Za-z0-9_-]{43}$/;
const hostShape = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function remoteError(code, message) {
  return Object.assign(new Error(message), { code });
}

async function readIdentity(home, relayUrl) {
  let file;
  try {
    file = await open(path.join(home, identityName), constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
    const stat = await file.stat();
    // DEFENSE: The persisted credential may be replaced with a public, foreign-owned, oversized, or nonregular file.
    if (!stat.isFile() || stat.size > 4096 || (stat.mode & 0o077) !== 0 ||
        stat.uid !== process.getuid()) {
      throw remoteError('remote_identity_permissions', 'Remote identity must be a private regular file owned by this user');
    }
    const buffer = Buffer.alloc(stat.size + 1);
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await file.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    // Atomic publication removes its temporary hard link after exposing the
    // complete identity; that cleanup changes ctime without changing content.
    const publicationCleanup = stat.nlink === 2 && after.nlink === 1;
    // DEFENSE: Another local process can edit the credential during the bounded read; refuse a mixed or permission-changed identity.
    if (length !== stat.size || after.size !== stat.size || after.mtimeMs !== stat.mtimeMs ||
        (after.ctimeMs !== stat.ctimeMs && !publicationCleanup) ||
        after.mode !== stat.mode || after.uid !== stat.uid) {
      throw remoteError('remote_identity_invalid', 'Remote identity changed while being read');
    }
    let value;
    try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(buffer.subarray(0, length))); }
    // DEFENSE: Malformed credential bytes must fail without exposing file contents in the parser's diagnostic.
    catch { throw remoteError('remote_identity_invalid', 'Remote identity has an invalid current format'); }
    // DEFENSE: A hand-edited or obsolete identity file must not supply credentials for a different relay or format.
    if (value?.format !== identityFormat || !hostShape.test(value.host_id) || !tokenShape.test(value.host_token) ||
        value.relay_url !== relayUrl || Object.keys(value).sort().join(',') !== 'format,host_id,host_token,relay_url') {
      throw remoteError('remote_identity_invalid', 'Remote identity does not match this relay or the current format');
    }
    return value;
  } catch (error) {
    // DEFENSE: Startup before remote init has no identity; selecting a symlink must not follow it to credential data.
    if (error.code === 'ENOENT') throw remoteError('remote_identity_missing', 'Initialize this relay with remote init before enabling remote control');
    if (error.code === 'ELOOP') throw remoteError('remote_identity_permissions', 'Remote identity must not be a symbolic link');
    throw error;
  } finally { await file?.close(); }
}

/** Register one persistent installation; secrets remain in the private service home. */
export async function provisionRemote({ home, relayUrl, enrollmentToken, allowLoopback = false }) {
  const relay_url = assertRelayUrl(relayUrl, { allowLoopback });
  // DEFENSE: remote init reads this credential from the user's environment; absent or invalid header bytes cannot authenticate enrollment.
  if (typeof enrollmentToken !== 'string' || enrollmentToken.length < 32 || enrollmentToken.length > 512 ||
      !/^[\x21-\x7e]+$/.test(enrollmentToken)) {
    throw remoteError('remote_enrollment_missing', 'Set SELVEDGE_RELAY_ENROLLMENT_TOKEN to the relay enrollment credential');
  }
  await mkdir(home, { recursive: true, mode: 0o700 });
  let identity;
  try { identity = await readIdentity(home, relay_url); }
  catch (error) {
    // DEFENSE: Only a missing identity permits first-time creation; permission, format, and disk errors must propagate.
    if (error.code !== 'remote_identity_missing') throw error;
    const proposed = { format: identityFormat, host_id: randomUUID(), host_token: randomBytes(32).toString('base64url'), relay_url };
    const filename = path.join(home, identityName);
    const temporary = `${filename}.${randomUUID()}.tmp`;
    let file;
    try {
      file = await open(temporary, 'wx', 0o600);
      await file.writeFile(JSON.stringify(proposed) + '\n');
      await file.sync();
      await file.close();
      file = undefined;
      try { await link(temporary, filename); }
      // DEFENSE: Concurrent remote-init processes may publish first; the loser reads the winner's completed private identity.
      catch (error) { if (error.code !== 'EEXIST') throw error; }
      await unlink(temporary);
      const directory = await open(home, 'r');
      try { await directory.sync(); } finally { await directory.close(); }
    } finally {
      await file?.close();
      // DEFENSE: Successful publication already removed this temporary file; every other cleanup failure remains visible.
      await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
    }
    identity = await readIdentity(home, relay_url);
  }
  let registered;
  try {
    registered = await requestJson(`${relay_url}/v1/hosts/register`, {
      headers: { authorization: `Bearer ${enrollmentToken}` },
      body: { host_id: identity.host_id, host_token: identity.host_token }, maximum: 4096,
    });
  // DEFENSE: Enrollment network/HTTP-body failures retain the installation identity and do not expose credential-bearing diagnostics.
  } catch {
    throw remoteError('remote_registration_failed', 'Remote relay registration failed; the private installation identity is retained for retry');
  }
  // DEFENSE: The remote registration endpoint may reject enrollment or return an unrelated host identity.
  if (!registered.ok || registered.value?.host_id !== identity.host_id) {
    throw remoteError('remote_registration_rejected', `Remote relay rejected host registration (HTTP ${registered.status})`);
  }
  return { host_id: identity.host_id, relay_url };
}

function unwrap(result) {
  if (!result.reply.ok) throw remoteError(result.reply.error.code, result.reply.error.message);
  return result.reply.result;
}

/** Local owner management; remote devices cannot invoke these methods over the relay. */
export class RemoteControl {
  #service;
  #identity;
  #options;
  #connector;
  #pairingState = { expires_at: 0, pending: [] };
  #pairingStep(kind, observation = {}) {
    this.#pairingState = remoteControl('pairing', { state: this.#pairingState, event: { kind, now: Date.now(), ...observation } });
  }
  #closed = false;
  #dirty = false;
  #reconciling;
  #grantsKey;

  static async open(service, options = {}) {
    const manager = new RemoteControl();
    manager.#service = service;
    manager.#options = options;
    try {
      if (service.config.remote) {
        const relayUrl = assertRelayUrl(service.config.remote.relay_url, { allowLoopback: options.allowLoopback === true });
        manager.#identity = await readIdentity(service.home, relayUrl);
      }
      if (manager.#identity) await manager.#reconcile();
      return manager;
    // DEFENSE: Opening a configured identity or starting its socket may fail; close already-acquired resources before propagating.
    } catch (error) {
      await manager.close();
      throw error;
    }
  }

  async #nativeStatus() {
    return unwrap(await this.#service.command({ op: 'remote_status' }));
  }

  async status() {
    const state = await this.#nativeStatus();
    return { configured: Boolean(this.#identity), relay_url: this.#identity?.relay_url ?? null,
      host_id: this.#identity?.host_id ?? null, ...state,
      connection: this.#connector?.status() ?? { state: 'disabled' } };
  }

  #configured() {
    // DEFENSE: Local management requests can arrive after shutdown or before the owner has initialized remote control.
    if (this.#closed) throw remoteError('remote_closed', 'Remote control is closed');
    if (!this.#identity) throw remoteError('remote_unconfigured', 'Run remote init and restart Selvedge before enabling remote control');
  }

  async #enabled() {
    this.#configured();
    // DEFENSE: The owner can request pairing while the persisted native remote feature is disabled.
    if (!(await this.#nativeStatus()).enabled) throw remoteError('remote_disabled', 'Enable remote control before pairing a device');
  }

  async enable() {
    this.#configured();
    unwrap(await this.#service.command({ op: 'remote_enable' }));
    await this.reconcile();
    return this.status();
  }

  async disable() {
    unwrap(await this.#service.command({ op: 'remote_disable' }));
    this.#pairingStep('clear');
    await this.reconcile();
    return this.status();
  }

  async pair() {
    await this.#enabled();
    const code = randomBytes(32).toString('base64url');
    const expires_at = Date.now() + REMOTE_PAIRING_TTL_MS;
    this.#pairingStep('begin', { expires_at });
    await this.#connector.pair(code, expires_at);
    return { code, expires_at, host_id: this.#identity.host_id, relay_url: this.#identity.relay_url };
  }

  pending() {
    this.#pairingStep('observe');
    return this.#pairingState.pending.map(request => ({ ...request }));
  }

  async approve(request_id, permissions) {
    await this.#enabled();
    this.pending();
    const request = this.#pairingState.pending.find(request => request.request_id === request_id);
    // DEFENSE: A local approve request can name an expired, already-consumed, or nonexistent pairing request.
    if (!request) throw remoteError('remote_pairing_missing', 'This pairing request is unavailable or expired');
    const result = unwrap(await this.#service.command({ op: 'remote_grant', controller_id: request.controller_id, permissions }));
    this.#pairingStep('consume', { request_id });
    await this.reconcile();
    return result;
  }

  async revoke(controller_id) {
    const result = unwrap(await this.#service.command({ op: 'remote_revoke', controller_id }));
    await this.reconcile();
    return result;
  }

  #pairRequested(request) {
    if (this.#closed) return;
    this.#pairingStep('receive', { request: { request_id: request.request_id, controller_id: request.controller_id, label: request.label } });
  }

  reconcile() {
    if (this.#closed || !this.#identity) return Promise.resolve();
    this.#dirty = true;
    if (!this.#reconciling) {
      this.#reconciling = (async () => {
        while (this.#dirty && !this.#closed) {
          this.#dirty = false;
          await this.#reconcile();
        }
      // DEFENSE: Background grant synchronization can encounter a stopped kernel or failed socket; report it to local observers.
      })().catch(() => {
        this.#service.notify({ type: 'diagnostic', message: 'Remote control connection could not be reconciled' });
      }).finally(() => {
        this.#reconciling = undefined;
        if (this.#dirty && !this.#closed) this.reconcile();
      });
    }
    return this.#reconciling;
  }

  async #reconcile() {
    const state = await this.#nativeStatus();
    // DEFENSE: A native status observation may finish after local shutdown begins.
    if (this.#closed) return;
    if (!state.enabled) {
      const connector = this.#connector;
      this.#connector = undefined;
      this.#grantsKey = undefined;
      this.#pairingStep('clear');
      await connector?.close();
      return;
    }
    if (!this.#connector) {
      this.#connector = new RemoteConnector({ relayUrl: this.#identity.relay_url, hostId: this.#identity.host_id,
        hostToken: this.#identity.host_token, service: this.#service,
        allowLoopback: this.#options.allowLoopback === true,
        getGrants: async () => {
          const current = await this.#nativeStatus();
          return current.enabled ? current.grants : [];
        },
        onPairRequest: request => this.#pairRequested(request),
      });
      await this.#connector.start();
    }
    const key = JSON.stringify(state.grants);
    if (key !== this.#grantsKey) {
      await this.#connector.syncGrants();
      this.#grantsKey = key;
    }
  }

  async close() {
    this.#closed = true;
    this.#pairingStep('clear');
    await this.#connector?.close();
    await this.#reconciling;
    this.#connector = undefined;
  }
}

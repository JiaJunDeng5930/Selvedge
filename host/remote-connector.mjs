import { randomUUID } from 'node:crypto';
import { encodeBendValue } from './public/bend-value.mjs';
import {
  REMOTE_PROTOCOL_VERSION, MAX_REMOTE_FRAME_BYTES, MAX_REMOTE_CONTROLLERS,
  assertRelayUrl, isHostId, isRemoteToken, parseRemoteFrame, encodeRemoteFrame,
  validateHostFrame, validateRelayFrame,
} from '../remote/protocol.mjs';

const MAX_CONNECTION_QUEUE = 32;
const MAX_CONNECTOR_QUEUE = 256;
const MAX_BUFFERED_BYTES = MAX_REMOTE_FRAME_BYTES * 2;

/** Outbound relay transport only; disconnecting never cancels a native task. */
export class RemoteConnector {
  #service;
  #getGrants;
  #onPairRequest;
  #onStatus;
  #hostToken;
  #hostUrl;
  #running = false;
  #session;
  #retryTimer;
  #probe;
  #attempt = 0;
  #generation = 0;
  #pairing;
  #grantTail = Promise.resolve();
  #noticeSequence = 0;
  #incarnation = randomUUID();
  #status = { state: 'stopped', connected: false, controller_count: 0 };
  #settings;
  #noticeListener;

  constructor({ relayUrl, hostId, hostToken, service, getGrants, onPairRequest = () => {}, onStatus = () => {},
    allowLoopback = false, retryBaseMs = 1000, retryMaxMs = 30_000,
    heartbeatMs = 15_000, heartbeatTimeoutMs = 45_000, connectTimeoutMs = 10_000,
    createWebSocket = (url, options) => new WebSocket(url, options), fetch: fetchRequest = fetch } = {}) {
    const origin = assertRelayUrl(relayUrl, { allowLoopback });
    if (!isHostId(hostId) || !isRemoteToken(hostToken)) throw new TypeError('Remote connector host identity is invalid');
    if (!service || typeof service.remoteCheck !== 'function' || typeof service.remoteCommand !== 'function'
        || typeof service.browserSnapshot !== 'function' || typeof service.browserStreams !== 'function'
        || typeof service.on !== 'function' || typeof service.off !== 'function' || typeof getGrants !== 'function') {
      throw new TypeError('Remote connector requires a service and native grant observer');
    }
    if (![retryBaseMs, retryMaxMs, heartbeatMs, heartbeatTimeoutMs, connectTimeoutMs].every(value => Number.isSafeInteger(value) && value > 0)
        || retryMaxMs < retryBaseMs || heartbeatTimeoutMs < heartbeatMs) {
      throw new TypeError('Remote connector timing limits are invalid');
    }
    this.#hostUrl = `${origin}/v1/hosts/${hostId}/host`;
    this.#hostToken = hostToken;
    this.#service = service;
    this.#getGrants = getGrants;
    this.#onPairRequest = onPairRequest;
    this.#onStatus = onStatus;
    this.#settings = { retryBaseMs, retryMaxMs, heartbeatMs, heartbeatTimeoutMs, connectTimeoutMs, createWebSocket, fetchRequest };
    this.#noticeListener = notice => this.#notice(notice);
  }

  status() { return { ...this.#status }; }

  start() {
    if (this.#running) return this.status();
    this.#running = true;
    this.#attempt = 0;
    this.#service.on('notice', this.#noticeListener);
    this.#connect();
    return this.status();
  }

  close() {
    this.#running = false;
    ++this.#generation;
    clearTimeout(this.#retryTimer);
    this.#retryTimer = undefined;
    this.#probe?.abort();
    this.#probe = undefined;
    this.#pairing = undefined;
    this.#service.off('notice', this.#noticeListener);
    this.#retireSession();
    this.#setStatus('stopped');
  }

  pair(code, expiresAt) {
    const frame = validateHostFrame({ type: 'pairing', code, expires_at: expiresAt });
    if (expiresAt <= Date.now()) throw new TypeError('Remote connector pairing code has expired');
    this.#pairing = frame;
    if (this.#session?.ready) this.#send(this.#session, frame);
  }

  syncGrants() {
    // A single owner preserves native grant observation order across reconnects.
    const next = this.#grantTail.then(async () => {
      const session = this.#session;
      if (!session?.ready) return;
      const grants = (await this.#getGrants()).map(({ controller_id, grant_epoch }) => ({ controller_id, grant_epoch }));
      if (!this.#current(session)) return;
      const frame = validateHostFrame({ type: 'grants', grants });
      const active = new Map(grants.map(grant => [grant.controller_id, grant.grant_epoch]));
      for (const [id, connection] of session.connections) {
        if (active.get(connection.controllerId) !== connection.grantEpoch) this.#forgetConnection(session, id);
      }
      this.#send(session, frame);
    });
    this.#grantTail = next.catch(() => {});
    return next;
  }

  #setStatus(state, detail = {}) {
    this.#status = { state, connected: state === 'online', controller_count: this.#session?.connections.size ?? 0, ...detail };
    try { this.#onStatus(this.status()); } catch { /* Status observers do not own transport lifetime. */ }
  }

  async #connect() {
    if (!this.#running) return;
    const generation = ++this.#generation;
    this.#setStatus('connecting');
    const probe = new AbortController();
    this.#probe = probe;
    const timeout = setTimeout(() => probe.abort(), this.#settings.connectTimeoutMs);
    timeout.unref?.();
    try {
      // Bun's failed WebSocket handshake hides HTTP status. Probe the same
      // authenticated route to distinguish a rejected credential from an outage.
      const response = await this.#settings.fetchRequest(this.#hostUrl, {
        headers: { authorization: `Bearer ${this.#hostToken}` }, redirect: 'error', signal: probe.signal,
      });
      await response.body?.cancel();
      if (!this.#running || generation !== this.#generation) return;
      if ([401, 403, 404].includes(response.status)) {
        this.#stopForAuth();
        return;
      }
      if (response.status !== 426) throw new Error('Remote connector relay probe failed');
      const url = new URL(this.#hostUrl);
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      const socket = this.#settings.createWebSocket(url.href, { headers: { authorization: `Bearer ${this.#hostToken}` } });
      const session = { socket, generation, connections: new Map(), ready: false, negotiated: false,
        queued: 0, queuedBytes: 0, lastPong: Date.now() };
      this.#session = session;
      session.timeout = setTimeout(() => this.#disconnect(session, 'negotiation_timeout'), this.#settings.connectTimeoutMs);
      session.timeout.unref?.();
      socket.addEventListener('open', () => {
        if (this.#current(session)) this.#send(session, { type: 'hello', version: REMOTE_PROTOCOL_VERSION });
      });
      socket.addEventListener('message', event => this.#receive(session, event.data));
      socket.addEventListener('error', () => { /* Close owns the single reconnect timer. */ });
      socket.addEventListener('close', event => {
        if (!this.#current(session)) return;
        if (event.code === 1008) this.#stopForAuth();
        else this.#disconnect(session, 'connection_closed');
      });
    } catch {
      if (this.#running && generation === this.#generation) this.#retry('connection_unavailable');
    } finally {
      clearTimeout(timeout);
      if (this.#probe === probe) this.#probe = undefined;
    }
  }

  #current(session) { return this.#running && this.#session === session && session.generation === this.#generation; }

  #stopForAuth() {
    this.#running = false;
    ++this.#generation;
    clearTimeout(this.#retryTimer);
    this.#service.off('notice', this.#noticeListener);
    this.#retireSession();
    this.#setStatus('auth_failed', { last_error: 'relay_authentication_failed' });
  }

  #retireSession() {
    const session = this.#session;
    this.#session = undefined;
    if (!session) return;
    // A consumed pair_request might have been lost with this connection. A new
    // connection needs a fresh local code, never a replay of the previous code.
    this.#pairing = undefined;
    clearTimeout(session.timeout);
    clearInterval(session.heartbeat);
    for (const connection of session.connections.values()) connection.active = false;
    session.connections.clear();
    try { session.socket.close(1000, 'Remote connector disconnected'); } catch { /* Already closed. */ }
  }

  #disconnect(session, reason) {
    if (!this.#current(session)) return;
    this.#retireSession();
    this.#retry(reason);
  }

  #retry(reason) {
    if (!this.#running || this.#retryTimer) return;
    const ceiling = Math.min(this.#settings.retryMaxMs, this.#settings.retryBaseMs * 2 ** Math.min(this.#attempt++, 16));
    const delay = Math.max(1, Math.floor(ceiling * (0.5 + Math.random() * 0.5)));
    this.#setStatus('retrying', { last_error: reason, next_retry_at: Date.now() + delay });
    this.#retryTimer = setTimeout(() => {
      this.#retryTimer = undefined;
      this.#connect();
    }, delay);
    this.#retryTimer.unref?.();
  }

  #send(session, frame) {
    if (!this.#current(session)) return false;
    try {
      const encoded = encodeRemoteFrame(frame, validateHostFrame);
      if (session.socket.readyState !== WebSocket.OPEN || session.socket.bufferedAmount + Buffer.byteLength(encoded) > MAX_BUFFERED_BYTES) {
        this.#disconnect(session, 'transport_backpressure');
        return false;
      }
      session.socket.send(encoded);
      return true;
    } catch {
      this.#disconnect(session, 'outbound_frame_rejected');
      return false;
    }
  }

  #receive(session, data) {
    if (!this.#current(session)) return;
    let frame;
    try { frame = parseRemoteFrame(data, validateRelayFrame); }
    catch { this.#disconnect(session, 'relay_frame_rejected'); return; }
    if (frame.type === 'ready') {
      if (session.negotiated) { this.#disconnect(session, 'duplicate_negotiation'); return; }
      session.negotiated = true;
      session.ready = true;
      this.syncGrants().then(() => {
        if (!this.#current(session)) return;
        if (this.#pairing?.expires_at > Date.now()) {
          if (!this.#send(session, this.#pairing)) return;
        }
        else this.#pairing = undefined;
        clearTimeout(session.timeout);
        this.#attempt = 0;
        this.#setStatus('online');
        session.heartbeat = setInterval(() => {
          if (Date.now() - session.lastPong > this.#settings.heartbeatTimeoutMs) this.#disconnect(session, 'heartbeat_timeout');
          else this.#send(session, { type: 'ping' });
        }, this.#settings.heartbeatMs);
        session.heartbeat.unref?.();
      }).catch(() => this.#disconnect(session, 'grant_sync_failed'));
      return;
    }
    if (!session.ready) { this.#disconnect(session, 'negotiation_required'); return; }
    if (frame.type === 'pong') { session.lastPong = Date.now(); return; }
    if (frame.type === 'pair_request') {
      // The relay spent the one-time code. Reconnection must never republish it.
      this.#pairing = undefined;
      Promise.resolve().then(() => this.#onPairRequest(frame)).catch(() => {});
      return;
    }
    if (frame.type === 'controller_close') { this.#forgetConnection(session, frame.connection_id); return; }
    if (frame.type === 'controller_open') {
      if (session.connections.has(frame.connection_id) || session.connections.size >= MAX_REMOTE_CONTROLLERS) {
        this.#disconnect(session, 'controller_limit_exceeded'); return;
      }
      session.connections.set(frame.connection_id, { controllerId: frame.controller_id, grantEpoch: frame.grant_epoch,
        active: true, subscribed: false, queued: 0, tail: Promise.resolve() });
      this.#setStatus('online');
      return;
    }
    if (frame.type === 'request') {
      const connection = session.connections.get(frame.connection_id);
      if (!connection || connection.controllerId !== frame.controller_id || connection.grantEpoch !== frame.grant_epoch) {
        this.#disconnect(session, 'controller_identity_mismatch'); return;
      }
      this.#enqueue(session, connection, Buffer.byteLength(data), () => this.#request(session, frame.connection_id, connection, frame.request));
    }
  }

  #forgetConnection(session, id) {
    const connection = session.connections.get(id);
    if (connection) connection.active = false;
    session.connections.delete(id);
    if (this.#current(session) && this.#status.state === 'online') this.#setStatus('online');
  }

  #enqueue(session, connection, bytes, operation) {
    if (!connection.active || !this.#current(session)) return;
    if (connection.queued >= MAX_CONNECTION_QUEUE || session.queued >= MAX_CONNECTOR_QUEUE
        || session.queuedBytes + bytes > MAX_BUFFERED_BYTES) {
      this.#disconnect(session, 'request_queue_full'); return;
    }
    ++connection.queued;
    ++session.queued;
    session.queuedBytes += bytes;
    connection.tail = connection.tail.then(async () => {
      if (connection.active && this.#current(session)) await operation();
    }).catch(() => {
      this.#disconnect(session, 'request_processing_failed');
    }).finally(() => {
      --connection.queued;
      --session.queued;
      session.queuedBytes -= bytes;
    });
  }

  async #authorize(session, connection, authorized) {
    for (let attempt = 0; attempt < 4; ++attempt) {
      const check = await this.#service.remoteCheck(connection.controllerId, connection.grantEpoch);
      if (!this.#current(session) || !connection.active) return false;
      if (!check.reply?.ok) { connection.subscribed = false; return false; }
      // No await follows this comparison before capture/send. A revocation
      // committed while the native check returned forces a new native check.
      if (this.#service.browserSnapshot().sequence === check.sequence) {
        authorized();
        return true;
      }
    }
    this.#disconnect(session, 'authorization_revision_changed');
    return false;
  }

  #snapshot() {
    const snapshot = this.#service.browserSnapshot();
    return { incarnation: this.#incarnation, namespace: snapshot.namespace, sequence: snapshot.sequence, program: encodeBendValue(snapshot.program),
      streams: encodeBendValue(this.#service.browserStreams()), notice_sequence: this.#noticeSequence };
  }

  async #request(session, id, connection, request) {
    try {
      if (request.method === 'command') {
        const result = await this.#service.remoteCommand(connection.controllerId, connection.grantEpoch, request.params);
        if (connection.active) this.#send(session, { type: 'response', connection_id: id, response: { id: request.id, result: encodeBendValue(result) } });
        return;
      }
      const allowed = await this.#authorize(session, connection, () => {
        let result;
        if (request.method === 'unsubscribe') {
          connection.subscribed = false;
          result = { subscribed: false };
        } else {
          result = this.#snapshot();
          if (request.method === 'subscribe') {
            connection.subscribed = true;
            connection.after = result.notice_sequence;
          }
        }
        this.#send(session, { type: 'response', connection_id: id, response: { id: request.id, result } });
      });
      if (!allowed) {
        if (connection.active) this.#send(session, { type: 'response', connection_id: id,
          response: { id: request.id, error: { code: 'remote_access_denied', message: 'Remote access is unavailable for this device' } } });
        return;
      }
    } catch {
      if (connection.active) this.#send(session, { type: 'response', connection_id: id,
        response: { id: request.id, error: { code: 'remote_request_failed', message: 'Remote request could not be completed' } } });
    }
  }

  #notice(notice) {
    const sequence = ++this.#noticeSequence;
    const session = this.#session;
    if (!session?.ready) return;
    let event;
    let bytes;
    try {
      event = { incarnation: this.#incarnation, notice_sequence: sequence, notice: encodeBendValue(notice) };
      bytes = Buffer.byteLength(encodeRemoteFrame(event));
    } catch { this.#disconnect(session, 'observation_frame_rejected'); return; }
    for (const [id, connection] of session.connections) {
      if (!connection.subscribed || sequence <= connection.after) continue;
      this.#enqueue(session, connection, bytes, async () => {
        if (!connection.subscribed || sequence <= connection.after) return;
        await this.#authorize(session, connection, () => {
          connection.after = sequence;
          this.#send(session, { type: 'event', connection_id: id, event });
        });
      });
    }
  }
}

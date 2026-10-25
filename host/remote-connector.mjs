import { remoteControl } from '../remote/control-model.mjs';
import { randomUUID } from 'node:crypto';
import {
  REMOTE_PROTOCOL_VERSION, MAX_REMOTE_FRAME_BYTES,
  assertRelayUrl, parseRemoteFrame, encodeRemoteFrame,
  validateRelayFrame,
} from '../remote/protocol.mjs';

const MAX_BUFFERED_BYTES = MAX_REMOTE_FRAME_BYTES * 2;


/** Outbound relay transport only; disconnecting never cancels a native task. */
export class RemoteConnector {
  #service;
  #getGrants;
  #onPairRequest;
  #onStatus;
  #hostToken;
  #hostUrl;
  #control = { running: false, generation: 0 };
  get #running() { return this.#control.running; }
  get #generation() { return this.#control.generation; }
  #step(kind, observation = {}) {
    const result = remoteControl('connector', { state: this.#control, event: { kind, ...observation } });
    this.#control = result.state;
    return result.action;
  }
  #session;
  #retryTimer;
  #probe;
  #attempt = 0;
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
    this.#step('enable');
    this.#attempt = 0;
    this.#service.on('notice', this.#noticeListener);
    this.#connect();
    return this.status();
  }

  close() {
    this.#step('stop');
    clearTimeout(this.#retryTimer);
    this.#retryTimer = undefined;
    this.#probe?.abort();
    this.#probe = undefined;
    this.#service.off('notice', this.#noticeListener);
    this.#retireSession();
    this.#setStatus('stopped');
  }

  pair(code, expiresAt) {
    const frame = { type: 'pairing', code, expires_at: expiresAt };
    const action = this.#step('pair', { generation: this.#generation, now: Date.now(), frame });
    if (action === 'pairing') this.#send(this.#session, frame);
  }

  syncGrants() {
    // A single owner preserves native grant observation order across reconnects.
    const next = this.#grantTail.then(async () => {
      const session = this.#session;
      if (!session?.ready) return;
      const grants = (await this.#getGrants()).map(({ controller_id, grant_epoch }) => ({ controller_id, grant_epoch }));
      // DEFENSE: Grant observation can complete after a reconnect or shutdown retired this socket.
      if (!this.#current(session)) return;
      const frame = { type: 'grants', grants };
      this.#step('grants', { generation: session.generation, grants });
      const active = new Set(this.#control.connections.map(connection => connection.connection_id));
      for (const [id, connection] of session.connections) {
        // DEFENSE: A grant update may revoke or replace a controller already connected to this transport.
        if (!active.has(id)) this.#forgetConnection(session, id);
      }
      this.#send(session, frame);
    });
    // DEFENSE: A stopped kernel rejects grant observation; the caller handles it and later grant changes still need serialization.
    this.#grantTail = next.catch(() => {});
    return next;
  }

  #setStatus(state, detail = {}) {
    this.#status = { state, connected: state === 'online', controller_count: this.#session?.connections.size ?? 0, ...detail };
    this.#onStatus(this.status());
  }

  async #connect() {
    if (!this.#running) return;
    this.#step('start');
    const generation = this.#generation;
    this.#setStatus('connecting');
    const probe = new AbortController();
    this.#probe = probe;
    const timeout = setTimeout(() => probe.abort(), this.#settings.connectTimeoutMs);
    timeout.unref();
    try {
      // Bun's failed WebSocket handshake hides HTTP status. Probe the same
      // authenticated route to distinguish a rejected credential from an outage.
      const response = await this.#settings.fetchRequest(this.#hostUrl, {
        headers: { authorization: `Bearer ${this.#hostToken}` }, redirect: 'error', signal: probe.signal,
      });
      await response.body?.cancel();
      // DEFENSE: Shutdown or a newer attempt can retire this probe while the HTTP request is in flight.
      if (!this.#running || generation !== this.#generation) return;
      // DEFENSE: A relay can reject a deleted host or revoked credential; these statuses stop reconnecting until reconfigured.
      if ([401, 403, 404].includes(response.status)) {
        this.#stopForAuth();
        return;
      }
      // DEFENSE: The authenticated probe must confirm the WebSocket route rather than accept an unrelated HTTP response.
      if (response.status !== 426) throw new Error('Remote connector relay probe failed');
      const url = new URL(this.#hostUrl);
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      const socket = this.#settings.createWebSocket(url.href, { headers: { authorization: `Bearer ${this.#hostToken}` } });
      const session = { socket, generation, connections: new Map(), ready: false, negotiated: false, lastPong: Date.now() };
      this.#session = session;
      session.timeout = setTimeout(() => this.#disconnect(session, 'negotiation_timeout'), this.#settings.connectTimeoutMs);
      session.timeout.unref();
      socket.addEventListener('open', () => {
        if (this.#current(session)) this.#send(session, { type: 'hello', version: REMOTE_PROTOCOL_VERSION });
      });
      socket.addEventListener('message', event => this.#receive(session, event.data));
      socket.addEventListener('error', () => { /* Close owns the single reconnect timer. */ });
      socket.addEventListener('close', event => {
        // DEFENSE: A retired socket can deliver its close event after a replacement has connected.
        if (!this.#current(session)) return;
        // DEFENSE: A relay 1008 close rejects this host's protocol/policy; repeated negotiation needs owner intervention rather than a reconnect loop.
        if (event.code === 1008) this.#stopForAuth();
        else this.#disconnect(session, 'connection_closed');
      });
    // DEFENSE: Network/probe failure before negotiation reconnects the transport; no command is replayed.
    } catch {
      if (this.#running && generation === this.#generation) this.#retry('connection_unavailable');
    } finally {
      clearTimeout(timeout);
      if (this.#probe === probe) this.#probe = undefined;
    }
  }

  #current(session) { return this.#session === session && remoteControl('current', { state: this.#control, event: { generation: session.generation } }); }

  #stopForAuth() {
    this.#step('stop');
    clearTimeout(this.#retryTimer);
    this.#service.off('notice', this.#noticeListener);
    this.#retireSession();
    this.#setStatus('auth_failed', { last_error: 'relay_authentication_failed' });
  }

  #retireSession() {
    const session = this.#session;
    this.#session = undefined;
    if (!session) return;
    this.#step('retire', { generation: session.generation });
    // A consumed pair_request might have been lost with this connection. A new
    // connection needs a fresh local code, never a replay of the previous code.
    clearTimeout(session.timeout);
    clearInterval(session.heartbeat);
    for (const connection of session.connections.values()) connection.active = false;
    session.connections.clear();
    session.socket.close(1000, 'Remote connector disconnected');
  }

  #disconnect(session, reason) {
    // DEFENSE: A timeout or socket callback can fire after another callback already retired its session.
    if (!this.#current(session)) return;
    this.#retireSession();
    this.#retry(reason);
  }

  #retry(reason) {
    // DEFENSE: Close and multiple socket callbacks can race with an already scheduled reconnect.
    if (!this.#running || this.#retryTimer) return;
    const ceiling = Math.min(this.#settings.retryMaxMs, this.#settings.retryBaseMs * 2 ** Math.min(this.#attempt++, 16));
    const delay = Math.max(1, Math.floor(ceiling * (0.5 + Math.random() * 0.5)));
    this.#setStatus('retrying', { last_error: reason, next_retry_at: Date.now() + delay });
    this.#retryTimer = setTimeout(() => {
      this.#retryTimer = undefined;
      this.#connect();
    }, delay);
    this.#retryTimer.unref();
  }

  #send(session, frame) {
    // DEFENSE: A command or notice may complete after its socket session has been replaced.
    if (!this.#current(session)) return false;
    try {
      const encoded = encodeRemoteFrame(frame);
      // DEFENSE: A disconnected or slow relay cannot accept another bounded frame without growing the socket buffer indefinitely.
      if (session.socket.readyState !== WebSocket.OPEN || session.socket.bufferedAmount + Buffer.byteLength(encoded) > MAX_BUFFERED_BYTES) {
        this.#disconnect(session, 'transport_backpressure');
        return false;
      }
      session.socket.send(encoded);
      return true;
    // DEFENSE: Encoding an oversized observation or sending to a socket closed by the peer rejects this transport session.
    } catch {
      this.#disconnect(session, 'outbound_frame_rejected');
      return false;
    }
  }

  #receive(session, data) {
    // DEFENSE: Socket events queued before reconnect can arrive for a retired session.
    if (!this.#current(session)) return;
    let frame;
    try { frame = parseRemoteFrame(data, validateRelayFrame); }
    // DEFENSE: Relay frames can contain malformed JSON, unsupported types, or invalid fields.
    catch { this.#disconnect(session, 'relay_frame_rejected'); return; }
    const action = this.#step('frame', { generation: session.generation, frame });
    if (action === 'ignore') return;
    if (action === 'disconnect') { this.#disconnect(session, 'relay_session_rejected'); return; }
    if (action === 'ready') {
      session.negotiated = true;
      session.ready = true;
      this.syncGrants().then(() => {
        // DEFENSE: Grant synchronization can finish after disconnection or replacement.
        if (!this.#current(session)) return;
        if (this.#step('pairing_current', { generation: session.generation, now: Date.now() }) === 'pairing') {
          if (!this.#send(session, this.#control.pairing)) return;
        }
        clearTimeout(session.timeout);
        this.#attempt = 0;
        this.#setStatus('online');
        session.heartbeat = setInterval(() => {
          // DEFENSE: A dropped connection may never deliver close; missing pongs retire it without replaying commands.
          if (Date.now() - session.lastPong > this.#settings.heartbeatTimeoutMs) this.#disconnect(session, 'heartbeat_timeout');
          else this.#send(session, { type: 'ping' });
        }, this.#settings.heartbeatMs);
        session.heartbeat.unref();
      // DEFENSE: The kernel or transport can fail while obtaining/sending current grants; do not mark that session online.
      }).catch(() => this.#disconnect(session, 'grant_sync_failed'));
      return;
    }
    if (frame.type === 'pong') { session.lastPong = Date.now(); return; }
    if (frame.type === 'pair_request') {
      // The relay spent the one-time code. Reconnection must never republish it.
      this.#onPairRequest(frame);
      return;
    }
    if (frame.type === 'controller_close') { this.#forgetConnection(session, frame.connection_id); return; }
    if (frame.type === 'controller_open') {
      session.connections.set(frame.connection_id, { id: frame.connection_id, controllerId: frame.controller_id, grantEpoch: frame.grant_epoch,
        active: true, subscribed: false, tail: Promise.resolve() });
      this.#setStatus('online');
      return;
    }
    if (frame.type === 'request') {
      const connection = session.connections.get(frame.connection_id);
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
    // DEFENSE: A controller may close while a notice is being delivered or its prior request is queued.
    if (!connection.active || !this.#current(session)) return;
    const action = this.#step('enqueue', { generation: session.generation, connection_id: connection.id, bytes });
    if (action === 'disconnect') { this.#disconnect(session, 'request_queue_full'); return; }
    if (action !== 'enqueue') return;
    connection.tail = connection.tail.then(async () => {
      if (connection.active && this.#current(session)) await operation();
    // DEFENSE: A queued kernel command can fail after the worker or journal stops; retire its transport instead of replaying it.
    }).catch(() => {
      this.#disconnect(session, 'request_processing_failed');
    }).finally(() => {
      this.#step('dequeue', { generation: session.generation, connection_id: connection.id, bytes });
    });
  }

  async #authorize(session, connection, authorized) {
    // DEFENSE: Concurrent commits may supersede a grant check before capture/send; retry only the read-only check, bounded to four observations.
    for (let attempt = 0; attempt < 4; ++attempt) {
      const check = await this.#service.remoteCheck(connection.controllerId, connection.grantEpoch);
      // DEFENSE: Disconnect/revocation may occur while the native grant check is awaited.
      if (!this.#current(session) || !connection.active) return false;
      // DEFENSE: The owner can revoke the native grant while a device remains connected.
      if (!check.reply.ok) { connection.subscribed = false; return false; }
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
    return { incarnation: this.#incarnation, namespace: snapshot.namespace, sequence: snapshot.sequence, program: snapshot.program,
      streams: this.#service.browserStreams(), notice_sequence: this.#noticeSequence };
  }

  async #request(session, id, connection, request) {
    try {
      if (request.method === 'command') {
        const result = await this.#service.remoteCommand(connection.controllerId, connection.grantEpoch, request.params);
        if (connection.active) this.#send(session, { type: 'response', connection_id: id, response: { id: request.id, result: result } });
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
    // DEFENSE: A remote command may fail on a stopped worker or journal; return a bounded error without disclosing local exception text.
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
      event = { incarnation: this.#incarnation, notice_sequence: sequence, notice: notice };
      bytes = Buffer.byteLength(encodeRemoteFrame(event));
    // DEFENSE: A committed notice can exceed the remote frame budget; close instead of buffering an undeliverable observation.
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

import { initialTransport, observeTransport, transportRunning, transportCurrent, initialConnectorSession, observeConnectorSession, interpretConnectorFrame, interpretConnectorCapture, interpretConnectorDelivery, enqueueRemoteOperation, authorizeRemoteCapture } from '../remote/transport-runner.ts';
import { randomUUID } from 'node:crypto';
import {
  REMOTE_PROTOCOL_VERSION, MAX_REMOTE_FRAME_BYTES,
  assertRelayUrl, parseRemoteFrame, encodeRemoteFrame,
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
  #control = initialConnectorSession();
  #transport = initialTransport();
  get #running() { return transportRunning(this.#transport); }
  get #generation() { return this.#transport.generation; }
  #observe(kind, observation = {}) {
    observeTransport(this.#transport, { kind, ...observation }, {
      retry_base: this.#settings.retryBaseMs, retry_max: this.#settings.retryMaxMs,
      heartbeat: this.#settings.heartbeatMs, heartbeat_timeout: this.#settings.heartbeatTimeoutMs,
    }, {
      install: state => { this.#transport = state; },
      connect: generation => { void this.#connect(generation); },
      open: generation => this.#openSocket(generation),
      retry: (generation, deadline) => this.#scheduleRetry(generation, deadline),
      heartbeat: (generation, deadline) => this.#scheduleHeartbeat(generation, deadline),
      online: () => this.#setStatus('online'),
      ping: () => this.#send(this.#session, { type: 'ping' }),
      retire: () => {
        clearTimeout(this.#retryTimer);
        this.#retryTimer = undefined;
        this.#probe?.abort();
        this.#probe = undefined;
        this.#retireSession();
      },
      stopped: () => this.#setStatus('stopped'),
      authenticationFailed: () => {
        this.#service.off('notice', this.#noticeListener);
        this.#setStatus('auth_failed', { last_error: 'relay_authentication_failed' });
      },
    });
  }
  #sample() { return Math.floor(Math.random() * 1000); }
  #step(kind, observation = {}) {
    const result = observeConnectorSession(this.#control, { kind, ...observation });
    this.#control = result.state;
    return result.action;
  }
  #session;
  #retryTimer;
  #probe;
  #lastError;
  #grantTail = Promise.resolve();
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
    this.#service.on('notice', this.#noticeListener);
    this.#observe('enable');
    return this.status();
  }

  close() {
    this.#service.off('notice', this.#noticeListener);
    this.#observe('stop');
  }

  pair(code, expiresAt) {
    const frame = { type: 'pairing', code, expires_at: expiresAt };
    const action = this.#step('pair', { generation: this.#generation, now: Date.now(), frame });
    if (action.kind === 'pairing') this.#send(this.#session, frame);
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

  async #connect(generation) {
    this.#step('install', { generation });
    this.#setStatus('connecting');
    const probe = new AbortController();
    this.#probe = probe;
    const timeout = setTimeout(() => probe.abort(), this.#settings.connectTimeoutMs);
    timeout.unref();
    try {
      // Bun's failed WebSocket handshake hides HTTP status. Probe the same
      // authenticated route and let the controller classify the observation.
      const response = await this.#settings.fetchRequest(this.#hostUrl, {
        headers: { authorization: `Bearer ${this.#hostToken}` }, redirect: 'error', signal: probe.signal,
      });
      await response.body?.cancel();
      this.#observe('probe', { generation, status: response.status, now: Date.now(), sample: this.#sample() });
    // DEFENSE: A network or aborted probe supplies a failed physical attempt; the controller rejects stale observations.
    } catch {
      this.#lastError = 'connection_unavailable';
      this.#observe('lost', { generation, now: Date.now(), sample: this.#sample() });
    } finally {
      clearTimeout(timeout);
      if (this.#probe === probe) this.#probe = undefined;
    }
  }

  #openSocket(generation) {
    const url = new URL(this.#hostUrl);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    const socket = this.#settings.createWebSocket(url.href, { headers: { authorization: `Bearer ${this.#hostToken}` } });
    const session = { socket, generation, connections: new Map(), ready: false };
    this.#session = session;
    session.timeout = setTimeout(() => this.#disconnect(session, 'negotiation_timeout'), this.#settings.connectTimeoutMs);
    session.timeout.unref();
    socket.addEventListener('open', () => {
      if (this.#current(session)) this.#send(session, { type: 'hello', version: REMOTE_PROTOCOL_VERSION });
    });
    socket.addEventListener('message', event => this.#receive(session, event.data));
    socket.addEventListener('error', () => { /* Close reports the physical failure once. */ });
    socket.addEventListener('close', event => {
      // DEFENSE: A retired socket can deliver its close event after its replacement starts.
      if (!this.#current(session)) return;
      if (event.code === 1008) this.#observe('rejected', { generation });
      else this.#disconnect(session, 'connection_closed');
    });
  }

  #current(session) {
    return Boolean(session) && this.#session === session && transportCurrent(this.#transport, session.generation);
  }

  #retireSession() {
    const session = this.#session;
    this.#session = undefined;
    if (!session) return;
    this.#step('retire', { generation: session.generation });
    // A consumed pair_request might have been lost with this connection. A new
    // connection needs a fresh local code, never a replay of the previous code.
    clearTimeout(session.timeout);
    clearTimeout(session.heartbeat);
    for (const connection of session.connections.values()) connection.active = false;
    session.connections.clear();
    session.socket.close(1000, 'Remote connector disconnected');
  }

  #disconnect(session, reason) {
    // DEFENSE: Timeout and socket callbacks can arrive after another observation retired this generation.
    if (!this.#current(session)) return;
    this.#lastError = reason;
    this.#observe('lost', { generation: session.generation, now: Date.now(), sample: this.#sample() });
  }

  #scheduleRetry(generation, deadline) {
    this.#setStatus('retrying', { last_error: this.#lastError ?? 'connection_unavailable', next_retry_at: deadline });
    this.#retryTimer = setTimeout(() => {
      this.#retryTimer = undefined;
      this.#observe('retry', { generation, now: Date.now() });
    }, Math.max(0, deadline - Date.now()));
    this.#retryTimer.unref();
  }

  #scheduleHeartbeat(generation, deadline) {
    const session = this.#session;
    // DEFENSE: Sending a ping can synchronously fail and retire its socket before the following timer primitive runs.
    if (!this.#current(session)) return;
    session.heartbeat = setTimeout(() => {
      this.#observe('heartbeat', { generation, now: Date.now(), sample: this.#sample() });
    }, Math.max(0, deadline - Date.now()));
    session.heartbeat.unref();
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
    let action;
    try { action = parseRemoteFrame(data, frame => this.#step('frame', { generation: session.generation, frame })); }
    // DEFENSE: Relay frames can contain malformed JSON, unsupported types, or invalid fields.
    catch { this.#disconnect(session, 'relay_frame_rejected'); return; }
    interpretConnectorFrame(action, {
      disconnect: () => this.#disconnect(session, 'relay_session_rejected'),
      ready: () => this.#ready(session),
      pong: () => this.#observe('pong', { generation: session.generation, now: Date.now() }),
      pairRequest: request => this.#onPairRequest(request),
      closed: connectionId => this.#forgetConnection(session, connectionId),
      opened: connection => {
        session.connections.set(connection.connection_id, { id: connection.connection_id, controllerId: connection.controller_id, grantEpoch: connection.grant_epoch,
          active: true, tail: Promise.resolve() });
        this.#setStatus('online');
      },
      request: accepted => {
        const connection = session.connections.get(accepted.connection_id);
        this.#enqueue(session, connection, Buffer.byteLength(data), () => this.#request(session, accepted.connection_id, connection, accepted.request));
      },
    });
  }

  #ready(session) {
    session.ready = true;
    this.syncGrants().then(() => {
      // DEFENSE: Grant synchronization can finish after disconnection or replacement.
      if (!this.#current(session)) return;
      if (this.#step('pairing_current', { generation: session.generation, now: Date.now() }).kind === 'pairing') {
        if (!this.#send(session, this.#control.pairing)) return;
      }
      clearTimeout(session.timeout);
      this.#observe('negotiated', { generation: session.generation, now: Date.now() });
    // DEFENSE: The kernel or transport can fail while sending current grants; do not mark that socket online.
    }).catch(() => this.#disconnect(session, 'grant_sync_failed'));
  }

  #forgetConnection(session, id) {
    const connection = session.connections.get(id);
    if (connection) connection.active = false;
    session.connections.delete(id);
    if (this.#current(session) && this.#status.state === 'online') this.#setStatus('online');
  }

  #enqueue(session, connection, bytes, operation, noticeSequence = null) {
    enqueueRemoteOperation(connection, bytes, operation, {
      current: () => this.#current(session),
      observe: (kind, size) => this.#step(kind, { generation: session.generation, connection_id: connection.id,
        bytes: size, notice_sequence: noticeSequence }),
      disconnect: reason => this.#disconnect(session, reason),
    });
  }

  #authorize(session, connection, authorized) {
    return authorizeRemoteCapture({
      check: () => this.#service.remoteCheck(connection.controllerId, connection.grantEpoch),
      active: () => this.#current(session) && connection.active,
      currentSequence: () => this.#service.browserSnapshot().sequence,
      capture: authorized,
      deny: () => { this.#step('capture', { generation: session.generation, connection_id: connection.id, method: 'unsubscribe' }); },
      disconnect: () => this.#disconnect(session, 'authorization_revision_changed'),
    });
  }

  #snapshot() {
    const snapshot = this.#service.browserSnapshot();
    return { incarnation: this.#incarnation, namespace: snapshot.namespace, sequence: snapshot.sequence, program: snapshot.program,
      streams: this.#service.browserStreams(), notice_sequence: this.#control.notice_sequence };
  }

  async #request(session, id, connection, request) {
    try {
      if (request.method === 'command') {
        const result = await this.#service.remoteCommand(connection.controllerId, connection.grantEpoch, request.params);
        if (connection.active) this.#send(session, { type: 'response', connection_id: id, response: { id: request.id, result: result } });
        return;
      }
      const allowed = await this.#authorize(session, connection, () => {
        const action = this.#step('capture', { generation: session.generation, connection_id: id, method: request.method });
        const reply = result => this.#send(session, { type: 'response', connection_id: id, response: { id: request.id, result } });
        interpretConnectorCapture(action, { snapshot: () => reply(this.#snapshot()), unsubscribed: () => reply({ subscribed: false }) });
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
    this.#step('notice');
    const sequence = this.#control.notice_sequence;
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
      this.#enqueue(session, connection, bytes, async () => {
        await this.#authorize(session, connection, () => {
          interpretConnectorDelivery(this.#step('deliver', { generation: session.generation, connection_id: id, notice_sequence: sequence }),
            () => this.#send(session, { type: 'event', connection_id: id, event }));
        });
      }, sequence);
    }
  }
}

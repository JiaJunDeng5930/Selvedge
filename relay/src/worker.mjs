import { remoteControl } from '../../remote/control-model.mjs';
import {
  REMOTE_PROTOCOL_VERSION,
  REMOTE_TICKET_TTL_MS,
  parseRemoteFrame, encodeRemoteFrame, protocolError, RemoteProtocolError,
} from '../../remote/protocol.mjs';

const utf8 = new TextEncoder();
const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const result = (body, status = 200) => Response.json(body, { status, headers: jsonHeaders });
const failure = (code, status) => result({ error: { code } }, status);
const admission = (operation, source) => remoteControl(`relay_${operation}`, source);
const bearer = (request, route) => {
  const admitted = admission('credential', { route, header: request.headers.get('authorization') || '' });
  if (!admitted.accepted) throw Object.assign(new Error(admitted.code), { status: admitted.status, code: admitted.code });
  return admitted.credential;
};
const admitBody = (route, body) => {
  const admitted = admission('body', { route, body });
  // DEFENSE: Public request bodies may omit required fields or violate their declared token and label formats.
  if (admitted.action === 'reject') throw Object.assign(new Error(admitted.code), { status: admitted.status, code: admitted.code });
  return admitted;
};
const digest = async value => [...new Uint8Array(await crypto.subtle.digest('SHA-256', utf8.encode(value)))
  ].map(byte => byte.toString(16).padStart(2, '0')).join('');
const sameDigest = (left, right) => {
  let difference = 0;
  for (let index = 0; index < left.length; index++) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
};
const token = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
};

async function readJson(request) {
  const content = { content_type: request.headers.get('content-type') || '',
    content_length: request.headers.get('content-length') || '', received_bytes: 0 };
  const requireContent = () => {
    const admitted = admission('content', content);
    if (admitted !== 0) throw Object.assign(new Error(admitted.code), { status: admitted.status, code: admitted.code });
  };
  requireContent();
  const reader = request.body?.getReader();
  let size = 0;
  const chunks = [];
  if (reader) {
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.byteLength;
        content.received_bytes = size;
        // DEFENSE: Chunked HTTP bodies have no trustworthy declared byte count.
        try { requireContent(); }
        catch (error) { await reader.cancel(); throw error; }
        chunks.push(value);
      }
    } finally { reader.releaseLock(); }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  // DEFENSE: Public request bytes may be malformed UTF-8 or JSON and must return a 400 response.
  catch { throw Object.assign(new Error('Remote relay invalid JSON'), { status: 400 }); }
}

function send(socket, frame) {
  socket.send(encodeRemoteFrame(frame));
}

function upgrade(request) { return request.headers.get('upgrade')?.toLowerCase() === 'websocket'; }

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      const route = admission('route', { protocol: url.protocol, hostname: url.hostname,
        local_test: env.REMOTE_LOCAL_TEST === 'true', path: url.pathname, method: request.method,
        query: [...url.searchParams] });
      if (route.action === 'reject') return failure(route.code, route.status);
      if (route.action === 'health') return result({ service: 'selvedge-remote-relay', version: REMOTE_PROTOCOL_VERSION });
      if (route.action === 'register') {
        // DEFENSE: Deployments without an enrollment secret must not allow host registration.
        if (!env.RELAY_ENROLLMENT_TOKEN) return failure('enrollment_disabled', 503);
        const supplied = bearer(request, 'register');
        // DEFENSE: Anyone can reach registration; only the configured enrollment credential admits a host.
        if (!sameDigest(await digest(supplied), await digest(env.RELAY_ENROLLMENT_TOKEN))) {
          return failure('unauthorized', 401);
        }
        const body = admitBody('register', await readJson(request));
        const stub = env.REMOTE_HOSTS.get(env.REMOTE_HOSTS.idFromName(body.host_id));
        return stub.fetch(new Request('https://relay.internal/register', {
          method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
        }));
      }
      const stub = env.REMOTE_HOSTS.get(env.REMOTE_HOSTS.idFromName(route.host_id));
      return stub.fetch(request);
    } catch (error) {
      // DEFENSE: readJson rejects unsupported content types, oversized bodies, and malformed UTF-8/JSON with an explicit HTTP status.
      if (error.status) return failure(error.code || 'invalid_request', error.status);
      throw error;
    }
  },
};

export class RemoteHostRelay {
  constructor(ctx) {
    this.ctx = ctx;
    this.hostDigest = null;
    this.grants = new Map();
    this.generation = 0;
    ctx.blockConcurrencyWhile(async () => {
      this.hostDigest = (await ctx.storage.get('host_digest')) ?? null;
      this.grants = new Map((await ctx.storage.get('grants')) ?? []);
      this.generation = (await ctx.storage.get('generation')) ?? 0;
    });
  }

  host(ready = true) {
    return this.ctx.getWebSockets('host').find(socket => {
      const state = socket.deserializeAttachment();
      return remoteControl('host_current', { connection: state, generation: this.generation, ready });
    });
  }

  controllers() { return this.ctx.getWebSockets('controller'); }

  controller(connectionId) {
    return this.controllers().find(socket => socket.deserializeAttachment().connection_id === connectionId);
  }

  controllerCurrent(state) {
    return state.role === 'controller' && remoteControl('delivery', { connection: state,
      generation: this.generation, grants: this.grantSnapshot(),
      host_ready: Boolean(this.host()) });
  }

  grantSnapshot() { return [...this.grants].map(([controller_id, grant_epoch]) => ({ controller_id, grant_epoch })); }

  step(state, event) { return remoteControl('relay', { state, event }); }

  async fetch(request) {
    try {
      const url = new URL(request.url);
      if (url.pathname === '/register') {
        const body = await readJson(request);
        const nextDigest = await digest(body.host_token);
        // DEFENSE: Another enrollment must not replace a registered host's credential.
        if (this.hostDigest && !sameDigest(this.hostDigest, nextDigest)) return failure('host_already_registered', 409);
        if (!this.hostDigest) {
          await this.ctx.storage.put('host_digest', nextDigest);
          this.hostDigest = nextDigest;
        }
        return result({ host_id: body.host_id });
      }
      // DEFENSE: A public request can target a host UUID that has never been enrolled.
      if (!this.hostDigest) return failure('unknown_host', 404);
      const action = url.pathname.slice(url.pathname.lastIndexOf('/') + 1);
      if (action === 'host') return await this.connectHost(request);
      if (action === 'pair') return await this.pair(request);
      if (action === 'tickets') return await this.ticket(request);
      return await this.connectController(request, url);
    } catch (error) {
      // DEFENSE: readJson rejects unsupported content types, oversized bodies, and malformed UTF-8/JSON with an explicit HTTP status.
      if (error.status) return failure(error.code || 'invalid_request', error.status);
      throw error;
    }
  }

  async connectHost(request) {
    const secret = bearer(request, 'host');
    // DEFENSE: A caller can know the host UUID without possessing its installation credential.
    if (!sameDigest(await digest(secret), this.hostDigest)) {
      return failure('unauthorized', 401);
    }
    // DEFENSE: The connector probes authentication over HTTP before upgrading; report the required transport explicitly.
    if (!upgrade(request)) return failure('websocket_required', 426);
    // DEFENSE: Persist the generation before accepting its socket so a replaced
    // host cannot forward delayed responses after a Durable Object restart.
    const nextHost = this.step({ generation: this.generation }, { kind: 'host_new' }).state;
    this.generation = nextHost.generation;
    await this.ctx.storage.put('generation', this.generation);
    for (const socket of this.ctx.getWebSockets()) socket.close(1012, 'Remote host connection replaced');
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.serializeAttachment(nextHost);
    this.ctx.acceptWebSocket(server, ['host']);
    send(server, { type: 'ready', version: REMOTE_PROTOCOL_VERSION });
    return new Response(null, { status: 101, webSocket: client });
  }

  async pair(request) {
    const host = this.host();
    // DEFENSE: A controller can pair, request a ticket, or connect while its host is offline; never queue commands.
    if (!host) return failure('host_offline', 503);
    const body = admitBody('pair', await readJson(request));
    const supplied = bearer(request, 'pair');
    const suppliedDigest = await digest(supplied);
    const state = host.deserializeAttachment();
    const consumed = this.step(state, { kind: 'pair_consume', now: Date.now(), digest: suppliedDigest });
    if (!consumed.allowed) return failure('invalid_pairing_code', 401);
    host.serializeAttachment(consumed.state);
    const controllerId = await digest(body.controller_token);
    // DEFENSE: Hashing yields; a replacement host must not receive an already-consumed code from the prior generation.
    if (this.host() !== host) return failure('host_offline', 503);
    const delivery = this.step(host.deserializeAttachment(), { kind: 'pair_delivery', now: Date.now(),
      revision: state.pairing_revision, expires_at: state.pairing.expires_at });
    if (!delivery.allowed) return failure('invalid_pairing_code', 401);
    const requestId = crypto.randomUUID();
    send(host, { type: 'pair_request', request_id: requestId, controller_id: controllerId, label: body.label });
    return result({ request_id: requestId, controller_id: controllerId, status: 'pending' });
  }

  async ticket(request) {
    admitBody('tickets', await readJson(request));
    const secret = bearer(request, 'tickets');
    const controllerId = await digest(secret);
    const grantEpoch = this.grants.get(controllerId);
    // DEFENSE: A valid-shaped controller token may have no current owner-approved grant.
    if (!grantEpoch) return failure('unauthorized', 401);
    const host = this.host();
    // DEFENSE: A controller can pair, request a ticket, or connect while its host is offline; never queue commands.
    if (!host) return failure('host_offline', 503);
    const secretTicket = token();
    const ticketDigest = await digest(secretTicket);
    // DEFENSE: Hashing yields; a ticket must belong to the still-current host connection.
    if (this.host() !== host) return failure('host_offline', 503);
    const expiresAt = Date.now() + REMOTE_TICKET_TTL_MS;
    const issued = this.step(host.deserializeAttachment(), { kind: 'ticket_issue', now: Date.now(), grants: this.grantSnapshot(),
      ticket: { digest: ticketDigest, controller_id: controllerId, grant_epoch: grantEpoch, expires_at: expiresAt } });
    host.serializeAttachment(issued.state);
    if (!issued.allowed) return failure(issued.reason, issued.reason === 'host_offline' ? 503 : 429);
    return result({ ticket: secretTicket, expires_at: expiresAt });
  }

  async connectController(request, url) {
    // DEFENSE: Controller connections require a GET WebSocket upgrade.
    if (!upgrade(request)) return failure('websocket_required', 426);
    const supplied = admission('credential', { route: 'control', header: `Bearer ${url.searchParams.get('ticket') || ''}` });
    // DEFENSE: A control URL can contain an invalid or missing ticket.
    if (!supplied.accepted) return failure(supplied.code, supplied.status);
    const secret = supplied.credential;
    const secretDigest = await digest(secret);
    const host = this.host();
    // DEFENSE: A controller can pair, request a ticket, or connect while its host is offline; never queue commands.
    if (!host) return failure('host_offline', 503);
    const consumed = this.step(host.deserializeAttachment(), { kind: 'ticket_consume', now: Date.now(), grants: this.grantSnapshot(),
      digest: secretDigest, controller_count: this.controllers().length });
    // Consumption is published atomically before a socket or authorization is issued.
    host.serializeAttachment(consumed.state);
    if (!consumed.allowed) return failure(consumed.reason, consumed.reason === 'connection_limit' ? 429 : 401);
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const connectionId = crypto.randomUUID();
    const installed = remoteControl('relay_controller', { generation: this.generation,
      connection_id: connectionId, ticket: consumed.ticket });
    server.serializeAttachment(installed.state);
    this.ctx.acceptWebSocket(server, ['controller']);
    send(host, installed.host_frame);
    send(server, installed.controller_frame);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket, message) {
    try {
      const state = socket.deserializeAttachment();
      if (state.role === 'host') {
        // DEFENSE: A replaced host may deliver queued frames after the new socket has been accepted.
        if (this.host(false) !== socket) {
          socket.close(1012, 'Remote host connection replaced');
          return;
        }
        const frame = parseRemoteFrame(message, source => {
          const admitted = remoteControl('relay_frame_allowed', { state, frame: source });
          // DEFENSE: A host may send a malformed frame or send it before protocol negotiation.
          if (admitted === null) throw protocolError('Host frame rejected by relay session');
          return admitted;
        });
        if (frame.type === 'hello') {
          socket.serializeAttachment(this.step(state, { kind: 'hello' }).state);
          return;
        }
        await this.hostFrame(socket, state, frame);
      } else if (this.controllerCurrent(state)) {
        const frame = parseRemoteFrame(message, request => {
          const admitted = remoteControl('relay_request', { connection: state, request });
          // DEFENSE: A controller may send an unknown method or malformed RPC parameters.
          if (admitted === null) throw protocolError('Controller request rejected by relay session');
          return admitted;
        });
        send(this.host(), frame);
      // DEFENSE: A queued controller frame may outlive its grant, host generation, or socket retirement.
      } else socket.close(1008, 'Remote grant unavailable');
    // DEFENSE: Malformed peer frames and failed storage/socket effects retire this connection without retrying the command.
    } catch (error) {
      this.disconnect(socket);
      const protocolRejected = error instanceof RemoteProtocolError;
      socket.close(protocolRejected ? (error.code === 'frame_too_large' ? 1009 : 1008) : 1011,
        protocolRejected ? 'Remote protocol rejected' : 'Remote relay operation failed');
    }
  }

  async hostFrame(socket, state, frame) {
    switch (frame.type) {
      case 'grants': {
        const next = new Map(frame.grants.map(grant => [grant.controller_id, grant.grant_epoch]));
        await this.ctx.storage.put('grants', [...next]);
        // DEFENSE: Storage writes and hashing yield; a replaced host must not publish stale grants or pairing codes.
        if (this.host(false) !== socket) return;
        this.grants = next;
        const current = socket.deserializeAttachment();
        socket.serializeAttachment(this.step(current, { kind: 'grants', grants: this.grantSnapshot() }).state);
        for (const controller of this.controllers()) {
          const attachment = controller.deserializeAttachment();
          // DEFENSE: A grant update can revoke an already connected controller; close its socket immediately.
          if (!this.controllerCurrent(attachment)) controller.close(1008, 'Remote grant revoked');
        }
        break;
      }
      case 'pairing': {
        const pending = this.step(socket.deserializeAttachment(), { kind: 'pairing_begin' }).state;
        socket.serializeAttachment(pending);
        const revision = pending.pairing_revision;
        const codeDigest = await digest(frame.code);
        // DEFENSE: Hashing may complete after this socket was replaced.
        if (this.host(false) !== socket) return;
        const installed = this.step(socket.deserializeAttachment(), { kind: 'pairing_install', now: Date.now(), revision,
          pairing: { digest: codeDigest, expires_at: frame.expires_at } });
        socket.serializeAttachment(installed.state);
        if (!installed.allowed && revision === installed.state.pairing_revision) throw protocolError('Remote pairing expiry rejected');
        break;
      }
      case 'response':
      case 'event': {
        const controller = this.controller(frame.connection_id);
        // DEFENSE: A host reply can arrive after controller disconnect, revocation, or host replacement.
        if (!controller || !this.controllerCurrent(controller.deserializeAttachment())) return;
        send(controller, frame.type === 'response'
          ? frame.response : { type: 'event', event: frame.event });
        break;
      }
      case 'ping': send(socket, { type: 'pong' }); break;
    }
  }

  webSocketClose(socket, code, reason) {
    this.disconnect(socket);
    // DEFENSE: Close events can report reserved 1005/1006 codes, which cannot be sent in a close frame.
    socket.close(code === 1005 || code === 1006 ? 1000 : code, reason);
  }

  webSocketError(socket) {
    this.disconnect(socket);
    socket.close(1011, 'Remote connection failed');
  }

  disconnect(socket) {
    const transition = admission('disconnect', { connection: socket.deserializeAttachment(),
      generation: this.generation, host_ready: Boolean(this.host()) });
    socket.serializeAttachment(transition.state);
    if (transition.action === 'close_controllers') {
      for (const controller of this.controllers()) controller.close(1012, 'Remote host disconnected');
    } else if (transition.action === 'notify_host') {
      const host = this.host();
      if (host) {
        try { send(host, { type: 'controller_close', connection_id: transition.connection_id }); }
        // DEFENSE: The host can close before its controller-close notification is sent; retire that failed transport.
        catch { host.close(1011, 'Remote connection failed'); }
      }
    }
  }
}

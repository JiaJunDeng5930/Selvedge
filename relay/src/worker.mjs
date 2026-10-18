import {
  REMOTE_PROTOCOL_VERSION, MAX_REMOTE_HTTP_BYTES, MAX_REMOTE_CONTROLLERS,
  MAX_REMOTE_TICKETS, REMOTE_TICKET_TTL_MS, REMOTE_PAIRING_TTL_MS,
  isHostId, isRemoteToken, parseRemoteFrame, encodeRemoteFrame,
  validateHostFrame, validateControllerRequest,
} from '../../remote/protocol.mjs';

const utf8 = new TextEncoder();
const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const result = (body, status = 200) => Response.json(body, { status, headers: jsonHeaders });
const failure = (code, status) => result({ error: { code } }, status);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, fields) => object(value) && Object.keys(value).length === fields.length
  && fields.every(field => Object.hasOwn(value, field));
const labelValid = value => typeof value === 'string' && value.trim().length > 0
  && value.length <= 80 && !/[\u0000-\u001f\u007f]/u.test(value);
const bearer = request => {
  const value = request.headers.get('authorization');
  return value?.length <= 200 && /^Bearer [^\s]+$/.test(value) ? value.slice(7) : null;
};
const digest = async value => [...new Uint8Array(await crypto.subtle.digest('SHA-256', utf8.encode(value)))
  ].map(byte => byte.toString(16).padStart(2, '0')).join('');
const sameDigest = (left, right) => {
  if (typeof left !== 'string' || typeof right !== 'string' || left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
};
const token = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
};

async function readJson(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type') || '')) {
    throw Object.assign(new Error('Remote relay requires JSON'), { status: 415 });
  }
  if (Number(request.headers.get('content-length')) > MAX_REMOTE_HTTP_BYTES) {
    throw Object.assign(new Error('Remote relay body too large'), { status: 413 });
  }
  const reader = request.body?.getReader();
  let size = 0;
  const chunks = [];
  if (reader) {
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_REMOTE_HTTP_BYTES) {
          await reader.cancel();
          throw Object.assign(new Error('Remote relay body too large'), { status: 413 });
        }
        chunks.push(value);
      }
    } finally { reader.releaseLock(); }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  catch { throw Object.assign(new Error('Remote relay invalid JSON'), { status: 400 }); }
}

function safeClose(socket, code, message) {
  try { socket.close(code, message); } catch { /* NOTE: An already closed peer needs no cleanup frame. */ }
}

function send(socket, frame) {
  socket.send(encodeRemoteFrame(frame));
}

function attach(socket, state) {
  if (utf8.encode(JSON.stringify(state)).byteLength > 2048) {
    throw new Error('Remote hibernation attachment exceeds 2 KiB');
  }
  socket.serializeAttachment(state);
}

function upgrade(request) { return request.headers.get('upgrade')?.toLowerCase() === 'websocket'; }

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      const localTest = env.REMOTE_LOCAL_TEST === 'true' && url.protocol === 'http:'
        && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
      if (url.protocol !== 'https:' && !localTest) return failure('https_required', 400);
      if (url.pathname === '/health') {
        return request.method === 'GET' && !url.search
          ? result({ service: 'selvedge-remote-relay', version: REMOTE_PROTOCOL_VERSION })
          : failure('method_not_allowed', 405);
      }
      if (url.pathname === '/v1/hosts/register') {
        if (request.method !== 'POST' || url.search) return failure('method_not_allowed', 405);
        const supplied = bearer(request);
        if (!env.RELAY_ENROLLMENT_TOKEN) return failure('enrollment_disabled', 503);
        if (!supplied || !sameDigest(await digest(supplied), await digest(env.RELAY_ENROLLMENT_TOKEN))) {
          return failure('unauthorized', 401);
        }
        const body = await readJson(request);
        if (!exact(body, ['host_id', 'host_token']) || !isHostId(body.host_id) || !isRemoteToken(body.host_token)) {
          return failure('invalid_registration', 400);
        }
        const stub = env.REMOTE_HOSTS.get(env.REMOTE_HOSTS.idFromName(body.host_id));
        return stub.fetch(new Request('https://relay.internal/register', {
          method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
        }));
      }
      const route = /^\/v1\/hosts\/([^/]+)\/(host|pair|tickets|control)$/.exec(url.pathname);
      if (!route || !isHostId(route[1])) return failure('not_found', 404);
      if (route[2] === 'control') {
        if (request.method !== 'GET' || [...url.searchParams.keys()].some(key => key !== 'ticket')
            || url.searchParams.getAll('ticket').length !== 1) return failure('invalid_control_route', 400);
      } else if (url.search) return failure('invalid_route_query', 400);
      const stub = env.REMOTE_HOSTS.get(env.REMOTE_HOSTS.idFromName(route[1]));
      return stub.fetch(request);
    } catch (error) {
      return failure(error.status ? 'invalid_request' : 'relay_unavailable', error.status || 503);
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
      this.hostDigest = (await ctx.storage.get('host_digest')) || null;
      this.grants = new Map((await ctx.storage.get('grants')) || []);
      this.generation = (await ctx.storage.get('generation')) || 0;
    });
  }

  host(ready = true) {
    return this.ctx.getWebSockets('host').find(socket => {
      const state = socket.deserializeAttachment();
      return state?.role === 'host' && state.generation === this.generation
        && (!ready || (state.negotiated && state.synced));
    });
  }

  controllers() { return this.ctx.getWebSockets('controller'); }

  controller(connectionId) {
    return this.controllers().find(socket => socket.deserializeAttachment()?.connection_id === connectionId);
  }

  controllerCurrent(state) {
    return state?.role === 'controller' && state.generation === this.generation
      && this.grants.get(state.controller_id) === state.grant_epoch && Boolean(this.host());
  }

  async fetch(request) {
    try {
      const url = new URL(request.url);
      if (url.pathname === '/register') {
        const body = await readJson(request);
        const nextDigest = await digest(body.host_token);
        if (this.hostDigest && !sameDigest(this.hostDigest, nextDigest)) return failure('host_already_registered', 409);
        if (!this.hostDigest) {
          await this.ctx.storage.put('host_digest', nextDigest);
          this.hostDigest = nextDigest;
        }
        return result({ host_id: body.host_id });
      }
      if (!this.hostDigest) return failure('unknown_host', 404);
      const action = url.pathname.slice(url.pathname.lastIndexOf('/') + 1);
      if (action === 'host') return await this.connectHost(request);
      if (action === 'pair') return await this.pair(request);
      if (action === 'tickets') return await this.ticket(request);
      if (action === 'control') return await this.connectController(request, url);
      return failure('not_found', 404);
    } catch (error) {
      return failure(error.status ? 'invalid_request' : 'relay_unavailable', error.status || 503);
    }
  }

  async connectHost(request) {
    if (request.method !== 'GET') return failure('method_not_allowed', 405);
    const secret = bearer(request);
    if (!secret || !isRemoteToken(secret) || !sameDigest(await digest(secret), this.hostDigest)) {
      return failure('unauthorized', 401);
    }
    if (!upgrade(request)) return failure('websocket_required', 426);
    // NOTE: Persist the generation before accepting its socket so a replaced
    // host cannot forward delayed responses after a Durable Object restart.
    this.generation++;
    await this.ctx.storage.put('generation', this.generation);
    for (const socket of this.ctx.getWebSockets()) safeClose(socket, 1012, 'Remote host connection replaced');
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    attach(server, { role: 'host', generation: this.generation, negotiated: false,
      synced: false, pairing: null, pairing_revision: 0, tickets: [] });
    this.ctx.acceptWebSocket(server, ['host']);
    send(server, { type: 'ready', version: REMOTE_PROTOCOL_VERSION });
    return new Response(null, { status: 101, webSocket: client });
  }

  async pair(request) {
    if (request.method !== 'POST') return failure('method_not_allowed', 405);
    const host = this.host();
    if (!host) return failure('host_offline', 503);
    const body = await readJson(request);
    if (!exact(body, ['controller_token', 'label']) || !isRemoteToken(body.controller_token) || !labelValid(body.label)) {
      return failure('invalid_pairing_request', 400);
    }
    const supplied = bearer(request);
    const suppliedDigest = supplied ? await digest(supplied) : '';
    const state = host.deserializeAttachment();
    if (!state?.pairing || state.pairing.expires_at <= Date.now()
        || !sameDigest(state.pairing.digest, suppliedDigest)) return failure('invalid_pairing_code', 401);
    state.pairing = null;
    attach(host, state);
    const controllerId = await digest(body.controller_token);
    // NOTE: Hashing can yield, so recheck this exact host generation before
    // forwarding an already spent one-time pairing request.
    if (this.host() !== host || state.generation !== this.generation) return failure('host_offline', 503);
    const requestId = crypto.randomUUID();
    send(host, { type: 'pair_request', request_id: requestId, controller_id: controllerId, label: body.label });
    return result({ request_id: requestId, controller_id: controllerId, status: 'pending' });
  }

  async ticket(request) {
    if (request.method !== 'POST') return failure('method_not_allowed', 405);
    const body = await readJson(request);
    if (!exact(body, [])) return failure('invalid_ticket_request', 400);
    const secret = bearer(request);
    if (!isRemoteToken(secret)) return failure('unauthorized', 401);
    const controllerId = await digest(secret);
    const grantEpoch = this.grants.get(controllerId);
    if (!grantEpoch) return failure('unauthorized', 401);
    const host = this.host();
    if (!host) return failure('host_offline', 503);
    const state = host.deserializeAttachment();
    const now = Date.now();
    state.tickets = state.tickets.filter(entry => entry[3] > now);
    if (state.tickets.length >= MAX_REMOTE_TICKETS) return failure('ticket_limit', 429);
    const secretTicket = token();
    const ticketDigest = await digest(secretTicket);
    if (this.host() !== host || this.grants.get(controllerId) !== grantEpoch) return failure('host_offline', 503);
    // NOTE: Read again after hashing to avoid dropping a concurrently issued
    // ticket or restoring one that another request has already consumed.
    const current = host.deserializeAttachment();
    current.tickets = current.tickets.filter(entry => entry[3] > Date.now());
    if (current.tickets.length >= MAX_REMOTE_TICKETS) return failure('ticket_limit', 429);
    const expiresAt = now + REMOTE_TICKET_TTL_MS;
    current.tickets.push([ticketDigest, controllerId, grantEpoch, expiresAt]);
    attach(host, current);
    return result({ ticket: secretTicket, expires_at: expiresAt });
  }

  async connectController(request, url) {
    if (request.method !== 'GET' || !upgrade(request)) return failure('websocket_required', 426);
    const secret = url.searchParams.get('ticket');
    if (!isRemoteToken(secret)) return failure('invalid_ticket', 401);
    const secretDigest = await digest(secret);
    const host = this.host();
    if (!host) return failure('host_offline', 503);
    const state = host.deserializeAttachment();
    const index = state.tickets.findIndex(entry => sameDigest(entry[0], secretDigest));
    if (index < 0) return failure('invalid_ticket', 401);
    const [, controllerId, grantEpoch, expiresAt] = state.tickets.splice(index, 1)[0];
    attach(host, state);
    if (expiresAt <= Date.now() || this.grants.get(controllerId) !== grantEpoch) return failure('invalid_ticket', 401);
    if (this.controllers().length >= MAX_REMOTE_CONTROLLERS) return failure('connection_limit', 429);
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const connectionId = crypto.randomUUID();
    attach(server, { role: 'controller', generation: this.generation,
      connection_id: connectionId, controller_id: controllerId, grant_epoch: grantEpoch });
    this.ctx.acceptWebSocket(server, ['controller']);
    send(host, { type: 'controller_open', connection_id: connectionId, controller_id: controllerId, grant_epoch: grantEpoch });
    send(server, { type: 'ready', version: REMOTE_PROTOCOL_VERSION, controller_id: controllerId, grant_epoch: grantEpoch });
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket, message) {
    try {
      const state = socket.deserializeAttachment();
      if (state?.role === 'host') {
        if (state.generation !== this.generation || this.host(false) !== socket) {
          safeClose(socket, 1012, 'Remote host connection replaced');
          return;
        }
        const frame = parseRemoteFrame(message, validateHostFrame);
        if (frame.type === 'hello') {
          state.negotiated = true;
          attach(socket, state);
          return;
        }
        if (!state.negotiated) throw new Error('Remote protocol negotiation required');
        await this.hostFrame(socket, state, frame);
      } else if (this.controllerCurrent(state)) {
        const request = parseRemoteFrame(message, validateControllerRequest);
        send(this.host(), { type: 'request', connection_id: state.connection_id,
          controller_id: state.controller_id, grant_epoch: state.grant_epoch, request });
      } else safeClose(socket, 1008, 'Remote grant unavailable');
    } catch (error) {
      this.disconnect(socket);
      attach(socket, { role: 'closed' });
      safeClose(socket, error.code === 'frame_too_large' ? 1009 : 1008, 'Remote protocol rejected');
    }
  }

  async hostFrame(socket, state, frame) {
    switch (frame.type) {
      case 'grants': {
        const next = new Map(frame.grants.map(grant => [grant.controller_id, grant.grant_epoch]));
        await this.ctx.storage.put('grants', [...next]);
        if (this.host(false) !== socket || state.generation !== this.generation) return;
        this.grants = next;
        const current = socket.deserializeAttachment();
        current.synced = true;
        current.tickets = current.tickets.filter(entry => next.get(entry[1]) === entry[2]);
        attach(socket, current);
        for (const controller of this.controllers()) {
          const attachment = controller.deserializeAttachment();
          if (!this.controllerCurrent(attachment)) safeClose(controller, 1008, 'Remote grant revoked');
        }
        break;
      }
      case 'pairing': {
        const now = Date.now();
        if (frame.expires_at <= now || frame.expires_at > now + REMOTE_PAIRING_TTL_MS) {
          throw new Error('Remote pairing expiry rejected');
        }
        const pending = socket.deserializeAttachment();
        pending.pairing_revision++;
        pending.pairing = null;
        attach(socket, pending);
        const revision = pending.pairing_revision;
        const codeDigest = await digest(frame.code);
        if (this.host(false) !== socket || state.generation !== this.generation) return;
        const current = socket.deserializeAttachment();
        if (current.pairing_revision !== revision) return;
        current.pairing = { digest: codeDigest, expires_at: frame.expires_at };
        attach(socket, current);
        break;
      }
      case 'response':
      case 'event': {
        const controller = this.controller(frame.connection_id);
        if (!controller || !this.controllerCurrent(controller.deserializeAttachment())) return;
        send(controller, frame.type === 'response'
          ? frame.response : { type: 'event', event: frame.event });
        break;
      }
      case 'ping': send(socket, { type: 'pong' }); break;
      default: throw new Error('Remote host message rejected');
    }
  }

  webSocketClose(socket, code, reason) {
    this.disconnect(socket);
    attach(socket, { role: 'closed' });
    safeClose(socket, code === 1005 || code === 1006 ? 1000 : code, reason);
  }

  webSocketError(socket) {
    this.disconnect(socket);
    attach(socket, { role: 'closed' });
    safeClose(socket, 1011, 'Remote connection failed');
  }

  disconnect(socket) {
    const state = socket.deserializeAttachment();
    if (state?.role === 'host' && state.generation === this.generation) {
      const current = { ...state, negotiated: false, synced: false, tickets: [], pairing: null };
      attach(socket, current);
      for (const controller of this.controllers()) safeClose(controller, 1012, 'Remote host disconnected');
    } else if (state?.role === 'controller' && state.generation === this.generation) {
      const host = this.host();
      if (host) {
        try { send(host, { type: 'controller_close', connection_id: state.connection_id }); }
        catch { safeClose(host, 1011, 'Remote connection failed'); }
      }
    }
  }
}

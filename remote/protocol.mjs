export const REMOTE_PROTOCOL_VERSION = 1;
// NOTE: The native complete decision is bounded to 4 MiB; encoded observations
// and their surrounding wire envelope need additional room.
export const MAX_REMOTE_FRAME_BYTES = 16 * 1024 * 1024;
export const MAX_REMOTE_HTTP_BYTES = 4096;
export const MAX_REMOTE_GRANTS = 64;
export const MAX_REMOTE_CONTROLLERS = 32;
// NOTE: Tickets share the host's 2 KiB WebSocket hibernation attachment.
export const MAX_REMOTE_TICKETS = 8;
export const REMOTE_TICKET_TTL_MS = 30_000;
export const REMOTE_PAIRING_TTL_MS = 5 * 60_000;

const encoder = new TextEncoder();
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const isHostId = value => typeof value === 'string'
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
export const isRemoteToken = value => typeof value === 'string' && /^[A-Za-z0-9_-]{43}$/.test(value);
export const isControllerId = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const boundedString = (value, maximum = 128) => typeof value === 'string' && value.length > 0
  && value.length <= maximum && !/[\u0000-\u001f\u007f]/u.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0;
const rpcId = value => boundedString(value) || Number.isSafeInteger(value);

export class RemoteProtocolError extends Error {
  constructor(message, code = 'invalid_frame') {
    super(`Remote protocol: ${message}`);
    this.name = 'RemoteProtocolError';
    this.code = code;
  }
}

export function protocolError(message, code) { return new RemoteProtocolError(message, code); }

function requireShape(value, required) {
  // DEFENSE: Remote JSON may omit required fields, include unknown fields, or supply a scalar instead of an envelope.
  if (!plain(value) || required.some(key => !Object.hasOwn(value, key))
      || Object.keys(value).some(key => !required.includes(key))) {
    throw protocolError('Unexpected object fields');
  }
}

function requireValue(condition, message) {
  // DEFENSE: Peer frames can contain unsupported versions, malformed ids, nonpositive epochs, duplicate grants, or oversized lists/labels; reject the caller's failed wire predicate.
  if (!condition) throw protocolError(message);
}

function identifier(value) { requireValue(boundedString(value), 'Invalid identifier'); }
function identity(value) { requireValue(isControllerId(value), 'Invalid controller identity'); }
function epoch(value) { requireValue(positive(value), 'Invalid grant epoch'); }

export function validateControllerRequest(value) {
  requireShape(value, ['id', 'method', 'params']);
  requireValue(rpcId(value.id), 'Invalid request id');
  if (value.method === 'command') {
    requireShape(value.params, ['request_id', 'command']);
    identifier(value.params.request_id);
    requireValue(plain(value.params.command) && boundedString(value.params.command.op, 80), 'Invalid public command');
  } else if (['snapshot', 'subscribe', 'unsubscribe'].includes(value.method)) {
    requireShape(value.params, []);
  // DEFENSE: A controller may request a method outside the four relay operations.
  } else throw protocolError('Unsupported remote method');
  return value;
}

export function validateRemoteResponse(value) {
  requireValue(plain(value), 'Invalid response');
  const failed = Object.hasOwn(value, 'error');
  requireShape(value, failed ? ['id', 'error'] : ['id', 'result']);
  requireValue(rpcId(value.id), 'Invalid response id');
  if (failed) {
    requireShape(value.error, ['code', 'message']);
    requireValue(boundedString(value.error.code, 80) && boundedString(value.error.message, 1024), 'Invalid response error');
  }
  return value;
}

export function validateHostFrame(value) {
  requireValue(plain(value), 'Invalid host frame');
  switch (value.type) {
    case 'hello':
      requireShape(value, ['type', 'version']);
      requireValue(value.version === REMOTE_PROTOCOL_VERSION, 'Unsupported protocol version');
      break;
    case 'grants': {
      requireShape(value, ['type', 'grants']);
      requireValue(Array.isArray(value.grants) && value.grants.length <= MAX_REMOTE_GRANTS, 'Invalid grant list');
      const seen = new Set();
      for (const grant of value.grants) {
        requireShape(grant, ['controller_id', 'grant_epoch']);
        identity(grant.controller_id);
        epoch(grant.grant_epoch);
        requireValue(!seen.has(grant.controller_id), 'Duplicate controller grant');
        seen.add(grant.controller_id);
      }
      break;
    }
    case 'pairing':
      requireShape(value, ['type', 'code', 'expires_at']);
      requireValue(boundedString(value.code, 128) && value.code.length >= 20 && positive(value.expires_at), 'Invalid pairing code');
      break;
    case 'response':
      requireShape(value, ['type', 'connection_id', 'response']);
      identifier(value.connection_id);
      validateRemoteResponse(value.response);
      break;
    case 'event':
      requireShape(value, ['type', 'connection_id', 'event']);
      identifier(value.connection_id);
      requireValue(plain(value.event), 'Invalid observation event');
      break;
    case 'ping':
      requireShape(value, ['type']);
      break;
    // DEFENSE: An authenticated host can send an unrecognized wire frame type.
    default: throw protocolError('Unsupported host frame');
  }
  return value;
}

export function validateRelayFrame(value) {
  requireValue(plain(value), 'Invalid relay frame');
  switch (value.type) {
    case 'ready':
      requireShape(value, ['type', 'version']);
      requireValue(value.version === REMOTE_PROTOCOL_VERSION, 'Unsupported protocol version');
      break;
    case 'pair_request':
      requireShape(value, ['type', 'request_id', 'controller_id', 'label']);
      identifier(value.request_id);
      identity(value.controller_id);
      requireValue(boundedString(value.label, 80), 'Invalid controller label');
      break;
    case 'controller_open':
      requireShape(value, ['type', 'connection_id', 'controller_id', 'grant_epoch']);
      identifier(value.connection_id);
      identity(value.controller_id);
      epoch(value.grant_epoch);
      break;
    case 'request':
      requireShape(value, ['type', 'connection_id', 'controller_id', 'grant_epoch', 'request']);
      identifier(value.connection_id);
      identity(value.controller_id);
      epoch(value.grant_epoch);
      validateControllerRequest(value.request);
      break;
    case 'controller_close':
      requireShape(value, ['type', 'connection_id']);
      identifier(value.connection_id);
      break;
    case 'pong':
      requireShape(value, ['type']);
      break;
    // DEFENSE: A relay can send an unrecognized wire frame type.
    default: throw protocolError('Unsupported relay frame');
  }
  return value;
}

export function validateControllerFrame(value) {
  if (value?.type === 'ready') {
    requireShape(value, ['type', 'version', 'controller_id', 'grant_epoch']);
    requireValue(value.version === REMOTE_PROTOCOL_VERSION, 'Unsupported protocol version');
    identity(value.controller_id);
    epoch(value.grant_epoch);
  } else if (value?.type === 'event') {
    requireShape(value, ['type', 'event']);
    requireValue(plain(value.event), 'Invalid observation event');
  } else validateRemoteResponse(value);
  return value;
}

export function parseRemoteFrame(data, validator) {
  // DEFENSE: WebSocket peers can send binary frames or JSON larger than the transport budget.
  if (typeof data !== 'string') throw protocolError('Only JSON text frames are accepted');
  if (data.length > MAX_REMOTE_FRAME_BYTES || encoder.encode(data).byteLength > MAX_REMOTE_FRAME_BYTES) {
    throw protocolError('Frame exceeds remote limit', 'frame_too_large');
  }
  let value;
  // DEFENSE: A text WebSocket frame may contain malformed JSON; reject the frame before dispatch.
  try { value = JSON.parse(data); } catch { throw protocolError('Invalid JSON frame'); }
  return validator(value);
}

export function encodeRemoteFrame(value) {
  const encoded = JSON.stringify(value);
  // DEFENSE: A committed world snapshot or streamed observation can exceed the remote frame budget.
  if (encoded.length > MAX_REMOTE_FRAME_BYTES
      || encoder.encode(encoded).byteLength > MAX_REMOTE_FRAME_BYTES) {
    throw protocolError('Frame exceeds remote limit', 'frame_too_large');
  }
  return encoded;
}

export function assertRelayUrl(value, { allowLoopback = false } = {}) {
  let url;
  // DEFENSE: The relay origin comes from local configuration or the remote-init CLI and may be malformed.
  try { url = new URL(value); } catch { throw protocolError('Invalid relay URL'); }
  const local = allowLoopback && url.protocol === 'http:'
    && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  // DEFENSE: A configured relay must not send host credentials to a plaintext or non-origin production endpoint.
  if ((!local && (url.protocol !== 'https:' || (url.port && url.port !== '443')))
      || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw protocolError('Relay URL must be an HTTPS origin on TCP 443');
  }
  return url.origin;
}

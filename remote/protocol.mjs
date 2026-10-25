import { parseJson, stringifyJson, safeInteger } from '../host/public/json-tokens.mjs';
import { boundary } from '../host/public/model-boundary.mjs';

export const REMOTE_PROTOCOL_VERSION = 1;
// NOTE: The native complete decision is bounded to 4 MiB; encoded observations
// and their surrounding wire envelope need additional room.
export const MAX_REMOTE_FRAME_BYTES = 16 * 1024 * 1024;
export const MAX_REMOTE_GRANTS = 64;
export const MAX_REMOTE_CONTROLLERS = 32;
// NOTE: Tickets share the host's 2 KiB WebSocket hibernation attachment.
export const MAX_REMOTE_TICKETS = 8;
export const REMOTE_TICKET_TTL_MS = 30_000;
export const REMOTE_PAIRING_TTL_MS = 5 * 60_000;

const encoder = new TextEncoder();
export const isHostId = value => typeof value === 'string'
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
export const isRemoteToken = value => typeof value === 'string' && /^[A-Za-z0-9_-]{43}$/.test(value);
export const isControllerId = value => typeof value === 'string' && boundary('control.remote.controller_id', value);

export class RemoteProtocolError extends Error {
  constructor(message, code = 'invalid_frame') {
    super(`Remote protocol: ${message}`);
    this.name = 'RemoteProtocolError';
    this.code = code;
  }
}

export function protocolError(message, code) { return new RemoteProtocolError(message, code); }

// These conversions are confined to declared envelope integers. Opaque command,
// result and observation JSON retains the exact original number tokens.
function integer(object, name) {
  if (!object || !Object.hasOwn(object, name)) return;
  const value = safeInteger(object[name]);
  // DEFENSE: An external envelope may contain a fractional or out-of-range integer.
  if (value === undefined) throw protocolError(`Invalid integer ${name}`);
  object[name] = value;
}
function responseIntegers(value) {
  if (value && typeof value.id !== 'string') integer(value, 'id');
}
function normalize(value, kind) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return;
  if (kind === 'controller_request' || kind === 'response') responseIntegers(value);
  if (kind === 'controller_frame' && value.type !== 'ready' && value.type !== 'event') responseIntegers(value);
  if (['host_frame', 'relay_frame', 'controller_frame'].includes(kind)) {
    integer(value, 'version');
    integer(value, 'grant_epoch');
    integer(value, 'expires_at');
    if (kind === 'host_frame' && value.type === 'grants' && Array.isArray(value.grants)) {
      for (const grant of value.grants) integer(grant, 'grant_epoch');
    }
    if (kind === 'host_frame' && value.type === 'response') responseIntegers(value.response);
    if (kind === 'relay_frame' && value.type === 'request') responseIntegers(value.request);
  }
}
function validate(kind, value) {
  normalize(value, kind);
  // DEFENSE: Untrusted peers may violate the schema shared by the host, relay and controller.
  if (!boundary(`control.remote.${kind}`, value)) throw protocolError('Frame violates remote wire schema');
  return value;
}
export const validateControllerRequest = value => validate('controller_request', value);
export const validateRemoteResponse = value => validate('response', value);
export const validateHostFrame = value => validate('host_frame', value);
export const validateRelayFrame = value => validate('relay_frame', value);
export const validateControllerFrame = value => validate('controller_frame', value);

export function parseRemoteFrame(data, validator) {
  // DEFENSE: WebSocket peers can send binary frames or JSON larger than the transport budget.
  if (typeof data !== 'string') throw protocolError('Only JSON text frames are accepted');
  if (data.length > MAX_REMOTE_FRAME_BYTES || encoder.encode(data).byteLength > MAX_REMOTE_FRAME_BYTES) {
    throw protocolError('Frame exceeds remote limit', 'frame_too_large');
  }
  let value;
  // DEFENSE: A text WebSocket frame may contain malformed JSON; reject the frame before dispatch.
  try { value = parseJson(data); } catch { throw protocolError('Invalid JSON frame'); }
  return validator(value);
}

export function encodeRemoteFrame(value) {
  const encoded = stringifyJson(value);
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

import { parseJson, stringifyJson } from '../host/public/json-tokens.mjs';

export const REMOTE_PROTOCOL_VERSION = 1;
// NOTE: The native complete decision is bounded to 4 MiB; encoded observations
// and their surrounding wire envelope need additional room.
export const MAX_REMOTE_FRAME_BYTES = 16 * 1024 * 1024;
export const REMOTE_TICKET_TTL_MS = 30_000;
export const REMOTE_PAIRING_TTL_MS = 5 * 60_000;

const encoder = new TextEncoder();

export class RemoteProtocolError extends Error {
  constructor(message, code = 'invalid_frame') {
    super(`Remote protocol: ${message}`);
    this.name = 'RemoteProtocolError';
    this.code = code;
  }
}

export function protocolError(message, code) { return new RemoteProtocolError(message, code); }

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

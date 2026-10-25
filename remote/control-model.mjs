import { boundary } from '../host/public/model-boundary.mjs';
import { JsonNumber, safeInteger } from '../host/public/json-tokens.mjs';

// Control state has only bounded transport metadata, never opaque command JSON.
// Materialize it before passing it to WebSocket structured-clone attachments.
function materialize(value) {
  if (value instanceof JsonNumber) return safeInteger(value);
  if (Array.isArray(value)) return value.map(materialize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, materialize(item)]));
  return value;
}
export const remoteControl = (operation, source) => materialize(boundary(`control.remote.${operation}`, source));

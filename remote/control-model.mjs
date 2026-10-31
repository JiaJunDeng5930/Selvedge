import { boundary } from '../host/public/model-boundary.mjs';

// The native encoder canonicalizes admitted metadata and preserves opaque JSON.
export const remoteControl = (operation, source) => boundary(`control.remote.${operation}`, source);

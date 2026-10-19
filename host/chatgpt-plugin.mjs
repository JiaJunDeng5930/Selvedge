import { timingSafeEqual } from 'node:crypto';
import { boundary } from './public/model-boundary.mjs';
import { interpretCredential } from './opaque-credentials.mjs';

/** Transport configuration only. Project membership and operation policy live in features/chatgpt/MODEL.bend. */
export function connectionConfig(value = { connections: {} }) {
  return boundary('plugin.connection_config', value);
}

export function connectionGrants(config) {
  return boundary('plugin.connection_grants', config);
}

/** Credentials never enter the native model, SQLite journal, MCP output, or shell environment. */
export function connectionCredentials(config, env = process.env) {
  const seen = new Set();
  const plan = boundary('plugin.credential_plan', null);
  return new Map(Object.entries(config.connections).map(([id, settings]) => {
    const token = env[settings.token_env];
    const credential = interpretCredential(token, plan, seen);
    // DEFENSE: Environment tokens can be missing, malformed or reused by another configured connection.
    if (credential === null) {
      throw new Error(`ChatGPT connection ${id} needs a distinct 32–256 character base64url token in ${settings.token_env}`);
    }
    return [id, credential];
  }));
}

export function connectionAuthorized(credentials, id, authorization) {
  const expected = credentials.get(id);
  // DEFENSE: Incoming HTTP requests can name an unknown connection or omit/malformed the Bearer header;
  // timingSafeEqual requires equal byte lengths before comparing secret bytes.
  const supplied = Buffer.from(typeof authorization === 'string' ? authorization : '');
  return expected !== undefined && expected.length === supplied.length && timingSafeEqual(expected, supplied);
}

/** Authentication supplies the connection coordinate captured by the native constructor. */
export function connectionCommand(connection, body) {
  return boundary('plugin.command', { connection, body });
}

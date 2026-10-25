import http from 'node:http';
import { boundary } from '../generated/model-boundary.mjs';
import { interpretCredential } from '../generated/opaque-credentials.mjs';
import { parseJson } from '../generated/json-tokens.mjs';
import { readBoundedRegularSnapshot } from '../generated/file-io.mjs';
import path from 'node:path';
import { requirePackagedModel } from '../scripts/build-model.mjs';

await requirePackagedModel();
const utf8Decoder = new TextDecoder('utf-8', { fatal: true });

/** Installed clients supply PLUGIN_DATA instead of inheriting arbitrary credentials. */
export async function loadSettings(env = process.env) {
  if (!env.SELVEDGE_CONNECTION_FILE) return settings(env);
  const absolute = path.isAbsolute(env.SELVEDGE_CONNECTION_FILE);
  boundary('plugin.settings_file', { phase: 'path', absolute });
  const { bytes } = await readBoundedRegularSnapshot(env.SELVEDGE_CONNECTION_FILE, { maximumBytes: 4096,
    admitMetadata(stat) {
      boundary('plugin.settings_file', { phase: 'metadata', absolute, nofollow: true,
        regular: stat.isFile(), bytes: stat.size, mode: stat.mode,
        owner_uid: stat.uid, current_uid: process.getuid() });
    } });
  let value;
  try { value = parseJson(utf8Decoder.decode(bytes)); }
  // DEFENSE: A manually edited credential file can contain invalid UTF-8/JSON; parser diagnostics must not expose its contents.
  catch { throw new Error('Invalid connection file JSON'); }
  boundary('plugin.settings_file', { phase: 'keys', absolute,
    object: value !== null && typeof value === 'object' && !Array.isArray(value),
    keys: value !== null && typeof value === 'object' ? Object.keys(value) : [] });
  return settings(value);
}

export function settings(env = process.env) {
  const endpoint = new URL(env.SELVEDGE_URL ?? 'http://127.0.0.1:7421');
  const normalized = boundary('plugin.client_settings', {
    protocol: endpoint.protocol, hostname: endpoint.hostname, pathname: endpoint.pathname,
    search: endpoint.search, hash: endpoint.hash, origin: endpoint.origin,
    username_present: !!endpoint.username, password_present: !!endpoint.password,
    connection: env.SELVEDGE_CONNECTION_ID ?? null, keys: Object.keys(env),
  });
  const token = env.SELVEDGE_CONNECTION_TOKEN;
  // DEFENSE: The selected environment or private connection file can omit the dedicated credential or contain invalid header bytes.
  if (interpretCredential(token, normalized.credential_plan, null) === null) {
    throw new Error('SELVEDGE_CONNECTION_TOKEN must contain the dedicated connection credential');
  }
  return { endpoint: normalized.endpoint, connection: normalized.connection, token };
}

/** A narrow, bounded loopback client. It does not load Selvedge's admin token or execute files. */
export function callTool(config, tool, arguments_, { signal } = {}) {
  const body = JSON.stringify({ tool, arguments: arguments_ });
  // DEFENSE: MCP clients can supply arguments larger than the authenticated loopback endpoint accepts.
  if (Buffer.byteLength(body) > 256 * 1024) throw new RangeError('Tool request exceeds 256 KiB');
  const timeout = AbortSignal.timeout(30_000);
  const cancellation = signal ? AbortSignal.any([signal, timeout]) : timeout;
  return new Promise((resolve, reject) => {
    // node:http makes no proxy or redirect decisions, so this credential never
    // follows a redirect or an inherited HTTP_PROXY to a different server.
    const request = http.request(new URL(`/api/chatgpt/${config.connection}`, config.endpoint), {
      method: 'POST', signal: cancellation,
      headers: { authorization: interpretCredential(config.token, boundary('plugin.credential_plan', null), null).toString(), 'content-type': 'application/json',
        accept: 'application/json', 'content-length': Buffer.byteLength(body) },
    }, response => {
      const chunks = [];
      let length = 0;
      response.on('data', chunk => {
        length += chunk.length;
        // DEFENSE: A local HTTP peer can return a body beyond the plugin response budget, including chunked responses.
        if (length > 2 * 1024 * 1024) response.destroy(new RangeError('Selvedge response exceeds 2 MiB'));
        else chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        try {
          const text = utf8Decoder.decode(Buffer.concat(chunks));
          const reply = boundary('plugin.http_response', { tool, text, status: response.statusCode,
            status_text: String(response.statusCode), content_type: response.headers['content-type'] ?? '' });
          resolve(reply);
        // DEFENSE: HTTP reply bytes can be invalid UTF-8/JSON or violate the admitted MCP response contract; reject this tool call.
        } catch (error) { reject(error); }
      });
    });
    request.on('error', reject);
    request.end(body);
  });
}

import http from 'node:http';
import { constants } from 'node:fs';
import { open } from 'node:fs/promises';
import path from 'node:path';

/** Installed clients supply PLUGIN_DATA instead of inheriting arbitrary credentials. */
export async function loadSettings(env = process.env) {
  if (!env.SELVEDGE_CONNECTION_FILE) return settings(env);
  if (!path.isAbsolute(env.SELVEDGE_CONNECTION_FILE)) throw new Error('SELVEDGE_CONNECTION_FILE must be absolute');
  const file = await open(env.SELVEDGE_CONNECTION_FILE, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size > 4096 || (stat.mode & 0o077) || stat.uid !== process.getuid()) {
      throw new Error('The connection file must be a private, owned regular file of at most 4096 bytes');
    }
    let value;
    try { value = JSON.parse(await file.readFile('utf8')); }
    catch { throw new Error('Invalid connection file JSON'); }
    const keys = ['SELVEDGE_URL', 'SELVEDGE_CONNECTION_ID', 'SELVEDGE_CONNECTION_TOKEN'];
    if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !keys.includes(key))) {
      throw new Error('Invalid connection file');
    }
    return settings(value);
  } finally { await file.close(); }
}

export function settings(env = process.env) {
  const endpoint = new URL(env.SELVEDGE_URL ?? 'http://127.0.0.1:7421');
  if (endpoint.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(endpoint.hostname) ||
      endpoint.username || endpoint.password || endpoint.search || endpoint.hash || endpoint.pathname !== '/') {
    throw new Error('SELVEDGE_URL must be an HTTP loopback origin using 127.0.0.1 or [::1]');
  }
  const connection = env.SELVEDGE_CONNECTION_ID;
  if (typeof connection !== 'string' || !/^(0|[1-9][0-9]{0,9})$/.test(connection) || Number(connection) > 0xffffffff) {
    throw new Error('SELVEDGE_CONNECTION_ID must name a configured connection');
  }
  const token = env.SELVEDGE_CONNECTION_TOKEN;
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{32,256}$/.test(token)) {
    throw new Error('SELVEDGE_CONNECTION_TOKEN must contain the dedicated connection credential');
  }
  return { endpoint: endpoint.origin, connection, token };
}

/** A narrow, bounded loopback client. It does not load Selvedge's admin token or execute files. */
export function callTool(config, tool, arguments_, { signal } = {}) {
  const body = JSON.stringify({ tool, arguments: arguments_ });
  if (Buffer.byteLength(body) > 256 * 1024) throw new RangeError('Tool request exceeds 256 KiB');
  const timeout = AbortSignal.timeout(30_000);
  const cancellation = signal ? AbortSignal.any([signal, timeout]) : timeout;
  return new Promise((resolve, reject) => {
    // node:http makes no proxy or redirect decisions, so this credential never
    // follows a redirect or an inherited HTTP_PROXY to a different server.
    const request = http.request(new URL(`/api/chatgpt/${config.connection}`, config.endpoint), {
      method: 'POST', signal: cancellation,
      headers: { authorization: `Bearer ${config.token}`, 'content-type': 'application/json',
        accept: 'application/json', 'content-length': Buffer.byteLength(body) },
    }, response => {
      const chunks = [];
      let length = 0;
      response.on('data', chunk => {
        length += chunk.length;
        if (length > 2 * 1024 * 1024) response.destroy(new RangeError('Selvedge response exceeds 2 MiB'));
        else chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        try {
          if (!response.headers['content-type']?.toLowerCase().startsWith('application/json')) throw new Error('Selvedge returned a non-JSON response');
          const reply = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          if (!reply || typeof reply !== 'object' || typeof reply.ok !== 'boolean') throw new Error('Malformed Selvedge response');
          if (response.statusCode >= 300 && reply.ok) throw new Error(`Selvedge returned HTTP ${response.statusCode}`);
          resolve(reply);
        } catch (error) { reject(error); }
      });
    });
    request.on('error', reject);
    request.end(body);
  });
}

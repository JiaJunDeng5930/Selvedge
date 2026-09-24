import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, unlink } from 'node:fs/promises';
import path from 'node:path';
import { Service } from './service.mjs';
import { stringifyJson, parseJson } from './codec.mjs';
import { readText } from './network.mjs';
import { writeAtomic } from './files.mjs';

const assets = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/app.mjs', ['app.mjs', 'text/javascript; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
]);

export async function startServer(options) {
  const service = await Service.open(options);
  const token = randomBytes(32).toString('hex');
  const clients = new Set();
  const filename = path.join(options.home, 'server.json');
  let closing;
  let address;
  const server = http.createServer({ maxHeaderSize: service.limits.header_bytes }, (request, response) => {
    route(request, response).catch(error => {
      if (response.headersSent) response.destroy();
      else json(response, error instanceof RangeError || error instanceof SyntaxError || error instanceof TypeError ? 400 : 503,
        { ok: false, error: { code: 'request_failed', message: error.message } });
    });
  });
  server.requestTimeout = service.limits.request_timeout_ms;
  server.headersTimeout = service.limits.request_timeout_ms;
  server.keepAliveTimeout = service.limits.request_timeout_ms;

  function json(response, status, value) {
    const body = stringifyJson(value);
    response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    response.end(body);
  }

  function authorized(request) {
    const supplied = Buffer.from(request.headers.authorization ?? '');
    const expected = Buffer.from(`Bearer ${token}`);
    return supplied.length === expected.length && timingSafeEqual(supplied, expected);
  }

  function sendEvent(response, event) {
    if (response.destroyed || response.writableEnded) return;
    const id = event.type === 'commit' ? `id: ${event.sequence}\n` : '';
    if (!response.write(`${id}data: ${stringifyJson(event)}\n\n`)) response.destroy();
  }

  async function route(request, response) {
    if (closing) { json(response, 503, { ok: false, error: { code: 'stopping', message: 'Server is stopping' } }); return; }
    const host = request.headers.host;
    if (!address || host !== new URL(address).host) { json(response, 400, { ok: false, error: { code: 'host', message: 'Invalid local host' } }); return; }
    const url = new URL(request.url, address);
    if (request.method === 'GET' && assets.has(url.pathname)) {
      const [file, contentType] = assets.get(url.pathname);
      const data = await readFile(new URL(`./public/${file}`, import.meta.url));
      response.writeHead(200, { 'content-type': contentType, 'cache-control': 'no-cache',
        'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
        'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer' });
      response.end(data);
      return;
    }
    if (!authorized(request)) { json(response, 401, { ok: false, error: { code: 'unauthorized', message: 'A local access token is required' } }); return; }
    if (request.headers.origin && request.headers.origin !== address) { json(response, 403, { ok: false, error: { code: 'origin', message: 'Origin does not match this server' } }); return; }
    if (request.method === 'POST' && url.pathname === '/api/commands') {
      if (!request.headers['content-type']?.toLowerCase().startsWith('application/json')) { json(response, 415, { ok: false, error: { code: 'content_type', message: 'Send application/json' } }); return; }
      const command = parseJson(await readText(request, service.limits.frame_bytes));
      // The public boundary accepts commands only. It never passes an incoming
      // `kind: model/tool/configure` through to the private kernel channel.
      const result = await service.command(command);
      json(response, result.reply.ok ? 200 : 400, { sequence: result.sequence, ...result.reply });
    } else if (request.method === 'GET' && url.pathname === '/api/describe') {
      json(response, 200, { ok: true, result: service.description });
    } else if (request.method === 'GET' && url.pathname === '/api/events') {
      const supplied = request.headers['last-event-id'] ?? url.searchParams.get('after');
      const after = supplied === null || supplied === undefined ? service.journal.sequence : Number(supplied);
      service.journal.events(after, 1); // Validate before sending response headers.
      response.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
      response.flushHeaders();
      clients.add(response);
      response.once('close', () => clients.delete(response));
      // Reconnection needs the current durable revision, not every historical
      // UI invalidation. The authenticated event page retains exact cursors.
      sendEvent(response, { type: 'commit', sequence: service.journal.sequence });
    } else if (request.method === 'GET' && url.pathname === '/api/event-page') {
      json(response, 200, { ok: true, result: service.journal.events(Number(url.searchParams.get('after') ?? 0), Number(url.searchParams.get('limit') ?? 100)) });
    } else if (request.method === 'GET' && url.pathname === '/api/health') {
      json(response, 200, { ok: true, result: { sequence: service.journal.sequence } });
    } else json(response, 404, { ok: false, error: { code: 'not_found', message: 'Unknown local endpoint' } });
  }

  service.on('notice', event => {
    for (const client of clients) sendEvent(client, event);
    if (event.type === 'fatal') setImmediate(() => close().catch(() => {}));
  });
  const heartbeat = setInterval(() => {
    for (const client of clients) if (!client.write(': keepalive\n\n')) client.destroy();
  }, 15_000);
  heartbeat.unref();

  async function close() {
    closing ??= (async () => {
      clearInterval(heartbeat);
      for (const client of clients) client.end();
      const stopped = new Promise((resolve, reject) => server.close(error => error && error.code !== 'ERR_SERVER_NOT_RUNNING' ? reject(error) : resolve()));
      server.closeAllConnections();
      await Promise.all([stopped, service.close()]);
      try {
        const saved = JSON.parse(await readFile(filename, 'utf8'));
        if (saved.token === token) await unlink(filename);
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
    })();
    return closing;
  }

  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(options.config.port, options.config.host, () => { server.off('error', reject); resolve(); });
    });
    const endpoint = server.address();
    address = `http://${endpoint.family === 'IPv6' ? `[${endpoint.address}]` : endpoint.address}:${endpoint.port}`;
    await writeAtomic(filename, { format: 'selvedge-local-server-1', address, token, pid: process.pid });
    return { service, server, address, token, close, url: `${address}/#token=${token}` };
  } catch (error) { await close(); throw error; }
}

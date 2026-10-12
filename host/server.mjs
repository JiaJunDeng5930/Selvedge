import http from 'node:http';
import { boundary, observeJson } from './public/model-boundary.mjs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, readdir, unlink } from 'node:fs/promises';
import path from 'node:path';
import { encodeBendValue } from './public/bend-value.mjs';
import { emitJsonTokens } from './public/json-tokens.mjs';
import { Service, CommandNotSubmitted } from './service.mjs';
import { stringifyJson, parseJson } from './codec.mjs';
import { readText } from './network.mjs';
import { writeAtomic } from './files.mjs';
import { saveBoardAttachment, readBoardAttachment } from './board-files.mjs';
import { connectionCredentials, connectionAuthorized, connectionCommand } from './chatgpt-plugin.mjs';

async function publicAssets(directory, prefix = '') {
  const assets = new Map();
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const name = encodeURIComponent(entry.name);
    const file = `${prefix}${name}`;
    if (entry.isDirectory()) {
      for (const [pathname, resource] of await publicAssets(new URL(`${name}/`, directory), `${file}/`)) {
        assets.set(pathname, resource);
      }
    } else if (entry.isFile()) {
      const extension = path.extname(entry.name);
      const contentType = extension === '.html' ? 'text/html; charset=utf-8'
        : extension === '.mjs' ? 'text/javascript; charset=utf-8'
        : extension === '.css' ? 'text/css; charset=utf-8' : null;
      if (contentType) assets.set(`/${file}`, [file, contentType]);
    }
  }
  return assets;
}

// NOTE: Request paths select fixed resources; they never become filesystem paths.
const assets = await publicAssets(new URL('./public/', import.meta.url));
if (!assets.has('/index.html')) throw new Error('Browser index.html is missing');
assets.set('/', assets.get('/index.html'));

export async function startServer(options) {
  const connections = connectionCredentials(options.config.chatgpt_plugin);
  const service = await Service.open(options);
  const token = randomBytes(32).toString('hex');
  const clients = new Set();
  const filename = path.join(options.home, 'server.json');
  let closing;
  let address;
  const server = http.createServer({ maxHeaderSize: service.limits.header_bytes }, (request, response) => {
    route(request, response).catch(error => {
      if (response.headersSent) response.destroy();
      else if (error instanceof CommandNotSubmitted) json(response, 400,
        { ok: false, error: { code: 'command_not_submitted', message: error.message } });
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
    // NOTE: Explicit Authorization must stand on its own; browser cookies cannot
    // hide a stale or invalid credential supplied by another client.
    const authorization = request.headers.authorization;
    const credential = authorization !== undefined ? authorization : sessionCookie(request.headers.cookie);
    if (typeof credential !== 'string') return false;
    const supplied = Buffer.from(credential);
    const expected = Buffer.from(authorization !== undefined ? `Bearer ${token}` : token);
    return supplied.length === expected.length && timingSafeEqual(supplied, expected);
  }

  function sessionCookie(header) {
    if (typeof header !== 'string') return null;
    let session = null;
    for (const part of header.split(';')) {
      const cookie = part.trim();
      const separator = cookie.indexOf('=');
      const name = separator < 0 ? cookie : cookie.slice(0, separator);
      if (name.trim() !== 'selvedge-session') continue;
      if (name !== 'selvedge-session' || separator < 0 || session !== null) return null;
      const value = cookie.slice(separator + 1);
      if (!/^[0-9a-f]{64}$/.test(value)) return null;
      session = value;
    }
    return session;
  }

  function sendEvent(response, event) {
    if (response.destroyed || response.writableEnded) return;
    const id = event.type === 'commit' ? `id: ${event.sequence}\n` : '';
    if (!response.write(`${id}data: ${stringifyJson(event)}\n\n`)) response.destroy();
  }

  async function route(request, response) {
    // Secrets stay opaque. Each observation is made only when the native plan
    // requests it, preserving rejection before later parsing or secret access.
    const headers = {};
    for (const name of Object.keys(request.headers)) {
      if (name === 'authorization') continue;
      const value = request.headers[name];
      headers[name] = ['host', 'origin', 'content-type', 'content-length', 'last-event-id'].includes(name)
        ? value : { present: true, type: Array.isArray(value) ? 'array' : typeof value };
    }
    const source = {
      method: request.method, url: request.url, headers,
      closing: Boolean(closing), address_present: Boolean(address), address: address ?? null,
    };
    const decide = operation => boundary(operation, source);
    let plan = decide('http.closing');
    let url;
    let bodyObserved = false;
    let connectionId;
    for (;;) {
      switch (plan.action) {
        case 'respond': json(response, plan.status, plan.value); return;
        case 'throw':
          if (plan.kind === 'RangeError') throw new RangeError(plan.message);
          throw new TypeError(plan.message);
        case 'observe_host':
          source.expected_host = address ? new URL(address).host : null;
          plan = decide('http.preflight');
          break;
        case 'parse_url':
          url = new URL(request.url, address);
          Object.assign(source, { pathname: url.pathname, search: url.search,
            query: [...url.searchParams.entries()], asset: assets.has(url.pathname) });
          plan = decide('http.route');
          break;
        case 'observe_connection_authorization':
          connectionId = url.pathname.slice('/api/chatgpt/'.length);
          source.authorization = { present: request.headers.authorization !== undefined, type: typeof request.headers.authorization };
          source.authorized = connectionAuthorized(connections, connectionId, request.headers.authorization);
          plan = decide('http.connection_authorization');
          break;
        case 'connection_method_origin':
          plan = decide('http.connection_method_origin');
          break;
        case 'observe_local_authorization':
          source.authorization = { present: request.headers.authorization !== undefined, type: typeof request.headers.authorization };
          source.cookie = { present: request.headers.cookie !== undefined, type: typeof request.headers.cookie };
          source.authorized = authorized(request);
          plan = decide('http.local_authorization');
          break;
        case 'local_origin':
          plan = decide('http.local_origin');
          break;
        case 'observe_content_type':
          source.target = plan.target;
          source.content_type = request.headers['content-type']?.toLowerCase() ?? null;
          plan = decide('http.content_type');
          break;
        case 'asset': {
          const [file, contentType] = assets.get(url.pathname);
          const data = await readFile(new URL(`./public/${file}`, import.meta.url));
          response.writeHead(200, { 'content-type': contentType, 'cache-control': url.pathname === '/' ? 'no-store' : 'no-cache',
            ...(url.pathname === '/' ? { 'set-cookie': `selvedge-session=${token}; Path=/api; HttpOnly; SameSite=Strict` } : {}),
            // NOTE: Browser annotations inject inline styles into their selection overlay.
            'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
            'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer' });
          response.end(data);
          return;
        }
        case 'attachment_upload': {
          const attachment = await saveBoardAttachment(service.home, url.searchParams.get('name'), request);
          json(response, 201, { ok: true, result: attachment });
          return;
        }
        case 'attachment_download': {
          const { attachment, data } = await readBoardAttachment(service.home, url.pathname.slice('/api/board/attachments/'.length));
          response.writeHead(200, {
            'content-type': attachment.mime, 'content-length': data.length, 'cache-control': 'no-store',
            'x-content-type-options': 'nosniff', 'content-security-policy': "default-src 'none'; sandbox",
            'content-disposition': `${attachment.mime.startsWith('image/') ? 'inline' : 'attachment'}; filename*=UTF-8''${encodeURIComponent(attachment.name)}`,
          });
          response.end(data);
          return;
        }
        case 'account_refresh':
        case 'browser_command':
        case 'browser_observation':
        case 'command':
        case 'connection_command': {
          if (!bodyObserved) {
            const text = await readText(request, plan.action === 'account_refresh' ? 1024 : service.limits.frame_bytes);
            const parsed = parseJson(text);
            const tokens = [];
            emitJsonTokens(parsed, token => tokens.push(token));
            Object.assign(source, { text, observation: observeJson(text),
              parsed_observation: { text, tokens }, target: plan.action });
            bodyObserved = true;
            plan = decide('http.body');
            break;
          }
          const body = plan.body;
          switch (plan.action) {
            case 'account_refresh':
              json(response, 200, { ok: true, result: await service.refreshAccounts() });
              return;
            case 'browser_observation':
              json(response, 200, await service.browserObservation(body));
              return;
            case 'browser_command': {
              const result = await service.browserCommand(body.command);
              json(response, boundary('http.reply_status', result), { ...result, program: encodeBendValue(result.program) });
              return;
            }
            case 'command': {
              // Public commands are resolved by the service's native command boundary.
              const result = await service.command(body);
              json(response, boundary('http.reply_status', result), { sequence: result.sequence, ...result.reply });
              return;
            }
            case 'connection_command': {
              const result = await service.command(connectionCommand(Number(connectionId), body));
              json(response, boundary('http.reply_status', result), { sequence: result.sequence, ...result.reply });
              return;
            }
          }
          break;
        }
        case 'browser_state': {
          const snapshot = service.browserSnapshot();
          json(response, 200, { ...snapshot, program: encodeBendValue(snapshot.program) });
          return;
        }
        case 'describe':
          json(response, 200, { ok: true, result: service.description });
          return;
        case 'events': {
          const supplied = request.headers['last-event-id'] ?? url.searchParams.get('after');
          const after = supplied === null || supplied === undefined ? service.journal.sequence : Number(supplied);
          service.journal.events(after, 1); // Validate before sending response headers.
          response.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
          response.flushHeaders();
          clients.add(response);
          response.once('close', () => clients.delete(response));
          // Capture active streams before this synchronous subscription yields to notices.
          sendEvent(response, { type: 'stream-state', streams: service.browserStreams() });
          // Reconnection needs the current durable revision, not historical invalidations.
          sendEvent(response, { type: 'commit', sequence: service.journal.sequence });
          return;
        }
        case 'event_page':
          json(response, 200, { ok: true, result: service.journal.events(Number(url.searchParams.get('after') ?? 0), Number(url.searchParams.get('limit') ?? 100)) });
          return;
        case 'health':
          json(response, 200, { ok: true, result: { sequence: service.journal.sequence } });
          return;
        default: throw new TypeError('Invalid native HTTP action');
      }
    }
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
    return { service, server, address, token, close, url: `${address}/` };
  } catch (error) { await close(); throw error; }
}

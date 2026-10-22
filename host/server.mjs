import http from 'node:http';
import { boundary } from './public/model-boundary.mjs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, readdir, unlink } from 'node:fs/promises';
import path from 'node:path';
import { Service, CommandNotSubmitted } from './service.mjs';
import { stringifyJson } from './codec.mjs';
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
        : ['.mjs', '.js'].includes(extension) ? 'text/javascript; charset=utf-8'
        : extension === '.css' ? 'text/css; charset=utf-8' : null;
      if (contentType) assets.set(`/${file}`, [file, contentType]);
    }
  }
  return assets;
}

// NOTE: Request paths select fixed resources; they never become filesystem paths.
const assets = await publicAssets(new URL('./public/', import.meta.url));
assets.set('/', assets.get('/index.html'));

export async function startServer(options) {
  const connections = connectionCredentials(options.config.chatgpt_plugin);
  const service = await Service.open(options);
  const token = randomBytes(32).toString('hex');
  const clients = new Set();
  const audioClients = new Set();
  const sockets = new Set();
  const filename = path.join(options.home, 'server.json');
  let closing;
  let address;
  const server = http.createServer({ maxHeaderSize: service.limits.header_bytes }, (request, response) => {
    // DEFENSE: Requests can fail UTF-8/JSON admission, authentication or external filesystem/service work; return the declared HTTP failure before headers, otherwise close the partial response.
    route(request, response).catch(error => {
      if (response.headersSent) response.destroy();
      else if (error instanceof CommandNotSubmitted) json(response, 400,
        { ok: false, error: { code: 'command_not_submitted', message: error.message } });
      else json(response, error instanceof RangeError || error instanceof SyntaxError || error instanceof TypeError ? 400 : 503,
        { ok: false, error: { code: 'request_failed', message: error.message } });
    });
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
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
    // DEFENSE: A request can contain an invalid explicit Authorization plus a valid browser cookie; the explicit credential must stand on its own.
    const authorization = request.headers.authorization;
    const credential = authorization !== undefined ? authorization : sessionCookie(request.headers.cookie);
    // DEFENSE: An unauthenticated request may omit both Authorization and the session cookie.
    if (typeof credential !== 'string') return false;
    const supplied = Buffer.from(credential);
    const expected = Buffer.from(authorization !== undefined ? `Bearer ${token}` : token);
    // DEFENSE: Attackers can supply arbitrary credential lengths; timingSafeEqual requires equal-size buffers.
    return supplied.length === expected.length && timingSafeEqual(supplied, expected);
  }

  function sessionCookie(header) {
    // DEFENSE: Non-browser requests can have no Cookie header.
    if (typeof header !== 'string') return null;
    let session = null;
    for (const part of header.split(';')) {
      const cookie = part.trim();
      const separator = cookie.indexOf('=');
      const name = separator < 0 ? cookie : cookie.slice(0, separator);
      if (name.trim() !== 'selvedge-session') continue;
      // DEFENSE: Forged Cookie headers can repeat, omit '=' from, or add whitespace to the session field; reject ambiguous credentials.
      if (name !== 'selvedge-session' || separator < 0 || session !== null) return null;
      const value = cookie.slice(separator + 1);
      // DEFENSE: An edited browser cookie can contain a value other than the server's 32-byte hexadecimal session token.
      if (!/^[0-9a-f]{64}$/.test(value)) return null;
      session = value;
    }
    return session;
  }

  function writeSseFrame(response, frame) {
    // DEFENSE: A client can disconnect while a committed notice or heartbeat is being delivered.
    if (response.destroyed || response.writableEnded) return;
    // DEFENSE: A slow SSE client can accumulate queued frames; disconnect it when retained bytes exceed the published budget.
    if (response.writableLength + Buffer.byteLength(frame) > service.limits.frame_bytes) {
      response.destroy();
      return;
    }
    // A false result means this frame was accepted with backpressure. Keep the
    // connection; the byte limit above bounds a client that cannot keep up.
    response.write(frame);
  }

  function sendEvent(response, event) {
    const id = event.type === 'commit' ? `id: ${event.sequence}\n` : '';
    writeSseFrame(response, `${id}data: ${stringifyJson(event)}\n\n`);
  }

  function requestSignal(request, response) {
    const controller = new AbortController();
    const abort = () => controller.abort(new Error('Audio client disconnected'));
    request.once('aborted', abort);
    const closed = () => { if (!response.writableEnded) abort(); };
    response.once('close', closed);
    return { signal: controller.signal, close() {
      request.off('aborted', abort);
      response.off('close', closed);
    } };
  }

  async function readAudio(request, browser_id) {
    const started = Date.now();
    const mime = request.headers['content-type'] ?? '';
    const admit = body_bytes => {
      const plan = boundary('http.audio', { kind: 'transcribe', browser_id, mime,
        body_bytes, elapsed_ms: Date.now() - started });
      // DEFENSE: A microphone upload can exceed its native byte/time contract while streaming without Content-Length.
      if (!plan.allowed) throw new RangeError(plan.message);
      return plan;
    };
    const plan = admit(Number(request.headers['content-length'] ?? 0));
    const chunks = [];
    let size = 0;
    // DEFENSE: A client can hold an upload open without sending bytes; stop retaining the request when its declared duration expires.
    const timer = setTimeout(() => request.destroy(new Error('Audio upload timed out')), plan.timeout_ms);
    timer.unref();
    try {
      for await (const chunk of request) {
        size += chunk.byteLength;
        admit(size);
        chunks.push(chunk);
      }
      return { audio: Buffer.concat(chunks, size), mime, elapsed_ms: Date.now() - started };
    } finally { clearTimeout(timer); }
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
        case 'audio_capabilities': {
          const operation = requestSignal(request, response);
          try { json(response, 200, await service.audioCapabilities({ signal: operation.signal })); }
          finally { operation.close(); }
          return;
        }
        case 'audio_transcribe': {
          const operation = requestSignal(request, response);
          try {
            const browser_id = url.searchParams.get('browser_id');
            const upload = await readAudio(request, browser_id);
            json(response, 200, await service.audioTranscribe({ ...upload, browser_id,
              connection: url.searchParams.get('connection'), language: url.searchParams.get('language'), signal: operation.signal }));
          } finally { operation.close(); }
          return;
        }
        case 'audio_events': {
          const id = url.pathname.split('/')[4];
          // Validate and register before sending headers: the callback's first ready observation is sent below.
          const pending = [];
          let opened = false;
          const unsubscribe = service.audioSubscribe(id, url.searchParams.get('browser_id'), event => {
            if (!opened) { pending.push(event); return; }
            sendEvent(response, event);
            if (event.type === 'stopped') response.end();
          });
          response.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
          response.flushHeaders();
          audioClients.add(response);
          opened = true;
          for (const event of pending) sendEvent(response, event);
          response.once('close', () => {
            audioClients.delete(response);
            unsubscribe();
            service.audioDisconnect(id, url.searchParams.get('browser_id')).catch(error => service.notify({ type: 'diagnostic', message: error.message }));
          });
          return;
        }
        case 'audio_stop':
          json(response, 200, await service.audioStop(url.pathname.split('/')[4], url.searchParams.get('browser_id')));
          return;
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
        case 'audio_create':
        case 'audio_login':
        case 'remote_pair':
        case 'remote_enable':
        case 'remote_disable':
        case 'remote_approve':
        case 'remote_revoke':
        case 'browser_command':
        case 'browser_observation':
        case 'command':
        case 'assess':
        case 'connection_command': {
          if (!bodyObserved) {
            const maximum = ['account_refresh', 'audio_login'].includes(plan.action) ? 1024 : plan.action.startsWith('remote_') ? 8192 : service.limits.frame_bytes;
            const text = await readText(request, maximum);
            Object.assign(source, { text, target: plan.action });
            bodyObserved = true;
            plan = decide('http.body');
            break;
          }
          const body = plan.body;
          switch (plan.action) {
            case 'audio_login': {
              const operation = requestSignal(request, response);
              try { json(response, 200, await service.audioLogin(body, { signal: operation.signal })); }
              finally { operation.close(); }
              return;
            }
            case 'audio_create': {
              const operation = requestSignal(request, response);
              try { json(response, 200, await service.audioCreate(body, { signal: operation.signal })); }
              finally { operation.close(); }
              return;
            }
            case 'remote_pair':
              json(response, 200, { ok: true, result: await service.remote.pair() });
              return;
            case 'remote_enable':
              json(response, 200, { ok: true, result: await service.remote.enable() });
              return;
            case 'remote_disable':
              json(response, 200, { ok: true, result: await service.remote.disable() });
              return;
            case 'remote_approve':
              json(response, 200, { ok: true, result: await service.remote.approve(body.request_id, body.permissions) });
              return;
            case 'remote_revoke':
              json(response, 200, { ok: true, result: await service.remote.revoke(body.controller_id) });
              return;
            case 'account_refresh':
              json(response, 200, { ok: true, result: await service.refreshAccounts() });
              return;
            case 'browser_observation':
              json(response, 200, await service.browserObservation(body));
              return;
            case 'browser_command': {
              const result = await service.browserCommand(body.command);
              json(response, boundary('http.reply_status', { reply: result.reply }), { ...result, program: result.program });
              return;
            }
            case 'command': {
              // Public commands are resolved by the service's native command boundary.
              const result = await service.command(body);
              json(response, boundary('http.reply_status', { reply: result.reply }), { sequence: result.sequence, ...result.reply });
              return;
            }
            case 'assess': {
              json(response, 200, await service.assess(body));
              return;
            }
            case 'connection_command': {
              const result = await service.command(connectionCommand(Number(connectionId), body));
              json(response, boundary('http.reply_status', { reply: result.reply }), { sequence: result.sequence, ...result.reply });
              return;
            }
          }
          break;
        }
        case 'browser_state': {
          const snapshot = service.browserSnapshot();
          json(response, 200, { ...snapshot, program: snapshot.program });
          return;
        }
        case 'describe':
          json(response, 200, { ok: true, result: service.description });
          return;
        case 'remote_status':
          json(response, 200, { ok: true, result: await service.remote.status() });
          return;
        case 'remote_pending':
          json(response, 200, { ok: true, result: await service.remote.pending() });
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
          sendEvent(response, { type: 'stream-state', namespace: service.journal.namespace, streams: service.browserStreams() });
          // Reconnection needs the current durable revision, not historical invalidations.
          sendEvent(response, { type: 'commit', namespace: service.journal.namespace, sequence: service.journal.sequence });
          return;
        }
        case 'event_page':
          json(response, 200, { ok: true, result: service.journal.events(Number(url.searchParams.get('after') ?? 0), Number(url.searchParams.get('limit') ?? 100)) });
          return;
        case 'health':
          json(response, 200, { ok: true, result: { sequence: service.journal.sequence } });
          return;
      }
    }
  }

  service.on('notice', event => {
    for (const client of clients) sendEvent(client, event);
    // DEFENSE: A fatal journal/Worker failure requires server shutdown; report filesystem/listener cleanup errors rather than dropping them.
    if (event.type === 'fatal') setImmediate(() => close().catch(error => {
      service.notify({ type: 'diagnostic', message: `Server shutdown failed: ${error.message}` });
    }));
  });
  const heartbeat = setInterval(() => {
    for (const client of [...clients, ...audioClients]) writeSseFrame(client, ': keepalive\n\n');
  }, 15_000);
  heartbeat.unref();

  async function close() {
    closing ??= (async () => {
      clearInterval(heartbeat);
      for (const client of [...clients, ...audioClients]) client.end();
      // DEFENSE: Startup can fail before listen succeeds; ERR_SERVER_NOT_RUNNING then means there is no listener to close.
      const stopped = new Promise((resolve, reject) => server.close(error => error && error.code !== 'ERR_SERVER_NOT_RUNNING' ? reject(error) : resolve()));
      // DEFENSE: Bun's close() detaches its native server before closeAllConnections
      // can reach active keep-alive sockets, which could still target this stopping
      // service after a listener restarts on the same port.
      for (const socket of sockets) socket.destroy();
      await Promise.all([stopped, service.close()]);
      try {
        const saved = JSON.parse(await readFile(filename, 'utf8'));
        // DEFENSE: Another server can start after service.close releases the journal lock; do not unlink its new discovery record.
        if (saved.token === token) await unlink(filename);
      // DEFENSE: Failed startup may not have written server.json, or external cleanup may already have removed it.
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
  // DEFENSE: Listen/write failures after Service.open must stop the acquired service and listener.
  } catch (error) { await close(); throw error; }
}

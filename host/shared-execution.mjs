import { Database } from 'bun:sqlite';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { lstat, opendir, readFile, realpath, stat } from 'node:fs/promises';
import { createServer } from 'node:https';
import path from 'node:path';
import { WebSocketServer } from 'ws';
import { readBoundedRegularSnapshot, durableDirectory } from './file-io.mjs';
import { boundary } from './public/model-boundary.mjs';
import { parseJson, stringifyJson } from './public/json-tokens.mjs';
import { ProcessRegistry } from './process-registry.mjs';
import { readImageBytes, retainReadImage, startBash } from './process.mjs';

const protocol = 'selvedge-execution-v1';
const endpointPath = boundary('effect.execution_endpoint_path', null);
const maximumFrame = 24 * 1024 * 1024;
const decoder = new TextDecoder('utf-8', { fatal: true });
const digest = text => createHash('sha256').update(text).digest();
const fail = (code, message) => Object.assign(new Error(message), { code });
const decode = (operation, bytes) => boundary(operation, parseJson(decoder.decode(bytes)));

async function readToken(filename) {
  const token = (await readFile(filename, 'utf8')).trim();
  // DEFENSE: An empty, malformed or low-length credential must not enable a receiver.
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(token)) throw new Error('Shared execution token must be 43–128 base64url characters');
  return token;
}

function send(socket, message) {
  // DEFENSE: A peer can disconnect or stop reading while an effect is producing output.
  if (socket.readyState !== WebSocket.OPEN) return;
  const wire = stringifyJson(message);
  if (Buffer.byteLength(wire) > maximumFrame || socket.bufferedAmount > maximumFrame) socket.terminate();
  else socket.send(wire);
}

const kind = value => value.isSymbolicLink() ? 'link'
  : value.isDirectory() ? 'directory' : value.isFile() ? 'file' : 'other';
const typed = ({ kind, name }) => ({ name, isSymbolicLink: () => kind === 'link',
  isDirectory: () => kind === 'directory', isFile: () => kind === 'file' });
const observationMethods = {
  'execution.realpath': ({ path }) => realpath(path),
  'execution.stat': async ({ path }) => ({ kind: kind(await stat(path)) }),
  'execution.lstat': async ({ path }) => ({ kind: kind(await lstat(path)) }),
  'execution.readdir': async ({ path, maximum }) => {
    const entries = [];
    for await (const entry of await opendir(path)) {
      entries.push({ name: entry.name, kind: kind(entry) });
      if (entries.length >= maximum) break;
    }
    return entries;
  },
  'execution.read_file': async ({ path, maximum }) => (await readBoundedRegularSnapshot(path,
    { maximumBytes: maximum })).bytes.toString('base64'),
};

/** A paired Selvedge instance can submit its already-authorized workspace effects. */
export async function receiveExecution({ home, host, port, certFile, keyFile, tokenFile }) {
  const [cert, key, token] = await Promise.all([readFile(certFile), readFile(keyFile), readToken(tokenFile)]);
  const credential = digest(`Bearer ${token}`);
  await durableDirectory(home);
  const db = new Database(path.join(home, 'shared-execution.sqlite'), { create: true });
  db.exec(`PRAGMA journal_mode = WAL;
    PRAGMA synchronous = FULL;
    CREATE TABLE IF NOT EXISTS execution_receipts
      (operation_id TEXT PRIMARY KEY, request TEXT, outcome TEXT) STRICT;`);
  const receipt = db.query('SELECT request, outcome FROM execution_receipts WHERE operation_id = ?');
  const reserve = db.query('INSERT INTO execution_receipts (operation_id, request) VALUES (?, ?)');
  const cancelUnreceived = db.query('INSERT INTO execution_receipts (operation_id, outcome) VALUES (?, ?) ON CONFLICT DO NOTHING');
  const settle = db.query('UPDATE execution_receipts SET outcome = ? WHERE operation_id = ?');
  const admit = db.transaction(request => {
    const previous = receipt.get(request.operation_id);
    const action = boundary('effect.execution_start_action', {
      recorded: Boolean(previous), previous: previous?.request ? parseJson(previous.request) : null, incoming: request,
    });
    if (action === 'reserve') reserve.run(request.operation_id, stringifyJson(request));
    return action;
  }).immediate;
  const limits = boundary('effect.execution_limits', null);
  const active = new Map();
  const processes = new ProcessRegistry();
  const sockets = new WebSocketServer({ noServer: true, maxPayload: maximumFrame });
  const server = createServer({ cert, key }, (_request, response) => {
    response.writeHead(404).end();
  });
  server.on('upgrade', (request, socket, head) => {
    // DEFENSE: Only the configured peer may connect, and browser upgrades with an Origin cannot enter this endpoint.
    if (request.url !== endpointPath || request.headers.origin ||
        request.headers['sec-websocket-protocol'] !== protocol ||
        !timingSafeEqual(credential, digest(request.headers.authorization ?? ''))) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      return;
    }
    sockets.handleUpgrade(request, socket, head, connection => sockets.emit('connection', connection));
  });

  function output(operation, read) {
    operation.preview = read;
    operation.timer ??= setTimeout(() => {
      operation.timer = undefined;
      const packet = { method: 'execution.output', params: {
        operation_id: operation.id, output: operation.preview(32768),
      } };
      for (const socket of operation.listeners) send(socket, packet);
    }, 160);
  }

  function begin(request, socket) {
    const id = request.operation_id;
    const action = admit(request);
    // DEFENSE: Lost acknowledgements cause replays; using the same ID for different work is a protocol error.
    if (action === 'conflict') throw fail('execution_conflict', 'Shared execution operation ID already identifies a different request');
    if (action === 'cancelled') throw fail('execution_cancelled', 'Shared execution was cancelled before it started');
    if (action === 'observe') return { accepted: true };
    const operation = { id, controller: new AbortController(), listeners: new Set([socket]) };
    active.set(id, operation);
    const options = { signal: operation.controller.signal, execution: request.execution,
      readOnlyPaths: [home], onOutput: read => output(operation, read) };
    operation.result = (async () => {
      let outcome;
      try {
        let value;
        if (request.tool === 'bash') {
          const session = processes.register(id, request.arguments.mode ?? 'pipe');
          try {
            const runtime = startBash(request.arguments, limits, options);
            session.read = runtime.read;
            session.write = runtime.write;
            value = await runtime.result;
          } finally { processes.complete(id); }
        } else {
          const image = await readImageBytes(request.arguments, options);
          value = { ...image, bytes: image.bytes.toString('base64') };
        }
        outcome = { value };
      // DEFENSE: Process preparation, image reads and explicit cancellations can fail after reservation.
      } catch (error) {
        outcome = { error: { code: error.code ?? 'shared_execution_failed', message: error.message } };
      }
      settle.run(stringifyJson(outcome), id);
      return outcome;
    })().finally(() => {
      clearTimeout(operation.timer);
      active.delete(id);
    });
    // DEFENSE: A storage failure can prevent settlement before the caller attaches a waiter.
    operation.result.catch(() => {});
    return { accepted: true };
  }

  async function perform(socket, { method, params }) {
    if (Object.hasOwn(observationMethods, method)) return observationMethods[method](params);
    const operation = active.get(params.operation_id);
    switch (method) {
      case 'execution.start': return begin(params, socket);
      case 'execution.wait': {
        if (operation) {
          operation.listeners.add(socket);
          if (operation.preview) send(socket, { method: 'execution.output', params: {
            operation_id: operation.id, output: operation.preview(32768),
          } });
          return operation.result;
        }
        const saved = receipt.get(params.operation_id);
        if (saved?.outcome) return parseJson(saved.outcome);
        // DEFENSE: The receiver can restart after reserving an operation and before persisting its result.
        throw fail(saved ? 'outcome_unknown' : 'execution_missing', saved
          ? 'Shared execution may already have run before the receiver restarted'
          : 'Shared execution operation was not received');
      }
      case 'execution.read': {
        const { session, pending } = processes.lookup(params.operation_id);
        return session.read ? session.read(params.cursor) : pending;
      }
      case 'execution.write': {
        processes.admitWrite(params.operation_id);
        const { session } = processes.lookup(params.operation_id);
        return session.write(params.input);
      }
      case 'execution.cancel': {
        if (operation) {
          operation.controller.abort();
          return { outcome: await operation.result };
        }
        // A queued start can reach this receiver after cancellation crosses a reconnected channel.
        const outcome = { error: { code: 'execution_cancelled', message: 'Shared execution was cancelled before it started' } };
        cancelUnreceived.run(params.operation_id, stringifyJson(outcome));
        const saved = receipt.get(params.operation_id);
        return { outcome: saved.outcome ? parseJson(saved.outcome) : null };
      }
    }
  }

  sockets.on('connection', socket => {
    // DEFENSE: Connection resets are reported at A and do not undo operations already admitted at B.
    socket.on('error', () => socket.terminate());
    socket.on('close', () => {
      for (const operation of active.values()) operation.listeners.delete(socket);
    });
    socket.on('message', async (bytes, binary) => {
      let request;
      try {
        if (binary) throw new TypeError('Shared execution expects JSON text');
        request = decode('effect.execution_request', bytes);
      // DEFENSE: External frames can be malformed or use a different protocol version.
      } catch {
        socket.close(1007, 'Invalid shared execution request');
        return;
      }
      try { send(socket, { id: request.id, result: await perform(socket, request) }); }
      // DEFENSE: A real operation error or filesystem refusal must be returned to the requesting peer.
      catch (error) { send(socket, { id: request.id, error: {
        code: error.code ?? 'shared_execution_failed', message: error.message,
      } }); }
    });
  });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, host, () => { server.off('error', reject); resolve(); });
    });
  // DEFENSE: An occupied port or invalid listener address must release receiver storage.
  } catch (error) { db.close(); throw error; }
  return { address: server.address(), async close() {
    const stopped = new Promise(resolve => server.close(resolve));
    for (const socket of sockets.clients) socket.terminate();
    const operations = [...active.values()];
    for (const operation of operations) operation.controller.abort();
    await Promise.allSettled(operations.map(operation => operation.result));
    await stopped;
    db.close();
  } };
}

class ExecutionPeer {
  #socket;
  #connecting;
  #pending = new Map();
  #output = new Map();

  constructor(environment) {
    this.environment = environment;
    this.url = new URL(environment.url);
  }

  async #connect() {
    if (this.#socket?.readyState === WebSocket.OPEN) return this.#socket;
    this.#connecting ??= this.#open().finally(() => { this.#connecting = undefined; });
    return this.#connecting;
  }

  async #open() {
    const { token_file, ca_file } = this.environment;
    const [token, ca] = await Promise.all([readToken(token_file), ca_file ? readFile(ca_file) : undefined]);
    const socket = new WebSocket(this.url, {
      headers: { Authorization: `Bearer ${token}` }, protocols: [protocol],
      tls: { ca, rejectUnauthorized: true }, perMessageDeflate: false,
    });
    const closed = () => {
      if (this.#socket === socket) this.#socket = undefined;
      for (const [id, request] of this.#pending) {
        if (request.socket !== socket) continue;
        this.#pending.delete(id);
        request.reject(fail('execution_disconnected', 'Shared execution connection closed'));
      }
    };
    socket.addEventListener('close', closed);
    socket.addEventListener('error', closed);
    socket.addEventListener('message', ({ data }) => {
      try {
        if (typeof data !== 'string' || Buffer.byteLength(data) > maximumFrame) {
          throw new TypeError('Shared execution expects bounded JSON text');
        }
        const reply = boundary('effect.execution_response', parseJson(data));
        if (reply.method === 'execution.output') {
          this.#output.get(reply.params.operation_id)?.(reply.params.output);
        } else {
          const request = this.#pending.get(reply.id);
          if (request?.socket !== socket) return;
          this.#pending.delete(reply.id);
          if (reply.error) request.reject(fail(reply.error.code, reply.error.message));
          else request.resolve(reply.result);
        }
      // DEFENSE: An incompatible or corrupted remote reply must not settle a local operation.
      } catch { socket.terminate(); }
    });
    const timer = setTimeout(() => socket.terminate(), 5000);
    try {
      await new Promise((resolve, reject) => {
        socket.addEventListener('open', resolve, { once: true });
        socket.addEventListener('error', error => reject(fail('execution_disconnected', error.message)), { once: true });
        socket.addEventListener('close', () => reject(fail('execution_disconnected', 'Shared execution connection closed')), { once: true });
      });
    } finally { clearTimeout(timer); }
    this.#socket = socket;
    return socket;
  }

  async request(method, params, signal) {
    signal?.throwIfAborted();
    const socket = await this.#connect();
    signal?.throwIfAborted();
    // DEFENSE: A socket can close after handshake and before its first request.
    if (socket.readyState !== WebSocket.OPEN) throw fail('execution_disconnected', 'Shared execution connection closed');
    const id = randomUUID();
    const reply = Promise.withResolvers();
    const abort = () => {
      this.#pending.delete(id);
      reply.reject(signal.reason);
    };
    this.#pending.set(id, { ...reply, socket });
    signal?.addEventListener('abort', abort, { once: true });
    try {
      send(socket, { id, method, params });
      return await reply.promise;
    } finally { signal?.removeEventListener('abort', abort); }
  }

  async #recover(method, params, signal) {
    try { return await this.request(method, params, signal); }
    // DEFENSE: A connection may close after the receiver commits. Reads and
    // same-ID starts can be resubmitted under the durable receipt contract.
    catch (error) {
      if (error.code !== 'execution_disconnected' || signal?.aborted) throw error;
      return this.request(method, params, signal);
    }
  }

  operation(operation_id, tool, arguments_, execution, { signal, onOutput, onDiagnostic }) {
    const handle = { operation_id };
    const update = text => onOutput?.(limit => Array.from(text).slice(-limit).join(''));
    this.#output.set(operation_id, update);
    const received = this.#recover('execution.start', { ...handle, tool, arguments: arguments_, execution }, signal);
    const cancel = () => void this.#recover('execution.cancel', handle).catch(error => onDiagnostic?.(error.message));
    signal?.addEventListener('abort', cancel, { once: true });
    const settled = received.then(() => this.#recover('execution.wait', handle, signal))
      .catch(error => {
        // DEFENSE: A lost result after dispatch leaves open the possibility of physical side effects.
        if (error.code === 'execution_disconnected') {
          throw fail('outcome_unknown', 'Shared execution may already have run before the connection failed');
        }
        throw error;
      });
    const result = settled.then(outcome => {
      if (outcome.error) throw fail(outcome.error.code, outcome.error.message);
      return outcome.value;
    }).finally(() => {
      signal?.removeEventListener('abort', cancel);
      this.#output.delete(operation_id);
    });
    return { result, read: cursor => received.then(() => this.#recover('execution.read', { ...handle, cursor }, signal)),
      write: input => received.then(() => this.request('execution.write', { ...handle, input }, signal)) };
  }

  filesystem(signal) {
    const realpath = path => this.#recover('execution.realpath', { path }, signal);
    const stat = path => this.#recover('execution.stat', { path }, signal).then(typed);
    const lstat = path => this.#recover('execution.lstat', { path }, signal).then(typed);
    const readdir = path => this.#recover('execution.readdir', { path, maximum: 32768 }, signal)
      .then(entries => entries.map(typed));
    const readFile = (path, { maximum }) => this.#recover('execution.read_file', { path, maximum }, signal)
      .then(bytes => Buffer.from(bytes, 'base64'));
    return { realpath, stat, lstat, readdir, opendir: readdir, readFile, close() {} };
  }

  close() { this.#socket?.terminate(); }
}

export class ExecutionEnvironments {
  #peers = new Map();
  constructor(settings) {
    for (const environment of settings) this.#peers.set(environment.id, new ExecutionPeer(environment));
  }
  get(id, signal) {
    const peer = this.#peers.get(id);
    // DEFENSE: A saved task can name an environment that has been removed from the current configuration.
    if (!peer) throw fail('execution_environment_unavailable', `Shared execution environment is unavailable: ${id}`);
    return { filesystem: peer.filesystem(signal), peer };
  }
  choices() {
    return [...this.#peers.keys()];
  }
  async readImage(operationId, arguments_, execution, options) {
    const { peer } = this.get(execution.workspace.environment, options.signal);
    const image = await peer.operation(operationId, 'read_image', arguments_, execution, options).result;
    return retainReadImage(options.home, { ...image, bytes: Buffer.from(image.bytes, 'base64') });
  }
  close() { for (const peer of this.#peers.values()) peer.close(); }
}

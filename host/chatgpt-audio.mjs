import { randomUUID } from 'node:crypto';
import { interpretAudioTransport } from './model-api.ts';
import { Impit } from 'impit';
import WebSocket from 'ws';
import { createAudioAccount } from './chatgpt-account.mjs';
import { boundary } from './public/model-boundary.mjs';

const contract = () => boundary('audio.contract', {});
// NOTE: The transcription gateway challenges Bun's HTTP/TLS profile for requests that succeed through Chromium's network stack.
const transcriptionClient = new Impit({ browser: 'chrome' });
const transcriptionFetch = transcriptionClient.fetch.bind(transcriptionClient);

async function responseText(response, maximum) {
  const reader = response.body?.getReader();
  if (!reader) return '';
  const chunks = [];
  let bytes = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      // DEFENSE: Provider replies cross the network boundary and can exceed the bounded transcription/control response budget.
      if (bytes > maximum) throw new Error('ChatGPT audio response exceeds the response budget');
      chunks.push(value);
    }
    return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
  } finally {
    try { await reader.cancel(); } finally { reader.releaseLock(); }
  }
}

function parsedJson(value) {
  // DEFENSE: Upstream gateways can return HTML or malformed JSON; native response admission receives absence instead of parser diagnostics containing raw response bytes.
  try { return JSON.parse(value); } catch { return null; }
}

function callIdentity(location) {
  // DEFENSE: An upstream Location header may be missing or malformed; only the observed final path component is admitted by the native response operation.
  try { return new URL(location, contract().calls_url).pathname.split('/').filter(Boolean).at(-1) ?? null; }
  catch { return null; }
}

function authHeaders(authorization) {
  return { ...authorization.headers, 'ChatGPT-Account-Id': authorization.account_id };
}

/** Audio credentials stay in this host interpreter; callers receive only connection identities and SDP. */
export function createChatGPTAudio({ home, fetchImpl = fetch,
  WebSocketImpl = WebSocket, authorityFactory = createAudioAccount, onEvent = async () => {} }) {
  const sessions = new Map();
  const operations = new Map();
  let closed = false, closing;
  const authority = authorityFactory({ home, onChange: onEvent });

  function track(id, signal, action) {
    if (closed) return Promise.reject(new Error('Audio host is closed'));
    const controller = new AbortController();
    const lifetime = AbortSignal.any([signal, controller.signal].filter(Boolean));
    const operation = { controller, promise: null };
    operation.promise = Promise.resolve().then(() => {
      lifetime.throwIfAborted();
      return action(lifetime);
    }).finally(() => { if (operations.get(id) === operation) operations.delete(id); });
    operations.set(id, operation);
    return operation.promise;
  }

  async function connection(id, signal) {
    const rows = await authority.connections({ signal });
    const selected = rows.find(item => item.id === id);
    const capability = boundary('audio.capability', selected ?? { id, authorized: false });
    const authorization = await authority.authorize(capability.id, { signal });
    return { source: capability.source, authorization };
  }

  async function capabilities({ signal } = {}) {
    const limits = contract();
    const lifetime = AbortSignal.any([signal, AbortSignal.timeout(limits.request_timeout_ms)].filter(Boolean));
    const rows = await authority.connections({ signal: lifetime });
    return { connections: boundary('audio.capabilities', { connections: rows }),
      asr_max_bytes: limits.asr_max_bytes, connect_timeout_ms: limits.connect_timeout_ms };
  }

  async function authenticatedFetch(url, options, selected, signal, send = fetchImpl) {
    let authorization = selected.authorization;
    let response = await send(url, { ...options, signal,
      headers: { ...authHeaders(authorization), ...options.headers } });
    // DEFENSE: An access token can expire after authorization and before the audio request; the existing account refresh serializes rotation and permits exactly one retry after a 401.
    if (boundary('audio.transport', { status: response.status, ok: response.ok }) === 'refresh') {
      await response.body?.cancel();
      authorization = await authorization.refreshAfterRejection({ signal });
      selected.authorization = authorization;
      response = await send(url, { ...options, signal,
        headers: { ...authHeaders(authorization), ...options.headers } });
    }
    return response;
  }

  async function transcribe({ connection: connectionId, audio, mime, language = null, signal }) {
    const limits = contract();
    const lifetime = AbortSignal.any([signal, AbortSignal.timeout(limits.request_timeout_ms)].filter(Boolean));
    const selected = await connection(connectionId, lifetime);
    const bytes = audio instanceof Blob ? audio.size : audio.byteLength;
    const plan = boundary('audio.asr_request', { connection: connectionId, source: selected.source, authorized: true, bytes, mime, language });
    const body = new FormData();
    body.append('file', new Blob([audio], { type: plan.mime }), plan.filename);
    if (plan.language !== null) body.append('language', plan.language);
    const response = await authenticatedFetch(limits.transcribe_url, { method: 'POST', body }, selected, lifetime, transcriptionFetch);
    const value = parsedJson(await responseText(response, limits.response_max_bytes));
    return boundary('audio.asr_response', { status: response.status, value });
  }

  async function createSession({ connection: connectionId, task_id, sdp, id = randomUUID(), generation = randomUUID(), initial_items = [], signal }) {
    const limits = contract();
    const lifetime = AbortSignal.any([signal, AbortSignal.timeout(limits.connect_timeout_ms)].filter(Boolean));
    const selected = await connection(connectionId, lifetime);
    const body = boundary('audio.session_request', { connection: connectionId, source: selected.source, authorized: true,
      task_id, sdp, id, initial_items });
    const sessionHeaders = boundary('control.audio.headers', { task_id, id });
    const response = await authenticatedFetch(limits.calls_url, { method: 'POST', body: JSON.stringify(body),
      headers: { 'content-type': 'application/json', ...sessionHeaders } }, selected, lifetime);
    const answer = boundary('audio.session_response', { status: response.status,
      sdp: await responseText(response, limits.response_max_bytes), call_id: callIdentity(response.headers.get('location')) });
    const activation = boundary('control.audio.transport_initial', { id, task_id, generation });
    let finish;
    const record = { id, task_id, socket: null, retryTimer: null, call_id: answer.call_id,
      state: activation.state, finished: new Promise(resolve => { finish = resolve; }) };
    Object.defineProperties(record, {
      closed: { get: () => record.state.phase !== 'live' },
    });
    sessions.set(id, record);
    // Every physical arrival installs its model state before any asynchronous
    // primitive starts. Only the extracted FIFO chooses the next emission.
    const observe = observation => {
      const result = boundary('control.audio.transport_step', { state: record.state, observation });
      record.state = result.state;
      drive(result.actions);
      if (record.state.phase === 'closed') finish();
    };
    const cleanup = () => {
      signal?.removeEventListener('abort', abort);
      lifetime.removeEventListener('abort', startupAbort);
      if (sessions.get(id) === record) sessions.delete(id);
      clearTimeout(record.retryTimer);
      const socket = record.socket;
      if (socket?.readyState === 1) {
        try { socket.send(JSON.stringify({ type: 'session.close' })); } finally { socket.close(); }
      }
      else if (socket?.readyState === 0) socket.terminate();
    };
    function drive(actions) {
      for (const begin of actions) void interpretAudioTransport(begin, {
        ready: () => lifetime.removeEventListener('abort', startupAbort),
        emit: event => onEvent(event),
        close: async () => { cleanup(); },
        connect: attempt => connectSideband(attempt),
        retry: (attempt, delay) => {
          record.retryTimer = setTimeout(() => observe({ kind: 'retry', attempt }), Number(delay));
        },
        ack: token => observe({ kind: 'ack', token }),
        failed: token => observe({ kind: 'failed', token }),
      });
    }
    const terminate = error => observe({ kind: 'stop', message: error?.message ?? '' });
    const abort = () => terminate(signal.reason);
    const startupAbort = () => observe({ kind: 'startup_timeout', message: lifetime.reason?.message ?? '' });
    signal?.addEventListener('abort', abort, { once: true });
    lifetime.addEventListener('abort', startupAbort, { once: true });
    record.stop = terminate;
    function connectSideband(attempt) {
      const socket = new WebSocketImpl(`${limits.sideband_base}${encodeURIComponent(answer.call_id)}`, {
        headers: { ...authHeaders(selected.authorization), ...sessionHeaders, 'x-session-id': id }, maxPayload: limits.event_max_bytes,
      });
      record.socket = socket;
      socket.on('unexpected-response', (_request, response) => {
        observe({ kind: 'upgrade', attempt, status: response.statusCode });
        response.destroy(); socket.terminate();
      });
      socket.addEventListener('open', () => observe({ kind: 'open', attempt }));
      socket.addEventListener('message', message => {
        let value;
        // DEFENSE: Provider frames are external UTF-8/JSON input. A malformed
        // frame retires this call rather than entering the semantic event FIFO.
        try {
          const raw = typeof message.data === 'string' ? message.data : new TextDecoder('utf-8', { fatal: true }).decode(message.data);
          value = parsedJson(raw);
          if (value === null) throw new Error('ChatGPT voice control returned invalid JSON');
        } catch (error) { observe({ kind: 'error', attempt, message: error.message }); return; }
        observe({ kind: 'message', attempt, value });
      });
      socket.addEventListener('error', event => observe({ kind: 'error', attempt,
        message: `ChatGPT voice control connection failed${event.message ? `: ${event.message}` : ''}` }));
      socket.addEventListener('close', event => observe({ kind: 'close', attempt, code: event.code }));
    }
    drive(activation.actions);
    if (lifetime.aborted) {
      startupAbort(); await record.finished; throw lifetime.reason;
    }
    if (closed) {
      const error = new Error('Audio host is closed');
      terminate(error); await record.finished; throw error;
    }
    return { id, ...answer };
  }

  async function appendContext(id, source) {
    const record = sessions.get(id);
    // DEFENSE: Accepted task work outlives a hung-up voice call; an absent control session has no context receiver and does not cancel that work.
    if (!record || record.closed) return false;
    const content = boundary('audio.context', source);
    const maximum = contract().context_chunk_bytes;
    let chunk = '', bytes = 0;
    const send = text => record.socket.send(JSON.stringify({ ...content,
      content: [{ ...content.content[0], text }] }));
    // Keep complete code points while staying below the Live context message limit.
    // This byte budget is our conservative transport policy, not a text limit on a Task.
    for (const character of content.content[0].text) {
      const width = Buffer.byteLength(character);
      if (bytes + width > maximum) { send(chunk); chunk = ''; bytes = 0; }
      chunk += character;
      bytes += width;
    }
    if (chunk) send(chunk);
    return true;
  }

  async function stopSession(id) {
    const pending = operations.get(id);
    const record = sessions.get(id);
    if (!pending && !record) return false;
    pending?.controller.abort(new Error('Voice session stopped'));
    record?.stop();
    // A stop owns cancellation of its in-flight create; the create caller receives
    // that rejection while this caller waits for physical cleanup.
    if (pending) await Promise.allSettled([pending.promise]);
    if (record) await record.finished;
    return true;
  }

  function close() {
    return closing ??= (async () => {
      closed = true;
      const pending = [...operations.values()];
      for (const operation of pending) operation.controller.abort(new Error('Audio host is closed'));
      const released = await Promise.allSettled([
        authority.close(),
        ...[...sessions.values()].map(record => stopSession(record.id)),
        ...pending.map(operation => operation.promise.then(() => {}, error => {
          // The owner close cancelled these operations; their callers already receive the cancellation rejection.
          if (!operation.controller.signal.aborted) throw error;
        })),
      ]);
      const failed = released.find(result => result.status === 'rejected');
      if (failed) throw failed.reason;
    })();
  }

  return {
    capabilities: (options = {}) => track(`capabilities:${randomUUID()}`, options.signal,
      signal => capabilities({ ...options, signal })),
    transcribe: options => track(`transcribe:${randomUUID()}`, options.signal,
      signal => transcribe({ ...options, signal })),
    createSession: options => {
      const id = options.id ?? randomUUID();
      return track(id, options.signal, signal => createSession({ ...options, id, signal }));
    },
    startLogin: (options = {}) => track(`login:${randomUUID()}`, options.signal,
      signal => authority.startLogin({ ...options, signal })),
    appendContext, stopSession, close,
  };
}

import { randomUUID } from 'node:crypto';
import WebSocket from 'ws';
import { createCodexAudioAccount } from './codex-audio-account.mjs';
import { boundary } from './public/model-boundary.mjs';

const contract = () => boundary('audio.contract', {});

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
export function createChatGPTAudio({ home, command, fetchImpl = fetch,
  WebSocketImpl = WebSocket, authorityFactory = createCodexAudioAccount, onEvent = async () => {} }) {
  const sessions = new Map();
  const operations = new Map();
  let closed = false, closing;
  const authority = authorityFactory({ home, command,
    onChange: () => onEvent({ type: 'account_changed' }) });

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
    let rows, unavailable = [];
    try { rows = await authority.connections({ signal: lifetime }); }
    catch (error) {
      lifetime.throwIfAborted();
      // DEFENSE: The official authentication component can be missing or fail its public RPC; report this as unavailable instead of advertising audio from an unrelated grant.
      unavailable = [{ label: 'ChatGPT', error: error.message }];
      rows = [];
    }
    return { connections: boundary('audio.capabilities', { connections: rows }), unavailable,
      asr_max_bytes: limits.asr_max_bytes, connect_timeout_ms: limits.connect_timeout_ms };
  }

  async function authenticatedFetch(url, options, selected, signal) {
    let authorization = selected.authorization;
    let response = await fetchImpl(url, { ...options, signal,
      headers: { ...authHeaders(authorization), ...options.headers } });
    // DEFENSE: An access token can expire after authorization and before the audio request; the existing account refresh serializes rotation and permits exactly one retry after a 401.
    if (boundary('audio.transport', { status: response.status, ok: response.ok }) === 'refresh') {
      await response.body?.cancel();
      authorization = await authorization.refreshAfterRejection({ signal });
      selected.authorization = authorization;
      response = await fetchImpl(url, { ...options, signal,
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
    const response = await authenticatedFetch(limits.transcribe_url, { method: 'POST', body }, selected, lifetime);
    const value = parsedJson(await responseText(response, limits.response_max_bytes));
    return boundary('audio.asr_response', { status: response.status, value });
  }

  async function createSession({ connection: connectionId, task_id, sdp, id = randomUUID(), initial_items = [], signal }) {
    const limits = contract();
    const lifetime = AbortSignal.any([signal, AbortSignal.timeout(limits.connect_timeout_ms)].filter(Boolean));
    const selected = await connection(connectionId, lifetime);
    const body = boundary('audio.session_request', { connection: connectionId, source: selected.source, authorized: true,
      task_id, sdp, id, initial_items });
    const sessionHeaders = { 'OpenAI-Alpha': 'quicksilver=v2', 'Thread-Id': String(task_id), 'Session-Id': id };
    const response = await authenticatedFetch(limits.calls_url, { method: 'POST', body: JSON.stringify(body),
      headers: { 'content-type': 'application/json', ...sessionHeaders } }, selected, lifetime);
    const answer = boundary('audio.session_response', { status: response.status,
      sdp: await responseText(response, limits.response_max_bytes), call_id: callIdentity(response.headers.get('location')) });
    const record = { id, task_id, socket: null, retryTimer: null, call_id: answer.call_id, closed: false,
      tails: new Map(), turns: new Map(), pending: new Map(), sequence: 0, queue: Promise.resolve(), ready: false };
    sessions.set(id, record);
    const emit = event => onEvent({ session_id: id, task_id, ...event });
    const transcript = (event, completion) => emit({ ...event, type: 'transcript',
      item_id: event.item_id || `${id}:${++record.sequence}`, completion, final: true });
    const markReady = async () => {
      if (record.ready || record.closed) return;
      record.ready = true;
      lifetime.removeEventListener('abort', startupAbort);
      await emit({ type: 'ready' });
    };
    const enqueue = action => {
      record.queue = record.queue.then(action).catch(error => {
        // DEFENSE: A malformed provider event or a rejected journal commit ends this control connection; continuing would lose the correspondence between voice observations and accepted task input.
        terminate(error);
      });
    };
    function terminate(error) {
      if (record.closed) return;
      record.closed = true;
      signal?.removeEventListener('abort', abort);
      lifetime.removeEventListener('abort', startupAbort);
      sessions.delete(id);
      clearTimeout(record.retryTimer);
      const socket = record.socket;
      if (socket?.readyState === 1) { socket.send(JSON.stringify({ type: 'session.close' })); socket.close(); }
      else if (socket?.readyState === 0) socket.terminate();
      record.queue = record.queue.then(async () => {
        for (const [role, text] of record.tails) {
          if (text) await transcript({ role, text, remaining: '' }, 'interrupted');
        }
        record.tails.clear();
        for (const pending of record.pending.values()) await emit({ type: 'error', error: 'Voice delegation is missing its referenced user turn', item_id: pending.item?.id ?? pending.item_id });
        record.pending.clear();
        if (error) await emit({ type: 'error', error: error.message });
        await emit({ type: 'closed' });
      });
    }
    const abort = () => terminate(signal.reason ?? new Error('Voice cancelled'));
    const startupAbort = () => { if (!record.ready) terminate(lifetime.reason); };
    signal?.addEventListener('abort', abort, { once: true });
    lifetime.addEventListener('abort', startupAbort, { once: true });
    record.stop = terminate;
    const receiveMessage = message => {
      if (record.closed) return;
      enqueue(async () => {
        const raw = typeof message.data === 'string' ? message.data : new TextDecoder('utf-8', { fatal: true }).decode(message.data);
        const value = parsedJson(raw);
        if (value === null) throw new Error('ChatGPT voice control returned invalid JSON');
        const source = () => ({ value, turns: [...record.turns].map(([turn_id, text]) => ({ turn_id, text })) });
        const event = boundary('audio.event', source());
        if (event === null) return;
        switch (event.type) {
          case 'ready':
            await markReady();
            break;
          case 'delta':
            record.tails.set(event.role, (record.tails.get(event.role) ?? '') + event.text);
            await emit(event);
            break;
          case 'transcript': {
            const remaining = boundary('audio.transcript_tail', {
              pending: record.tails.get(event.role) ?? '', completed: event.text,
            });
            if (remaining) record.tails.set(event.role, remaining);
            else record.tails.delete(event.role);
            if (event.role === 'user' && event.item_id) record.turns.set(event.item_id, event.text);
            await transcript({ ...event, remaining }, 'completed');
            break;
          }
          case 'turn':
            record.turns.set(event.turn_id, event.text);
            record.tails.set('user', event.text);
            break;
          case 'delegation_pending':
            record.pending.set(event.item_id, value);
            break;
          case 'delegation':
            record.pending.delete(event.item_id);
            await emit({ ...event, delegation_id: event.item_id });
            break;
          case 'error': throw new Error(event.error);
        }
        for (const [itemId, pending] of record.pending) {
          const resolved = boundary('audio.event', { ...source(), value: pending });
          if (resolved.type === 'delegation') {
            record.pending.delete(itemId);
            await emit({ ...resolved, delegation_id: resolved.item_id });
          }
        }
      });
    };
    const activationDelays = [100, 300, 800];
    let activationAttempt = 0;
    function connectSideband() {
      const socket = new WebSocketImpl(`${limits.sideband_base}${encodeURIComponent(answer.call_id)}`, {
        headers: { ...authHeaders(selected.authorization), ...sessionHeaders, 'x-session-id': id }, maxPayload: limits.event_max_bytes,
      });
      record.socket = socket;
      let rejectedUpgrade = false;
      socket.on('unexpected-response', (_request, response) => {
        rejectedUpgrade = true;
        const status = response.statusCode;
        response.destroy();
        socket.terminate();
        // DEFENSE: Instant Connect can return404 before Chrome ICE activates the call. Retry only this documented upgrade status, without waiting for the gateway error body (observed to delay six seconds).
        if (status === 404 && activationAttempt < activationDelays.length) {
          record.retryTimer = setTimeout(() => {
            record.retryTimer = null;
            if (!record.closed) connectSideband();
          }, activationDelays[activationAttempt++]);
          return;
        }
        terminate(new Error(`ChatGPT voice control connection failed (HTTP ${status})`));
      });
      // ExistingCall already has its media session configuration; the official controller returns after the successful upgrade without waiting for a replayed session.started.
      socket.addEventListener('open', () => { if (!record.closed) enqueue(markReady); });
      socket.addEventListener('message', receiveMessage);
      socket.addEventListener('error', event => {
        if (!rejectedUpgrade && !record.closed) terminate(new Error(`ChatGPT voice control connection failed${event.message ? `: ${event.message}` : ''}`));
      });
      socket.addEventListener('close', event => {
        if (!rejectedUpgrade) terminate(event.code === 1000 || record.closed ? undefined
          : new Error(`ChatGPT voice control connection closed (${event.code})`));
      });
    }
    connectSideband();
    if (lifetime.aborted) {
      startupAbort();
      await record.queue;
      throw lifetime.reason;
    }
    if (closed) {
      const error = new Error('Audio host is closed');
      terminate(error);
      await record.queue;
      throw error;
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
    if (record) await record.queue;
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

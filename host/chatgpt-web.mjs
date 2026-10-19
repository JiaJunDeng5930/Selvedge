import { createHash } from 'node:crypto';
import { stringifyJson } from './codec.mjs';
import { emitJsonTokens } from './public/json-tokens.mjs';
import { boundary, observeJson } from './public/model-boundary.mjs';
import { readText, sseEvents, requestJson } from './network.mjs';
import { prepareModelRequest, requestHeaders } from './model-request.mjs';
import { WebRequestStore, retainedRequest } from './chatgpt-web-store.mjs';

const digest = value => createHash('sha256').update(stringifyJson(value)).digest('hex');
const requestOwner = effect => boundary('web.owner', { effect });

function nativeJson(text) {
  return boundary('web.decode', { observation: observeJson(text), text });
}

function failure(code, record, status) {
  const value = boundary('web.failure', { code, record, status });
  const error = retainedRequest(record);
  error.code = value.code;
  error.message = value.message;
  return error;
}

function credential(profile) {
  const token = process.env[profile.api_key_env];
  // DEFENSE: The configured API token environment variable can be unset; never dispatch an unauthenticated retained request.
  if (!token) throw new Error(`Set ${profile.api_key_env} to use this provider`);
  return { token, binding: digest([profile.endpoint, token]) };
}

function toolsFor(effect) { return boundary('web.tools', { effect }); }
function validateResource(value, body, model, tools) {
  return boundary('web.resource', { value, body, model, tools });
}

async function exchange(record, body, model, tools, token, store, limits, lifetime, { onSnapshot, onRetry }, index) {
  // A newly prepared receipt has no response yet; the native exchange selects fetching before cached-response decoding.
  const start = boundary('web.exchange_start', { record, body, model, tools, index,
    response_observation: record.response === null ? null : observeJson(record.response) });
  if (start.action === 'cached') return start.resource;
  const send = async () => {
    const response = await fetch(record.endpoint, { method: 'POST', redirect: 'error', signal: lifetime,
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', accept: 'text/event-stream', 'idempotency-key': record.request_key },
      body: record.body });
    try {
      const id = response.headers.get('x-response-id');
      if (id) store.identify(record, id);
      boundary('web.headers', { version: response.headers.get('x-web-protocol'), content_type: 'text/event-stream' });
      return response;
    } catch (error) {
      // DEFENSE: A receipt write or protocol-header rejection leaves an unread HTTP body; cancel it before propagating the failure.
      await response.body?.cancel();
      throw error;
    }
  };
  const response = await requestHeaders(send, limits.model_retry, lifetime, onRetry);
  // DEFENSE: HTTP rejection may carry HTML or an empty proxy error body; only admitted JSON supplies an optional provider error code.
  if (!response.ok) {
    if (boundary('web.http', { record, status: response.status }).reject) store.reject(record);
    const text = await readText(response.body, limits.frame_bytes);
    const observation = observeJson(text);
    const value = observation.error ? undefined : boundary('web.decode', { observation, text });
    throw failure(value?.error?.code, record, response.status);
  }
  let contentType;
  try {
    contentType = boundary('web.headers', { version: response.headers.get('x-web-protocol'),
      content_type: response.headers.get('content-type') });
  // DEFENSE: A mismatched protocol or unsupported content type must release the unread response before failing this observer.
  } catch (error) { await response.body?.cancel(); throw error; }
  let terminal;
  if (contentType === 'json') {
    terminal = validateResource(nativeJson(await readText(response.body, limits.frame_bytes)), body, model, tools);
  } else if (contentType === 'sse') {
    for await (const frame of sseEvents(response.body, limits.frame_bytes)) {
      const observation = observeJson(frame.data);
      const event = boundary('web.frame', { frame, observation });
      const tokens = [];
      emitJsonTokens(event, token => tokens.push(token));
      // NOTE: Capture the actual external parser output, including its object-key semantics.
      const parsed_observation = { text: frame.data, tokens };
      const source = { frame, observation, parsed_observation, record, body, model, tools, index };
      const header = boundary('web.event_header', source);
      if (header.action === 'stop') break;
      if (header.response_id) store.identify(record, header.response_id);
      const action = boundary('web.event', source);
      if (action.action === 'stop') break;
      if (action.action === 'snapshot') onSnapshot(action.text, action.index);
      else if (action.action === 'terminal') { terminal = action.resource; break; }
      // DEFENSE: A provider failure event retains the request identity and cannot be accepted as a completed response.
      else if (action.action === 'failure') throw failure(action.code, record);
    }
  }
  // DEFENSE: A disconnected stream or nonterminal resource leaves remote work unresolved; retain its original key instead of posting again.
  if (boundary('web.exchange_result', { resource: terminal, record, body, model, tools, index }).retained) throw retainedRequest(record);
  store.identify(record, terminal.id);
  const commit = boundary('web.commit', { resource: terminal, record, body, model, tools });
  // DEFENSE: An admitted terminal response can report provider failure; preserve its receipt rather than returning output as success.
  if (commit.action === 'failure') throw failure(commit.code, record);
  store.finish(record, terminal);
  return terminal;
}

export async function requestChatGPTWeb(effect, profile, home, limits, { signal, onSnapshot = () => {}, onRetry = () => {} } = {}) {
  signal?.throwIfAborted();
  const request = prepareModelRequest(effect);
  const options = boundary('web.options', { effect, profile, limits });
  const tools = toolsFor(request);
  const contract = digest(boundary('web.contract', { effect, request, tools }));
  const { token, binding } = credential(profile);
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(profile.timeout_ms)]) : AbortSignal.timeout(profile.timeout_ms);
  const owner = requestOwner(effect);
  const store = await WebRequestStore.open(home);
  let active;
  try {
    lifetime.throwIfAborted();
    const previous = store.latest(owner);
    // NOTE: Independent approval and board effects acquire their history in
    // backend.prepare. Cursor selection and prefix hashes use that same input.
    const position = boundary('web.position', { effect: request });
    const continuation = boundary('web.continuation', { effect: request, profile, limits, previous: previous ?? null,
      request, tools, owner, store_identity: store.identity, contract, binding,
      receipt_position: position.position,
      history_digest: digest(request.history.slice(0, Number(position.input_count))) });
    let { body, deferred } = continuation;
    const output = [];
    let terminal;
    // A tool-result batch cannot contain messages. If it completes the page
    // turn, deliver retained messages in one explicit successor before settling
    // this effect. If it asks for more tools, keep them in the opaque receipt.
    // No caller tool is executed here, and no unknown request is given a new key.
    for (let stage = 0; stage < options.stages; stage++) {
      lifetime.throwIfAborted();
      boundary('web.request_bounds', { effect, profile, body, deferred, limits });
      const reset = continuation.reset;
      active = store.prepare(boundary('web.invocation', { effect, profile, owner, stage, binding, body, reset }));
      terminal = await exchange(active, body, effect.model.name, tools, token, store, limits, lifetime, {
        onRetry, onSnapshot: options.snapshots ? onSnapshot : () => {},
      }, stage);
      const settled = boundary('web.settle', { effect, resource: terminal, deferred, body, index: stage });
      if (options.snapshots) onSnapshot(settled.snapshot, stage);
      output.push(...settled.items);
      body = settled.body;
      deferred = settled.deferred;
      if (settled.continue) continue;
      break;
    }
    if (options.receipt) output.push({ type: 'context', part: 2, value: boundary('web.receipt', {
      effect: request, profile, resource: terminal, record: active, deferred,
      input_hash: digest(request.history), output_count: output.length, contract, binding, store_identity: store.identity,
      tools, body_observation: nativeJson(active.body), response_observation: nativeJson(active.response),
    }) });
    return output;
  } catch (error) {
    // DEFENSE: Failure after the durable request was prepared can leave unknown remote work; expose the retained key without upstream secrets.
    if (boundary('web.catch', { record: active ?? null, error: { request_key: error.requestKey } }).retained) {
      const retained = retainedRequest(active);
      retained.cause = error;
      throw retained;
    }
    throw error;
  } finally { store.close(); }
}

// Explicit recovery never resends a browser prompt. An observer can then retry
// the same committed effect/key to receive the retained response.
export async function chatgptWebRequestAction(key, action, config, home, limits, { signal, confirm = false, timeout } = {}) {
  boundary('web.recovery_shape', { key, action, confirm });
  const store = await WebRequestStore.open(home, { create: false });
  // DEFENSE: Recovery accepts a user-supplied key even when no provider request has ever created the receipt database.
  if (!store) throw new Error('No ChatGPT Web request receipts');
  try {
    const record = store.find(key);
    // DEFENSE: A user-supplied recovery key may not name any retained request in this service home.
    if (!record) throw new Error('Unknown ChatGPT Web request key');
    const profile = config.profiles[record.profile];
    boundary('web.recovery_connection', { key, action, confirm, record, profile });
    const { token, binding } = credential(profile);
    const recovery = boundary('web.recovery', { key, action, confirm, record, profile, binding });
    if (recovery.retire) store.retire(record);
    // DEFENSE: Recovery cannot send a remote control request before the provider has supplied a response ID.
    if (recovery.retained) throw retainedRequest(record);
    const url = `${record.endpoint}/${encodeURIComponent(record.response_id)}${recovery.method === 'GET' ? '' : `/${action}`}`;
    const response = await requestJson(url, { method: recovery.method,
      body: recovery.method === 'GET' ? undefined : recovery.body,
      headers: { authorization: `Bearer ${token}` }, signal, timeout: timeout ?? profile.timeout_ms, maximum: limits.frame_bytes });
    const value = response.ok ? nativeJson(response.text) : response.value;
    // DEFENSE: An HTTP failure from the recovery endpoint leaves the retained request available for explicit later action.
    if (!response.ok) throw failure(value?.error?.code, record, response.status);
    return boundary('web.recovery_result', { key, action, confirm, record, profile, binding, value });
  } finally { store.close(); }
}

export async function cancelChatGPTWeb(task, config, home, limits) {
  const selected = boundary('web.cancel_owner', { task });
  const record = WebRequestStore.retireExisting(home, selected.owner, selected.ticket);
  const action = boundary('web.cancellation', { task, record: record ?? null });
  if (action === 'none') return;
  // DEFENSE: A cancelled request without an admitted remote response ID remains retained; it cannot target the provider's stop endpoint.
  if (action === 'retained') throw retainedRequest(record);
  return chatgptWebRequestAction(record.request_key, 'cancel', config, home, limits, { timeout: 5000 });
}

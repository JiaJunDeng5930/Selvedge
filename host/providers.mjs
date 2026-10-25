import { createHash } from 'node:crypto';
import { parseJson, stringifyJson } from './codec.mjs';
import { events, readText } from './network.mjs';
import { authorize } from './chatgpt-account.mjs';
import { boundary } from './public/model-boundary.mjs';
import { requestHeaders } from './model-request.mjs';
import { imageDataURL } from './files.mjs';
import { requestChatGPTWeb, cancelChatGPTWeb } from './chatgpt-web.mjs';
import { observeMarkdownFences, observeTextItems } from './public/markdown-fence-observation.mjs';

// Transport abort detaches an observer. A committed native cancellation also
// stops retained remote work where the provider has an explicit stop endpoint.
export function cancelModelTask(task, config, home, limits) {
  return cancelChatGPTWeb(task, config, home, limits);
}

function parseErrorBody(text) {
  try { return parseJson(text); }
  // DEFENSE: Upstream HTTP errors can contain HTML or an empty body rather than a structured provider code.
  catch (error) { if (error instanceof SyntaxError) return null; throw error; }
}

export class ContextLimitError extends Error {
  constructor() {
    super('Model rejected the request with context_length_exceeded');
    this.name = 'ContextLimitError';
  }
}

export class ContextScopeChangedError extends Error {
  constructor(scope) {
    super('The model context consumer changed before dispatch');
    this.name = 'ContextScopeChangedError';
    this.scope = scope;
  }
}

export function providerOutput(output, profile = {}, output_indices = []) {
  const markdown_observations = Array.isArray(output) ? output.map(item => {
    if (item?.type !== 'message' || item.role !== 'assistant' || !Array.isArray(item.content)) return [];
    const text = item.content.map(part => {
      if (part?.type === 'output_text') return typeof part.text === 'string' ? part.text : '';
      if (part?.type === 'refusal') return typeof part.refusal === 'string' ? part.refusal : '';
      return '';
    }).join('');
    return observeMarkdownFences(text);
  }) : [];
  return boundary('backend.output', { output, profile, output_indices, markdown_observations });
}

export function responseBody(effect, profile = { provider: effect.model.provider }) {
  return boundary('backend.request', { effect, profile });
}

// Keep the encoded bytes beside the value observed by the native meter. The
// dispatchers send this body directly rather than reconstructing the request.
export function prepareProviderRequest(request) {
  const body = stringifyJson(request);
  return Object.freeze({ request, body, bytes: Buffer.byteLength(body) });
}

// Native plans retain asset identities. Only this transport interpreter creates data URLs.
export async function prepareModelRequest(request, home, limits) {
  const assets = [];
  const slots = [];
  for (const item of request.input ?? []) {
    const parts = item.type === 'function_call_output' ? item.output : item.content;
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (part?.type === 'input_image' && part.image_asset) {
        assets.push(part.image_asset);
        slots.push(part);
      }
    }
  }
  const planned = prepareProviderRequest(request);
  // The ordinary frame budget still bounds every non-image byte in the plan.
  boundary('backend.request_size', { bytes: planned.bytes, limits });
  boundary('backend.image_request_budget', { assets });
  const urls = await Promise.all(assets.map(asset => imageDataURL(home, asset)));
  const images = new Map(slots.map((slot, index) => [slot, urls[index]]));
  const input = (request.input ?? []).map(item => {
    const key = item.type === 'function_call_output' ? 'output' : 'content';
    if (!Array.isArray(item[key])) return item;
    return { ...item, [key]: item[key].map(part => {
      if (!images.has(part)) return part;
      const { image_asset, ...fields } = part;
      return { ...fields, image_url: images.get(part) };
    }) };
  });
  const wire = slots.length ? { ...request, input } : request;
  const body = stringifyJson(wire);
  const prepared = Object.freeze({ request, body, bytes: Buffer.byteLength(body) });
  guardProviderRequest(prepared, limits);
  return prepared;
}

function guardProviderRequest(prepared, limits) {
  // DEFENSE: User history and external tool output can make the encoded provider request exceed the configured HTTP byte budget.
  boundary('backend.request_size', { bytes: prepared.bytes, limits, request: { input: prepared.request.input } });
}

// Resolve the complete consumer before selecting opaque input. API-key identity
// stays within the target digest, so rotating one credential reference also
// invalidates its old receipts without sending credential bytes into the domain state.
export async function providerSession(effect, config, home, options = {}) {
  const configured = config.profiles[effect.model.profile];
  const backend = boundary('backend.support', { effect, profile: configured });
  return createProviderSession(effect, configured, backend, home, options);
}

async function createProviderSession(effect, configured, backend, home, { signal } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(configured.timeout_ms)]) : AbortSignal.timeout(configured.timeout_ms);
  let authorization;
  let credential = null;
  const headers = { 'content-type': 'application/json' };
  if (backend.auth === 'account') {
    authorization = await authorize(configured, home, { signal: lifetime });
    boundary('backend.authorization', { profile: configured, authorization: { account_id: authorization.account_id } });
    Object.assign(headers, authorization.headers);
  } else if (backend.auth === 'environment') {
    const key = process.env[configured.api_key_env];
    boundary('backend.credentials', { profile: configured, key });
    credential = key;
    headers.authorization = `Bearer ${key}`;
  }
  const scope = authorization ? boundary('backend.compaction_scope', { profile: configured,
    account_id: authorization.account_id, model: effect.model.name }) : createHash('sha256')
    .update(JSON.stringify([configured.provider, configured.endpoint ?? null, effect.model.profile, effect.model.name, credential]))
    .digest('hex');
  const profile = { ...configured, scope };
  return { profile, backend, scope, lifetime, headers, home,
    account: Boolean(authorization),
    refresh: async () => {
      authorization = await authorization.refreshAfterRejection({ signal: lifetime });
      Object.assign(headers, authorization.headers);
    },
  };
}

export async function requestProviderJSON(session, suffix, prepared, limits, { onRetry = () => {} } = {}) {
  const { body } = prepared;
  guardProviderRequest(prepared, limits);
  const send = () => fetch(`${session.profile.endpoint}${suffix}`, { method: 'POST',
    headers: { ...session.headers, accept: 'application/json' }, body, signal: session.lifetime, redirect: 'error' });
  let response = await requestHeaders(send, limits.model_retry, session.lifetime, onRetry);
  const observation = refreshed => ({ status: response.status, ok: response.ok,
    authorization: session.account, refreshed });
  // DEFENSE: An account token can be rejected with HTTP 401; refresh once and surface a repeated rejection.
  if (boundary('backend.compaction_headers', observation(false)) === 'refresh') {
    await response.body?.cancel();
    await session.refresh();
    response = await send();
  }
  const text = await readText(response.body, limits.frame_bytes);
  const value = response.ok ? parseJson(text) : parseErrorBody(text);
  // DEFENSE: Non-success compaction HTTP responses must not be returned as successful JSON results.
  if (boundary('backend.compaction_headers', observation(true)) === 'read_error') {
    const failure = boundary('backend.http_failure', { status: response.status,
      code: value?.error?.code, output_started: false });
    // DEFENSE: Only an explicit pre-output context_length_exceeded rejection authorizes native context recovery.
    if (failure.recoverable) throw new ContextLimitError();
    const error = new Error(failure.message);
    error.status = response.status;
    error.provider_code = value?.error?.code;
    throw error;
  }
  return value;
}

export function observeCompactionScope(effect, scope) {
  const { kind, context_selected, context_scope } = effect;
  return boundary('backend.compaction_scope_changed', { effect: { kind, context_selected, context_scope }, scope });
}

export async function requestModel(effect, config, home, limits, { signal, onDelta = () => {}, onSnapshot = () => {}, onRetry = () => {}, onObservation = () => {} } = {}) {
  signal?.throwIfAborted();
  const configured = config.profiles[effect.model.profile];
  const support = boundary('backend.support', { effect, profile: configured });
  if (support.transport === 'web') {
    return requestChatGPTWeb(effect, configured, home, limits, { signal, onSnapshot, onRetry });
  }
  if (support.transport === 'echo') {
    const items = boundary('backend.echo', { history: effect.history });
    return boundary('backend.observe_text_output', { items, markdown_observations: observeTextItems(items) });
  }
  const session = await createProviderSession(effect, configured, support, home, { signal });
  const { profile, scope } = session;
  const consumer = observeCompactionScope(effect, scope);
  // DEFENSE: Credentials can rotate after context selection; old opaque context must not be dispatched to the new consumer.
  if (consumer.scope_changed) throw new ContextScopeChangedError(scope);
  const prepared = await prepareModelRequest(responseBody(effect, profile), home, limits);
  return requestProviderSSE(session, effect, prepared, limits, { onDelta, onRetry, onObservation });
}

// Model inference and compaction share the same physical SSE transport. A
// compaction caller passes the very session and request used for its meter.
export async function requestProviderSSE(session, effect, prepared, limits,
  { onDelta = () => {}, onRetry = () => {}, onObservation = () => {} } = {}) {
  const { profile, backend, scope, lifetime } = session;
  lifetime.throwIfAborted();
  const { body } = prepared;
  guardProviderRequest(prepared, limits);
  const headers = { ...session.headers, accept: 'text/event-stream' };
  const send = () => fetch(profile.endpoint, { method: 'POST', headers, body, signal: lifetime, redirect: 'error' });
  let response = await requestHeaders(send, limits.model_retry, lifetime, onRetry);
  let admission = boundary('backend.http_headers', {
    status: response.status, ok: response.ok, content_type: response.headers.get('content-type'),
    authorization: session.account, refreshed: false,
  });
  // DEFENSE: Account-backed inference can receive HTTP 401 after token rejection; refresh exactly once before reading the final response.
  if (admission.action === 'refresh') {
    await response.body?.cancel();
    await session.refresh();
    Object.assign(headers, session.headers);
    response = await send();
    admission = boundary('backend.http_headers', {
      status: response.status, ok: response.ok, content_type: response.headers.get('content-type'),
      authorization: true, refreshed: true,
    });
  }
  if (admission.action === 'read_error') {
    const errorBody = await readText(response.body, limits.frame_bytes);
    // DEFENSE: Proxies can return HTML/empty HTTP error bodies; absent JSON must not invent a context-limit recovery code.
    const upstream = parseErrorBody(errorBody);
    admission = boundary('backend.http_failure', {
      status: response.status, code: upstream?.error?.code, output_started: false,
    });
  }
  // DEFENSE: An HTTP failure or unsupported response content type cannot enter the model SSE parser.
  if (admission.action === 'failure') {
    if (admission.cancel) await response.body?.cancel();
    // DEFENSE: An explicit context_length_exceeded rejection before output is the only HTTP failure eligible for compaction.
    if (admission.recoverable) throw new ContextLimitError();
    throw new Error(admission.message);
  }
  let state = { output_started: false, completed_items: [] };
  for await (const data of events(response.body, limits.frame_bytes)) {
    if (data === '[DONE]') break;
    const event = parseJson(data);
    const step = boundary('backend.stream_step', { kind: backend.stream_kind, effect: { kind: effect.kind }, event, state });
    state = step.state;
    switch (step.action) {
      case 'delta': onDelta(step.text, step.index); break;
      case 'terminal': {
        onObservation({ scope, now: Date.now(), usage: event.response?.usage });
        const items = providerOutput(step.output, profile, step.output_indices);
        return effect.kind === 'model' ? boundary('backend.compaction_bind_output', { items, scope }) : items;
      }
      case 'failure':
        // DEFENSE: A provider failure event permits compaction only for context_length_exceeded before any exposed output.
        if (step.recoverable) throw new ContextLimitError();
        throw new Error(step.message);
    }
  }
  // DEFENSE: A disconnected or truncated SSE stream may end without a terminal response; expose failure instead of returning partial output.
  throw new Error(boundary('backend.stream_end', { kind: backend.stream_kind, effect, state }).message);
}

export { requestCompaction, observeModelRequest } from './compaction.mjs';

import { createHash } from 'node:crypto';
import { parseJson, stringifyJson } from './codec.mjs';
import { events, readText } from './network.mjs';
import { authorize } from './chatgpt-account.mjs';
import { boundary, observeJson } from './public/model-boundary.mjs';
import { requestHeaders } from './model-request.mjs';
import { requestChatGPTWeb, cancelChatGPTWeb } from './chatgpt-web.mjs';

// Transport abort detaches an observer. A committed native cancellation also
// stops retained remote work where the provider has an explicit stop endpoint.
export function cancelModelTask(task, config, home, limits) {
  return cancelChatGPTWeb(task, config, home, limits);
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

export function providerInput(history, profile = {}) {
  return boundary('backend.input', { history, profile });
}

export function providerOutput(output, profile = {}) {
  const arguments_observations = [];
  // Parsing supplies raw structural observations; admission belongs to Bend.
  if (Array.isArray(output)) {
    output.forEach((item, index) => {
      if (typeof item?.arguments === 'string') {
        arguments_observations.push({ index, observation: observeJson(item.arguments) });
      }
    });
  }
  return boundary('backend.output', { output, profile, arguments_observations });
}

export function responseBody(effect, profile = { provider: effect.model.provider }) {
  return boundary('backend.request', { effect, profile });
}

// Resolve the complete consumer before selecting opaque input. API-key identity
// stays within the target digest, so rotating one credential reference also
// invalidates its old receipts without sending credential bytes into Bend.
export async function providerSession(effect, config, home, { signal } = {}) {
  const configured = config.profiles[effect.model.profile];
  const backend = boundary('backend.support', { effect, profile: configured });
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
  return { profile, backend, scope, lifetime, headers,
    account: Boolean(authorization),
    refresh: async () => {
      authorization = await authorization.refreshAfterRejection({ signal: lifetime });
      Object.assign(headers, authorization.headers);
    },
  };
}

export async function requestProviderJSON(session, suffix, request, limits, { onRetry = () => {} } = {}) {
  const body = stringifyJson(request);
  boundary('backend.request_size', { bytes: Buffer.byteLength(body), limits });
  const send = () => fetch(`${session.profile.endpoint}${suffix}`, { method: 'POST',
    headers: { ...session.headers, accept: 'application/json' }, body, signal: session.lifetime, redirect: 'error' });
  let response = await requestHeaders(send, limits.model_retry, session.lifetime, onRetry);
  const observation = refreshed => ({ status: response.status, ok: response.ok,
    authorization: session.account, refreshed });
  if (boundary('backend.compaction_headers', observation(false)) === 'refresh') {
    await response.body?.cancel();
    await session.refresh();
    response = await send();
  }
  const text = await readText(response.body, limits.frame_bytes);
  let value;
  try { value = parseJson(text); }
  catch (error) { if (response.ok) throw error; }
  if (boundary('backend.compaction_headers', observation(true)) === 'read_error') {
    const failure = boundary('backend.http_failure', { status: response.status,
      code: value?.error?.code, output_started: false });
    if (failure.recoverable) throw new ContextLimitError();
    const error = new Error(failure.message);
    error.status = response.status;
    error.provider_code = value?.error?.code;
    throw error;
  }
  return value;
}

export async function requestModel(effect, config, home, limits, { signal, onDelta = () => {}, onSnapshot = () => {}, onRetry = () => {}, onObservation = () => {} } = {}) {
  signal?.throwIfAborted();
  const configured = config.profiles[effect.model.profile];
  const support = boundary('backend.support', { effect, profile: configured });
  if (support.transport === 'web') {
    return requestChatGPTWeb(effect, configured, home, limits, { signal, onSnapshot, onRetry });
  }
  if (support.transport === 'echo') return boundary('backend.echo', { history: effect.history });
  const session = await providerSession(effect, config, home, { signal });
  const { profile, backend, scope } = session;
  const consumer = boundary('backend.compaction_scope_changed', { effect, scope });
  if (consumer.scope_changed) throw new ContextScopeChangedError(scope);
  const lifetime = session.lifetime;
  boundary('backend.request_guard', { effect, profile, limits });
  const request = responseBody(effect, profile);
  const body = stringifyJson(request);
  try { boundary('backend.request_size', { bytes: Buffer.byteLength(body), limits }); }
  catch (error) { throw new RangeError(error.message); }
  const headers = { ...session.headers, accept: 'text/event-stream' };
  const send = () => fetch(profile.endpoint, { method: 'POST', headers, body, signal: lifetime, redirect: 'error' });
  let response = await requestHeaders(send, limits.model_retry, lifetime, onRetry);
  let admission = boundary('backend.http_headers', {
    status: response.status, ok: response.ok, content_type: response.headers.get('content-type'),
    authorization: session.account, refreshed: false,
  });
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
    let upstream = null;
    try { upstream = parseJson(errorBody); } catch {}
    admission = boundary('backend.http_failure', {
      status: response.status, code: upstream?.error?.code, output_started: false,
    });
  }
  if (admission.action === 'failure') {
    if (admission.cancel) await response.body?.cancel();
    if (admission.recoverable) throw new ContextLimitError();
    throw new Error(admission.message);
  }
  let state = { output_started: false, completed_items: [] };
  for await (const data of events(response.body, limits.frame_bytes)) {
    if (data === '[DONE]') break;
    const event = parseJson(data);
    const step = boundary('backend.stream_step', { kind: backend.stream_kind, effect, event, state });
    state = step.state;
    switch (step.action) {
      case 'delta': onDelta(step.text, step.index); break;
      case 'terminal': {
        onObservation({ scope, now: Date.now(), usage: event.response?.usage });
        const items = providerOutput(step.output, profile);
        return effect.kind === 'model' ? boundary('backend.compaction_bind_output', { items, scope }) : items;
      }
      case 'failure':
        if (step.recoverable) throw new ContextLimitError();
        throw new Error(step.message);
    }
  }
  throw new Error(boundary('backend.stream_end', { kind: backend.stream_kind, effect, state }).message);
}

export { requestCompaction, observeModelRequest } from './compaction.mjs';

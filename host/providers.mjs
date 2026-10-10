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

export async function requestModel(effect, config, home, limits, { signal, onDelta = () => {}, onSnapshot = () => {}, onRetry = () => {} } = {}) {
  signal?.throwIfAborted();
  const profile = config.profiles[effect.model.profile];
  const backend = boundary('backend.support', { effect, profile });
  if (backend.transport === 'web') {
    return requestChatGPTWeb(effect, profile, home, limits, { signal, onSnapshot, onRetry });
  }
  if (backend.transport === 'echo') return boundary('backend.echo', { history: effect.history });
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(profile.timeout_ms)]) : AbortSignal.timeout(profile.timeout_ms);
  boundary('backend.request_guard', { effect, profile, limits });
  const request = responseBody(effect, profile);
  const body = stringifyJson(request);
  try { boundary('backend.request_size', { bytes: Buffer.byteLength(body), limits }); }
  catch (error) { throw new RangeError(error.message); }
  let authorization;
  const headers = { 'content-type': 'application/json', accept: 'text/event-stream' };
  if (backend.auth === 'account') {
    authorization = await authorize(profile, home, { signal: lifetime });
    boundary('backend.authorization', { profile, authorization: { account_id: authorization.account_id } });
    Object.assign(headers, authorization.headers);
  } else {
    const key = process.env[profile.api_key_env];
    boundary('backend.credentials', { profile, key });
    headers.authorization = `Bearer ${key}`;
  }
  const send = () => fetch(profile.endpoint, { method: 'POST', headers, body, signal: lifetime, redirect: 'error' });
  let response = await requestHeaders(send, limits.model_retry, lifetime, onRetry);
  let admission = boundary('backend.http_headers', {
    status: response.status, ok: response.ok, content_type: response.headers.get('content-type'),
    authorization: Boolean(authorization), refreshed: false,
  });
  if (admission.action === 'refresh') {
    await response.body?.cancel();
    authorization = await authorization.refreshAfterRejection({ signal: lifetime });
    Object.assign(headers, authorization.headers);
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
      case 'terminal': return providerOutput(step.output, profile);
      case 'failure':
        if (step.recoverable) throw new ContextLimitError();
        throw new Error(step.message);
    }
  }
  throw new Error(boundary('backend.stream_end', { kind: backend.stream_kind, effect, state }).message);
}

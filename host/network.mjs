import { stringifyJson } from './codec.mjs';
import { boundary, observeJson } from './public/model-boundary.mjs';

export async function readText(body, maximum) {
  if (!body) return '';
  const chunks = [];
  let length = 0;
  for await (const chunk of body) {
    length += chunk.length;
    if (length > maximum) throw new RangeError('HTTP body exceeds the configured limit');
    chunks.push(chunk);
  }
  return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, length));
}

export async function requestJson(url, { method = 'POST', body, encoding = 'json', headers = {}, signal, timeout = 30_000, maximum = 1024 * 1024 } = {}) {
  if (!['json', 'form'].includes(encoding)) throw new TypeError('Unsupported request encoding');
  const response = await fetch(url, {
    method, headers: { 'content-type': encoding === 'form' ? 'application/x-www-form-urlencoded' : 'application/json', ...headers },
    body: body === undefined ? undefined : encoding === 'form' ? new URLSearchParams(body).toString() : stringifyJson(body),
    signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(timeout)]) : AbortSignal.timeout(timeout),
    redirect: 'error',
  });
  const text = await readText(response.body, maximum);
  const observation = observeJson(text);
  const source = { response: { status: response.status, ok: response.ok, status_text: response.statusText,
    url: response.url, type: response.type, redirected: response.redirected,
    headers: [...response.headers] }, text, observation };
  let decoded;
  try { decoded = boundary('web.http_json', source); }
  catch (error) {
    if (error.code === 'http_json_parse') {
      throw new Error(error.message, { cause: new SyntaxError(observation.error ?? error.message) });
    }
    throw error;
  }
  const value = decoded.present ? decoded.value : undefined;
  return { status: response.status, ok: response.ok, value, text, headers: response.headers };
}

/** SSE framing is independent of HTTP chunks, including UTF-8 and CRLF splits. */
export async function* events(body, maximum) {
  for await (const event of sseEvents(body, maximum)) yield event.data;
}

/** Preserve named SSE events without imposing a provider's JSON envelope. */
export async function* sseEvents(body, maximum) {
  if (!body) throw new Error('The provider returned no response stream');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let state = { pending: '', data: [], size: 0, name: 'message' };
  for await (const chunk of body) {
    const transition = boundary('web.sse_step', { state, chunk: decoder.decode(chunk, { stream: true }), maximum, eof: false });
    state = transition.state;
    for (const frame of transition.frames) yield frame;
    if (transition.error) throw new RangeError(transition.error);
  }
  const transition = boundary('web.sse_step', { state, chunk: decoder.decode(), maximum, eof: true });
  for (const frame of transition.frames) yield frame;
  if (transition.error) throw new Error(transition.error);
}

import { stringifyJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';

export async function readText(body, maximum) {
  // DEFENSE: HTTP HEAD/204 responses expose no body; their text observation is empty.
  if (!body) return '';
  const chunks = [];
  let length = 0;
  for await (const chunk of body) {
    length += chunk.length;
    // DEFENSE: An HTTP peer can stream more bytes than the configured response budget; stop before retaining them.
    if (length > maximum) throw new RangeError('HTTP body exceeds the configured limit');
    chunks.push(chunk);
  }
  return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, length));
}

export async function requestJson(url, { method = 'POST', body, headers = {}, signal, timeout = 30_000, maximum = 1024 * 1024 } = {}) {
  const response = await fetch(url, {
    method, headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : stringifyJson(body),
    signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(timeout)]) : AbortSignal.timeout(timeout),
    redirect: 'error',
  });
  const text = await readText(response.body, maximum);
  const source = { response: { status: response.status, ok: response.ok, status_text: response.statusText,
    url: response.url, type: response.type, redirected: response.redirected,
    headers: [...response.headers] }, text };
  let decoded;
  try { decoded = boundary('web.http_json', source); }
  catch (error) {
    // DEFENSE: A successful HTTP response containing malformed JSON is a protocol failure with a SyntaxError cause.
    if (error.code === 'http_json_parse') {
      throw new Error(error.message, { cause: new SyntaxError('Invalid JSON response') });
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
  // DEFENSE: HTTP responses with no body cannot supply the required SSE terminal event.
  if (!body) throw new Error('The provider returned no response stream');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let state = { pending: '', data: [], size: 0, name: 'message', after_cr: false };
  for await (const chunk of body) {
    const transition = boundary('web.sse_step', { state, chunk: decoder.decode(chunk, { stream: true }), maximum, eof: false });
    state = transition.state;
    for (const frame of transition.frames) yield frame;
    // DEFENSE: An SSE peer can exceed the frame byte budget before terminating a frame.
    if (transition.error) throw new RangeError(transition.error);
  }
  const transition = boundary('web.sse_step', { state, chunk: decoder.decode(), maximum, eof: true });
  for (const frame of transition.frames) yield frame;
  // DEFENSE: EOF can truncate an SSE frame; surface the framing failure instead of returning incomplete event data.
  if (transition.error) throw new Error(transition.error);
}

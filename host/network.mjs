import { parseJson, stringifyJson } from './codec.mjs';

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

export async function requestJson(url, { method = 'POST', body, headers = {}, signal, timeout = 30_000, maximum = 1024 * 1024 } = {}) {
  const response = await fetch(url, {
    method, headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : stringifyJson(body),
    signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(timeout)]) : AbortSignal.timeout(timeout),
    redirect: 'error',
  });
  const text = await readText(response.body, maximum);
  let value;
  try { value = parseJson(text); }
  catch (error) { if (response.ok) throw new Error('The service returned invalid JSON', { cause: error }); }
  return { status: response.status, ok: response.ok, value, headers: response.headers };
}

/** SSE framing is independent of HTTP chunks, including UTF-8 and CRLF splits. */
export async function* events(body, maximum) {
  if (!body) throw new Error('The provider returned no response stream');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let pending = '';
  let data = [];
  let size = 0;
  function line(value) {
    if (value.endsWith('\r')) value = value.slice(0, -1);
    if (value.startsWith('data:')) {
      const part = value.slice(5).replace(/^ /, '');
      size += Buffer.byteLength(part) + 1;
      if (size > maximum) throw new RangeError('SSE event exceeds the configured limit');
      data.push(part);
    }
    if (value !== '' || data.length === 0) return undefined;
    const message = data.join('\n');
    data = [];
    size = 0;
    return message;
  }
  for await (const chunk of body) {
    pending += decoder.decode(chunk, { stream: true });
    let end;
    while ((end = pending.indexOf('\n')) >= 0) {
      const message = line(pending.slice(0, end));
      pending = pending.slice(end + 1);
      if (message !== undefined) yield message;
    }
    if (Buffer.byteLength(pending) > maximum) throw new RangeError('SSE line exceeds the configured limit');
  }
  pending += decoder.decode();
  if (pending || data.length) throw new Error('The SSE stream ended inside an event');
}

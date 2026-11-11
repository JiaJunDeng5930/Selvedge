import { after } from 'node:test';
import http from 'node:http';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

export { taskIdle } from './fixtures/task-idle.mjs';

const temporaryHomes = new Set();
// Test cleanup hooks run in registration order in Bun. Keep homes until the
// suite ends so every per-test service can finish its journal before removal.
after(async () => {
  await Promise.all([...temporaryHomes].map(directory => rm(directory, { recursive: true, force: true })));
});

export async function home(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-service-test-'));
  temporaryHomes.add(directory);
  return realpath(directory);
}

export function asyncToolResult(item) {
  if (item.role !== 'user') return;
  const content = Array.isArray(item.content)
    ? item.content.filter(part => part.type === 'input_text').map(part => part.text).join('')
    : item.content;
  if (typeof content !== 'string') return;
  // The JSON result is observable data; the explanatory text before it is not a protocol marker.
  for (const match of content.matchAll(/\{/g)) {
    let result;
    try { result = JSON.parse(content.slice(match.index)); }
    catch (error) {
      // DEFENSE: Ordinary user text and the explanatory prefix can contain braces without beginning the result JSON.
      if (error instanceof SyntaxError) continue;
      throw error;
    }
    if (typeof result.call_id === 'string' && typeof result.is_error === 'boolean') return result;
  }
}

export async function responsesServer(t, respond, { measure, observeRequest } = {}) {
  const requests = [];
  const failures = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      observeRequest?.(body, request);
      if (measure && request.url.endsWith('/input_tokens')) {
        const input_tokens = await measure(body, request);
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end(JSON.stringify({ input_tokens }));
        return;
      }
      const naming = body.text?.format?.name === 'task_title';
      if (!naming) requests.push(body);
      const output = naming ? [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: '{"title":"Name the task"}' }] }]
        : await respond(body, requests.length - 1, request);
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      const outputIndex = output.findIndex(item => item.type === 'message');
      if (outputIndex >= 0) response.write(`data: ${JSON.stringify({ type: 'response.output_text.delta', output_index: outputIndex, delta: '处理中 😀' })}\r\n\r\n`);
      response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\r\n\r\n`);
    // DEFENSE: A malformed model HTTP request or a failing fixture assertion must be observable by the test and its HTTP client.
    })().catch(error => {
      failures.push(error);
      response.writeHead(500);
      response.end('fixture failure');
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => {
    // NOTE: The pinned Bun runtime also stops the server in this call.
    server.closeAllConnections();
  });
  return { endpoint: `http://127.0.0.1:${server.address().port}/responses`, requests, failures };
}

export function shellQuote(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

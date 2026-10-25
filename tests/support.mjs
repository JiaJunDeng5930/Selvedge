import assert from 'node:assert/strict';
import { after } from 'node:test';
import http from 'node:http';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

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

export async function taskIdle(service, taskId = 0, timeoutMs = 20_000) {
  // These scenarios include multiple model/tool roundtrips before becoming idle;
  // their physical IO deadlines are asserted separately.
  const deadline = Date.now() + timeoutMs;
  let page;
  do {
    const result = await service.command({ op: 'read', task_id: taskId });
    assert.equal(result.reply.ok, true);
    page = result.reply.result;
    if (page.task.phase === 'idle' && page.task.operations.length === 0) return page;
    await delay(10);
  } while (Date.now() < deadline);
  // DEFENSE: A service/provider regression can leave a real asynchronous task unsettled beyond the fixture deadline.
  throw new Error(`Task did not settle: ${JSON.stringify(page)}`);
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

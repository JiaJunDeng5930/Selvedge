import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

export async function home(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-service-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

export async function taskIdle(service, taskId = 0) {
  const deadline = Date.now() + 5000;
  let page;
  do {
    const result = await service.command({ op: 'read', task_id: taskId });
    assert.equal(result.reply.ok, true);
    page = result.reply.result;
    if (page.task.phase === 'idle' && page.task.operations.length === 0) return page;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Task did not settle: ${JSON.stringify(page)}`);
}

export async function responsesServer(t, respond) {
  const requests = [];
  const failures = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      requests.push(body);
      const output = await respond(body, requests.length - 1, request);
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.write(`data: ${JSON.stringify({ type: 'response.output_text.delta', delta: '处理中 😀' })}\r\n\r\n`);
      response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\r\n\r\n`);
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
  t.after(() => new Promise((resolve, reject) => {
    server.closeAllConnections();
    server.close(error => error ? reject(error) : resolve());
  }));
  return { endpoint: `http://127.0.0.1:${server.address().port}/responses`, requests, failures };
}

export function shellQuote(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

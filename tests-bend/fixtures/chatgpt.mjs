import http from 'node:http';
import path from 'node:path';
import { writeAtomic } from '../../host/files.mjs';
import { defaultChatGPTAccount } from '../../host/chatgpt-contract.mjs';
import { home } from '../support.mjs';

export function fakeTokens(account = 'fixture-account', marker = 'original') {
  const claims = { exp: Math.floor(Date.now() / 1000) + 3600,
    'https://api.openai.com/auth': { chatgpt_account_id: account } };
  const jwt = `fixture.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.${marker}`;
  return { access_token: jwt, id_token: jwt, refresh_token: 'fixture-refresh' };
}

export async function chatgptFixture(t, handler) {
  const directory = await home(t);
  const failures = [];
  const requests = [];
  const server = http.createServer((request, response) => {
    (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      const body = raw ? JSON.parse(raw) : undefined;
      requests.push({ method: request.method, url: request.url, headers: request.headers, body });
      await handler(requests.at(-1), response);
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const address = `http://127.0.0.1:${server.address().port}`;
  const profile = { ...defaultChatGPTAccount, endpoint: `${address}/backend-api/codex/responses`, issuer: address, timeout_ms: 5000 };
  const save = async (account = 'fixture-account', marker) => writeAtomic(path.join(directory, profile.auth_file), {
    format: 'selvedge-chatgpt-1', ...fakeTokens(account, marker), account_id: account, last_refresh: new Date().toISOString(),
  });
  await save();
  return { directory, profile, requests, failures, save, server, address };
}

export function jsonResponse(response, value, status = 200) {
  response.writeHead(status, { 'content-type': 'application/json' });
  response.end(JSON.stringify(value));
}

export function modelResponse(response, output, deltas = []) {
  response.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const delta of deltas) response.write(`data: ${JSON.stringify(delta)}\n\n`);
  for (const [output_index, item] of output.entries()) {
    response.write(`data: ${JSON.stringify({ type: 'response.output_item.done', output_index, item })}\n\n`);
  }
  response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [] } })}\n\n`);
}

export const modelEffect = () => ({
  kind: 'model', task_id: 1, ticket: 2,
  model: { profile: 'fixture', provider: 'chatgpt', name: 'model-from-account', reasoning: 'medium', project: null },
  instructions: 'Fixture instructions', history: [{ role: 'user', content: 'hello' }],
  tools: [
    { name: 'allowed', description: 'Allowed tool', parameters: { type: 'object', properties: {} } },
    { name: 'withheld', description: 'Not callable', parameters: { type: 'object', properties: {} } },
  ], callable: ['allowed'],
});

export const wireLimits = { frame_bytes: 4 * 1024 * 1024,
  model_retry: { delays_ms: [1], statuses: [429, 503], max_retry_after_ms: 100 } };

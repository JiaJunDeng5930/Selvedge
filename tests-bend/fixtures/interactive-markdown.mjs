import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServer } from '../../host/server.mjs';
import { defaultConfig, validateConfig } from '../../host/config.mjs';
import { stringifyJson } from '../../host/codec.mjs';

async function listening(server) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return `http://127.0.0.1:${server.address().port}`;
}
async function body(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}
function json(response, value, status = 200) {
  response.writeHead(status, { 'content-type': 'application/json' });
  response.end(stringifyJson(value));
}

/** A real service whose only fake boundary is the explicitly controlled model HTTP peer. */
export async function interactiveMarkdownFixture() {
  const root = await mkdtemp(path.join(tmpdir(), 'selvedge-interactive-browser-'));
  const requests = [];
  const failures = [];
  const peers = new Set();
  let running;
  let closed = false;
  const apiKey = `SELVEDGE_INTERACTIVE_FIXTURE_${process.pid}_${Math.random().toString(16).slice(2)}`;
  process.env[apiKey] = 'loopback-fixture';
  const upstream = http.createServer((request, response) => {
    void (async () => {
      const input = await body(request);
      if (request.url.endsWith('/input_tokens')) return json(response, { input_tokens: 100 });
      const entry = { index: requests.length, input, text: '', outputIndex: 0, closed: false, response };
      requests.push(entry);
      peers.add(response);
      response.on('close', () => {
        entry.closed = true;
        peers.delete(response);
      });
      response.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store' });
      response.flushHeaders();
    })().catch(error => { failures.push(String(error)); json(response, { error: String(error) }, 500); });
  });
  const endpoint = `${await listening(upstream)}/responses`;
  const config = validateConfig({ ...defaultConfig, port: 0, chatgpt: false,
    profiles: { ...defaultConfig.profiles, interactive: {
      provider: 'responses', model: 'interactive-fixture', endpoint, api_key_env: apiKey,
    } },
  });
  const open = async (home, port = config.port) => {
    const opened = await startServer({ home, config: { ...config, port }, cwd: root });
    const sockets = new Set();
    opened.server.on('connection', socket => {
      sockets.add(socket);
      socket.once('close', () => sockets.delete(socket));
    });
    return { ...opened, disconnect() {
      // Bun's closeAllConnections also stops listening; this fault only drops peers.
      for (const socket of [...sockets]) socket.destroy();
    } };
  };
  let home = path.join(root, 'state');
  try { running = await open(home); }
  catch (error) {
    upstream.closeAllConnections();
    await new Promise(resolve => upstream.close(resolve));
    delete process.env[apiKey];
    await rm(root, { recursive: true, force: true });
    throw error;
  }
  const status = () => ({ address: running.address, sequence: running.service.journal.sequence,
    requests: requests.map(({ index, input, text, outputIndex, closed }) => ({ index, input, text, outputIndex, closed })), failures });
  function entry(index) {
    const request = requests[index];
    if (!request || request.closed) throw new Error(`No open model request ${index}`);
    return request;
  }
  function event(request, value) { request.response.write(`data: ${JSON.stringify(value)}\n\n`); }
  function emit(index, text, outputIndex = 0) {
    const request = entry(index);
    request.text += text;
    request.outputIndex = outputIndex;
    event(request, { type: 'response.output_text.delta', output_index: outputIndex, delta: text });
  }
  function finish(index, { text, suffix = '', output } = {}) {
    const request = entry(index);
    const finalText = text ?? request.text + suffix;
    const result = output ?? [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: finalText }] }];
    event(request, { type: 'response.completed', response: { status: 'completed', output: result } });
    request.response.end();
  }
  async function command(value) { return running.service.command(value); }
  async function restart({ differentNamespace = false } = {}) {
    const port = Number(new URL(running.address).port);
    await running.close();
    if (differentNamespace) home = path.join(root, `other-state-${Date.now()}`);
    running = await open(home, port);
    return status();
  }
  const control = http.createServer((request, response) => {
    void (async () => {
      if (request.method === 'GET' && request.url === '/status') return json(response, status());
      const input = await body(request);
      if (request.url === '/command') return json(response, await command(input));
      if (request.url === '/emit') { emit(input.index, input.text, input.outputIndex); return json(response, { ok: true }); }
      if (request.url === '/finish') { finish(input.index, input); return json(response, { ok: true }); }
      if (request.url === '/restart') return json(response, await restart(input));
      if (request.url === '/disconnect') { running.disconnect(); return json(response, { ok: true }); }
      json(response, { error: 'unknown fixture control' }, 404);
    })().catch(error => json(response, { error: String(error) }, 500));
  });
  const controlAddress = await listening(control);
  async function close() {
    if (closed) return;
    closed = true;
    for (const peer of peers) peer.destroy();
    control.closeAllConnections(); upstream.closeAllConnections();
    await Promise.all([new Promise(resolve => control.close(resolve)), new Promise(resolve => upstream.close(resolve)), running.close()]);
    delete process.env[apiKey];
    await rm(root, { recursive: true, force: true });
  }
  return { get running() { return running; }, root, endpoint, controlAddress, requests, failures,
    command, emit, finish, restart, status, close };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const fixture = await interactiveMarkdownFixture();
  process.stdout.write(`${JSON.stringify({ address: fixture.running.address, control: fixture.controlAddress })}\n`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await fixture.close(); process.exit(0); });
}

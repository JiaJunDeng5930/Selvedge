import http from 'node:http';
import assert from 'node:assert/strict';
import { realpath } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { startServer } from '../../host/server.mjs';
import { defaultConfig, validateConfig } from '../../host/config.mjs';
import { login } from '../../host/chatgpt-account.mjs';
import { chatgptFixture } from './chatgpt.mjs';
import { home, responsesServer } from '../support.mjs';
import { imageBytes } from './image-data.mjs';

export { imageBase64, imageBytes, largeImageBytes } from './image-data.mjs';
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const hasImage = value => value !== null && typeof value === 'object'
  && (value.type === 'input_image' || Object.values(value).some(hasImage));

/** The production service, with only the external OAuth and model HTTP peer replaced. */
export async function imagesFixture(t, { respond = () => answer('Image request accepted.'), mcp = {}, includeTextProfile = true } = {}) {
  const upstream = await chatgptFixture(t);
  const requests = [];
  upstream.options.respond = async (entry, response) => {
    if (new URL(entry.url, upstream.address).pathname === '/v1/models') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ models: [{ slug: 'image-fixture', display_name: 'Image fixture',
        visibility: 'list', context_window: 128000, effective_context_window_percent: 100,
        default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium' }] }] }));
      return;
    }
    if (entry.url.endsWith('/input_tokens')) {
      const images = hasImage(entry.body);
      if (images) upstream.failures.push(new Error('Account image requests must not call an unavailable /input_tokens endpoint'));
      response.writeHead(images ? 404 : 200, { 'content-type': 'application/json' });
      response.end(images ? '{"error":"No account image token-counting endpoint."}' : '{"input_tokens":100}');
      return;
    }
    const title = entry.body.text?.format?.name === 'task_title';
    if (!title) requests.push(entry.body);
    const output = title ? answer('{"title":"Image fixture task"}') : await respond(entry.body, requests.length - 1);
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\n\n`);
  };
  await login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize });
  const workspace = await realpath(await home(t));
  const textBackend = await responsesServer(t, () => answer('Text-only request received.'));
  const apiKey = `SELVEDGE_IMAGES_FIXTURE_${process.pid}_${Math.random().toString(16).slice(2)}`;
  process.env[apiKey] = 'loopback-fixture';
  t.after(() => { delete process.env[apiKey]; });
  const config = validateConfig({ ...defaultConfig, port: 0, chatgpt: upstream.profile, mcp,
    profiles: includeTextProfile ? {
      text: { provider: 'responses', model: 'text-fixture', endpoint: textBackend.endpoint,
        api_key_env: apiKey, timeout_ms: 5000 },
    } : {} });
  const options = { home: upstream.directory, cwd: workspace, config };
  let running = await startServer(options);
  t.after(() => running.close());
  const headers = () => ({ authorization: `Bearer ${running.token}` });
  const catalogResponse = await fetch(`${running.address}/api/accounts/refresh`, { method: 'POST',
    headers: { ...headers(), 'content-type': 'application/json' }, body: '{}' });
  assert.equal(catalogResponse.status, 200, await catalogResponse.clone().text());
  const catalog = await catalogResponse.json();
  assert.equal(catalog.ok, true, JSON.stringify(catalog));
  const profile = catalog.result.profiles.find(value => value.provider === 'chatgpt' && value.name === 'image-fixture');
  assert.ok(profile, 'The public account catalog must discover the image model and its context window');
  async function rawCommand(command) {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { ...headers(), 'content-type': 'application/json' }, body: JSON.stringify(command) });
    assert.equal(response.status, 200);
    return response.json();
  }
  async function command(value) {
    const reply = await rawCommand(value);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  async function upload(name = 'red square.png', bytes = imageBytes) {
    const response = await fetch(`${running.address}/api/board/attachments?name=${encodeURIComponent(name)}`, {
      method: 'POST', headers: { ...headers(), 'content-type': 'application/octet-stream' }, body: bytes,
    });
    assert.equal(response.status, 201, await response.clone().text());
    return (await response.json()).result;
  }
  return { upstream, requests, textBackend, profile: profile.key, workspace, command, rawCommand, upload,
    get running() { return running; },
    async restart() {
      const port = Number(new URL(running.address).port);
      await running.close();
      running = await startServer({ ...options, config: { ...config, port } });
    },
    status() { return { address: running.address, requests, failures: upstream.failures.map(String) }; },
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const cleanups = [];
  const fixture = await imagesFixture({ after: callback => cleanups.push(callback) }, { includeTextProfile: false });
  const control = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const value = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : undefined;
      let result;
      if (request.url === '/status') result = fixture.status();
      else if (request.url === '/command') result = { reply: await fixture.rawCommand(value) };
      else if (request.url === '/restart') { await fixture.restart(); result = fixture.status(); }
      else throw new Error(`Unknown fixture route: ${request.url}`);
      response.writeHead(200, { 'content-type': 'application/json' }); response.end(JSON.stringify(result));
    // DEFENSE: A browser-driver command or service restart can fail; return the failure to the waiting test driver.
    })().catch(error => { response.writeHead(500); response.end(JSON.stringify({ error: String(error) })); });
  });
  await new Promise(resolve => control.listen(0, '127.0.0.1', resolve));
  process.stdout.write(`${JSON.stringify({ address: fixture.running.address,
    control: `http://127.0.0.1:${control.address().port}` })}\n`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
    control.closeAllConnections();
    await new Promise(resolve => control.close(resolve));
    for (const cleanup of cleanups.toReversed()) await cleanup();
    process.exit(0);
  });
}

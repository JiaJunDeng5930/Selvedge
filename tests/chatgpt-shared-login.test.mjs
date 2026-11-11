import test from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { chatgptFixture } from './fixtures/chatgpt.mjs';

const modelSlug = 'shared-login-fixture-model';

async function waitFor(description, observe) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const value = await observe();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  throw new Error(`Timed out waiting for ${description}`);
}

test('one ChatGPT authorization makes the model directory and voice transcription available', async t => {
  const upstream = await chatgptFixture(t);
  const { directory, profile } = upstream;
  upstream.options.respond = (entry, response) => {
    assert.equal(new URL(entry.url, upstream.address).pathname, '/v1/models');
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ models: [{
      slug: modelSlug,
      visibility: 'list',
      default_reasoning_level: 'medium',
      supported_reasoning_levels: [{ effort: 'low' }, { effort: 'medium' }],
      context_window: 128000,
    }] }));
  };
  const transcriptionRequests = [];
  const transcriptionFetchImpl = async (input, init = {}) => {
    const file = init.body?.get('file');
    transcriptionRequests.push({
      url: String(input),
      headers: new Headers(init.headers),
      fileName: file?.name,
      mime: file?.type,
      bytes: file ? Buffer.from(await file.arrayBuffer()) : null,
    });
    return new Response(JSON.stringify({ text: 'The shared ChatGPT login is transcribing audio.' }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  const config = validateConfig({ ...defaultConfig, chatgpt: profile, port: 0 });
  const running = await startServer({ home: directory, cwd: directory, config,
    audioOptions: { transcriptionFetchImpl } });
  t.after(() => running.close());
  const headers = { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' };

  const loginResponse = await fetch(`${running.address}/api/audio/login`, {
    method: 'POST', headers, body: '{}',
  });
  const login = await loginResponse.json();
  assert.equal(loginResponse.status, 200, JSON.stringify(login));
  assert.equal(new URL(login.url).origin, upstream.address);

  const callbackResponse = await fetch(login.url);
  assert.equal(callbackResponse.status, 200, await callbackResponse.text());

  const authorizationRequests = upstream.oauthRequests.filter(request => request.url.startsWith('/authorize?'));
  assert.equal(authorizationRequests.length, 1);
  const authorization = new URL(authorizationRequests[0].url, upstream.address);
  assert.ok(authorization.searchParams.get('state'));
  assert.ok(authorization.searchParams.get('nonce'));
  const callback = new URL(authorization.searchParams.get('redirect_uri'));
  assert.equal(callback.hostname, '127.0.0.1');
  assert.equal(callback.pathname, '/auth/callback');
  const commands = await waitFor('the signed-in model in the service model list', async () => {
    const response = await fetch(`${running.address}/api/commands`, {
      method: 'POST', headers, body: JSON.stringify({ op: 'list' }),
    });
    const body = await response.json();
    assert.equal(response.status, 200, JSON.stringify(body));
    return body.ok && body.result?.profiles?.some(profile => profile.name === modelSlug) ? body : null;
  });
  assert.ok(commands.result.profiles.some(profile => profile.provider === 'chatgpt' && profile.name === modelSlug));
  assert.ok(upstream.requests.length > 0, 'The signed-in model catalog must be fetched from the configured endpoint');
  const capabilitiesResponse = await fetch(`${running.address}/api/audio/capabilities`, { headers: { authorization: headers.authorization } });
  const capabilities = await capabilitiesResponse.json();
  assert.equal(capabilitiesResponse.status, 200, JSON.stringify(capabilities));
  assert.ok(capabilities.connections.some(connection => connection.id === 'chatgpt-voice' && connection.asr && connection.voice),
    'The same signed-in account must be advertised as an available voice connection');

  const audio = Buffer.from('524946462600000057415645666d74201000000001000100401f0000803e00000200100064617461020000000000', 'hex');
  const transcriptionResponse = await fetch(`${running.address}/api/audio/transcribe?connection=chatgpt-voice`, {
    method: 'POST',
    headers: { authorization: headers.authorization, 'content-type': 'audio/wav' },
    body: audio,
  });
  const transcription = await transcriptionResponse.json();
  assert.equal(transcriptionResponse.status, 200, JSON.stringify(transcription));
  assert.equal(transcription.text, 'The shared ChatGPT login is transcribing audio.');
  assert.equal(transcriptionRequests.length, 1, 'The public transcription request must reach the controlled audio upstream');
  assert.equal(transcriptionRequests[0].headers.get('authorization'), upstream.requests[0].headers.authorization);
  assert.equal(transcriptionRequests[0].headers.get('chatgpt-account-id'), upstream.requests[0].headers['chatgpt-account-id']);
  assert.equal(transcriptionRequests[0].mime, 'audio/wav');
  assert.deepEqual(transcriptionRequests[0].bytes, audio);

  assert.equal(upstream.oauthRequests.filter(request => request.url.startsWith('/authorize?')).length, 1,
    'Model discovery and transcription must not trigger a second account authorization');
  assert.equal(upstream.oauthRequests.filter(request => request.url === '/oauth/token').length, 1,
    'One browser authorization must produce one authorization-code exchange');
  assert.deepEqual(upstream.failures, []);
});

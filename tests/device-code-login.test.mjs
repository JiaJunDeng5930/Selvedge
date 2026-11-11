import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHash } from 'node:crypto';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { defaultChatGPTAccount } from '../host/chatgpt-account.mjs';
import { home } from './support.mjs';

const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
const accountId = 'device-code-fixture-workspace';
const subject = 'device-code-fixture-account';
const scope = 'openid profile email offline_access api.connectors.read api.connectors.invoke';
const modelSlug = 'device-code-fixture-model';

async function issuerFixture(t, { pendingForever = false } = {}) {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'device-fixture-key', use: 'sig', alg: 'RS256' };
  const requests = [];
  const polls = new Map();
  let address;
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      const url = new URL(request.url, address);
      const entry = { method: request.method, url: request.url, headers: request.headers,
        body: raw ? (request.headers['content-type']?.startsWith('application/json')
          ? JSON.parse(raw) : Object.fromEntries(new URLSearchParams(raw))) : undefined };
      requests.push(entry);
      if (url.pathname === '/.well-known/openid-configuration') {
        return json(response, { issuer: address, authorization_endpoint: `${address}/authorize`,
          token_endpoint: `${address}/oauth/token`, jwks_uri: `${address}/jwks`,
          response_types_supported: ['code'], subject_types_supported: ['public'],
          id_token_signing_alg_values_supported: ['RS256'], token_endpoint_auth_methods_supported: ['none'],
          code_challenge_methods_supported: ['S256'], scopes_supported: scope.split(' ') });
      }
      if (url.pathname === '/jwks') return json(response, { keys: [jwk] });
      if (url.pathname === '/api/accounts/deviceauth/usercode') {
        assert.deepEqual(entry.body, { client_id: clientId });
        const id = `fixture-device-auth-${polls.size + 1}`;
        polls.set(id, 0);
        return json(response, { device_auth_id: id, user_code: 'ABCD-EFGH', interval: '1' });
      }
      if (url.pathname === '/api/accounts/deviceauth/token') {
        const { device_auth_id: id, user_code: code } = entry.body;
        assert.equal(code, 'ABCD-EFGH');
        assert.ok(polls.has(id), 'poll must refer to a device authorization created by this issuer');
        const count = polls.get(id) + 1;
        polls.set(id, count);
        if (pendingForever) return json(response, { error: 'authorization_pending' }, 403);
        if (count === 1) return json(response, { error: 'authorization_pending' }, 403);
        if (count === 2) return json(response, { error: 'authorization_pending' }, 404);
        const verifier = 'fixture-device-code-verifier-that-is-long-enough';
        const challenge = createHash('sha256').update(verifier).digest('base64url');
        return json(response, { authorization_code: 'fixture-device-authorization-code', code_verifier: verifier,
          code_challenge: challenge });
      }
      if (url.pathname === '/oauth/token') {
        assert.equal(entry.headers['content-type']?.split(';')[0], 'application/x-www-form-urlencoded');
        assert.equal(entry.body.grant_type, 'authorization_code');
        assert.equal(entry.body.client_id, clientId);
        assert.equal(entry.body.code, 'fixture-device-authorization-code');
        assert.equal(entry.body.redirect_uri, `${address}/deviceauth/callback`);
        assert.equal(createHash('sha256').update(entry.body.code_verifier).digest('base64url'),
          createHash('sha256').update('fixture-device-code-verifier-that-is-long-enough').digest('base64url'));
        return json(response, { access_token: 'fixture-device-access-secret', refresh_token: 'fixture-device-refresh-secret',
          token_type: 'Bearer', scope, expires_in: 3600,
          // Device-code OIDC grants carry no nonce. The issuer signature and claims still need verification.
          id_token: await new SignJWT({ name: 'Device Fixture User', email: 'device@example.invalid',
            'https://api.openai.com/auth': { chatgpt_account_id: accountId } })
            .setProtectedHeader({ alg: 'RS256', kid: 'device-fixture-key' })
            .setIssuer(address).setSubject(subject).setAudience(clientId).setIssuedAt().setExpirationTime('1h').sign(privateKey),
        });
      }
      if (url.pathname === '/v1/models') {
        assert.equal(entry.headers.authorization, 'Bearer fixture-device-access-secret');
        assert.equal(entry.headers['chatgpt-account-id'], accountId);
        return json(response, { models: [{ slug: modelSlug, visibility: 'list', default_reasoning_level: 'medium',
          supported_reasoning_levels: [{ effort: 'low' }, { effort: 'medium' }], context_window: 128000 }] });
      }
      response.writeHead(404); response.end();
    })().catch(error => {
      response.writeHead(500, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ error: error.message }));
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  address = `http://127.0.0.1:${server.address().port}`;
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { address, requests };
}

function json(response, value, status = 200) {
  response.writeHead(status, { 'content-type': 'application/json' });
  response.end(JSON.stringify(value));
}

function assertNoCredentials(value, secrets) {
  const text = JSON.stringify(value);
  for (const secret of secrets) assert.equal(text.includes(secret), false, `response leaked ${secret}`);
  const visit = item => {
    if (Array.isArray(item)) return item.forEach(visit);
    if (!item || typeof item !== 'object') return;
    for (const [key, child] of Object.entries(item)) {
      assert.doesNotMatch(key, /device_auth_id|code_verifier|access_token|refresh_token/i);
      visit(child);
    }
  };
  visit(value);
}

async function serviceFor(t, issuer, directory) {
  const profile = { ...defaultChatGPTAccount, issuer: issuer.address,
    endpoint: `${issuer.address}/v1/responses`, timeout_ms: 5000 };
  const config = validateConfig({ ...defaultConfig, chatgpt: profile, port: 0 });
  const running = await startServer({ home: directory, cwd: directory, config });
  t.after(() => running.close());
  return { running, profile,
    headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    endpoint: `${running.address}/api/audio/login` };
}

async function post(endpoint, headers, value) {
  const response = await fetch(endpoint, { method: 'POST', headers, body: JSON.stringify(value) });
  const body = await response.json();
  return { response, body };
}

async function waitForSignedIn(endpoint, headers, attemptId) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const result = await post(endpoint, headers, { action: 'status', attempt_id: attemptId });
    assert.equal(result.response.status, 200, JSON.stringify(result.body));
    if (result.body.status !== 'pending') return result.body;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Timed out waiting for device-code sign-in');
}

async function waitForModel(running, headers) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const response = await fetch(`${running.address}/api/commands`, {
      method: 'POST', headers, body: JSON.stringify({ op: 'list' }),
    });
    const body = await response.json();
    assert.equal(response.status, 200, JSON.stringify(body));
    if (body.ok && body.result?.profiles?.some(profile => profile.provider === 'chatgpt' && profile.name === modelSlug)) return body;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Timed out waiting for the device-authorized ChatGPT model');
}

test('device-code sign-in verifies the issuer grant and exposes the shared account through service operations', async t => {
  const directory = await home(t);
  const issuer = await issuerFixture(t);
  const { running, profile, headers, endpoint } = await serviceFor(t, issuer, directory);

  const denied = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"method":"device_code"}' });
  await denied.arrayBuffer();
  assert.equal(denied.status, 401, 'device-code login must use the same local authorization as browser login');
  assert.equal(issuer.requests.some(request => request.url === '/api/accounts/deviceauth/usercode'), false);

  const started = await post(endpoint, headers, { method: 'device_code' });
  assert.equal(started.response.status, 200, JSON.stringify(started.body));
  assert.deepEqual(Object.keys(started.body).sort(), ['attempt_id', 'expires_at', 'user_code', 'verification_url']);
  assert.equal(started.body.verification_url, `${issuer.address}/codex/device`);
  assert.equal(started.body.user_code, 'ABCD-EFGH');
  assert.ok(Number.isFinite(Date.parse(started.body.expires_at)));
  assert.ok(started.body.attempt_id);
  const initial = await post(endpoint, headers, { action: 'status', attempt_id: started.body.attempt_id });
  assert.equal(initial.response.status, 200, JSON.stringify(initial.body));
  assert.equal(initial.body.status, 'pending');
  const completed = await waitForSignedIn(endpoint, headers, started.body.attempt_id);
  assert.equal(completed.status, 'signed_in');

  const polls = issuer.requests.filter(request => request.url === '/api/accounts/deviceauth/token');
  assert.ok(polls.length >= 3, '403 and 404 pending responses must both be retried before success');
  assert.ok(polls.every(request => request.body.device_auth_id && request.body.user_code === 'ABCD-EFGH'));
  const grant = issuer.requests.find(request => request.url === '/oauth/token');
  assert.equal(grant.body.redirect_uri, `${issuer.address}/deviceauth/callback`);
  assert.equal(grant.body.code_verifier, 'fixture-device-code-verifier-that-is-long-enough');

  const commands = await waitForModel(running, headers);
  assert.ok(commands.result.profiles.some(profile => profile.provider === 'chatgpt' && profile.name === modelSlug),
    'device-only account authorization must populate the model directory');
  const capabilitiesResponse = await fetch(`${running.address}/api/audio/capabilities`, {
    headers: { authorization: headers.authorization },
  });
  const capabilities = await capabilitiesResponse.json();
  assert.equal(capabilitiesResponse.status, 200, JSON.stringify(capabilities));
  assert.ok(capabilities.connections.some(connection => connection.id === 'chatgpt-voice' && connection.asr && connection.voice),
    'the same device-authorized account must enable voice capabilities');

  const secrets = ['fixture-device-auth-1', 'fixture-device-code-verifier-that-is-long-enough',
    'fixture-device-access-secret', 'fixture-device-refresh-secret'];
  assertNoCredentials(started.body, secrets);
  assertNoCredentials(initial.body, secrets);
  assertNoCredentials(completed, secrets);
  assert.deepEqual(issuer.requests.filter(request => request.url === '/api/accounts/deviceauth/usercode').map(request => request.body),
    [{ client_id: clientId }]);
  assert.deepEqual(profile.issuer, issuer.address);
});

test('cancelling browser login releases the account lock and leaves one cancellable device attempt', async t => {
  const directory = await home(t);
  const issuer = await issuerFixture(t, { pendingForever: true });
  const { profile, headers, endpoint } = await serviceFor(t, issuer, directory);

  const browser = await post(endpoint, headers, {});
  assert.equal(browser.response.status, 200, JSON.stringify(browser.body));
  assert.deepEqual(Object.keys(browser.body).sort(), ['attempt_id', 'url']);
  assert.equal(new URL(browser.body.url).origin, issuer.address);
  const browserCancel = await post(endpoint, headers, { action: 'cancel', attempt_id: browser.body.attempt_id });
  assert.equal(browserCancel.response.status, 200, JSON.stringify(browserCancel.body));
  assert.equal(browserCancel.body.status, 'cancelled');
  assert.equal(issuer.requests.some(request => request.url === '/oauth/token'), false,
    'cancelling browser login must not exchange an authorization code');

  const started = await post(endpoint, headers, { method: 'device_code' });
  assert.equal(started.response.status, 200, JSON.stringify(started.body));
  assert.deepEqual(Object.keys(started.body).sort(), ['attempt_id', 'expires_at', 'user_code', 'verification_url']);
  const conflict = await post(endpoint, headers, { method: 'device_code' });
  assert.equal(conflict.response.status, 409, JSON.stringify(conflict.body));

  const cancelled = await post(endpoint, headers, { action: 'cancel', attempt_id: started.body.attempt_id });
  assert.equal(cancelled.response.status, 200, JSON.stringify(cancelled.body));
  assert.equal(cancelled.body.status, 'cancelled');
  const status = await post(endpoint, headers, { action: 'status', attempt_id: started.body.attempt_id });
  assert.equal(status.response.status, 200, JSON.stringify(status.body));
  assert.equal(status.body.status, 'cancelled');
  await assert.rejects(access(path.resolve(directory, profile.auth_file)), { code: 'ENOENT' });
  assert.equal(issuer.requests.some(request => request.url === '/oauth/token'), false,
    'a cancelled attempt must not exchange a grant or save credentials');
  assertNoCredentials(browser.body, ['fixture-device-auth-1', 'fixture-device-access-secret', 'fixture-device-refresh-secret']);
  assertNoCredentials(browserCancel.body, ['fixture-device-auth-1', 'fixture-device-access-secret', 'fixture-device-refresh-secret']);
  assertNoCredentials(cancelled.body, ['fixture-device-auth-1', 'fixture-device-access-secret', 'fixture-device-refresh-secret']);
});

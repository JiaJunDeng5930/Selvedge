import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile, writeFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { login, resolveAuth } from '../host/auth.mjs';
import { home } from './support.mjs';

const jwt = (account, exp = Math.floor(Date.now() / 1000) + 3600) =>
  `fixture.${Buffer.from(JSON.stringify({ exp, 'https://api.openai.com/auth': { chatgpt_account_id: account } })).toString('base64url')}.fixture`;
const tokens = (account, exp) => ({ access_token: jwt(account, exp), id_token: jwt(account), refresh_token: 'fixture-refresh-token' });

async function issuer(t, handler) {
  const requests = [];
  const failures = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      const form = request.headers['content-type'] === 'application/x-www-form-urlencoded';
      const body = form ? Object.fromEntries(new URLSearchParams(raw)) : JSON.parse(raw);
      // The two OAuth grants intentionally have different upstream encodings.
      assert.equal(form, body.grant_type === 'authorization_code');
      requests.push({ path: request.url, body });
      const result = handler(request.url, body);
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(result));
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { address: `http://127.0.0.1:${server.address().port}`, requests, failures };
}

test('device login persists a private credential and uses the received authorization grant', async t => {
  const directory = await home(t);
  const upstream = await issuer(t, (url, body) => {
    assert.equal(body.client_id ?? 'fixture-client', 'fixture-client');
    if (url.endsWith('/usercode')) return { device_auth_id: 'device-fixture', user_code: 'USER-CODE', interval: 1 };
    if (url.endsWith('/deviceauth/token')) {
      assert.deepEqual(body, { device_auth_id: 'device-fixture', user_code: 'USER-CODE' });
      return { authorization_code: 'grant-fixture', code_verifier: 'verifier-fixture' };
    }
    assert.equal(url, '/oauth/token');
    assert.equal(body.grant_type, 'authorization_code');
    assert.equal(body.code, 'grant-fixture');
    assert.equal(body.code_verifier, 'verifier-fixture');
    assert.equal(body.redirect_uri, `${upstream.address}/deviceauth/callback`);
    return tokens('account-fixture');
  });
  const profile = { issuer: upstream.address, client_id: 'fixture-client', auth_file: 'auth/chatgpt.json' };
  const codes = [];
  const result = await login(profile, directory, { onCode: code => codes.push(code) });
  assert.equal(result.account_id, 'account-fixture');
  assert.deepEqual(codes, [{ url: `${upstream.address}/codex/device`, code: 'USER-CODE' }]);
  assert.equal((await stat(result.filename)).mode & 0o777, 0o600);
  assert.equal((await resolveAuth(profile, directory)).account_id, 'account-fixture');
  assert.equal(upstream.requests.length, 3);
  assert.deepEqual(upstream.failures, []);
});

test('concurrent refreshes reuse one result and cannot replace the account identity', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'credential.json');
  const current = { format: 'selvedge-chatgpt-1', ...tokens('original', 0), account_id: 'original', last_refresh: new Date(0).toISOString() };
  await writeFile(filename, JSON.stringify(current), { mode: 0o600 });
  let account = 'original';
  const upstream = await issuer(t, (url, body) => {
    assert.equal(url, '/oauth/token');
    assert.equal(body.grant_type, 'refresh_token');
    assert.equal(body.refresh_token, 'fixture-refresh-token');
    return tokens(account);
  });
  const profile = { issuer: upstream.address, client_id: 'fixture-client', auth_file: filename };
  const refreshed = await Promise.all([1, 2, 3].map(() => resolveAuth(profile, directory)));
  assert.equal(upstream.requests.length, 1);
  assert.deepEqual(refreshed[0], refreshed[1]);
  assert.deepEqual(refreshed[1], refreshed[2]);
  const before = await readFile(filename, 'utf8');
  account = 'different-account';
  await assert.rejects(resolveAuth(profile, directory, { rejectedToken: refreshed[0].access_token }), /changed the ChatGPT account/);
  assert.equal(await readFile(filename, 'utf8'), before);
  assert.equal(upstream.requests.length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('malformed credential contents cannot escape in an error message', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'credential.json');
  const marker = 'SECRET-CREDENTIAL-MATERIAL';
  await writeFile(filename, marker, { mode: 0o600 });
  await assert.rejects(resolveAuth({ auth_file: filename }, directory), error => {
    assert.equal(error.message.includes('SECRET'), false);
    assert.match(error.message, /credential/i);
    return true;
  });
});

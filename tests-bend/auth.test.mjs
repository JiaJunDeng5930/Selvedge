import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { generateKeyPair } from 'jose';
import { login, authorize } from '../host/chatgpt-account.mjs';
import { requestModel } from '../host/providers.mjs';
import { chatgptFixture } from './fixtures/chatgpt.mjs';

const filename = upstream => path.join(upstream.directory, upstream.profile.auth_file);
const grants = upstream => upstream.oauthRequests.filter(request => request.url === '/oauth/token');

test('loopback login persists private credentials and rejects an untrusted signing key on reuse', async t => {
  const upstream = await chatgptFixture(t);
  const credentialFile = filename(upstream), registrationFile = `${credentialFile}.registration.json`;
  await login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize });
  const saved = await readFile(credentialFile, 'utf8');
  assert.equal((await authorize(upstream.profile, upstream.directory)).headers.authorization,
    `Bearer ${JSON.parse(saved).access_token}`);
  for (const file of [credentialFile, registrationFile, path.join(upstream.directory, 'auth/chatgpt-host.json')]) {
    assert.equal((await stat(file)).mode & 0o777, 0o600);
  }
  upstream.options.privateKey = (await generateKeyPair('RS256')).privateKey;
  await assert.rejects(login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize }));
  assert.equal(await readFile(credentialFile, 'utf8'), saved);
  const attempts = upstream.oauthRequests.filter(request => request.url.startsWith('/authorize?'));
  assert.deepEqual(attempts.map(request => new URL(request.url, upstream.address).searchParams.get('client_id')),
    ['dynamic_agent_client', 'fixture-issued-client']);
  assert.equal(grants(upstream).length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('concurrent account refresh rotates once and a repeated HTTP rejection stops after one further refresh', async t => {
  const upstream = await chatgptFixture(t);
  await upstream.seedExpiredCredential();
  const refreshed = await Promise.all([1, 2, 3].map(() => authorize(upstream.profile, upstream.directory)));
  assert.equal(grants(upstream).length, 1);
  for (const authorization of refreshed) assert.equal(authorization.headers.authorization, 'Bearer opaque-access-renewed-1');
  assert.equal(JSON.parse(await readFile(filename(upstream), 'utf8')).refresh_token, 'fixture-refresh-renewed-1');
  const effect = { kind: 'model', task_id: 1, ticket: 2,
    model: { profile: 'fixture', provider: 'chatgpt', name: 'fixture', reasoning: 'medium' },
    history: [{ role: 'user', content: 'hello' }], tools: [], callable: [] };
  const limits = { frame_bytes: 4 * 1024 * 1024, provider_checkpoint_limit_bytes: 262144,
    model_retry: { delays_ms: [], statuses: [], max_retry_after_ms: 0 } };
  await assert.rejects(requestModel(effect, { profiles: { fixture: upstream.profile } }, upstream.directory, limits), /HTTP 401/);
  assert.deepEqual(upstream.requests.map(request => request.headers.authorization),
    ['Bearer opaque-access-renewed-1', 'Bearer opaque-access-renewed-2']);
  assert.equal(grants(upstream).length, 2);
  assert.deepEqual(upstream.failures, []);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, stat, rm } from 'node:fs/promises';
import path from 'node:path';
import { generateKeyPair } from 'jose';
import { login, resolveAuth } from '../host/auth.mjs';
import { home } from './support.mjs';
import { chatgptFixture } from './fixtures/chatgpt.mjs';

const filename = upstream => path.join(upstream.directory, upstream.profile.auth_file);
const grants = upstream => upstream.oauthRequests.filter(request => request.url === '/oauth/token');
const fresh = async upstream => {
  await rm(filename(upstream));
  await rm(`${filename(upstream)}.registration.json`);
};

test('loopback OAuth verifies signed identity and persists private credentials and registration', async t => {
  const upstream = await chatgptFixture(t);
  await fresh(upstream);
  const result = await login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize });
  assert.equal(result.account_id, upstream.accountId('fixture-account'));
  const saved = JSON.parse(await readFile(filename(upstream), 'utf8'));
  assert.equal(saved.subject, 'fixture-account');
  assert.equal(saved.access_token, 'opaque-access-original', 'Opaque access tokens supply no identity claims');
  assert.equal(saved.client_id, 'fixture-issued-client');
  assert.equal(saved.format, 'selvedge-chatgpt-2');
  assert.equal((await stat(filename(upstream))).mode & 0o777, 0o600);
  assert.equal((await stat(`${filename(upstream)}.registration.json`)).mode & 0o777, 0o600);
  assert.equal((await stat(path.join(upstream.directory, 'auth/chatgpt-host.json'))).mode & 0o777, 0o600);
  assert.equal((await resolveAuth(upstream.profile, upstream.directory)).account_id, result.account_id);
  await login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize });
  const attempts = upstream.oauthRequests.filter(request => request.url.startsWith('/authorize?'));
  assert.equal(attempts.length, 2);
  assert.equal(new URL(attempts[0].url, upstream.address).searchParams.get('client_id'), 'dynamic_agent_client');
  assert.equal(new URL(attempts[1].url, upstream.address).searchParams.get('client_id'), 'fixture-issued-client');
  assert.deepEqual(upstream.failures, []);
});

test('concurrent refreshes rotate one credential and cannot replace verified identity', async t => {
  const upstream = await chatgptFixture(t);
  await upstream.save('fixture-account', 'original', { expires_at: new Date(0).toISOString() });
  const refreshed = await Promise.all([1, 2, 3].map(() => resolveAuth(upstream.profile, upstream.directory)));
  assert.equal(grants(upstream).length, 1);
  assert.deepEqual(refreshed[0], refreshed[1]); assert.deepEqual(refreshed[1], refreshed[2]);
  assert.equal(refreshed[0].refresh_token, 'fixture-refresh-renewed');
  const before = await readFile(filename(upstream), 'utf8');
  upstream.options.subject = 'different-account';
  await assert.rejects(resolveAuth(upstream.profile, upstream.directory, { rejectedToken: refreshed[0].access_token }), /identity verification/i);
  assert.equal(await readFile(filename(upstream), 'utf8'), before);
  assert.equal(grants(upstream).length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('invalid signed identity and missing plan scope never replace credentials', async t => {
  for (const [name, options] of [
    ['audience', { audience: 'foreign-client' }],
    ['nonce', { nonce: 'foreign-nonce' }],
    ['scope', { scope: 'openid profile email offline_access' }],
    ['signature', { privateKey: (await generateKeyPair('RS256')).privateKey }],
  ]) await t.test(name, async t => {
    const upstream = await chatgptFixture(t);
    const before = await readFile(filename(upstream), 'utf8');
    Object.assign(upstream.options, options);
    await assert.rejects(login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize }));
    assert.equal(await readFile(filename(upstream), 'utf8'), before);
    assert.equal(grants(upstream).length, 1);
    assert.deepEqual(upstream.failures, []);
  });
});

test('state mismatch makes no token exchange and a pending issued registration survives failure', async t => {
  const upstream = await chatgptFixture(t);
  await fresh(upstream);
  upstream.options.callbackState = 'wrong-state';
  await assert.rejects(login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize }));
  assert.equal(grants(upstream).length, 0);
  delete upstream.options.callbackState;
  upstream.options.tokenStatus = 503;
  await assert.rejects(login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize }));
  const pending = JSON.parse(await readFile(`${filename(upstream)}.registration.json`, 'utf8'));
  assert.equal(pending.client_id, 'fixture-issued-client'); assert.equal(pending.subject, null);
  await assert.rejects(stat(filename(upstream)), { code: 'ENOENT' });
  delete upstream.options.tokenStatus;
  await login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize });
  const attempts = upstream.oauthRequests.filter(request => request.url.startsWith('/authorize?'));
  assert.equal(new URL(attempts.at(-1).url, upstream.address).searchParams.get('client_id'), pending.client_id);
  assert.deepEqual(upstream.failures, []);
});

test('obsolete and malformed credentials fail without leaking material', async t => {
  const directory = await home(t), file = path.join(directory, 'credential.json');
  for (const value of ['SECRET-CREDENTIAL-MATERIAL', JSON.stringify({ format: 'selvedge-chatgpt-1', access_token: 'SECRET' })]) {
    await writeFile(file, value, { mode: 0o600 });
    await assert.rejects(resolveAuth({ auth_file: file }, directory), error => {
      assert.equal(error.message.includes('SECRET'), false); assert.match(error.message, /credential|authentication record/i); return true;
    });
  }
});

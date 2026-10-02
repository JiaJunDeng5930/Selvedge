import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, stat, rm } from 'node:fs/promises';
import path from 'node:path';
import { generateKeyPair } from 'jose';
import { login, authorize } from '../host/chatgpt-account.mjs';
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
  assert.equal((await authorize(upstream.profile, upstream.directory)).account_id, result.account_id);
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
  const refreshed = await Promise.all([1, 2, 3].map(() => authorize(upstream.profile, upstream.directory)));
  assert.equal(grants(upstream).length, 1);
  for (const authorization of refreshed) {
    assert.equal(authorization.account_id, refreshed[0].account_id);
    assert.deepEqual(authorization.headers, refreshed[0].headers);
  }
  const saved = JSON.parse(await readFile(filename(upstream), 'utf8'));
  assert.equal(saved.refresh_token, 'fixture-refresh-renewed');
  const before = await readFile(filename(upstream), 'utf8');
  upstream.options.subject = 'different-account';
  await assert.rejects(refreshed[0].refreshAfterRejection(), /identity verification/i);
  assert.equal(await readFile(filename(upstream), 'utf8'), before);
  assert.equal(grants(upstream).length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('invalid signed identity and missing plan scope never replace credentials', async t => {
  for (const [name, options] of [
    ['audience', { audience: 'foreign-client' }],
    ['authorized party', { claims: { azp: 'foreign-client' } }],
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
    await assert.rejects(authorize({ auth_file: file }, directory), error => {
      assert.equal(error.message.includes('SECRET'), false); assert.match(error.message, /credential|authentication record/i); return true;
    });
  }
});


test('refresh without optional identity or scope retains verified account fields', async t => {
  const upstream = await chatgptFixture(t);
  const before = await upstream.save('fixture-account', 'original', { expires_at: new Date(0).toISOString() });
  upstream.options.tokenOmissions = ['id_token', 'scope'];
  await authorize(upstream.profile, upstream.directory);
  const renewed = JSON.parse(await readFile(filename(upstream), 'utf8'));
  for (const key of ['subject', 'account_id', 'client_id', 'id_token', 'scope', 'name', 'email']) assert.equal(renewed[key], before[key]);
  assert.equal(renewed.refresh_token, 'fixture-refresh-renewed');
  assert.ok(Date.parse(renewed.expires_at) > Date.now());
  assert.equal(grants(upstream).length, 1);
  assert.deepEqual(upstream.failures, []);
});

test('a refresh without the required rotating token leaves credentials unchanged', async t => {
  const upstream = await chatgptFixture(t);
  await upstream.save('fixture-account', 'original', { expires_at: new Date(0).toISOString() });
  const before = await readFile(filename(upstream), 'utf8');
  upstream.options.tokenOmissions = ['refresh_token'];
  await assert.rejects(authorize(upstream.profile, upstream.directory));
  assert.equal(await readFile(filename(upstream), 'utf8'), before);
  assert.equal(grants(upstream).length, 1);
  assert.deepEqual(upstream.failures, []);
});

test('aborting login closes its callback listener without exchanging or replacing credentials', async t => {
  const upstream = await chatgptFixture(t);
  const before = await readFile(filename(upstream), 'utf8');
  const controller = new AbortController();
  let redirect;
  await assert.rejects(login(upstream.profile, upstream.directory, { signal: controller.signal, onAuthorize: ({ redirect_uri }) => {
    redirect = redirect_uri; controller.abort();
  } }), error => error.name === 'AbortError');
  assert.ok(redirect);
  await assert.rejects(fetch(redirect));
  assert.equal(grants(upstream).length, 0);
  assert.equal(await readFile(filename(upstream), 'utf8'), before);
  assert.deepEqual(upstream.failures, []);
});

test('aborting an in-flight grant cancels issuer HTTP and leaves credentials unchanged', { timeout: 5000 }, async t => {
  const upstream = await chatgptFixture(t);
  const before = await readFile(filename(upstream), 'utf8');
  const controller = new AbortController();
  let started, closed;
  const requested = new Promise(resolve => { started = resolve; });
  const disconnected = new Promise(resolve => { closed = resolve; });
  upstream.options.holdToken = (_, response) => {
    response.once('close', closed); started();
  };
  const attempt = login(upstream.profile, upstream.directory, { signal: controller.signal, onAuthorize: upstream.authorize });
  const rejected = assert.rejects(attempt, error => error.name === 'AbortError');
  await requested;
  controller.abort();
  await rejected;
  await disconnected;
  assert.equal(grants(upstream).length, 1);
  assert.equal(await readFile(filename(upstream), 'utf8'), before);
  assert.deepEqual(upstream.failures, []);
});

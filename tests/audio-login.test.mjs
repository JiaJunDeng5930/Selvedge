import test from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';

test('audio sign-in needs local authorization but no browser identity', async t => {
  const directory = await home(t);
  const signInURL = 'https://auth.openai.com/oauth/authorize?client_id=audio-login-fixture';
  let loginStarted = false;
  const running = await startServer({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0 }),
    audioOptions: { authorityFactory: () => ({
      async startLogin() { loginStarted = true; return { url: signInURL }; },
      async close() {},
    }) },
  });
  t.after(() => running.close());

  const endpoint = `${running.address}/api/audio/login`;
  const headers = { 'content-type': 'application/json' };
  const denied = await fetch(endpoint, { method: 'POST', headers, body: '{}' });
  await denied.arrayBuffer();
  assert.equal(denied.status, 401);
  assert.equal(loginStarted, false, 'An unauthenticated request must not start account sign-in');

  const admitted = await fetch(endpoint, { method: 'POST',
    headers: { ...headers, authorization: `Bearer ${running.token}` }, body: '{}' });
  const result = await admitted.json();
  assert.equal(admitted.status, 200, JSON.stringify(result));
  assert.equal(result.url, signInURL);
  assert.equal(loginStarted, true, 'The authorized request must reach the account provider');
});

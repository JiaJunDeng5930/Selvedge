import test from 'node:test';
import assert from 'node:assert/strict';
import { writeFile, readFile } from 'node:fs/promises';
import path from 'node:path';
import { createCodexAudioAccount } from '../host/codex-audio-account.mjs';
import { home } from './support.mjs';

const token = revision => `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify({
  'https://api.openai.com/auth': { chatgpt_account_id: 'fixture-account' }, revision,
})).toString('base64url')}.fixture`;

async function fixture(t, mode = 'chatgpt') {
  const directory = await home(t);
  const command = path.join(directory, 'official-codex-fixture');
  await writeFile(command, `#!${process.execPath}
import { createInterface } from 'node:readline';
import { appendFileSync } from 'node:fs';
import path from 'node:path';
const mode = ${JSON.stringify(mode)};
const calls = path.join(process.env.CODEX_HOME, 'calls.jsonl');
let revision = 0;
const token = ${token.toString()};
for await (const line of createInterface({ input: process.stdin })) {
  const message = JSON.parse(line);
  appendFileSync(calls, JSON.stringify({ method: message.method, params: message.params,
    cwd: process.cwd(), home: process.env.CODEX_HOME, hasApiKey: Boolean(process.env.OPENAI_API_KEY) }) + '\\n');
  if (!Object.hasOwn(message, 'id')) continue;
  let result;
  if (message.method === 'initialize') result = { userAgent: 'official-protocol-fixture' };
  else if (message.method === 'account/read') result = { account: { type: mode === 'apiKey' ? 'apiKey' : 'chatgpt' } };
  else if (message.method === 'account/login/start') result = { loginId: 'login-fixture', authUrl: 'https://auth.openai.com/oauth/authorize?state=fixture' };
  else if (message.method === 'getAuthStatus' && mode !== 'noTokenRpc') {
    if (message.params.refreshToken) revision++;
    result = { authMethod: mode === 'apiKey' ? 'apiKey' : 'chatgpt', authToken: token(revision) };
  } else { console.log(JSON.stringify({ id: message.id, error: { code: -32601, message: 'Method not found' } })); continue; }
  console.log(JSON.stringify({ id: message.id, result }));
  if (message.method === 'account/login/start') console.log(JSON.stringify({ method: 'account/login/completed', params: { loginId: 'login-fixture', success: true } }));
}
`, { mode: 0o700 });
  const changes = [];
  const authority = createCodexAudioAccount({ home: directory, command, onChange: value => changes.push(value) });
  t.after(() => authority.close());
  const calls = async () => (await readFile(path.join(directory, 'codex-audio/calls.jsonl'), 'utf8'))
    .trim().split('\n').map(line => JSON.parse(line));
  return { directory, authority, changes, calls };
}

test('official account process isolates credentials, reads metadata without tokens and refreshes the same account through public RPC', async t => {
  const previousKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'fixture-parent-key';
  t.after(() => { if (previousKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = previousKey; });
  const fixtureAccount = await fixture(t);
  const { authority, directory, changes, calls } = fixtureAccount;
  assert.deepEqual(await authority.connections(), [{ id: 'chatgpt-voice', label: 'ChatGPT', source: 'codex_audio', authorized: true }]);
  assert.deepEqual((await calls()).map(call => call.method), ['initialize', 'initialized', 'account/read']);
  const authorization = await authority.authorize('chatgpt-voice');
  assert.equal(authorization.headers.authorization, `Bearer ${token(0)}`);
  assert.equal(authorization.account_id, 'fixture-account');
  assert.equal(authorization.headers.originator, (await calls())[0].params.clientInfo.name);
  const refreshed = await authorization.refreshAfterRejection();
  assert.equal(refreshed.headers.authorization, `Bearer ${token(1)}`);
  assert.equal(refreshed.account_id, authorization.account_id);
  assert.equal(refreshed.headers.originator, authorization.headers.originator);
  assert.deepEqual(await authority.startLogin(), { url: 'https://auth.openai.com/oauth/authorize?state=fixture', login_id: 'login-fixture' });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(changes, [{ type: 'account_changed' }]);
  const observations = await calls();
  for (const call of observations) {
    assert.equal(call.cwd, path.join(directory, 'codex-audio'));
    assert.equal(call.home, call.cwd);
    assert.equal(call.hasApiKey, false);
  }
  assert.deepEqual(observations.filter(call => call.method === 'getAuthStatus').map(call => call.params),
    [{ includeToken: true, refreshToken: false }, { includeToken: true, refreshToken: true }]);
  assert.ok(observations.every(call => !call.method.startsWith('thread/') && !call.method.startsWith('turn/')));
  await authority.close();
  await assert.rejects(authority.connections(), /closed/);
});

test('API-key auth, absent official binary and removed token RPC do not acquire audio authority', async t => {
  const apiKey = await fixture(t, 'apiKey');
  assert.deepEqual(await apiKey.authority.connections(), []);
  await assert.rejects(apiKey.authority.authorize('chatgpt-voice'), /Official Codex ChatGPT audio authorization is required/);
  assert.ok((await apiKey.calls()).every(call => call.method !== 'getAuthStatus'));
  const removed = await fixture(t, 'noTokenRpc');
  await assert.rejects(removed.authority.authorize('chatgpt-voice'), /does not provide the required audio token RPC/);
  const directory = await home(t);
  const missing = createCodexAudioAccount({ home: directory, command: path.join(directory, 'not-installed') });
  t.after(() => missing.close());
  await assert.rejects(missing.connections(), /Install the official Codex CLI/);
});

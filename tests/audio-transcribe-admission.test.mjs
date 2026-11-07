import test from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';

test('audio transcription uses account authority without browser identity', async t => {
  const directory = await home(t);
  const connection = 'audio-transcribe-fixture';
  const accountCalls = [];
  const running = await startServer({ home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0 }),
    audioOptions: { authorityFactory: () => ({
      async connections() {
        accountCalls.push({ kind: 'connections' });
        return [{ id: connection, source: 'chatgpt_audio', authorized: true }];
      },
      async authorize(selected) {
        accountCalls.push({ kind: 'authorize', connection: selected });
        throw new Error('The audio account fixture denies authorization');
      },
      async close() {},
    }) },
  });
  t.after(() => running.close());

  // One mono PCM sample in an 8 kHz WAV keeps this an actual audio upload.
  const audio = Buffer.from('524946462600000057415645666d74201000000001000100401f0000803e00000200100064617461020000000000', 'hex');
  const endpoint = `${running.address}/api/audio/transcribe?connection=${encodeURIComponent(connection)}`;
  const headers = { 'content-type': 'audio/wav' };
  const denied = await fetch(endpoint, { method: 'POST', headers, body: audio });
  await denied.arrayBuffer();
  assert.equal(denied.status, 401);
  assert.deepEqual(accountCalls, [], 'An unauthenticated upload must not contact the account provider');

  const admitted = await fetch(endpoint, { method: 'POST',
    headers: { ...headers, authorization: `Bearer ${running.token}` }, body: audio });
  const response = await admitted.text();
  assert.ok(accountCalls.some(call => call.kind === 'authorize' && call.connection === connection),
    `The authenticated upload must reach the selected account without browser_id: HTTP ${admitted.status} ${response}`);
  assert.equal(admitted.ok, false, 'Denied account authorization must remain a failed transcription');
});

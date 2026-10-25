import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';

test('a provider diagnostic containing NUL settles assisted drafting without retiring the service', async t => {
  const directory = await home(t);
  const key = `SELVEDGE_DIAGNOSTIC_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-provider';
  t.after(() => { delete process.env[key]; });
  let requests = 0;
  const provider = http.createServer((request, response) => {
    request.resume();
    requests++;
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(`data: ${JSON.stringify({ type: 'response.completed', response: {
      status: 'completed', output: [{ type: 'a\u0000b' }],
    } })}\n\n`);
  });
  await new Promise((resolve, reject) => {
    provider.once('error', reject);
    provider.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => new Promise(resolve => {
    provider.close(resolve);
    provider.closeAllConnections();
  }));
  const running = await startServer({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, port: 0,
    profiles: { draft: { provider: 'responses', model: 'draft',
      endpoint: `http://127.0.0.1:${provider.address().port}/responses`, api_key_env: key } },
  }) });
  t.after(() => running.close());
  const command = async value => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(value), signal: AbortSignal.timeout(10_000) });
    const reply = await response.json();
    assert.equal(response.status, 200, JSON.stringify(reply));
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const created = await command({ op: 'create_card', title: 'Preserve this request',
    description: 'Draft a useful board card.', assisted: true, draft_profile: 'draft' });
  let card;
  const deadline = Date.now() + 10_000;
  do {
    card = await command({ op: 'read_card', card_id: created.card_id });
    if (card.enrichment.status === 'failed') break;
    await delay(10);
  } while (Date.now() < deadline);
  assert.equal(card.enrichment.status, 'failed', JSON.stringify(card));
  assert.match(card.enrichment.reason, /Unsupported provider output type/);
  assert.equal(card.enrichment.reason.includes('\u0000'), false);
  assert.match(card.enrichment.reason, /a\\(?:u0000|0)b/);
  assert.equal(card.title, 'Preserve this request');
  assert.equal(card.description, 'Draft a useful board card.');
  assert.equal(requests, 1);

  // Archiving is publicly refused while drafting is pending, so success observes settlement of the original request.
  await command({ op: 'archive_card', card_id: created.card_id, revision: card.revision });
  const next = await command({ op: 'create_card', title: 'The service remains usable' });
  assert.equal((await command({ op: 'read_card', card_id: next.card_id })).title,
    'The service remains usable');
});

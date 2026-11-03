import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

test('assisted cards trim the saved title and provider request before applying the title bound', async t => {
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const upstream = await responsesServer(t, async () => {
    await pending;
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text',
      text: JSON.stringify({ title: 'Generated title', description: 'Generated description' }) }] }];
  });
  const directory = await home(t);
  const credential = 'SELVEDGE_BOARD_NORMALIZATION_FIXTURE_KEY';
  const previous = process.env[credential];
  process.env[credential] = 'loopback-fixture';
  t.after(() => {
    if (previous === undefined) delete process.env[credential];
    else process.env[credential] = previous;
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    draft: { provider: 'responses', model: 'draft-fixture', endpoint: upstream.endpoint,
      api_key_env: credential, timeout_ms: 10_000 },
  } });
  const service = await Service.open({ home: directory, cwd: directory, config });
  t.after(async () => { release(); await service.close(); });
  const cases = [
    { title: '\uFEFF\t  Fix  now!?  \u00a0', description: '  Preserve this request.  ', expected: 'Fix  now!?' },
    { title: `${' '.repeat(2000)}BOUNDARY-TITLE`, description: 'Long raw title', expected: 'BOUNDARY-TITLE' },
    { title: ' \n\u3000', description: ` \n${'😀'.repeat(121)}\t `, expected: '😀'.repeat(120) },
  ];
  for (const input of cases) {
    const created = await service.command({ op: 'create_card', title: input.title,
      description: input.description, assisted: true, draft_profile: 'draft' });
    assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
    const card = (await service.command({ op: 'read_card', card_id: created.reply.result.card_id })).reply.result;
    assert.equal(card.title, input.expected);
    assert.equal(card.description, input.description);
  }
  const deadline = Date.now() + 5000;
  while (upstream.requests.length < cases.length && Date.now() < deadline) await delay(10);
  assert.equal(upstream.requests.length, cases.length);
  const prompts = upstream.requests.map(request => JSON.stringify(request.input));
  for (const input of cases) {
    const required = [input.expected, input.description].map(text => JSON.stringify(text).slice(1, -1));
    assert.ok(prompts.some(prompt => required.every(text => prompt.includes(text))), input.expected);
  }
  assert.ok(prompts.every(prompt => !prompt.includes(' '.repeat(2000))));

  const invalid = await service.command({ op: 'create_card', title: ' '.repeat(3000), assisted: true,
    draft_profile: 'missing' });
  assert.equal(invalid.reply.ok, false);
  assert.ok(invalid.reply.error?.code);
});

// Pure agent capacity, revision conflicts and slot reuse are
// owned by theories/Features/BoardAgentProofs.v at the actual save/delete handlers.

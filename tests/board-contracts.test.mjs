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
    { title: `${' '.repeat(2000)}x`, description: 'Long raw title', expected: 'x' },
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
    const preview = `Title/request preview:\n${input.expected}\n\nOriginal user request:\n${input.description}`;
    assert.ok(prompts.some(prompt => prompt.includes(JSON.stringify(preview).slice(1, -1))), input.expected);
  }
  assert.ok(prompts.every(prompt => !prompt.includes(' '.repeat(2000))));

  const ordinary = await service.command({ op: 'create_card', title: '  Keep spacing  ' });
  assert.equal(ordinary.reply.ok, true);
  const id = ordinary.reply.result.card_id;
  assert.equal((await service.command({ op: 'read_card', card_id: id })).reply.result.title, '  Keep spacing  ');
  assert.equal((await service.command({ op: 'update_card', card_id: id, revision: 0, title: '  Updated title  ' })).reply.ok, true);
  assert.equal((await service.command({ op: 'read_card', card_id: id })).reply.result.title, '  Updated title  ');
  const invalid = await service.command({ op: 'create_card', title: ' '.repeat(3000), assisted: true,
    draft_profile: 'missing' });
  assert.equal(invalid.reply.error.code, 'invalid_card');
});

test('board agent validation precedes capacity, lookup and revision failures', async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false });
  const service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  const agent = { op: 'save_board_agent', agent: '', revision: 0, name: 'Reviewer',
    profile: 'demo', reasoning: 'default', instructions: 'Review the saved request.', concurrency: 1 };
  const error = async (changes, expected) => {
    const result = await service.command({ ...agent, ...changes });
    assert.equal(result.reply.ok, false);
    assert.equal(result.reply.error.code, expected);
  };
  await error({ agent: '999', revision: 99, name: '' }, 'invalid_agent');
  await error({ agent: '999', revision: 99 }, 'agent_not_found');
  for (let index = 0; index < 64; index++) {
    const result = await service.command({ ...agent, name: `Reviewer ${index}` });
    assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
  }
  await error({ name: '' }, 'invalid_agent');
  await error({}, 'agent_limit');
  await error({ agent: '999' }, 'agent_not_found');
  await error({ agent: '0', revision: 1 }, 'agent_conflict');
  const updated = await service.command({ ...agent, agent: '0', name: 'Updated at capacity' });
  assert.equal(updated.reply.ok, true, JSON.stringify(updated.reply));
  assert.equal(updated.reply.result.revision, 1);
  assert.equal((await service.command({ op: 'delete_board_agent', agent_id: 1, revision: 0 })).reply.ok, true);
  await error({ agent: '1' }, 'agent_not_found');
  const replacement = await service.command(agent);
  assert.equal(replacement.reply.ok, true, JSON.stringify(replacement.reply));
});

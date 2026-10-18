import test from 'node:test';
import assert from 'node:assert/strict';
import { requestCompaction, providerSession } from '../host/providers.mjs';
import { validateConfig, defaultConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

const wireLimits = { frame_bytes: 4 * 1024 * 1024, provider_checkpoint_limit_bytes: 262144,
  model_retry: { delays_ms: [1], statuses: [429, 503], max_retry_after_ms: 100 } };

test('portable compaction sends the metered request with its original consumer after an API key rotation', async t => {
  const directory = await home(t);
  const key = 'SELVEDGE_PORTABLE_COMPACTION_SESSION_KEY';
  const previous = process.env[key];
  process.env[key] = 'original';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  let meter;
  const sent = [];
  const server = await responsesServer(t, (body, _, request) => {
    sent.push({ body, url: request.url, authorization: request.headers.authorization, key: process.env[key] });
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Pinned continuation note.' }] }];
  }, { measure: (body, request) => {
    meter = { body, url: request.url, authorization: request.headers.authorization, key: process.env[key] };
    process.env[key] = 'changed';
    return 100;
  } });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    provider: 'responses', model: 'fixture-model', endpoint: server.endpoint,
    api_key_env: key, timeout_ms: 5000,
  } } });
  const effect = {
    kind: 'context_compaction', task_id: 1, ticket: 2,
    model: { profile: 'fixture', provider: 'responses', name: 'fixture-model', reasoning: 'medium' },
    plan: { method: 'portable', window_tokens: 4096, output_reserve_tokens: 256,
      prompt: 'Produce a factual continuation note from the quoted task history. Return only the note.',
      carry: 'Prior note: retain the original decision.', chunk: 'Quoted history: continue after the Unicode edit 😀.' },
  };
  const initial = await providerSession(effect, config, directory);
  effect.context_scope = initial.scope;
  const result = await requestCompaction(effect, config, directory, wireLimits);

  assert.deepEqual(server.failures, []);
  assert.equal(meter.url, '/responses/input_tokens');
  assert.equal(meter.key, 'original');
  assert.equal(meter.authorization, 'Bearer original');
  assert.equal(process.env[key], 'changed', 'The token-count HTTP handler must actually rotate the environment credential');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, '/responses');
  assert.equal(sent[0].key, 'changed', 'The Responses HTTP request must arrive after the external credential changed');
  assert.equal(sent[0].authorization, 'Bearer original');
  const { model, input, instructions, tools, tool_choice, parallel_tool_calls } = sent[0].body;
  assert.deepEqual(meter.body, { model, input, tools, tool_choice, parallel_tool_calls,
    ...(Object.hasOwn(sent[0].body, 'instructions') ? { instructions } : {}) });
  assert.equal(sent[0].body.max_output_tokens, effect.plan.output_reserve_tokens);
  assert.equal(result.summary_text, 'Pinned continuation note.');
  assert.equal(result.scope, initial.scope);
});

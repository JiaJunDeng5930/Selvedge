import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile, rm, stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { accountModels, discoverAccount, withAccountModels, modelCacheFile, loginAccount } from '../host/chatgpt-models.mjs';
import { defaultChatGPTAccount } from '../host/chatgpt-account.mjs';
import { requestModel } from '../host/providers.mjs';
import { startServer } from '../host/server.mjs';
import { taskIdle, home } from './support.mjs';
import { chatgptFixture, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

const model = (slug = 'account-model', priority = 0, visibility = 'list') => ({
  slug, priority, visibility, display_name: `Model ${slug}`, supported_in_api: false,
  default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium', description: 'Normal' }, { effort: 'high', description: 'High' }],
});
const configFor = profile => validateConfig({ ...defaultConfig, port: 0, chatgpt: profile });
const walk = node => [node, ...(node.children ?? []).flatMap(walk)];

test('login needs no model profile, and a logged-out home makes no model request', async t => {
  const config = validateConfig(defaultConfig);
  assert.deepEqual(loginAccount(config), defaultChatGPTAccount);
  assert.deepEqual(validateConfig(config), config);
  const result = await withAccountModels(config, await home(t));
  assert.deepEqual(result.config.profiles, config.profiles);
  assert.deepEqual(result.accounts, []);
  assert.throws(() => loginAccount({ ...config, chatgpt: false }), /disabled/);
  assert.throws(() => loginAccount(config, 'demo'), /ChatGPT profile/);
});

test('the account catalog is authenticated, ordered, cached and not filtered by API-key support', async t => {
  const upstream = await chatgptFixture(t, (request, response) => {
    assert.equal(request.method, 'GET');
    assert.equal(request.url, '/v1/models');
    assert.equal(request.headers.authorization, 'Bearer opaque-access-original');
    jsonResponse(response, { models: [model('second', 2), model('hidden', -1, 'hide'), model('first', 0), model('unavailable', -2, 'none')] });
  });
  const config = configFor(upstream.profile);
  const first = await withAccountModels(config, upstream.directory);
  assert.deepEqual(Object.values(first.config.profiles).map(profile => profile.model), ['second', 'first', 'echo']);
  const key = Object.keys(first.config.profiles)[0];
  assert.match(key, /^chatgpt\/[a-f0-9]{16}\/second$/);
  assert.equal(first.config.profiles[key].bound_account_id, upstream.accountId('fixture-account'));
  assert.equal((await stat(modelCacheFile(upstream.profile, upstream.directory))).mode & 0o777, 0o600);
  const second = await withAccountModels(config, upstream.directory);
  assert.deepEqual(first.config.profiles, second.config.profiles);
  assert.equal(second.accounts[0].cached, true);
  assert.equal(upstream.requests.length, 1);
  await withAccountModels(config, upstream.directory, { force: true });
  assert.equal(upstream.requests.length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('login materializes an independent Astra Auto profile and preserves a manual policy override', async t => {
  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, {
    models: [model('gpt-6-astra'), model('another-account-model', 1)],
  }));
  const config = configFor(upstream.profile);
  const first = await withAccountModels(config, upstream.directory);
  const autoKey = Object.keys(first.config.profiles).find(key => key.endsWith('/gpt-6-astra-auto'));
  assert.ok(autoKey);
  const baseKey = autoKey.slice(0, -5);
  const auto = first.config.profiles[autoKey];
  assert.equal(auto.model, 'gpt-6-astra');
  assert.equal(auto.bound_account_id, first.config.profiles[baseKey].bound_account_id);
  assert.equal(auto.adaptive_reasoning.evaluator, 'jev');
  assert.deepEqual(auto.adaptive_reasoning.efforts, ['medium', 'high']);
  assert.equal(first.config.profiles[baseKey].adaptive_reasoning, undefined);
  assert.deepEqual(first.config.reasoning_evaluators, {});
  assert.equal(Object.keys(first.config.profiles).filter(key => key.endsWith('-auto')).length, 1);
  const manual = validateConfig({ ...config, profiles: { ...config.profiles,
    [autoKey]: { ...upstream.profile, model: 'gpt-6-astra', adaptive_reasoning: {
      ...auto.adaptive_reasoning, evaluator: 'my-evaluator', max_lease: 2,
    } },
  } });
  const overridden = await withAccountModels(manual, upstream.directory);
  assert.equal(overridden.config.profiles[autoKey].adaptive_reasoning.evaluator, 'my-evaluator');
  assert.equal(overridden.config.profiles[autoKey].adaptive_reasoning.max_lease, 2);
  assert.equal(overridden.config.profiles[baseKey].adaptive_reasoning, undefined,
    'discovering from an adaptive profile must not spread its policy to ordinary account models');
  assert.deepEqual(upstream.failures, []);
});

test('cache fallback is bounded and cannot mask invalid data, authorization failure or account changes', async t => {
  let status = 200;
  let payload = { models: [model()] };
  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, payload, status));
  const options = { now: Date.now() - 10 * 60_000 };
  await discoverAccount(upstream.profile, upstream.directory, options);
  status = 503;
  assert.equal((await discoverAccount(upstream.profile, upstream.directory)).stale, true);
  await assert.rejects(discoverAccount(upstream.profile, upstream.directory, { force: true }), /HTTP 503/);
  status = 403;
  await assert.rejects(discoverAccount(upstream.profile, upstream.directory), /HTTP 403/);
  status = 200;
  payload = { data: [{ id: 'not-the-account-contract' }] };
  await assert.rejects(discoverAccount(upstream.profile, upstream.directory), /invalid model catalog/);
  payload = { models: [model()] };
  const before = await withAccountModels(configFor(upstream.profile), upstream.directory, { force: true });
  await upstream.save('another-account');
  const after = await withAccountModels(configFor(upstream.profile), upstream.directory);
  assert.notEqual(Object.keys(before.config.profiles)[0], Object.keys(after.config.profiles)[0]);
  const oldKey = Object.keys(before.config.profiles)[0];
  const effect = modelEffect();
  effect.model.profile = oldKey;
  const calls = upstream.requests.length;
  await assert.rejects(requestModel(effect, before.config, upstream.directory, wireLimits), /different ChatGPT account/);
  assert.equal(upstream.requests.length, calls, 'A frozen old-account task must fail before an HTTP model call');
  const cached = JSON.parse(await readFile(modelCacheFile(upstream.profile, upstream.directory), 'utf8'));
  cached.fetched_at = new Date(Date.now() - 25 * 60 * 60_000).toISOString();
  await writeFile(modelCacheFile(upstream.profile, upstream.directory), JSON.stringify(cached));
  status = 503;
  await assert.rejects(discoverAccount(upstream.profile, upstream.directory), /HTTP 503/);
});

test('minimal official descriptors are usable without optional capability metadata', () => {
  const models = accountModels({ models: [{ slug: 'minimal', display_name: 'Minimal', visibility: 'list' }] });
  assert.equal(models[0].slug, 'minimal');
});

test('catalog decode rejects wrong envelopes, duplicate models, malformed capabilities, and hidden-only accounts', async t => {
  assert.throws(() => accountModels({ data: [] }), /catalog/);
  for (const models of [[model(), model()], [{ ...model(), supported_reasoning_levels: null }], [{ ...model(), slug: '../ bad' }]]) {
    assert.throws(() => accountModels({ models }), /descriptor/);
  }
  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, { models: [model('hidden', 0, 'hide')] }));
  await assert.rejects(discoverAccount(upstream.profile, upstream.directory), /no selectable/);
  await writeFile(modelCacheFile(upstream.profile, upstream.directory), 'PRIVATE-CORRUPT-CACHE');
  await assert.rejects(discoverAccount(upstream.profile, upstream.directory), error => !error.message.includes('PRIVATE') && /no selectable/.test(error.message));
});

test('login CLI discovers models and hot-refreshes a running native UI without editing model configuration', { timeout: 20_000 }, async t => {
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.method === 'GET') jsonResponse(response, { models: [model()] });
    else modelResponse(response, [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Discovered model answered.' }] }]);
  });
  await rm(path.join(upstream.directory, upstream.profile.auth_file));
  await rm(path.join(upstream.directory, `${upstream.profile.auth_file}.registration.json`));
  const config = configFor(upstream.profile);
  const filename = path.join(upstream.directory, 'config.json');
  await writeFile(filename, JSON.stringify(config));
  let server = await startServer({ home: upstream.directory, config, cwd: upstream.directory });
  t.after(() => server.close());
  const initialSequence = server.service.journal.sequence;
  const child = spawn(process.execPath, [fileURLToPath(new URL('../host/cli.mjs', import.meta.url)), '--home', upstream.directory, 'login']);
  t.after(() => child.kill());
  let stdout = '', stderr = '', authorizing;
  child.stderr.on('data', chunk => { stderr += chunk; });
  child.stdout.on('data', chunk => {
    stdout += chunk;
    const url = stdout.match(/Continue with ChatGPT: (http[^\s]+)/)?.[1];
    if (url && !authorizing) authorizing = upstream.authorize({ url });
  });
  const exit = await new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', resolve); });
  if (authorizing) await authorizing;
  assert.equal(exit, 0, stderr);
  assert.match(stdout, /Available account models: account-model/);
  assert.match(stdout, /model selector has been refreshed/);
  assert.equal(await readFile(filename, 'utf8'), JSON.stringify(config));
  assert.ok(server.service.journal.sequence > initialSequence);
  const result = await server.service.presentation({ event: { type: 'refresh' } });
  const form = walk(result.reply.result.presentation.root).find(node => node.key === 'create');
  const key = form.fields.find(field => field.name === 'profile').value;
  assert.match(key, /^chatgpt\//);
  const created = await server.service.command({ op: 'create', profile: key, message: 'Use the discovered model.' });
  assert.equal(created.reply.ok, true);
  const finished = await taskIdle(server.service);
  assert.ok(finished.messages.some(message => message.role === 'model_context' && message.content.content?.[0]?.text === 'Discovered model answered.'));
  await server.close();
  server = await startServer({ home: upstream.directory, config, cwd: upstream.directory });
  assert.ok(Object.hasOwn(server.service.config.profiles, key));
  const response = await fetch(`${server.address}/api/accounts/refresh`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
  assert.equal(response.status, 401);
  assert.deepEqual(upstream.failures, []);
});

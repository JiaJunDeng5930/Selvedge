import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile, rm, stat, realpath } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { accountModels, discoverAccount, withAccountModels, modelCacheFile, loginAccount } from '../host/chatgpt-models.mjs';
import { defaultChatGPTAccount } from '../host/chatgpt-account.mjs';
import { requestModel } from '../host/providers.mjs';
import { startServer } from '../host/server.mjs';
import { taskIdle, home, browserUI, surfaceNodes } from './support.mjs';
import { bendValue, bendTag } from '../host/public/bend-value.mjs';
import browserModel from '../host/public/generated/browser-model.mjs';
import { chatgptFixture, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

const model = (slug = 'account-model', priority = 0, visibility = 'list') => ({
  slug, priority, visibility, display_name: `Model ${slug}`, supported_in_api: false,
  default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium', description: 'Normal' }, { effort: 'high', description: 'High' }],
});
const configFor = profile => validateConfig({ ...defaultConfig, port: 0, chatgpt: profile });

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

test('login CLI hot-refresh selects the discovered model in the browser draft without editing model configuration', { timeout: 20_000 }, async t => {
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
  const snapshot = server.service.browserSnapshot();
  const state = browserModel.initial(snapshot.program, BigInt(snapshot.sequence));
  const key = state.legacy.web.application.core.application.session.drafts.head.body.profile;
  const profiles = snapshot.program.local.environment.profiles;
  assert.equal(key, profiles.head.key);
  const profileKeys = [];
  for (let rest = profiles; rest.head; rest = rest.tail) profileKeys.push(rest.head.key);
  assert.ok(profileKeys.includes(key));
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

function runtimeSession(state) {
  return state.legacy.web.application.core.application.session;
}

function creationDraft(state) {
  for (let drafts = runtimeSession(state).drafts; bendTag(drafts) === 'Con'; drafts = drafts.tail) {
    if (bendTag(drafts.head.body) === 'NewTask') return drafts.head.body;
  }
  throw new Error('The production runtime did not expose a new-task draft');
}

function applicationEvent(input) {
  return bendValue('browser/runtime/SEMANTICS.Native', { input:
    bendValue('browser/MODEL.PlatformInput', { input:
      bendValue('browser/runtime/PLATFORM.ProductInput', { input:
        bendValue('interaction/MODEL.InterfaceInput', { input:
          bendValue('interaction/TYPES.ApplicationInput', { input }) }) }) }) });
}

function preferenceEffects(decision) {
  const effects = [];
  for (let rest = decision.effects; bendTag(rest) === 'Con'; rest = rest.tail) {
    if (bendTag(rest.head) === 'PersistModelPreference') effects.push(rest.head);
  }
  return effects;
}

test('the browser reasoning choice reaches the authenticated server with each current approval policy', { timeout: 180_000 }, async t => {
  const ui = await browserUI(t);
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.method === 'GET') jsonResponse(response, { models: [model('task-edit')] });
    else modelResponse(response, [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Task settled.' }] }]);
  });
  const config = validateConfig({ ...defaultConfig, port: 0, profiles: {}, chatgpt: upstream.profile });
  const workspace = await realpath(upstream.directory);
  const server = await startServer({ home: upstream.directory, cwd: workspace, config });
  t.after(() => server.close());
  const profile = server.service.browserSnapshot().program.local.environment.profiles.head.key;
  const project = await server.service.command({ op: 'create_project', name: 'Browser configuration project',
    workspace: { roots: [workspace], primary_root: workspace } });
  assert.equal(project.reply.ok, true, JSON.stringify(project.reply));
  const policies = [
    { mode: 'ask-for-approval' },
    { mode: 'full-access' },
    { mode: 'approval-for-me', reviewer_profile: profile },
  ];
  for (const [task, approval] of policies.entries()) {
    const created = await server.service.command({ op: 'create', profile, reasoning: 'medium', message: 'Existing task.',
      settings: { project_id: project.reply.result.project_id, approval } });
    assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
    const before = await taskIdle(server.service, task);
    assert.equal(before.task.settings.approval.mode, approval.mode);
    assert.equal(before.task.settings.project_id, project.reply.result.project_id);
    assert.deepEqual(before.task.settings.workspace, { roots: [workspace], primary_root: workspace });
    const snapshot = server.service.browserSnapshot();
    const authenticated = ui.authenticated(snapshot.program, BigInt(task));
    assert.equal(bendTag(authenticated), 'Done');
    const selected = authenticated.value;
    const modelControl = surfaceNodes(ui.surface_state(selected))
      .find(node => node.semantic === `composer/model/message/${task}`);
    assert.ok(modelControl, 'The selected task must expose its actual model control');
    const opened = ui.activate_state(selected, ui.key(modelControl));
    const decisions = surfaceNodes(ui.surface_state(opened)).filter(node =>
      bendTag(node.meaning) === 'DecisionGroup'
      && bendTag(node.meaning.decision.subject.field) === 'ReasoningEffort');
    assert.equal(decisions.length, 1, 'The actual model menu must expose one reasoning decision');
    assert.equal(bendTag(decisions[0].meaning.decision.subject.editor), 'MessageEditor');
    assert.equal(Number(decisions[0].meaning.decision.subject.editor.task), task);
    const options = [];
    for (let rest = decisions[0].children; bendTag(rest) === 'Con'; rest = rest.tail) options.push(rest.head);
    const high = options.find(node => node.semantic === 'effort/high');
    assert.ok(high, 'The actual reasoning decision must expose the permitted high option');
    assert.equal(bendTag(high.meaning), 'Choice');
    assert.equal(bendTag(high.meaning.kind), 'SingleChoice');
    assert.equal(bendTag(high.meaning.availability), 'Available');
    assert.equal(high.meaning.selected, false);
    const pressed = ui.press_state(opened, ui.key(high));
    assert.equal(bendTag(pressed), 'Done');
    const commands = JSON.parse(pressed.value);
    assert.equal(commands.length, 1, `Task ${task} reasoning choice must emit one actual server command`);
    const generatedBody = commands[0];
    assert.equal(generatedBody.op, 'configure_task_execution');
    assert.equal(generatedBody.task_id, task);
    assert.equal(generatedBody.approval.mode, approval.mode);
    assert.equal(Object.hasOwn(generatedBody.approval, 'reviewer'), false);
    if (approval.reviewer_profile) assert.equal(generatedBody.approval.reviewer_profile, approval.reviewer_profile);
    const response = await fetch(`${server.address}/api/browser/command`, { method: 'POST',
      headers: { authorization: `Bearer ${server.token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ command: generatedBody }) });
    const result = await response.json();
    assert.equal(response.status, 200, JSON.stringify(result));
    assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
    const after = await server.service.command({ op: 'read', task_id: task });
    assert.equal(after.reply.ok, true, JSON.stringify(after.reply));
    assert.deepEqual(after.reply.result, { ...before, task: { ...before.task, reasoning: 'high' } },
      'A browser reasoning change must preserve model, approval, sandbox, project, workspace and complete history');
  }
  assert.deepEqual(upstream.failures, []);
});

test('catalog observation resolves the boot draft and a persisted user model choice survives a fresh runtime', { timeout: 20_000 }, async t => {
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.method === 'GET') jsonResponse(response, { models: [model('preference-a'), model('preference-b', 1)] });
    else modelResponse(response, [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Selected model answered.' }] }]);
  });
  const config = validateConfig({ ...defaultConfig, port: 0, profiles: {}, chatgpt: upstream.profile });
  const server = await startServer({ home: upstream.directory, cwd: upstream.directory, config });
  t.after(() => server.close());
  const snapshot = server.service.browserSnapshot();
  const firstProfile = snapshot.program.local.environment.profiles.head;
  const profiles = [];
  for (let rest = snapshot.program.local.environment.profiles; bendTag(rest) === 'Con'; rest = rest.tail) profiles.push(rest.head);
  assert.ok(profiles.length >= 2);
  const selected = profiles.find(profile => profile.key !== firstProfile.key);
  let state = browserModel.initial(browserModel.empty(), 0n);
  assert.equal(creationDraft(state).profile, '');
  state = browserModel.step(bendValue('browser/runtime/SEMANTICS.Snapshot', {
    sequence: BigInt(snapshot.sequence), program: snapshot.program }), state).state;
  assert.equal(creationDraft(state).profile, firstProfile.key);
  assert.equal(creationDraft(state).reasoning, 'medium');
  assert.equal((await server.service.command({ op: 'create', profile: firstProfile.key, reasoning: 'medium', message: 'Existing task.' })).reply.ok, true);
  const existing = await taskIdle(server.service, 0);
  const populated = server.service.browserSnapshot();
  state = browserModel.step(bendValue('browser/runtime/SEMANTICS.Snapshot', {
    sequence: BigInt(populated.sequence), program: populated.program }), state).state;
  const changed = browserModel.step(applicationEvent(bendValue('interaction/session/MODEL.UserInput', { input:
    bendValue('interaction/INPUT.EditDraft', { editor: bendValue('interaction/INPUT.NewTaskEditor'),
      edit: bendValue('interaction/INPUT.ChooseModel', { profile: selected.key, reasoning: 'high' }) }) })), state);
  assert.equal(creationDraft(changed.state).profile, selected.key);
  assert.equal(creationDraft(changed.state).reasoning, 'high');
  const persisted = preferenceEffects(changed);
  assert.equal(persisted.length, 1, 'A valid manual choice must request preference persistence');
  assert.equal(persisted[0].profile, selected.key);
  assert.equal(persisted[0].reasoning, 'high');

  let restored = browserModel.initial(browserModel.empty(), 0n);
  restored = browserModel.step(applicationEvent(bendValue('interaction/session/MODEL.ModelPreferenceRestored', {
    profile: persisted[0].profile, reasoning: persisted[0].reasoning })), restored).state;
  restored = browserModel.step(bendValue('browser/runtime/SEMANTICS.Snapshot', {
    sequence: BigInt(populated.sequence), program: populated.program }), restored).state;
  const restoredDraft = creationDraft(restored);
  assert.equal(restoredDraft.profile, selected.key);
  assert.equal(restoredDraft.reasoning, 'high');
  assert.deepEqual((await server.service.command({ op: 'read', task_id: 0 })).reply.result, existing);
  assert.equal((await server.service.command({ op: 'create', profile: restoredDraft.profile,
    reasoning: restoredDraft.reasoning, message: 'Restored preference task.' })).reply.ok, true);
  const created = await taskIdle(server.service, 1);
  assert.equal(created.task.profile, selected.key);
  assert.equal(created.task.reasoning, 'high');
  const modelRequests = upstream.requests.filter(request => request.method === 'POST' && request.url === '/v1/responses');
  assert.equal(modelRequests.length, 2);
  assert.equal(modelRequests[1].body.model, selected.name);
  assert.equal((await server.service.command({ op: 'read', task_id: 0 })).reply.result.task.profile, firstProfile.key);
  assert.deepEqual(upstream.failures, []);
});

test('an empty catalog leaves the runtime model selection unavailable', { timeout: 180_000 }, async t => {
  const state = browserModel.initial(browserModel.empty(), 0n);
  assert.equal(creationDraft(state).profile, '');
  assert.equal(creationDraft(state).reasoning, '');
  const ui = await browserUI(t);
  const surface = ui.surface_state(state.legacy.web.application.core);
  const modelControl = surfaceNodes(surface).find(node => node.semantic === 'composer/model');
  assert.ok(modelControl, 'The empty-catalog composer must still expose its model control');
  assert.equal(bendTag(modelControl.meaning.availability), 'Unavailable');
  const invalid = browserModel.step(applicationEvent(bendValue('interaction/session/MODEL.UserInput', { input:
    bendValue('interaction/INPUT.EditDraft', { editor: bendValue('interaction/INPUT.NewTaskEditor'),
      edit: bendValue('interaction/INPUT.ChooseModel', { profile: 'absent', reasoning: 'high' }) }) })), state);
  assert.equal(creationDraft(invalid.state).profile, '');
  assert.deepEqual(preferenceEffects(invalid), []);
});

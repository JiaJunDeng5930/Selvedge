import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile, rm, stat, realpath, mkdir } from 'node:fs/promises';
import { execFile, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { accountModels, discoverAccount, withAccountModels, modelCacheFile, loginAccount } from '../host/chatgpt-models.mjs';
import { defaultChatGPTAccount } from '../host/chatgpt-account.mjs';
import { requestModel } from '../host/providers.mjs';
import { startServer } from '../host/server.mjs';
import { taskIdle, home, browserUI, surfaceNodes, shellQuote } from './support.mjs';
import { bendValue, bendTag } from '../host/public/bend-value.mjs';
import browserModel from '../host/public/generated/browser-model.mjs';
import { chatgptFixture, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

const model = (slug = 'account-model', priority = 0, visibility = 'list') => ({
  slug, priority, visibility, display_name: `Model ${slug}`, supported_in_api: false,
  default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium', description: 'Normal' }, { effort: 'high', description: 'High' }],
});
const configFor = profile => validateConfig({ ...defaultConfig, port: 0, chatgpt: profile });
const autoReviewModel = (visibility = 'hide') => ({ ...model('codex-auto-review', -10, visibility),
  supported_reasoning_levels: [{ effort: 'low', description: 'Review' }, ...model().supported_reasoning_levels],
});

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
    jsonResponse(response, { models: [autoReviewModel(), model('second', 2), model('hidden', -1, 'hide'),
      model('first', 0), model('unavailable', -2, 'none')] });
  });
  const config = configFor(upstream.profile);
  const diagnostics = [];
  const first = await withAccountModels(config, upstream.directory, { onDiagnostic: message => diagnostics.push(message) });
  assert.deepEqual(Object.values(first.config.profiles).map(profile => profile.model), ['second', 'first', 'codex-auto-review', 'echo']);
  const key = Object.keys(first.config.profiles)[0];
  assert.match(key, /^chatgpt\/[a-f0-9]{16}\/second$/);
  assert.equal(first.config.profiles[key].bound_account_id, upstream.accountId('fixture-account'));
  assert.equal(first.config.profiles[key].model_info.default_reasoning_level, 'medium');
  const reviewerKey = key.replace(/\/second$/, '/codex-auto-review');
  const reviewer = first.config.profiles[reviewerKey];
  assert.equal(reviewer.model_info.visibility, 'hide');
  assert.equal(reviewer.model_info.default_reasoning_level, 'low');
  assert.equal(reviewer.endpoint, upstream.profile.endpoint);
  assert.equal(reviewer.bound_account_id, first.config.profiles[key].bound_account_id);
  assert.equal(first.accounts[0].models, 2, 'The hidden reviewer must not count as an ordinary account model');
  assert.deepEqual(diagnostics, []);
  assert.equal((await stat(modelCacheFile(upstream.profile, upstream.directory))).mode & 0o777, 0o600);
  const cached = JSON.parse(await readFile(modelCacheFile(upstream.profile, upstream.directory), 'utf8'));
  assert.equal(cached.models.find(model => model.slug === 'codex-auto-review').default_reasoning_level, 'medium',
    'Caching must retain the advertised descriptor rather than its reviewer-only low-effort preference');
  const second = await withAccountModels(config, upstream.directory);
  assert.deepEqual(first.config.profiles, second.config.profiles);
  assert.equal(second.accounts[0].cached, true);
  assert.equal(upstream.requests.length, 1);
  await withAccountModels(config, upstream.directory, { force: true });
  assert.equal(upstream.requests.length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('missing or unavailable Codex Auto-review models report task-model fallback without exposing other hidden models', async t => {
  let advertised = [];
  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, {
    models: [...advertised, model('ordinary'), model('other-hidden', -20, 'hide')],
  }));
  const config = configFor(upstream.profile);
  for (const descriptors of [[], [autoReviewModel('none')]]) {
    advertised = descriptors;
    const diagnostics = [];
    const result = await withAccountModels(config, upstream.directory, { force: true,
      onDiagnostic: message => diagnostics.push(message) });
    assert.deepEqual(Object.values(result.config.profiles).map(profile => profile.model), ['ordinary', 'echo']);
    assert.equal(diagnostics.length, 1);
    assert.match(diagnostics[0], /does not advertise codex-auto-review.*defaults to the task model/);
  }
  advertised = [model('codex-auto-review', -10)];
  const diagnostics = [];
  const result = await withAccountModels(config, upstream.directory, { force: true,
    onDiagnostic: message => diagnostics.push(message) });
  assert.deepEqual(Object.values(result.config.profiles).map(profile => profile.model), ['ordinary', 'codex-auto-review', 'echo']);
  assert.equal(Object.values(result.config.profiles)[1].model_info.default_reasoning_level, 'medium',
    'A reviewer that does not advertise low effort must retain its advertised default');
  assert.deepEqual(diagnostics, []);
  assert.deepEqual(upstream.failures, []);
});

test('account approvals use their own Codex Auto-review endpoint, preserve explicit reviewers and cover managed Git worktrees', { timeout: 30_000 }, async t => {
  const scenarios = [];
  const reviews = [];
  const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
  const handler = account => (request, response) => {
    if (request.method === 'GET') return jsonResponse(response, { models: [autoReviewModel(), model(`task-${account}`)] });
    const { body } = request;
    if (body.instructions?.startsWith('You are an independent one-operation safety reviewer')) {
      const input = JSON.parse(body.input.findLast(item => item.role === 'user').content);
      const scenario = scenarios.find(scenario => scenario.arguments.command === input.command.arguments.command);
      assert.ok(scenario, 'The reviewer must receive one of the actual task commands');
      assert.equal(account, scenario.reviewAccount, 'A default reviewer must remain on its task account and endpoint');
      assert.equal(body.model, scenario.reviewModel);
      assert.deepEqual(body.reasoning, scenario.reviewModel === 'codex-auto-review' ? { effort: 'low' } : undefined);
      assert.deepEqual(body.tools, []);
      assert.equal(body.tool_choice, 'none');
      assert.deepEqual(input.command.arguments, scenario.arguments);
      assert.deepEqual(input.recent_user_requests_newest_first, [scenario.message]);
      if (scenario.worktree) {
        assert.deepEqual(input.task_settings.workspace, scenario.workspace);
        assert.deepEqual(input.task_settings.sandbox, { mode: 'read-only', network_access: false });
        assert.equal(input.task_settings.approval.reviewer_profile, scenario.reviewer);
      }
      assert.match(body.instructions, /keys decision \(allow or deny\) and reason/);
      reviews.push({ id: scenario.id, account, model: body.model });
      return modelResponse(response, answer(scenario.malformed
        ? JSON.stringify({ decision: 'allow', reason: 'The command is authorized.', outcome: 'allow' })
        : JSON.stringify({ decision: 'allow', reason: 'The user requested this exact output.' })));
    }
    const scenario = scenarios.find(scenario => body.input.some(item => item.role === 'user' && item.content === scenario.message));
    assert.ok(scenario, 'The ordinary model must receive its task message');
    assert.equal(account, scenario.taskAccount);
    assert.equal(body.model, `task-${account}`);
    if (scenario.worktree) assert.ok(JSON.stringify(body.input).includes(scenario.workspace.primary_root),
      'The task model must receive the committed managed-worktree settings before requesting approval');
    if (body.input.some(item => item.type === 'function_call_output')) return modelResponse(response, answer('The operation has settled.'));
    return modelResponse(response, [{ type: 'function_call', namespace: 'selvedge', call_id: scenario.id,
      name: 'bash', arguments: JSON.stringify(scenario.arguments) }]);
  };
  const first = await chatgptFixture(t, handler('first'));
  const second = await chatgptFixture(t, handler('second'));
  const secondAuthFile = path.join(second.directory, second.profile.auth_file);
  const config = validateConfig({ ...defaultConfig, port: 0, chatgpt: first.profile, profiles: {
    alternate: { ...second.profile, auth_file: secondAuthFile, model: 'task-second' },
    'alternate-relative': { ...second.profile, auth_file: path.relative(first.directory, secondAuthFile), model: 'task-second' },
    'chatgpt/custom': { ...second.profile, auth_file: secondAuthFile, model: 'task-second' },
  } });
  const server = await startServer({ home: first.directory, cwd: await realpath(first.directory), config });
  t.after(() => server.close());
  const toolEffects = [];
  server.service.journal.on('commit', decision => {
    toolEffects.push(...decision.effects.filter(effect => effect.kind === 'tool'));
  });
  const profile = (account, name) => Object.entries(server.service.config.profiles).find(([, profile]) =>
    profile.model === name && profile.endpoint === (account === 'first' ? first : second).profile.endpoint
      && profile.bound_account_id)?.[0];
  const firstTask = profile('first', 'task-first');
  const secondTask = profile('second', 'task-second');
  const firstReviewer = profile('first', 'codex-auto-review');
  const secondReviewer = profile('second', 'codex-auto-review');
  assert.ok(firstTask && secondTask && firstReviewer && secondReviewer);
  assert.notEqual(firstReviewer, secondReviewer);
  assert.equal(server.service.config.profiles[firstReviewer].bound_account_id, first.accountId('fixture-account'));
  assert.equal(server.service.config.profiles[secondReviewer].bound_account_id, second.accountId('fixture-account'));
  const alternateReviewerKey = `alternate/codex-auto-review/${secondReviewer.split('/')[1]}`;
  const relativeReviewerKey = `alternate-relative/codex-auto-review/${secondReviewer.split('/')[1]}`;
  const customReviewerKey = `chatgpt/custom/codex-auto-review/${secondReviewer.split('/')[1]}`;
  const alternateReviewer = server.service.config.profiles[alternateReviewerKey];
  assert.equal(alternateReviewer.endpoint, second.profile.endpoint);
  assert.equal(alternateReviewer.bound_account_id, second.accountId('fixture-account'));
  for (const key of [relativeReviewerKey, customReviewerKey]) {
    assert.equal(server.service.config.profiles[key].endpoint, second.profile.endpoint);
    assert.equal(server.service.config.profiles[key].bound_account_id, alternateReviewer.bound_account_id);
  }
  assert.deepEqual(Object.keys(server.service.config.profiles).filter(key =>
    key.includes('/codex-auto-review/')), [alternateReviewerKey, relativeReviewerKey, customReviewerKey],
  'Only a configured profile for the same account connection may receive its reviewer alias');
  assert.equal(second.requests.filter(request => request.method === 'GET').length, 1,
    'Relative and absolute auth-file spellings must share one account discovery');
  const sourceRoot = path.join(await realpath(await home(t)), 'approval source repository');
  const sourcePrimary = path.join(sourceRoot, 'packages', 'app');
  await mkdir(sourcePrimary, { recursive: true });
  const executeGit = promisify(execFile);
  const git = async (root, ...arguments_) => (await executeGit('git', [
    '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false', '-c', 'user.name=Approval worktree fixture',
    '-c', 'user.email=approval-worktree@example.test', '-C', root, ...arguments_,
  ], { env: Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_'))) })).stdout.trim();
  await git(sourceRoot, 'init', '--initial-branch=main');
  const committedContents = 'Committed account approval worktree contents.\n';
  await writeFile(path.join(sourcePrimary, 'tracked.txt'), committedContents);
  await git(sourceRoot, 'add', '.');
  await git(sourceRoot, 'commit', '-m', 'Initialize account approval worktree fixture');
  const sourceCommit = await git(sourceRoot, 'rev-parse', 'HEAD');
  assert.equal(first.directory.startsWith(`${sourceRoot}${path.sep}`), false,
    'The service home must stay outside the source repository');
  const cases = [
    { id: 'default-first', taskAccount: 'first', taskProfile: firstTask, reviewAccount: 'first', reviewModel: 'codex-auto-review', reviewer: firstReviewer },
    { id: 'default-second', taskAccount: 'second', taskProfile: secondTask, reviewAccount: 'second', reviewModel: 'codex-auto-review', reviewer: secondReviewer },
    { id: 'configured-account', taskAccount: 'second', taskProfile: 'alternate', reviewAccount: 'second', reviewModel: 'codex-auto-review', reviewer: alternateReviewerKey },
    { id: 'relative-account', taskAccount: 'second', taskProfile: 'alternate-relative', reviewAccount: 'second', reviewModel: 'codex-auto-review', reviewer: relativeReviewerKey },
    { id: 'custom-account', taskAccount: 'second', taskProfile: 'chatgpt/custom', reviewAccount: 'second', reviewModel: 'codex-auto-review', reviewer: customReviewerKey },
    { id: 'explicit-reviewer', taskAccount: 'first', taskProfile: firstTask, reviewAccount: 'second', reviewModel: 'task-second', reviewer: secondTask, explicit: true },
    { id: 'malformed-review', taskAccount: 'first', taskProfile: firstTask, reviewAccount: 'first', reviewModel: 'codex-auto-review', reviewer: firstReviewer, malformed: true },
    { id: 'managed-worktree', taskAccount: 'first', taskProfile: firstTask, reviewAccount: 'first', reviewModel: 'codex-auto-review', reviewer: firstReviewer, worktree: true },
  ];
  for (const [task_id, settings] of cases.entries()) {
    const managedRoot = path.join(first.directory, 'worktrees', `task-${task_id}`);
    const managedPrimary = path.join(managedRoot, 'packages', 'app');
    const marker = settings.worktree ? path.join(managedPrimary, 'approval-worktree.txt') : path.join(first.directory, `${settings.id}.txt`);
    const workspace = settings.worktree ? { roots: [managedPrimary], primary_root: managedPrimary } : { roots: [], primary_root: null };
    const scenario = { ...settings, marker, workspace,
      message: settings.worktree ? 'Use the managed checkout and append exactly managed-worktree to approval-worktree.txt there.'
        : `Write exactly ${settings.id} to ${marker}.`, arguments: {
      command: settings.worktree ? `printf '%s' ${shellQuote(settings.id)} >> approval-worktree.txt\npwd > approval-cwd.txt\ncat tracked.txt > approval-source-copy.txt`
        : `printf '%s' ${shellQuote(settings.id)} > ${shellQuote(marker)}`,
      sandbox_permissions: 'require_escalated', justification: 'Write the one exact output requested by the user.', timeout_ms: 5000,
    } };
    scenarios.push(scenario);
    const created = await server.service.command({ op: settings.worktree ? 'create_worktree_task' : 'create', profile: scenario.taskProfile, reasoning: 'medium',
      message: scenario.message, settings: { workspace: settings.worktree ? { roots: [sourcePrimary], primary_root: sourcePrimary } : { roots: [] },
        sandbox: { mode: 'read-only', network_access: false },
        approval: { mode: 'approval-for-me', ...(scenario.explicit ? { reviewer_profile: scenario.reviewer } : {}) } } });
    assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
    if (scenario.worktree) {
      const deadline = Date.now() + 10_000;
      let worktree;
      do {
        const observed = await server.service.command({ op: 'read_worktree', task_id });
        assert.equal(observed.reply.ok, true, JSON.stringify(observed.reply));
        worktree = observed.reply.result;
        if (worktree.status === 'ready') break;
        assert.equal(worktree.status, 'creating', JSON.stringify(worktree));
        await delay(10);
      } while (Date.now() < deadline);
      assert.equal(worktree.status, 'ready', `The managed checkout did not become ready: ${JSON.stringify(worktree)}`);
    }
    const completed = await taskIdle(server.service, task_id);
    assert.equal(completed.task.settings.approval.reviewer_profile, scenario.reviewer);
    assert.deepEqual(completed.task.settings.workspace, workspace);
    assert.deepEqual(completed.task.settings.sandbox, { mode: 'read-only', network_access: false });
    const record = completed.messages.find(message => message.role === 'approval_record');
    assert.equal(record.content.decision, scenario.malformed ? 'failed' : 'allow');
    if (scenario.malformed) await assert.rejects(readFile(marker), { code: 'ENOENT' });
    else assert.equal(await readFile(marker, 'utf8'), scenario.id, 'An admitted review must launch the real one-operation Bash command');
    if (scenario.worktree) {
      const worktree = await server.service.command({ op: 'read_worktree', task_id });
      assert.equal(worktree.reply.ok, true, JSON.stringify(worktree.reply));
      assert.equal(worktree.reply.result.status, 'ready');
      assert.equal(worktree.reply.result.target_primary, managedPrimary);
      assert.equal(worktree.reply.result.root, managedRoot);
      assert.equal(await git(managedRoot, 'rev-parse', 'HEAD'), sourceCommit);
      assert.equal(await readFile(path.join(managedPrimary, 'approval-cwd.txt'), 'utf8'), `${managedPrimary}\n`);
      assert.equal(await readFile(path.join(managedPrimary, 'approval-source-copy.txt'), 'utf8'), committedContents);
      await assert.rejects(readFile(path.join(sourcePrimary, 'approval-worktree.txt')), { code: 'ENOENT' });
      assert.equal(await readFile(path.join(sourcePrimary, 'tracked.txt'), 'utf8'), committedContents);
      const executions = toolEffects.filter(effect => effect.task_id === task_id);
      assert.equal(executions.length, 1, 'The approved worktree invocation must execute once');
      assert.deepEqual(executions[0].execution.workspace, workspace);
      assert.equal(executions[0].execution.access, 'unrestricted');
    }
  }
  assert.deepEqual(reviews, cases.map(({ id, reviewAccount: account, reviewModel: model }) => ({ id, account, model })));
  assert.deepEqual(first.failures, []);
  assert.deepEqual(second.failures, []);
});

test('login materializes an independent Astra Auto profile, preserves policy overrides and rejects a foreign account namespace', async t => {
  let advertised = [model('gpt-6-astra'), model('another-account-model', 1), autoReviewModel()];
  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, {
    models: advertised,
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
  const copiedAuthFile = path.join(upstream.directory, 'copied-chatgpt-auth.json');
  await writeFile(copiedAuthFile, await readFile(path.join(upstream.directory, upstream.profile.auth_file)), { mode: 0o600 });
  await writeFile(`${copiedAuthFile}.registration.json`,
    await readFile(path.join(upstream.directory, `${upstream.profile.auth_file}.registration.json`)), { mode: 0o600 });
  const sharedAccount = validateConfig({ ...manual, profiles: { ...manual.profiles,
    'copied-credentials': { ...upstream.profile, auth_file: copiedAuthFile, model: 'gpt-6-astra' },
  } });
  const duplicated = await withAccountModels(sharedAccount, upstream.directory);
  assert.equal(duplicated.config.profiles[autoKey].adaptive_reasoning.evaluator, 'my-evaluator');
  assert.equal(duplicated.config.profiles[baseKey].bound_account_id, auto.bound_account_id);
  const copiedReviewerKey = `copied-credentials/codex-auto-review/${autoKey.split('/')[1]}`;
  assert.equal(duplicated.config.profiles[copiedReviewerKey].bound_account_id, auto.bound_account_id,
    'Two signed credential files for the same account and target must share the canonical namespace');
  const foreign = await chatgptFixture(t, (_, response) => jsonResponse(response, {
    models: [model('foreign-account-model'), autoReviewModel()],
  }));
  advertised = [model('another-account-model'), autoReviewModel()];
  await discoverAccount(upstream.profile, upstream.directory, { force: true });
  const current = JSON.parse(await readFile(modelCacheFile(upstream.profile, upstream.directory), 'utf8'));
  assert.equal(current.models.some(model => model.slug === 'gpt-6-astra'), false,
    'The namespace check must cover declared profiles even after their original model leaves the catalog');
  const foreignOverride = validateConfig({ ...config, profiles: { ...config.profiles,
    [autoKey]: { ...foreign.profile, auth_file: path.join(foreign.directory, foreign.profile.auth_file), model: 'gpt-6-astra',
      adaptive_reasoning: { ...auto.adaptive_reasoning } },
  } });
  await assert.rejects(withAccountModels(foreignOverride, upstream.directory), { code: 'account_namespace_mismatch' });
  const foreignWithoutPrimary = validateConfig({ ...foreignOverride, chatgpt: false, profiles: {
    [autoKey]: foreignOverride.profiles[autoKey],
  } });
  await assert.rejects(withAccountModels(foreignWithoutPrimary, upstream.directory), { code: 'account_namespace_mismatch' });
  assert.deepEqual(upstream.failures, []);
  assert.deepEqual(foreign.failures, []);
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
  payload = { models: [model(), autoReviewModel()] };
  const reloginConfig = validateConfig({ ...configFor(upstream.profile), profiles: {
    manual: { ...upstream.profile, model: 'account-model' },
  } });
  const before = await withAccountModels(reloginConfig, upstream.directory, { force: true });
  const oldReviewer = Object.keys(before.config.profiles).find(key => key.startsWith('manual/codex-auto-review/'));
  assert.ok(oldReviewer);
  assert.equal(oldReviewer.split('/').at(-1), Object.keys(before.config.profiles)[0].split('/')[1]);
  await upstream.save('another-account');
  const after = await withAccountModels(reloginConfig, upstream.directory);
  assert.notEqual(Object.keys(before.config.profiles)[0], Object.keys(after.config.profiles)[0]);
  const newReviewer = Object.keys(after.config.profiles).find(key => key.startsWith('manual/codex-auto-review/'));
  assert.ok(newReviewer);
  assert.notEqual(newReviewer, oldReviewer, 'A configured reviewer alias must freeze the authenticated account identity');
  assert.equal(Object.hasOwn(after.config.profiles, oldReviewer), false);
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
  assert.ok(finished.messages.some(message => message.role === 'model_context' && message.content.type === 'provider_receipt' &&
    message.content.item.content?.[0]?.text === 'Discovered model answered.'));
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

function actualUIInput(value, tag) {
  if (!value || typeof value !== 'object') return undefined;
  if (bendTag(value) === tag) return value;
  for (const child of Object.values(value)) {
    const found = actualUIInput(child, tag);
    if (found) return found;
  }
  return undefined;
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
    const entrances = surfaceNodes(ui.surface_state(opened)).filter(node =>
      bendTag(node.meaning) === 'SettingEntry'
      && bendTag(node.meaning.subject.field) === 'ReasoningEffort'
      && actualUIInput(node.meaning.input, 'EnterDecision')?.field_key === 'reasoning-effort');
    assert.equal(entrances.length, 1, 'The actual model menu must expose one reasoning parameter entrance');
    assert.equal(bendTag(entrances[0].meaning.subject.editor), 'MessageEditor');
    assert.equal(Number(entrances[0].meaning.subject.editor.task), task);
    const expanded = ui.activate_state(opened, ui.key(entrances[0]));
    const options = surfaceNodes(ui.surface_state(expanded)).filter(node =>
      bendTag(node.meaning) === 'Choice' && node.semantic.startsWith('effort/'));
    assert.deepEqual(options.map(node => actualUIInput(node.meaning.input, 'ChooseModel')?.reasoning).sort(),
      ['high', 'medium'], "The expanded parameter must expose precisely the model's declared reasoning alternatives");
    for (const option of options) {
      const edit = actualUIInput(option.meaning.input, 'EditDraft');
      assert.equal(bendTag(edit?.editor), 'MessageEditor');
      assert.equal(Number(edit.editor.task), task);
      assert.equal(actualUIInput(option.meaning.input, 'ChooseModel').profile, profile);
    }
    assert.equal(options.find(node => node.semantic === 'effort/medium').meaning.selected, true);
    const high = options.find(node => node.semantic === 'effort/high');
    assert.ok(high, 'The actual reasoning parameter must expose the permitted high option');
    assert.equal(bendTag(high.meaning), 'Choice');
    assert.equal(bendTag(high.meaning.kind), 'SingleChoice');
    assert.equal(bendTag(high.meaning.availability), 'Available');
    assert.equal(high.meaning.selected, false);
    const pressed = ui.press_state(expanded, ui.key(high));
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
    const settingsRecord = { role: 'task_context', type: 'settings', content: before.task.settings,
      profile: before.task.profile, reasoning: 'high' };
    assert.deepEqual(after.reply.result, { ...before,
      cursor: before.cursor + 1,
      task: { ...before.task, reasoning: 'high', cursor: before.task.cursor + 1 },
      messages: [...before.messages, settingsRecord],
    }, 'A browser reasoning change must preserve every unrelated field and the complete history prefix, appending only its settings record');
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

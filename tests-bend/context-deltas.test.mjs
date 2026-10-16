import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, symlink, unlink, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { requestModel } from '../host/providers.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { webServer, answer } from './fixtures/chatgpt-web.mjs';

const hash = text => createHash('sha256').update(text).digest('hex');
const context = change => ({ role: 'task_context', type: 'context_change', change });
const changes = messages => messages.filter(item => item.type === 'context_change').map(item => item.change);

function textFromPatch(base, edits) {
  const points = Array.from(base);
  let cursor = 0;
  let result = '';
  for (const { start, removed, inserted } of edits) {
    const end = start + Array.from(removed).length;
    assert.ok(start >= cursor, 'Text edits use ordered coordinates in the original version');
    assert.equal(points.slice(start, end).join(''), removed);
    result += points.slice(cursor, start).join('') + inserted;
    cursor = end;
  }
  return result + points.slice(cursor).join('');
}

function credentials(t, key, value = 'fixture-only') {
  const previous = process.env[key]; process.env[key] = value;
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  return key;
}

test('changed AGENTS sources append patches, reversals and removal without replacing committed prefixes or task settings', { timeout: 35_000 }, async t => {
  const directory = await home(t);
  const state = path.join(directory, 'state'); const workspace = path.join(directory, 'workspace');
  await mkdir(state); await mkdir(workspace);
  const globalPath = path.join(state, 'AGENTS.md'); const projectPath = path.join(workspace, 'AGENTS.md');
  const globalA = 'Keep 🧵 global policy.\nUse npm.\nKeep global tail.\n';
  const globalB = 'Keep 🧵 global policy.\nUse bun.\nKeep global tail.\n';
  const projectA = 'Keep 🧵 project prefix.\nUse npm.\nKeep project middle.\nFormat before review.\nKeep project tail.\n';
  const projectB = 'Keep 🧵 project prefix.\nUse bun.\nKeep project middle.\nLint before review.\nKeep project tail.\n';
  await writeFile(globalPath, globalA); await writeFile(projectPath, projectA);
  const effects = [];
  const model = await responsesServer(t, async body => {
    const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
    let effect;
    try {
      const committed = JSON.parse(db.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 1').get().decision);
      effect = committed.effects.find(item => ['model', 'summary'].includes(item.kind));
    } finally { db.close(); }
    assert.ok(effect, 'HTTP dispatch must follow the decision containing its model effect');
    const developer = body.input.filter(item => item.role === 'developer').map(item => item.content).join('\n');
    for (const change of changes(effect.history)) {
      const key = change.type === 'introduce' ? change.snapshot.key : change.key;
      if (key.type === 'project_guidance') assert.ok(developer.includes(await realpath(workspace)));
      if (change.type === 'amend') {
        assert.ok(developer.includes(change.base_revision)); assert.ok(developer.includes(change.revision));
      }
    }
    effects.push(effect);
    return answer(effect.kind === 'summary' ? 'Continue using the recorded context revisions.' : 'done');
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint,
    api_key_env: credentials(t, 'SELVEDGE_DELTA_CONTEXT_FIXTURE_KEY'), timeout_ms: 5000,
  } } });
  let service = await Service.open({ home: state, cwd: workspace, config });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'create', profile: 'fixture', message: 'start' })).reply.ok, true);
  let page = await taskIdle(service);
  const initial = page.messages;
  const settings = structuredClone(page.task.settings);
  const introductions = changes(initial).filter(change => change.type === 'introduce');
  const global = introductions.find(change => change.snapshot.key.origin === 'global_agents').snapshot;
  const project = introductions.find(change => change.snapshot.key.type === 'project_guidance').snapshot;
  assert.equal(global.revision, hash(globalA)); assert.equal(project.revision, hash(projectA));
  assert.equal(global.key.path, await realpath(globalPath));
  assert.equal(project.key.workspace, await realpath(workspace));

  const send = async message => {
    const before = page.messages;
    assert.equal((await service.command({ op: 'send', task_id: 0, message })).reply.ok, true);
    page = await taskIdle(service);
    assert.deepEqual(page.messages.slice(0, before.length), before);
    assert.deepEqual(page.task.settings, settings, 'Source refresh does not change workspace or sandbox contracts');
    return changes(page.messages.slice(before.length));
  };
  assert.deepEqual(await send('unchanged'), []);
  await writeFile(globalPath, globalB); await writeFile(projectPath, projectB);
  const amended = await send('changed sources');
  assert.equal(amended.length, 2);
  for (const [snapshot, before, after] of [[global, globalA, globalB], [project, projectA, projectB]]) {
    const change = amended.find(item => JSON.stringify(item.key) === JSON.stringify(snapshot.key));
    assert.equal(change.type, 'amend'); assert.equal(change.base_revision, snapshot.revision);
    assert.equal(change.revision, hash(after)); assert.equal(change.patch.type, 'text_edits');
    assert.equal(textFromPatch(before, change.patch.edits), after);
    assert.equal('snapshot' in change, false); assert.equal('value' in change, false);
    assert.equal(JSON.stringify(change).includes('Keep 🧵'), false, 'The appended change excludes the untouched prefix');
  }
  await writeFile(globalPath, globalA); await writeFile(projectPath, projectA);
  const reversed = await send('return to initial content');
  assert.equal(reversed.length, 2);
  for (const change of reversed) {
    const previous = amended.find(item => JSON.stringify(item.key) === JSON.stringify(change.key));
    assert.equal(change.base_revision, previous.revision);
    assert.equal(change.revision, change.key.type === 'project_guidance' ? project.revision : global.revision);
  }
  await unlink(projectPath);
  await unlink(globalPath); await symlink(projectPath, globalPath);
  const errorPrefix = page.messages.length;
  const removed = await send('removed project and unreadable global');
  assert.deepEqual(removed, [{ type: 'remove', key: project.key, base_revision: project.revision }]);
  assert.ok(page.messages.slice(errorPrefix).some(item => item.role === 'error'), 'A failed source observation remains visible');
  await unlink(globalPath); await writeFile(globalPath, globalB);
  const restored = await send('readable global');
  assert.equal(restored.length, 1);
  assert.equal(restored[0].type, 'amend'); assert.equal(restored[0].base_revision, global.revision);
  assert.equal(restored[0].revision, hash(globalB));

  const beforeSummary = page.messages;
  assert.equal((await service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
  page = await taskIdle(service);
  assert.deepEqual(page.messages.slice(0, beforeSummary.length), beforeSummary);
  assert.ok(page.messages.some(item => item.role === 'context_summary'));
  assert.deepEqual(changes(page.messages), changes(beforeSummary));
  const parent = page.messages;
  assert.equal((await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['child'] })).reply.ok, true);
  const child = await taskIdle(service, 1); await taskIdle(service);
  assert.deepEqual(child.messages.slice(0, parent.length), parent);
  assert.deepEqual(changes(child.messages), changes(parent));
  await service.close();
  service = await Service.open({ home: state, cwd: workspace, config });
  assert.deepEqual((await taskIdle(service, 1)).messages, child.messages);
  assert.equal((await service.command({ op: 'send', task_id: 1, message: 'continue after restart' })).reply.ok, true);
  assert.deepEqual(changes((await taskIdle(service, 1)).messages), changes(child.messages));
  for (const effect of effects) {
    const recorded = (await service.command({ op: 'read', task_id: effect.task_id })).reply.result.messages;
    const history = effect.kind === 'summary' ? effect.history.slice(0, -1) : effect.history;
    assert.deepEqual(recorded.slice(0, history.length), history);
  }
  assert.deepEqual(model.failures, []);
});

test('ChatGPT Web sends context amendments as the verified continuation suffix', async t => {
  const directory = await home(t);
  const key = { type: 'instruction', origin: 'configured', path: '' };
  const original = 'Keep the long unchanged prefix. Use npm.';
  const updated = 'Keep the long unchanged prefix. Use bun.';
  const introduction = context({ type: 'introduce', snapshot: { key, revision: 'initial', value: { type: 'instruction', content: original } } });
  const amendment = context({ type: 'amend', key, base_revision: 'initial', revision: hash(updated),
    patch: { type: 'text_edits', edits: [{ start: Array.from('Keep the long unchanged prefix. Use ').length, removed: 'npm', inserted: 'bun' }] } });
  const server = await webServer(t, async () => ({ output: answer('done') }));
  const api_key_env = credentials(t, 'SELVEDGE_DELTA_WEB_FIXTURE_KEY', 'local-web-fixture');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { web: {
    provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: server.endpoint, api_key_env, timeout_ms: 5000,
  } } });
  const limits = { frame_bytes: 1024 * 1024, approval_reason_bytes: 400,
    model_retry: { delays_ms: [1, 2], statuses: [429, 500, 502, 503, 504], max_retry_after_ms: 1000 } };
  const first = { kind: 'model', task_id: 0, ticket: 1,
    model: { profile: 'web', provider: 'chatgpt-web', name: 'chatgpt-web/high', reasoning: 'medium' },
    history: [introduction, { role: 'user', content: 'first question' }], tools: [], callable: [], settings: { workspace: '/fixture' } };
  const result = await requestModel(first, config, directory, limits);
  const committed = result.map(item => item.type === 'text' ? { role: 'assistant', content: item.text }
    : { role: 'model_context', content: item.value });
  const next = { ...first, ticket: 2, history: [...first.history, ...committed, amendment, { role: 'user', content: 'continue' }] };
  await requestModel(next, config, directory, limits);
  assert.equal(server.requests.length, 2);
  assert.ok(server.requests[1].body.previous_response_id);
  const suffix = server.requests[1].body.input;
  const update = suffix.find(item => item.role === 'developer');
  assert.ok(update); assert.match(update.content, /initial/); assert.ok(update.content.includes(hash(updated)));
  assert.match(update.content, /npm/); assert.match(update.content, /bun/);
  assert.equal(JSON.stringify(suffix).includes('long unchanged prefix'), false);
  assert.equal(JSON.stringify(suffix).includes('first question'), false);
  assert.deepEqual(server.failures, []);
});

test('large guidance survives generated-kernel comparison and widely separated edits', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const state = path.join(directory, 'state'); const workspace = path.join(directory, 'workspace');
  await mkdir(state); await mkdir(workspace);
  const middle = Array.from({ length: 360 }, (_, index) =>
    `Policy ${String(index).padStart(3, '0')}: retain invariant ${index}; inspect changed files before execution.\n`).join('');
  const original = `First policy: use npm.\n${middle}Last policy: run fmt.\n`;
  const updated = `First policy: use bun.\n${middle}Last policy: run lint.\n`;
  assert.ok(Buffer.byteLength(original) >= 20 * 1024);
  assert.ok(Buffer.byteLength(original) < 32768);
  const agents = path.join(workspace, 'AGENTS.md');
  await writeFile(agents, original);
  const model = await responsesServer(t, async () => answer('done'));
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint,
    api_key_env: credentials(t, 'SELVEDGE_LARGE_CONTEXT_FIXTURE_KEY'), timeout_ms: 5000,
  } } });
  const service = await Service.open({ home: state, cwd: workspace, config });
  t.after(() => service.close());
  const fatal = Promise.withResolvers();
  void fatal.promise.catch(() => {});
  const notices = [];
  service.on('notice', notice => {
    notices.push(notice);
    if (notice.type === 'fatal') fatal.reject(new Error(`Service fatal: ${notice.message}`));
  });
  const settled = () => Promise.race([taskIdle(service), fatal.promise]);
  assert.equal((await service.command({ op: 'create', profile: 'fixture', message: 'large initial guidance' })).reply.ok, true);
  const initial = await settled();
  assert.equal(model.requests.length, 1);
  const introduced = changes(initial.messages).find(change => change.type === 'introduce' && change.snapshot.key.type === 'project_guidance');
  assert.equal(introduced.snapshot.value.content, original);
  await service.command({ op: 'send', task_id: 0, message: 'unchanged large guidance' });
  const unchanged = await settled();
  assert.equal(model.requests.length, 2);
  assert.deepEqual(changes(unchanged.messages), changes(initial.messages));
  await writeFile(agents, updated);
  await service.command({ op: 'send', task_id: 0, message: 'two separated edits' });
  const changed = await settled();
  assert.equal(model.requests.length, 3);
  assert.deepEqual(changed.messages.slice(0, unchanged.messages.length), unchanged.messages);
  const appended = changes(changed.messages.slice(unchanged.messages.length));
  assert.equal(appended.length, 1);
  assert.equal(appended[0].type, 'amend');
  assert.equal(appended[0].base_revision, introduced.snapshot.revision);
  assert.equal(appended[0].revision, hash(updated));
  assert.equal(textFromPatch(original, appended[0].patch.edits), updated);
  assert.equal(JSON.stringify(appended[0]).includes('Policy 180:'), false, 'Unchanged guidance stays in the inherited prefix');
  assert.ok(JSON.stringify(model.requests.at(-1).input).includes(appended[0].revision));
  assert.equal(notices.some(notice => notice.type === 'fatal'), false);
  assert.deepEqual(model.failures, []);
});

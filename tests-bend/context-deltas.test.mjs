import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, symlink, unlink, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { Kernel } from '../host/kernel.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { requestModel } from '../host/providers.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { contextReplaced } from './fixtures/compaction.mjs';
import { webServer, answer } from './fixtures/chatgpt-web.mjs';

const hash = text => createHash('sha256').update(text).digest('hex');
const context = change => ({ role: 'task_context', type: 'context_change', change });
const edits = (patch, field = 'content') => patch.fields.find(item => item.field === field).edits;
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
      effect = committed.effects.find(item => ['model', 'context_compaction'].includes(item.kind));
    } finally { db.close(); }
    assert.ok(effect, 'HTTP dispatch must follow the decision containing its model effect');
    if (effect.kind === 'context_compaction') {
      assert.equal(body.tool_choice, 'none');
      assert.ok(body.input.some(item => item.content.includes(effect.plan.chunk)));
      assert.equal(JSON.stringify(body.input).includes('base_revision'), false,
        'Tracked context remains fixed outside the summarized dialogue');
      return answer('Continue using the retained task context and the recorded work.');
    }
    const developer = body.input.filter(item => item.role === 'developer').map(item => item.content).join('\n');
    for (const change of changes(effect.history)) {
      const key = change.type === 'introduce' ? change.snapshot.key : change.key;
      if (key.type === 'project_guidance') assert.ok(developer.includes(await realpath(workspace)));
      if (change.type === 'amend') {
        assert.equal(developer.includes(change.base_revision), false); assert.equal(developer.includes(change.revision), false);
      }
    }
    effects.push(effect);
    return answer('done');
  }, { measure: () => 100 });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint,
    api_key_env: credentials(t, 'SELVEDGE_DELTA_CONTEXT_FIXTURE_KEY'), timeout_ms: 5000,
  } }, compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 0,
    targets: [{ profile: 'fixture', window_tokens: 65_536, output_reserve_tokens: 2048, cache_ttl_ms: null, method: 'summary' }] } });
  let service = await Service.open({ home: state, cwd: workspace, config });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'create', profile: 'fixture', message: 'start' })).reply.ok, true);
  let page = await taskIdle(service);
  const initial = page.messages;
  const settings = structuredClone(page.task.settings);
  const introductions = changes(initial).filter(change => change.type === 'introduce');
  const global = introductions.find(change => change.snapshot.key.type === 'global_agents').snapshot;
  const project = introductions.find(change => change.snapshot.key.type === 'project_guidance').snapshot;
  assert.equal(global.value.fields.content, globalA); assert.equal(project.value.fields.content, projectA);
  assert.match(global.revision, /^[a-f0-9]{64}$/); assert.match(project.revision, /^[a-f0-9]{64}$/);
  assert.equal(global.key.identity.path, await realpath(globalPath));
  assert.equal(project.key.identity.workspace, await realpath(workspace));

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
    assert.match(change.revision, /^[a-f0-9]{64}$/); assert.notEqual(change.revision, change.base_revision);
    assert.equal(change.patch.type, 'field_edits');
    assert.equal(textFromPatch(before, edits(change.patch)), after);
    assert.equal('snapshot' in change, false); assert.equal('value' in change, false);
    assert.equal(JSON.stringify(change).includes('Keep 🧵'), false, 'The appended change excludes the untouched prefix');
  }
  await writeFile(globalPath, globalA); await writeFile(projectPath, projectA);
  const reversed = await send('return to initial content');
  assert.equal(reversed.length, 2);
  for (const change of reversed) {
    const previous = amended.find(item => JSON.stringify(item.key) === JSON.stringify(change.key));
    assert.equal(change.base_revision, previous.revision);
    assert.notEqual(change.revision, change.base_revision);
    const [before, after] = change.key.type === 'project_guidance' ? [projectB, projectA] : [globalB, globalA];
    assert.equal(textFromPatch(before, edits(change.patch)), after);
  }
  await unlink(projectPath);
  await unlink(globalPath); await symlink(projectPath, globalPath);
  const errorPrefix = page.messages.length;
  const removed = await send('removed project and unreadable global');
  assert.deepEqual(removed, [{ type: 'remove', key: project.key,
    base_revision: reversed.find(change => change.key.type === 'project_guidance').revision }]);
  assert.ok(page.messages.slice(errorPrefix).some(item => item.role === 'error'), 'A failed source observation remains visible');
  await unlink(globalPath); await writeFile(globalPath, globalB);
  const restored = await send('readable global');
  assert.equal(restored.length, 1);
  assert.equal(restored[0].type, 'amend');
  assert.equal(restored[0].base_revision, reversed.find(change => change.key.type === 'global_agents').revision);
  assert.equal(restored[0].revision, amended.find(change => change.key.type === 'global_agents').revision);

  const beforeCompaction = page.messages;
  const globalC = globalB + 'Preserve context changes across compaction.\n';
  await writeFile(globalPath, globalC);
  assert.equal((await service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
  await contextReplaced(service);
  page = await taskIdle(service);
  assert.deepEqual(page.messages.slice(0, beforeCompaction.length), beforeCompaction);
  const refreshed = changes(page.messages.slice(beforeCompaction.length));
  assert.equal(refreshed.length, 1, 'Manual compaction refreshes sources before selecting its committed snapshot');
  assert.equal(refreshed[0].base_revision, restored[0].revision);
  assert.equal(textFromPatch(globalB, edits(refreshed[0].patch)), globalC);
  assert.ok(page.messages.some(item => item.role === 'context_replacement'));
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
    assert.deepEqual(changes(recorded).slice(0, changes(effect.history).length), changes(effect.history));
    if (effect.context_replacement_source === null) {
      assert.deepEqual(recorded.slice(0, effect.history.length), effect.history);
    }
  }
  assert.deepEqual(model.failures, []);
});

test('discovered context commits before dispatch and survives scoped forks, compaction and restart', { timeout: 35_000 }, async t => {
  const directory = await realpath(await home(t));
  const state = path.join(directory, 'state');
  const repository = path.join(directory, 'repository');
  const workspace = path.join(repository, 'app');
  const nested = path.join(workspace, 'src', 'api', 'internal');
  const secondary = path.join(directory, 'secondary');
  const alternate = path.join(directory, 'alternate');
  await Promise.all([state, path.join(repository, '.git'), nested, path.join(secondary, '.git'), path.join(alternate, '.git')].map(filename => mkdir(filename, { recursive: true })));
  await writeFile(path.join(repository, 'AGENTS.md'), 'Repository ancestor policy.');
  await writeFile(path.join(workspace, 'AGENTS.md'), 'Primary workspace policy.');
  const primaryOverride = path.join(workspace, 'AGENTS.override.md');
  await writeFile(primaryOverride, 'Primary override policy.');
  await writeFile(path.join(secondary, 'AGENTS.md'), 'Secondary workspace policy.');
  const nestedGuidance = path.join(nested, 'AGENTS.md');
  const skillDirectory = path.join(nested, '.agents', 'skills', 'inspect');
  await mkdir(skillDirectory, { recursive: true });
  const skillFile = path.join(skillDirectory, 'SKILL.md');
  const metadata = (description, body) => `---\nname: inspect\ndescription: ${description}\n---\n${body}\n`;
  await writeFile(nestedGuidance, 'Keep 🧵 the nested prefix.\nUse npm.\nKeep the tail.\n');
  await writeFile(skillFile, metadata('Inspect version A.', 'PRIVATE-DISCOVERED-BODY-A'));
  const userSkillDirectory = path.join(state, '.agents', 'skills', 'user');
  await mkdir(userSkillDirectory, { recursive: true });
  await writeFile(path.join(userSkillDirectory, 'SKILL.md'), metadata('User inspection skill.', 'PRIVATE-USER-BODY'));
  const effects = [];
  const model = await responsesServer(t, async body => {
    const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
    let committed;
    try { committed = db.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 30').all()
      .flatMap(row => JSON.parse(row.decision).effects); }
    finally { db.close(); }
    if (body.tool_choice === 'none') {
      const effect = committed.find(effect => effect.kind === 'context_compaction');
      assert.ok(effect, 'Summary transport follows its committed compaction effect');
      assert.equal(effect.plan.chunk.includes('PRIVATE-'), false);
      return answer('Continue following the retained directory instructions and skill catalog.');
    }
    const effect = committed.find(effect => effect.kind === 'model' && body.input.some(item => item.role === 'user'
      && item.content === effect.history.filter(item => item.role === 'user').at(-1)?.content));
    assert.ok(effect, 'Every provider request is backed by its committed model history');
    const developer = body.input.filter(item => item.role === 'developer').map(item => item.content).join('\n');
    for (const change of changes(effect.history)) {
      const key = change.type === 'introduce' ? change.snapshot.key : change.key;
      assert.ok(developer.includes(JSON.stringify({ type: key.type, identity: key.identity })));
      if (change.type === 'introduce') {
        for (const value of Object.values(change.snapshot.value.fields)) assert.ok(developer.includes(value));
      }
    }
    assert.equal(JSON.stringify(body.input).includes('PRIVATE-'), false, 'Discovery injects metadata without skill bodies');
    effects.push(effect);
    return answer('done');
  }, { measure: () => 100 });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint,
    api_key_env: credentials(t, 'SELVEDGE_HIERARCHICAL_CONTEXT_FIXTURE_KEY'), timeout_ms: 5000,
  } }, compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 0,
    targets: [{ profile: 'fixture', window_tokens: 65_536, output_reserve_tokens: 2048, cache_ttl_ms: null, method: 'summary' }] } });
  let service = await Service.open({ home: state, cwd: workspace, config });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'create', profile: 'fixture', message: 'inspect discovered context',
    settings: { workspace: { roots: [workspace, secondary, alternate], primary_root: workspace } } })).reply.ok, true);
  let page = await taskIdle(service);
  const initial = page.messages;
  const introduced = changes(initial).filter(change => change.type === 'introduce').map(change => change.snapshot);
  const guidance = introduced.find(snapshot => snapshot.key.type === 'directory_guidance' && snapshot.value.fields.path === nestedGuidance);
  const primaryGuidance = introduced.find(snapshot => snapshot.key.type === 'project_guidance');
  const skill = introduced.find(snapshot => snapshot.key.type === 'workspace_skill_information');
  const userSkill = introduced.find(snapshot => snapshot.key.type === 'user_skill_information');
  assert.ok(guidance); assert.ok(skill); assert.ok(userSkill);
  assert.equal(primaryGuidance.value.fields.path, primaryOverride);
  assert.equal(primaryGuidance.value.fields.content, 'Primary override policy.');
  assert.equal(changes(initial).some(change => change.type === 'amend' && change.key.type === 'project_guidance'), false, 'Initial root guidance already records its selected override path');
  assert.equal(guidance.value.fields.applies_to, nested);
  assert.equal(skill.value.fields.applies_to, nested);
  assert.ok(introduced.some(snapshot => snapshot.key.type === 'directory_guidance' && snapshot.value.fields.applies_to === secondary));
  const settings = structuredClone(page.task.settings);
  const send = async message => {
    const before = page.messages;
    assert.equal((await service.command({ op: 'send', task_id: 0, message })).reply.ok, true);
    page = await taskIdle(service);
    assert.deepEqual(page.messages.slice(0, before.length), before);
    assert.deepEqual(page.task.settings, settings);
    return changes(page.messages.slice(before.length));
  };
  await writeFile(skillFile, metadata('Inspect version A.', 'PRIVATE-DISCOVERED-BODY-B'));
  assert.deepEqual(await send('body-only discovery update'), []);
  const updatedGuidance = 'Keep 🧵 the nested prefix.\nUse bun.\nKeep the tail.\n';
  await writeFile(nestedGuidance, updatedGuidance);
  await writeFile(skillFile, metadata('Inspect version B.', 'PRIVATE-DISCOVERED-BODY-C'));
  const amended = await send('change discovered guidance and metadata');
  assert.equal(amended.length, 2);
  const amendedGuidance = amended.find(change => change.key.type === 'directory_guidance');
  const amendedSkill = amended.find(change => change.key.type === 'workspace_skill_information');
  assert.equal(amendedGuidance.base_revision, guidance.revision);
  assert.equal(textFromPatch(guidance.value.fields.content, edits(amendedGuidance.patch)), updatedGuidance);
  assert.equal(amendedSkill.base_revision, skill.revision);
  assert.equal(textFromPatch('Inspect version A.', edits(amendedSkill.patch, 'description')), 'Inspect version B.');

  await unlink(nestedGuidance); await symlink(path.join(repository, 'AGENTS.md'), nestedGuidance);
  const beforeFailure = page.messages.length;
  assert.deepEqual(await send('unreadable discovered guidance'), []);
  assert.ok(page.messages.slice(beforeFailure).some(item => item.role === 'error'));
  await unlink(nestedGuidance); await writeFile(nestedGuidance, updatedGuidance);
  assert.deepEqual(await send('readable discovered guidance restored'), []);

  const beforeCompaction = page.messages;
  const compactedGuidance = updatedGuidance + 'Preserve this directory scope after compaction.\n';
  await writeFile(nestedGuidance, compactedGuidance);
  assert.equal((await service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
  await contextReplaced(service);
  page = await taskIdle(service);
  assert.deepEqual(page.messages.slice(0, beforeCompaction.length), beforeCompaction);
  const compactedChanges = changes(page.messages.slice(beforeCompaction.length));
  assert.equal(compactedChanges.length, 1);
  assert.equal(compactedChanges[0].base_revision, amendedGuidance.revision);
  assert.equal(textFromPatch(updatedGuidance, edits(compactedChanges[0].patch)), compactedGuidance);
  assert.deepEqual(await send('continue after directory context compaction'), []);
  assert.deepEqual(changes(effects.at(-1).history), changes(page.messages), 'Compressed provider input retains every tracked baseline and edit');

  const parent = page.messages;
  const roots = [workspace, secondary, alternate];
  assert.equal((await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['switch primary to root without guidance'],
    settings: { workspace: { roots, primary_root: alternate } } })).reply.ok, true);
  const switched = await taskIdle(service, 1); await taskIdle(service);
  const switchedChanges = changes(switched.messages.slice(parent.length));
  assert.ok(switchedChanges.some(change => change.type === 'remove' && JSON.stringify(change.key) === JSON.stringify(primaryGuidance.key)));
  assert.equal(switchedChanges.some(change => change.type === 'introduce' && change.snapshot.key.type === 'project_guidance'), false,
    'An empty new primary root cannot retain or introduce a primary guidance slot');
  assert.ok(switchedChanges.some(change => change.type === 'introduce' && change.snapshot.key.type === 'directory_guidance'
    && change.snapshot.value.fields.path === primaryOverride), 'Guidance from the former primary remains available within its directory scope');
  assert.equal((await service.command({ op: 'fork', task_id: 1, child_count: 1, messages: ['restore guided primary root'],
    settings: { workspace: { roots, primary_root: workspace } } })).reply.ok, true);
  const restoredPrimary = await taskIdle(service, 2); await taskIdle(service, 1);
  const restoredSlot = changes(restoredPrimary.messages.slice(switched.messages.length)).find(change => change.type === 'introduce' && change.snapshot.key.type === 'project_guidance');
  assert.ok(restoredSlot);
  assert.equal(restoredSlot.snapshot.value.fields.path, primaryOverride);
  assert.equal(restoredSlot.snapshot.value.fields.content, 'Primary override policy.');
  assert.equal((await service.command({ op: 'fork', task_id: 2, child_count: 1, messages: ['switch primary back to empty root'],
    settings: { workspace: { roots, primary_root: alternate } } })).reply.ok, true);
  const switchedAgain = await taskIdle(service, 3); await taskIdle(service, 2);
  const switchedAgainChanges = changes(switchedAgain.messages.slice(restoredPrimary.messages.length));
  assert.ok(switchedAgainChanges.some(change => change.type === 'remove' && JSON.stringify(change.key) === JSON.stringify(restoredSlot.snapshot.key)));
  assert.equal(switchedAgainChanges.some(change => change.type === 'introduce' && change.snapshot.key.type === 'project_guidance'), false);
  assert.equal((await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['keep primary but remove secondary root'],
    settings: { workspace: { roots: [workspace], primary_root: workspace } } })).reply.ok, true);
  const primaryOnly = await taskIdle(service, 4); await taskIdle(service);
  const primaryOnlyChanges = changes(primaryOnly.messages.slice(parent.length));
  const secondaryGuidance = introduced.find(snapshot => snapshot.key.type === 'directory_guidance' && snapshot.value.fields.applies_to === secondary);
  assert.ok(primaryOnlyChanges.some(change => change.type === 'remove' && JSON.stringify(change.key) === JSON.stringify(secondaryGuidance.key)));
  assert.equal(primaryOnlyChanges.some(change => JSON.stringify(change.key ?? change.snapshot?.key) === JSON.stringify(guidance.key)), false,
    'A secondary-root change preserves existing primary-directory baselines');
  const inheritedWorkspace = introduced.filter(snapshot => ['project_guidance', 'directory_guidance', 'workspace_skill_information'].includes(snapshot.key.type));
  assert.equal((await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['inspect alternate workspace'],
    settings: { workspace: { roots: [alternate], primary_root: alternate } } })).reply.ok, true);
  const child = await taskIdle(service, 5); await taskIdle(service);
  assert.deepEqual(child.messages.slice(0, parent.length), parent);
  const childChanges = changes(child.messages.slice(parent.length));
  for (const snapshot of inheritedWorkspace) assert.ok(childChanges.some(change => change.type === 'remove'
    && JSON.stringify(change.key) === JSON.stringify(snapshot.key)), `Alternate roots withdraw ${snapshot.key.type}`);
  assert.equal(childChanges.some(change => (change.key ?? change.snapshot?.key).type === 'user_skill_information'), false, 'User skills retain their global baseline across a workspace fork');
  await service.close();
  service = await Service.open({ home: state, cwd: alternate, config });
  assert.deepEqual((await taskIdle(service, 5)).messages, child.messages);
  assert.equal((await service.command({ op: 'send', task_id: 5, message: 'continue scoped child after restart' })).reply.ok, true);
  assert.deepEqual(changes((await taskIdle(service, 5)).messages), changes(child.messages));
  assert.equal((await service.command({ op: 'send', task_id: 0, message: 'continue parent after restart' })).reply.ok, true);
  const restoredParent = await taskIdle(service);
  assert.deepEqual(changes(restoredParent.messages), changes(parent));
  assert.deepEqual(changes(effects.at(-1).history), changes(parent));
  assert.deepEqual(model.failures, []);
});

test('ChatGPT Web sends context amendments as the verified continuation suffix', async t => {
  const directory = await home(t);
  const kernel = new Kernel();
  t.after(() => kernel.close());
  await kernel.initialize();
  const send = async input => (await kernel.request(input)).value;
  assert.equal((await send({ kind: 'configure', instructions: { configured: 'Fixture instructions', global: null },
    profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture', reasoning_options: null }],
    tools: [], max_fork: 4, max_descendants: 8 })).reply.ok, true);
  const created = await send({ kind: 'command', command: { op: 'create', profile: 'fixture', message: 'initial schema' } });
  const observation = created.effects.find(effect => effect.kind === 'observe_context');
  assert.ok(observation);
  const definition = observation.definitions.find(definition => definition.observer.type === 'config_text');
  assert.ok(definition);
  const key = { type: 'configured_instruction', definition, identity: { origin: 'configured' } };
  const original = 'Keep the long unchanged prefix. Use npm.';
  const updated = 'Keep the long unchanged prefix. Use bun.';
  const introduction = context({ type: 'introduce', snapshot: { key, revision: 'initial', value: { type: 'configured_instruction', fields: { content: original } } } });
  const amendment = context({ type: 'amend', key, base_revision: 'initial', revision: hash(updated),
    patch: { type: 'field_edits', fields: [{ field: 'content', edits: [{ start: Array.from('Keep the long unchanged prefix. Use ').length, removed: 'npm', inserted: 'bun' }] }] } });
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
  assert.ok(update); assert.ok(update.content.includes('configured'));
  assert.equal(update.content.includes(hash(updated)), false);
  assert.equal(update.content.includes('base_revision'), false);
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
  assert.equal(introduced.snapshot.value.fields.content, original);
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
  assert.match(appended[0].revision, /^[a-f0-9]{64}$/);
  assert.notEqual(appended[0].revision, introduced.snapshot.revision);
  assert.equal(textFromPatch(original, edits(appended[0].patch)), updated);
  assert.equal(JSON.stringify(appended[0]).includes('Policy 180:'), false, 'Unchanged guidance stays in the inherited prefix');
  assert.equal(JSON.stringify(model.requests.at(-1).input).includes(appended[0].revision), false);
  assert.equal(notices.some(notice => notice.type === 'fatal'), false);
  assert.deepEqual(model.failures, []);
});

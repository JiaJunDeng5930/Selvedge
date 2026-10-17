import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, rename, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig, loadConfig, validateConfig } from '../host/config.mjs';
import { observeContextSources } from '../host/context-sources.mjs';
import { Kernel } from '../host/kernel.mjs';
import { Service } from '../host/service.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const limits = { project_context_bytes: 32768 };
const skill = (name, description, body = 'Skill body remains outside the context.') =>
  `---\nname: ${name}\ndescription: ${description}\n---\n${body}\n`;
const edits = (patch, field) => patch.fields.find(item => item.field === field).edits;
const changes = page => page.messages.filter(item => item.type === 'context_change').map(item => item.change);

function applyEdits(content, edits) {
  const base = Array.from(content);
  let cursor = 0;
  let result = '';
  for (const edit of edits) {
    assert.ok(edit.start >= cursor);
    const end = edit.start + Array.from(edit.removed).length;
    assert.equal(base.slice(edit.start, end).join(''), edit.removed);
    result += base.slice(cursor, edit.start).join('') + edit.inserted;
    cursor = end;
  }
  return result + base.slice(cursor).join('');
}

test('skill information observes bounded nofollow frontmatter and excludes the body', async t => {
  const directory = await realpath(await home(t));
  const filename = path.join(directory, 'SKILL.md');
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const contract = await kernel.initialize();
  const send = async input => (await kernel.request(input)).value;
  const configured = await send({ kind: 'configure', instructions: { configured: 'Fixture instructions', global: null },
    profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture', reasoning_options: null }],
    tools: [], max_fork: 4, max_descendants: 8 });
  assert.equal(configured.reply.ok, true);
  const created = await send({ kind: 'command', command: { op: 'create', profile: 'fixture', message: 'inspect skill metadata' } });
  const effect = created.effects.find(effect => effect.kind === 'observe_context');
  assert.ok(effect);
  const definition = effect.definitions.find(definition => definition.kind === 'skill_information');
  assert.ok(definition, 'Production observation exposes the constructed skill definition');
  const config = validateConfig({ ...defaultConfig, skills: ['SKILL.md'] });
  const observe = async () => {
    const result = await observeContextSources({ ...effect, definitions: [definition] },
      { home: directory, config, limits: contract.limits });
    assert.equal(result.length, 1);
    return result[0];
  };
  assert.equal((await observe()).type, 'absent');
  await writeFile(filename, skill('fixture-skill', 'Explain the fixture.', 'PRIVATE-SKILL-BODY-A'));
  const firstObservation = await observe();
  assert.equal(firstObservation.type, 'present');
  const first = firstObservation.snapshot;
  assert.equal(first.key.type, 'skill_information');
  assert.deepEqual(first.key.definition, definition);
  assert.deepEqual(first.key.identity, { installation: directory, path: await realpath(filename) });
  assert.deepEqual(first.value, { type: 'skill_information', fields: { name: 'fixture-skill', description: 'Explain the fixture.', path: await realpath(filename) } });
  assert.match(first.revision, /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(first).includes('PRIVATE-SKILL-BODY'), false);
  await writeFile(filename, skill('fixture-skill', 'Explain the fixture.', 'PRIVATE-SKILL-BODY-B'));
  assert.deepEqual((await observe()).snapshot, first);
  await writeFile(filename, skill('fixture-skill', 'Explain the changed fixture.'));
  assert.notEqual((await observe()).snapshot.revision, first.revision);
  for (const content of ['No frontmatter', '---\ndescription: Missing name.\n---\nBody',
    '---\nname: [fixture]\ndescription: Explain it.\n---\nBody', Buffer.from([0xff]),
    Buffer.alloc(limits.project_context_bytes + 1, 65)]) {
    await writeFile(filename, content);
    assert.equal((await observe()).type, 'failure');
  }
  await unlink(filename);
  await symlink(path.join(directory, 'target.md'), filename);
  await writeFile(path.join(directory, 'target.md'), skill('linked', 'Must not follow links.'));
  assert.equal((await observe()).type, 'failure');
});

test('configured skills accept only bounded file paths', () => {
  assert.deepEqual(validateConfig({ ...defaultConfig }).skills, []);
  assert.deepEqual(validateConfig({ ...defaultConfig, skills: ['skills/fixture/SKILL.md'] }).skills, ['skills/fixture/SKILL.md']);
  for (const skills of [{ path: 'SKILL.md' }, [42], ['bad\0path'], ['a'.repeat(4097)], Array(65).fill('SKILL.md')]) {
    assert.throws(() => validateConfig({ ...defaultConfig, skills }));
  }
});

test('hierarchical discovery observes scoped guidance and skill catalogs without following links or losing failed scans', async t => {
  const directory = await realpath(await home(t));
  const state = path.join(directory, 'state');
  const repository = path.join(directory, 'repository');
  const workspace = path.join(repository, 'packages', 'app');
  const nested = [path.join(workspace, 'src'), path.join(workspace, 'src', 'api'), path.join(workspace, 'src', 'api', 'internal')];
  const second = path.join(directory, 'second');
  await Promise.all([state, path.join(repository, '.git'), nested.at(-1), path.join(second, '.git')].map(filename => mkdir(filename, { recursive: true })));
  const write = async (filename, content) => {
    await mkdir(path.dirname(filename), { recursive: true });
    await writeFile(filename, content);
    return filename;
  };
  await write(path.join(directory, 'AGENTS.md'), 'OUTSIDE-GIT-BOUNDARY');
  await write(path.join(repository, 'AGENTS.md'), 'Repository policy.');
  await write(path.join(workspace, 'AGENTS.md'), 'Primary root policy.');
  for (let index = 0; index < nested.length; index++) await write(path.join(nested[index], 'AGENTS.md'), `Nested policy ${index}.`);
  await write(path.join(second, 'AGENTS.md'), 'Secondary root policy.');
  const userSkill = await write(path.join(state, '.agents', 'skills', 'shared', 'SKILL.md'), skill('shared', 'User skill.', 'PRIVATE-USER-BODY'));
  await write(path.join(state, 'skills', 'legacy', 'SKILL.md'), skill('legacy', 'Service home skill.'));
  const ancestorSkill = await write(path.join(repository, '.agents', 'skills', 'shared', 'SKILL.md'), skill('shared', 'Repository skill.'));
  const nestedSkill = await write(path.join(nested.at(-1), '.claude', 'skills', 'shared', 'SKILL.md'), skill('shared', 'Nested skill.', 'PRIVATE-NESTED-BODY-A'));
  const configuredSkill = await write(path.join(workspace, '.agents', 'skills', 'configured', 'SKILL.md'), skill('explicit', 'Configured once.'));
  const secondSkill = await write(path.join(second, '.agents', 'skills', 'shared', 'SKILL.md'), skill('shared', 'Secondary root skill.'));
  await write(path.join(workspace, 'node_modules', 'dependency', 'AGENTS.md'), 'IGNORED-DEPENDENCY-GUIDANCE');
  await write(path.join(workspace, 'dist', '.agents', 'skills', 'ignored', 'SKILL.md'), skill('ignored', 'IGNORED-BUILD-SKILL'));
  await write(path.join(repository, '.git', 'AGENTS.md'), 'IGNORED-GIT-GUIDANCE');
  const external = path.join(directory, 'external');
  await write(path.join(external, 'AGENTS.md'), 'MUST-NOT-FOLLOW-DIRECTORY-LINK');
  await symlink(external, path.join(workspace, 'linked-directory'));

  const kernel = new Kernel();
  t.after(() => kernel.close());
  const contract = await kernel.initialize();
  const send = async input => (await kernel.request(input)).value;
  assert.equal((await send({ kind: 'configure', instructions: { configured: 'Fixture instructions', global: null },
    project: { workspace, path: '', revision: 'absent', instructions: '' },
    profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture', reasoning_options: null }],
    tools: [], max_fork: 4, max_descendants: 8 })).reply.ok, true);
  const created = await send({ kind: 'command', command: { op: 'create', profile: 'fixture', message: 'observe hierarchy' } });
  const initialEffect = created.effects.find(effect => effect.kind === 'observe_context');
  assert.ok(initialEffect);
  const expectedKinds = ['project_guidance', 'directory_guidance', 'user_skill_information', 'workspace_skill_information'];
  for (const kind of expectedKinds) assert.ok(initialEffect.definitions.some(definition => definition.kind === kind), kind);
  let config = validateConfig({ ...defaultConfig, instructions: 'Fixture instructions', skills: [configuredSkill] });
  let bindings = [];
  const observe = () => observeContextSources({ ...initialEffect, bindings,
    settings: { ...initialEffect.settings, workspace: { roots: [workspace, second], primary_root: workspace } } },
  { home: state, config, limits: contract.limits });
  const first = await observe();
  assert.equal(first.some(observation => observation.type === 'failure'), false, JSON.stringify(first));
  bindings = first.filter(observation => observation.type === 'present').map(observation => observation.snapshot);
  const byPath = filename => bindings.find(snapshot => snapshot.value.fields.path === filename);
  const directoryGuidance = bindings.filter(snapshot => snapshot.key.type === 'directory_guidance');
  assert.deepEqual(directoryGuidance.map(snapshot => snapshot.value.fields.path).sort(),
    [repository, ...nested, second].map(root => path.join(root, 'AGENTS.md')).sort());
  for (const snapshot of bindings.filter(snapshot => expectedKinds.includes(snapshot.key.type))) {
    const fields = snapshot.value.fields;
    if (snapshot.key.type === 'user_skill_information') {
      assert.equal(fields.applies_to, '*');
      assert.equal(fields.precedence, state);
    } else {
      assert.equal(fields.applies_to, fields.precedence);
      assert.ok(path.isAbsolute(fields.applies_to));
    }
    if (snapshot.key.type.endsWith('guidance')) assert.equal(fields.applies_to, path.dirname(fields.path));
  }
  assert.equal(byPath(path.join(workspace, 'AGENTS.md')).key.type, 'project_guidance');
  assert.equal(byPath(path.join(second, 'AGENTS.md')).key.type, 'directory_guidance');
  assert.equal(byPath(userSkill).key.type, 'user_skill_information');
  assert.equal(byPath(nestedSkill).value.fields.applies_to, nested.at(-1));
  assert.equal(byPath(ancestorSkill).value.fields.applies_to, repository);
  assert.equal(byPath(secondSkill).value.fields.applies_to, second);
  assert.equal(bindings.filter(snapshot => snapshot.value.fields.name === 'shared').length, 4, 'Same-name skills remain distinct by source path and scope');
  assert.equal(bindings.filter(snapshot => snapshot.value.fields.path === configuredSkill).length, 1, 'An explicitly configured discovered path is introduced once');
  assert.equal(byPath(configuredSkill).key.type, 'skill_information');
  assert.equal(JSON.stringify(bindings).includes('PRIVATE-'), false);
  for (const hidden of ['OUTSIDE-GIT-BOUNDARY', 'IGNORED-', 'MUST-NOT-FOLLOW']) assert.equal(JSON.stringify(bindings).includes(hidden), false);

  const originalNestedSkill = byPath(nestedSkill);
  await writeFile(nestedSkill, skill('shared', 'Nested skill.', 'PRIVATE-NESTED-BODY-B'));
  const bodyOnly = await observe();
  assert.deepEqual(bodyOnly.find(observation => observation.type === 'present' && observation.snapshot.value.fields.path === nestedSkill).snapshot, originalNestedSkill);
  await writeFile(nestedSkill, skill('shared', 'Nested skill updated.', 'PRIVATE-NESTED-BODY-C'));
  const metadataObserved = await observe();
  const metadata = metadataObserved.find(observation => observation.type === 'present' && observation.snapshot.value.fields.path === nestedSkill);
  assert.notEqual(metadata.snapshot.revision, originalNestedSkill.revision);
  assert.equal(applyEdits('Nested skill.', edits(metadata.patch, 'description')), 'Nested skill updated.');
  bindings = metadataObserved.filter(observation => observation.type === 'present').map(observation => observation.snapshot);

  config = validateConfig({ ...defaultConfig, instructions: 'Fixture instructions', skills: [configuredSkill, nestedSkill] });
  await writeFile(nestedSkill, 'Broken frontmatter during explicit-path handoff.');
  const failedHandoff = await observe();
  assert.ok(failedHandoff.some(observation => observation.type === 'failure' && JSON.stringify(observation.key) === JSON.stringify(metadata.snapshot.key)));
  assert.equal(failedHandoff.some(observation => observation.type === 'absent' && JSON.stringify(observation.key) === JSON.stringify(metadata.snapshot.key)), false,
    'An unreadable explicit replacement cannot withdraw its last accepted automatic metadata');
  await writeFile(nestedSkill, skill('shared', 'Nested skill updated.', 'PRIVATE-NESTED-BODY-D'));
  const explicitHandoff = await observe();
  assert.ok(explicitHandoff.some(observation => observation.type === 'present' && observation.snapshot.key.type === 'skill_information' && observation.snapshot.value.fields.path === nestedSkill));
  assert.ok(explicitHandoff.some(observation => observation.type === 'absent' && JSON.stringify(observation.key) === JSON.stringify(metadata.snapshot.key)));
  bindings = explicitHandoff.filter(observation => observation.type === 'present').map(observation => observation.snapshot);
  config = validateConfig({ ...defaultConfig, instructions: 'Fixture instructions', skills: [configuredSkill] });
  const automaticHandoff = await observe();
  assert.ok(automaticHandoff.some(observation => observation.type === 'present' && observation.snapshot.key.type === 'workspace_skill_information' && observation.snapshot.value.fields.path === nestedSkill));
  assert.ok(automaticHandoff.some(observation => observation.type === 'absent' && observation.key.type === 'skill_information' && observation.key.identity.path === nestedSkill));
  bindings = automaticHandoff.filter(observation => observation.type === 'present').map(observation => observation.snapshot);

  const agents = path.join(nested[1], 'AGENTS.md');
  const override = path.join(nested[1], 'AGENTS.override.md');
  await writeFile(override, 'Override policy.');
  const overridden = await observe();
  assert.ok(overridden.some(observation => observation.type === 'present' && observation.snapshot.value.fields.path === override
    && observation.snapshot.value.fields.content === 'Override policy.'));
  assert.ok(overridden.some(observation => observation.type === 'absent' && observation.key.identity.path === agents));
  bindings = overridden.filter(observation => observation.type === 'present').map(observation => observation.snapshot);
  await unlink(override);
  const fallback = await observe();
  assert.ok(fallback.some(observation => observation.type === 'present' && observation.snapshot.value.fields.path === agents));
  assert.ok(fallback.some(observation => observation.type === 'absent' && observation.key.identity.path === override));
  bindings = fallback.filter(observation => observation.type === 'present').map(observation => observation.snapshot);

  await unlink(agents); await symlink(path.join(repository, 'AGENTS.md'), agents);
  const unreadable = await observe();
  const previousGuidance = bindings.filter(snapshot => snapshot.key.type === 'directory_guidance');
  assert.equal(unreadable.filter(observation => observation.type === 'absent' && observation.key.type === 'directory_guidance').length, 0);
  for (const snapshot of previousGuidance) assert.ok(unreadable.some(observation => observation.type === 'failure'
    && JSON.stringify(observation.key) === JSON.stringify(snapshot.key)), 'A failed guidance collection preserves every accepted baseline');
  await unlink(agents); await writeFile(agents, 'Nested policy 1.');

  const moved = `${workspace}-moved`;
  await rename(workspace, moved); await symlink(moved, workspace);
  const failedScan = await observe();
  for (const snapshot of bindings.filter(snapshot => ['directory_guidance', 'workspace_skill_information'].includes(snapshot.key.type))) {
    assert.ok(failedScan.some(observation => observation.type === 'failure' && JSON.stringify(observation.key) === JSON.stringify(snapshot.key)));
    assert.equal(failedScan.some(observation => observation.type === 'absent' && JSON.stringify(observation.key) === JSON.stringify(snapshot.key)), false);
  }
  assert.ok(failedScan.some(observation => observation.type === 'present' && observation.snapshot.value.fields.path === userSkill), 'Independent user catalogs continue refreshing after a workspace scan fails');
  await unlink(workspace); await rename(moved, workspace);

  await unlink(path.join(nested.at(-1), 'AGENTS.md')); await unlink(nestedSkill);
  const removed = await observe();
  for (const filename of [path.join(nested.at(-1), 'AGENTS.md'), nestedSkill]) {
    const before = bindings.find(snapshot => snapshot.value.fields.path === filename);
    assert.ok(removed.some(observation => observation.type === 'absent' && JSON.stringify(observation.key) === JSON.stringify(before.key)));
  }

  const guidanceDefinition = initialEffect.definitions.find(definition => definition.kind === 'directory_guidance');
  for (const [bound, maximum] of [['max_sources', 1], ['max_directories', 1], ['max_entries', 1], ['max_bytes', 1]]) {
    const definition = structuredClone(guidanceDefinition);
    definition.observer.policy[bound] = maximum;
    const boundedBindings = previousGuidance.map(snapshot => ({ ...snapshot, key: { ...snapshot.key, definition } }));
    const bounded = await observeContextSources({ ...initialEffect, definitions: [definition], bindings: boundedBindings,
      settings: { ...initialEffect.settings, workspace: { roots: [workspace, second], primary_root: workspace } } },
    { home: state, config, limits: contract.limits });
    assert.equal(bounded.length, boundedBindings.length);
    assert.ok(bounded.every(observation => observation.type === 'failure' && /budget exceeded/.test(observation.message)), bound);
    for (const snapshot of boundedBindings) assert.ok(bounded.some(observation => JSON.stringify(observation.key) === JSON.stringify(snapshot.key)), 'A budget failure preserves every accepted binding');
  }
});

test('live instruction and skill metadata changes use deltas while unintroduced bodies stay absent', { timeout: 30_000 }, async t => {
  const directory = await home(t);
  const state = path.join(directory, 'state');
  const workspace = path.join(directory, 'workspace');
  await mkdir(state); await mkdir(workspace);
  const filename = path.join(state, 'SKILL.md');
  const configFile = path.join(state, 'config.json');
  const credential = 'SELVEDGE_SKILL_CONTEXT_FIXTURE_KEY';
  const previous = process.env[credential]; process.env[credential] = 'fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[credential]; else process.env[credential] = previous; });
  const model = await responsesServer(t, async () => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] }]);
  const config = instructions => ({ ...defaultConfig, instructions, skills: ['SKILL.md'], profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: credential, timeout_ms: 5000,
  } } });
  const originalInstruction = 'Keep 🧵 the shared prefix.\nUse npm.\nKeep the unchanged tail.\n';
  const updatedInstruction = 'Keep 🧵 the shared prefix.\nUse bun.\nKeep the unchanged tail.\n';
  await writeFile(configFile, JSON.stringify(config(originalInstruction)));
  await writeFile(filename, skill('fixture-skill', 'Describe version A.', 'NEVER-INJECT-BODY-A'));
  const loaded = await loadConfig({ home: state, filename: configFile });
  const service = await Service.open({ home: state, cwd: workspace, config: loaded.config });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'create', profile: 'fixture', message: 'start' })).reply.ok, true);
  const initial = await taskIdle(service);
  const initialSkill = changes(initial).find(change => change.type === 'introduce' && change.snapshot.key.type === 'skill_information');
  assert.ok(initialSkill);
  assert.equal(initialSkill.snapshot.value.fields.name, 'fixture-skill');
  assert.equal(JSON.stringify(initial.messages).includes('NEVER-INJECT-BODY'), false);
  await writeFile(filename, skill('fixture-skill', 'Describe version A.', 'NEVER-INJECT-BODY-B'));
  await service.command({ op: 'send', task_id: 0, message: 'body only' });
  const bodyChanged = await taskIdle(service);
  assert.equal(changes(bodyChanged).length, changes(initial).length);
  await writeFile(configFile, JSON.stringify(config(updatedInstruction)));
  await writeFile(filename, skill('changed-skill', 'Describe version B.', 'NEVER-INJECT-BODY-C'));
  await service.command({ op: 'send', task_id: 0, message: 'metadata and instruction' });
  const updated = await taskIdle(service);
  assert.deepEqual(updated.messages.slice(0, bodyChanged.messages.length), bodyChanged.messages);
  const appended = updated.messages.slice(bodyChanged.messages.length).filter(item => item.type === 'context_change').map(item => item.change);
  const instruction = appended.find(change => change.key?.type === 'configured_instruction' && change.key.identity.origin === 'configured');
  const metadata = appended.find(change => change.key?.type === 'skill_information');
  assert.equal(appended.length, 2);
  assert.equal(instruction.type, 'amend');
  assert.equal(instruction.patch.type, 'field_edits');
  assert.equal(applyEdits(originalInstruction, edits(instruction.patch, 'content')), updatedInstruction);
  assert.ok(!JSON.stringify(instruction).includes('shared prefix'));
  assert.equal(metadata.type, 'amend');
  assert.equal(metadata.base_revision, initialSkill.snapshot.revision);
  assert.equal(metadata.patch.type, 'field_edits');
  assert.equal(applyEdits('fixture-skill', edits(metadata.patch, 'name')), 'changed-skill');
  assert.equal(applyEdits('Describe version A.', edits(metadata.patch, 'description')), 'Describe version B.');
  assert.equal(JSON.stringify(model.requests).includes('NEVER-INJECT-BODY'), false);
  const wire = JSON.stringify(model.requests.at(-1).input);
  assert.equal(wire.includes(metadata.base_revision), false); assert.equal(wire.includes(metadata.revision), false);
  await unlink(filename);
  await service.command({ op: 'send', task_id: 0, message: 'skill removed' });
  const removed = await taskIdle(service);
  const removal = changes(removed).at(-1);
  assert.deepEqual(removal, { type: 'remove', key: initialSkill.snapshot.key, base_revision: metadata.revision });
  assert.deepEqual(model.failures, []);
});

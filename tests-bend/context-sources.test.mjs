import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig, loadConfig, validateConfig } from '../host/config.mjs';
import { snapshotSkillInformation } from '../host/context-sources.mjs';
import { Service } from '../host/service.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const limits = { project_context_bytes: 32768 };
const skill = (name, description, body = 'Skill body remains outside the context.') =>
  `---\nname: ${name}\ndescription: ${description}\n---\n${body}\n`;
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
  assert.equal(await snapshotSkillInformation(filename, directory, limits), null);
  await writeFile(filename, skill('fixture-skill', 'Explain the fixture.', 'PRIVATE-SKILL-BODY-A'));
  const first = await snapshotSkillInformation(filename, directory, limits);
  assert.deepEqual(first.key, { type: 'skill_information', installation: await realpath(directory), path: await realpath(filename) });
  assert.deepEqual(first.value, { type: 'skill_information', name: 'fixture-skill', description: 'Explain the fixture.', path: await realpath(filename) });
  assert.match(first.revision, /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(first).includes('PRIVATE-SKILL-BODY'), false);
  await writeFile(filename, skill('fixture-skill', 'Explain the fixture.', 'PRIVATE-SKILL-BODY-B'));
  assert.deepEqual(await snapshotSkillInformation(filename, directory, limits), first);
  await writeFile(filename, skill('fixture-skill', 'Explain the changed fixture.'));
  assert.notEqual((await snapshotSkillInformation(filename, directory, limits)).revision, first.revision);
  for (const content of ['No frontmatter', '---\nname: fixture\n---\nBody',
    '---\nname: [fixture]\ndescription: Explain it.\n---\nBody', Buffer.from([0xff]),
    Buffer.alloc(limits.project_context_bytes + 1, 65)]) {
    await writeFile(filename, content);
    await assert.rejects(snapshotSkillInformation(filename, directory, limits));
  }
  await unlink(filename);
  await symlink(path.join(directory, 'target.md'), filename);
  await writeFile(path.join(directory, 'target.md'), skill('linked', 'Must not follow links.'));
  await assert.rejects(snapshotSkillInformation(filename, directory, limits), error => ['ELOOP', 'EMLINK'].includes(error.code));
});

test('configured skills accept only bounded file paths', () => {
  assert.deepEqual(validateConfig({ ...defaultConfig }).skills, []);
  assert.deepEqual(validateConfig({ ...defaultConfig, skills: ['skills/fixture/SKILL.md'] }).skills, ['skills/fixture/SKILL.md']);
  for (const skills of [{ path: 'SKILL.md' }, [42], ['bad\0path'], ['a'.repeat(4097)], Array(65).fill('SKILL.md')]) {
    assert.throws(() => validateConfig({ ...defaultConfig, skills }));
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
  assert.equal(initialSkill.snapshot.value.name, 'fixture-skill');
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
  const instruction = appended.find(change => change.key?.type === 'instruction' && change.key.origin === 'configured');
  const metadata = appended.find(change => change.key?.type === 'skill_information');
  assert.equal(appended.length, 2);
  assert.equal(instruction.type, 'amend');
  assert.equal(instruction.patch.type, 'text_edits');
  assert.equal(applyEdits(originalInstruction, instruction.patch.edits), updatedInstruction);
  assert.ok(!JSON.stringify(instruction).includes('shared prefix'));
  assert.equal(metadata.type, 'amend');
  assert.equal(metadata.base_revision, initialSkill.snapshot.revision);
  assert.equal(metadata.patch.type, 'skill_edits');
  assert.equal(applyEdits('fixture-skill', metadata.patch.name), 'changed-skill');
  assert.equal(applyEdits('Describe version A.', metadata.patch.description), 'Describe version B.');
  assert.equal(JSON.stringify(model.requests).includes('NEVER-INJECT-BODY'), false);
  const wire = JSON.stringify(model.requests.at(-1).input);
  assert.ok(wire.includes(metadata.base_revision)); assert.ok(wire.includes(metadata.revision));
  await unlink(filename);
  await service.command({ op: 'send', task_id: 0, message: 'skill removed' });
  const removed = await taskIdle(service);
  const removal = changes(removed).at(-1);
  assert.deepEqual(removal, { type: 'remove', key: initialSkill.snapshot.key, base_revision: metadata.revision });
  assert.deepEqual(model.failures, []);
});

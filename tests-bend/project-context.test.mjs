import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile, symlink, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { snapshotProject, snapshotGlobalInstructions } from '../host/project.mjs';
import { Kernel } from '../host/kernel.mjs';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

test('project snapshots are bounded, versioned UTF-8 observations and never follow root AGENTS symlinks', async t => {
  const directory = await home(t);
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const { limits } = await kernel.initialize();
  assert.equal(limits.project_context_bytes, 32768);
  assert.equal(await snapshotGlobalInstructions(directory, limits), null);
  assert.deepEqual(await snapshotProject(directory, limits), {
    workspace: await realpath(directory), revision: 'absent', instructions: '',
  });
  const text = 'Run the checked tests. 保留约束。\n';
  await writeFile(path.join(directory, 'AGENTS.md'), text);
  assert.deepEqual(await snapshotProject(directory, limits), {
    workspace: await realpath(directory), instructions: text,
    revision: createHash('sha256').update(text).digest('hex'),
  });
  for (const [name, content, error] of [
    ['large', Buffer.alloc(limits.project_context_bytes + 1, 65), /exceeds/],
    ['invalid-utf8', Buffer.from([0xff, 0xfe]), /UTF-8/],
    ['binary', Buffer.from([65, 0, 66]), /NUL/],
  ]) {
    const cwd = path.join(directory, name);
    await mkdir(cwd);
    await writeFile(path.join(cwd, 'AGENTS.md'), content);
    await assert.rejects(snapshotProject(cwd, limits), error);
    await assert.rejects(snapshotGlobalInstructions(cwd, limits), error);
  }
  const linked = path.join(directory, 'linked');
  await mkdir(linked);
  await symlink(path.join(directory, 'AGENTS.md'), path.join(linked, 'AGENTS.md'));
  await assert.rejects(snapshotProject(linked, limits), error => ['ELOOP', 'EMLINK'].includes(error.code));
  await assert.rejects(snapshotGlobalInstructions(linked, limits), error => ['ELOOP', 'EMLINK'].includes(error.code));
  const nonfile = path.join(directory, 'nonfile');
  await mkdir(path.join(nonfile, 'AGENTS.md'), { recursive: true });
  await assert.rejects(snapshotProject(nonfile, limits), /regular file/);
  await assert.rejects(snapshotGlobalInstructions(nonfile, limits), /regular file/);
});

test('Bend-generated JavaScript rejects an invalid project revision', async t => {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const configure = project => input({ kind: 'configure', instructions: { configured: 'Fixture instructions', global: null }, profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture', reasoning_options: null }],
    tools: [], max_fork: 4, max_descendants: 8, project });
  const project = { workspace: '/project', instructions: 'Original project instructions', revision: 'a'.repeat(64) };
  assert.equal((await configure(project)).reply.ok, true);
  const rejected = await configure({ ...project, revision: 'absent' });
  assert.equal(rejected.reply.ok, false, 'An absent source cannot carry invented guidance');
});

test('instruction changes append committed deltas across file changes, forks and restart', { timeout: 25_000 }, async t => {
  const directory = await home(t);
  const state = path.join(directory, 'state');
  const workspace = path.join(directory, 'workspace');
  await mkdir(state); await mkdir(workspace);
  const credential = 'SELVEDGE_CONTEXT_FIXTURE_KEY';
  const previous = process.env[credential]; process.env[credential] = 'fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[credential]; else process.env[credential] = previous; });
  const globalFirst = 'Global guidance snapshot A';
  const projectFirst = 'Project guidance snapshot A';
  await writeFile(path.join(state, 'AGENTS.md'), globalFirst);
  await writeFile(path.join(workspace, 'AGENTS.md'), projectFirst);
  const effects = [];
  const model = await responsesServer(t, async body => {
    const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
    let effect;
    try {
      const row = db.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 1').get();
      effect = JSON.parse(row.decision).effects.find(item => item.kind === 'model');
    } finally { db.close(); }
    assert.ok(effect, 'Model HTTP dispatch must follow its SQLite commit');
    assert.equal('instructions' in effect, false);
    assert.equal('context_instructions' in effect, false);
    assert.equal('project' in effect.model, false);
    assert.ok(!body.instructions);
    const developer = body.input.filter(item => item.role === 'developer').map(item => item.content).join('\n');
    for (const item of effect.history.filter(item => item.type === 'context_change')) {
      const change = item.change;
      assert.ok(developer.includes(change.type === 'introduce' ? change.snapshot.revision : change.base_revision));
      if (change.type === 'amend') assert.ok(developer.includes(change.revision));
    }
    effects.push(effect);
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'fixture answer' }] }];
  });
  const configuration = instructions => validateConfig({ ...defaultConfig, instructions, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: credential, timeout_ms: 5000,
  } } });
  let config = configuration('Configured instructions A');
  let service = await Service.open({ home: state, cwd: workspace, config });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'create', profile: 'fixture', message: 'original objective' })).reply.ok, true);
  const original = await taskIdle(service);
  const initial = effects[0].history;
  assert.deepEqual(initial.map(item => item.role === 'task_context' ? item.type : item.role), ['context_change', 'context_change', 'context_change', 'settings', 'user']);
  assert.deepEqual(initial[0].change, { type: 'introduce', snapshot: {
    key: { type: 'instruction', origin: 'configured', path: '' }, revision: 'initial',
    value: { type: 'instruction', content: 'Configured instructions A' },
  } });
  assert.deepEqual(initial[1].change, { type: 'introduce', snapshot: {
    key: { type: 'instruction', origin: 'global_agents', path: await realpath(path.join(state, 'AGENTS.md')) },
    revision: createHash('sha256').update(globalFirst).digest('hex'), value: { type: 'instruction', content: globalFirst },
  } });
  assert.equal(initial[2].change.snapshot.value.content, projectFirst);
  assert.deepEqual(initial[2].change.snapshot.key, { type: 'project_guidance', workspace: await realpath(workspace) });
  assert.deepEqual(original.messages.slice(0, initial.length), initial);
  await service.close();
  await writeFile(path.join(state, 'AGENTS.md'), 'Global guidance snapshot B');
  await writeFile(path.join(workspace, 'AGENTS.md'), 'Project guidance snapshot B');
  config = configuration('Configured instructions B');
  service = await Service.open({ home: state, cwd: workspace, config });
  await service.command({ op: 'send', task_id: 0, message: 'continue original' });
  const continued = await taskIdle(service);
  assert.deepEqual(continued.messages.slice(0, original.messages.length), original.messages);
  const revisions = continued.messages.slice(original.messages.length).filter(item => item.type === 'context_change').map(item => item.change);
  assert.equal(revisions.length, 3);
  assert.ok(revisions.every(change => change.type === 'amend' && change.patch.type === 'text_edits'));
  assert.deepEqual(revisions.map(change => change.key), initial.slice(0, 3).map(item => item.change.snapshot.key));
  assert.ok(revisions.every(change => !('value' in change) && !('snapshot' in change)));
  assert.equal(continued.messages.slice(original.messages.length).filter(item => item.type === 'settings').length, 0);
  assert.equal((await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['child objective'] })).reply.ok, true);
  const child = await taskIdle(service, 1); await taskIdle(service, 0);
  assert.deepEqual(child.messages.slice(0, continued.messages.length), continued.messages);
  assert.equal(child.messages.slice(continued.messages.length).filter(item => item.type === 'context_change').length, 0);
  await service.command({ op: 'create', profile: 'fixture', message: 'new objective' });
  const fresh = await taskIdle(service, 2);
  assert.equal(fresh.messages[0].change.snapshot.value.content, 'Configured instructions B');
  assert.equal(fresh.messages[1].change.snapshot.value.content, 'Global guidance snapshot B');
  assert.equal(fresh.messages[2].change.snapshot.value.content, 'Project guidance snapshot B');
  assert.deepEqual(model.failures, []);
  const alternate = path.join(directory, 'alternate'); await mkdir(alternate);
  await writeFile(path.join(alternate, 'AGENTS.md'), 'Explicit child project selection');
  const project = await service.command({ op: 'create_project', name: 'Alternate project', workspace: { roots: [alternate] } });
  assert.equal(project.reply.ok, true);
  const parent = await taskIdle(service);
  const fork = await service.command({ op: 'fork', task_id: 0, child_count: 1, messages: ['selected child'],
    settings: { project_id: project.reply.result.project_id } });
  assert.equal(fork.reply.ok, true);
  const selected = await taskIdle(service, 3); const afterFork = await taskIdle(service);
  assert.deepEqual(selected.messages.slice(0, parent.messages.length), parent.messages);
  const override = selected.messages.slice(parent.messages.length);
  const selection = override.findIndex(item => item.type === 'context_change' && item.change.type === 'introduce'
    && item.change.snapshot.key.type === 'project_guidance');
  assert.ok(selection >= 0);
  assert.deepEqual(override.slice(selection, selection + 2).map(item => item.type ?? item.role), ['context_change', 'settings']);
  assert.ok(override.findIndex(item => item.role === 'user' && item.content === 'selected child') > selection + 1);
  assert.equal(override[selection].change.snapshot.value.content, 'Explicit child project selection');
  assert.deepEqual(afterFork.messages.slice(0, parent.messages.length), parent.messages);
  assert.equal(JSON.stringify(afterFork.messages).includes('Explicit child project selection'), false);
  await service.close();
  service = await Service.open({ home: state, cwd: workspace, config: configuration('') });
  await service.command({ op: 'create', profile: 'fixture', message: 'explicit empty configuration' });
  const empty = await taskIdle(service, 4);
  assert.equal(empty.messages[0].type, 'context_change'); assert.equal(empty.messages[0].change.snapshot.value.content, '');
  for (const effect of effects) {
    const recorded = (await service.command({ op: 'read', task_id: effect.task_id })).reply.result.messages;
    assert.deepEqual(recorded.slice(0, effect.history.length), effect.history);
  }
  assert.deepEqual(model.failures, []);
});

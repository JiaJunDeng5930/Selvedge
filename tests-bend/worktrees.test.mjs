import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { existsSync, renameSync } from 'node:fs';
import { access, chmod, mkdir, readFile, readdir, realpath, rename, symlink, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import path from 'node:path';
import { CommandNotSubmitted, Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { archiveManagedWorktree, createManagedWorktree, observeWorkspaceGit, reconcileManagedWorktree } from '../host/worktrees.mjs';
import { home, responsesServer, shellQuote, taskIdle } from './support.mjs';

const execute = promisify(execFile);
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const contextLimits = { project_context_bytes: 65536 };

async function git(cwd, ...arguments_) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Worktree fixture', '-c', 'user.email=worktree@example.test', '-C', cwd, ...arguments_], { env });
  return stdout.trim();
}

async function repository(t) {
  const base = await realpath(await home(t));
  const root = path.join(base, 'source repository');
  const primary = path.join(root, 'packages', 'app');
  await mkdir(primary, { recursive: true });
  await git(root, 'init', '--initial-branch=main');
  await writeFile(path.join(root, '.gitignore'), 'ignored.local\n');
  await writeFile(path.join(primary, 'AGENTS.md'), 'Keep the worktree task guidance.');
  await writeFile(path.join(primary, 'tracked.txt'), 'committed tracked contents');
  await writeFile(path.join(primary, 'staged.txt'), 'committed staged contents');
  await git(root, 'add', '.');
  await git(root, 'commit', '-m', 'Initial worktree fixture');
  const commit = await git(root, 'rev-parse', 'HEAD');
  await writeFile(path.join(primary, 'tracked.txt'), 'uncommitted tracked contents 世界');
  await writeFile(path.join(primary, 'staged.txt'), 'staged local contents');
  await git(root, 'add', 'packages/app/staged.txt');
  await writeFile(path.join(primary, 'untracked.txt'), 'untracked local contents');
  await writeFile(path.join(primary, 'ignored.local'), 'source-only ignored contents');
  return { base, root, primary, commit };
}

function journalRows(state) {
  const database = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
  try {
    return database.prepare('SELECT seq, input, decision FROM journal ORDER BY seq').all()
      .map(row => ({ sequence: row.seq, input: JSON.parse(row.input), decision: JSON.parse(row.decision) }));
  } finally { database.close(); }
}

function credentials(t) {
  const key = `SELVEDGE_WORKTREE_FIXTURE_${process.pid}_${Math.random().toString(16).slice(2)}`;
  process.env[key] = 'local-test-only';
  t.after(() => { delete process.env[key]; });
  return key;
}

async function worktreeStatus(service, taskId, status) {
  const deadline = Date.now() + 10000;
  let entry;
  do {
    const decision = await service.command({ op: 'read_worktree', task_id: taskId });
    assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
    entry = decision.reply.result;
    if (entry.status === status) return entry;
    assert.ok(!['create_failed', 'archive_failed'].includes(entry.status), JSON.stringify(entry));
    await delay(10);
  } while (Date.now() < deadline);
  assert.fail(`Managed worktree did not reach ${status}: ${JSON.stringify(entry)}`);
}

test('committed Git worktree creation precedes model execution and its home sandbox preserves other worktrees', { timeout: 30000 }, async t => {
  const { base, root, primary, commit } = await repository(t);
  const state = path.join(base, 'state');
  const extra = path.join(base, 'second root');
  await mkdir(extra);
  const api_key_env = credentials(t);
  let service;
  let taskId;
  let siblingRoot;
  let managedRoot;
  let managedPrimary;
  const model = await responsesServer(t, async (body, index) => {
    const entries = (await service.command({ op: 'list_worktrees' })).reply.result.worktrees;
    const entry = entries.find(value => value.task_id === taskId);
    assert.equal(entry.status, 'ready', 'The provider must not run while its checkout is being created');
    assert.equal(entry.source_root, primary);
    assert.equal(entry.root, managedRoot);
    assert.equal(entry.target_primary, managedPrimary);
    const rows = journalRows(state);
    const created = rows.find(row => row.input.kind === 'worktree_created' && row.input.task_id === taskId);
    const requested = rows.find(row => row.decision.effects.some(effect => effect.kind === 'model' && effect.task_id === taskId));
    assert.ok(created, 'A successful checkout completion must be durable before the model request');
    assert.equal(created.input.ok, true);
    assert.ok(requested.sequence >= created.sequence);
    if (index === 0) {
      assert.ok(JSON.stringify(body.input).includes('Keep the worktree task guidance.'));
      assert.equal(await git(managedRoot, 'rev-parse', 'HEAD'), commit);
      await assert.rejects(git(managedRoot, 'symbolic-ref', '-q', 'HEAD'), error => error.code === 1);
      assert.equal(await readFile(path.join(managedPrimary, 'tracked.txt'), 'utf8'), 'uncommitted tracked contents 世界');
      assert.equal(await readFile(path.join(managedPrimary, 'staged.txt'), 'utf8'), 'staged local contents');
      assert.equal(await readFile(path.join(managedPrimary, 'untracked.txt'), 'utf8'), 'untracked local contents');
      await assert.rejects(access(path.join(managedPrimary, 'ignored.local')), { code: 'ENOENT' });
      const command = [
        'set -eu', 'pwd', 'printf allowed > task-write.txt',
        `printf second > ${shellQuote(path.join(extra, 'task-write.txt'))}`,
        ...[path.join(state, 'forbidden'), path.join(siblingRoot, 'forbidden'), path.join(primary, 'forbidden')]
          .map(filename => `if (printf denied > ${shellQuote(filename)}) 2>/dev/null; then exit 71; fi`),
        'printf sandbox-ok',
      ].join('\n');
      return [{ type: 'function_call', call_id: 'worktree-sandbox', name: 'bash', arguments: JSON.stringify({ command }) }];
    }
    assert.equal(index, 1);
    const output = JSON.parse(body.input.find(item => item.type === 'function_call_output' && item.call_id === 'worktree-sandbox').output);
    assert.equal(output.is_error, false, JSON.stringify(output));
    assert.ok(output.value.stdout.includes(managedPrimary));
    assert.ok(output.value.stdout.includes('sandbox-ok'));
    return answer('The isolated worktree is writable.');
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    ...defaultConfig.profiles,
    fixture: { provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env },
  } });
  service = await Service.open({ home: state, cwd: root, config });
  t.after(() => service.close());
  const project = await service.command({ op: 'create_project', name: 'Worktree project',
    workspace: { roots: [extra, primary], primary_root: primary } });
  assert.equal(project.reply.ok, true, JSON.stringify(project.reply));
  const settings = { project_id: project.reply.result.project_id };
  const sibling = await service.command({ op: 'create_worktree_task', profile: 'demo', message: 'Keep this sibling checkout.', settings });
  assert.equal(sibling.reply.ok, true, JSON.stringify(sibling.reply));
  siblingRoot = (await worktreeStatus(service, sibling.reply.result.task_id, 'ready')).root;
  await taskIdle(service, sibling.reply.result.task_id);
  const effectsAtCommit = [];
  service.journal.on('commit', decision => {
    for (const effect of decision.effects) {
      if (effect.kind === 'worktree_create') effectsAtCommit.push({ kind: effect.kind, task_id: effect.task_id,
        activeExists: existsSync(path.join(state, 'worktrees', `task-${effect.task_id}`)) });
      if (effect.kind === 'worktree_archive') effectsAtCommit.push({ kind: effect.kind, task_id: effect.task_id,
        activeExists: existsSync(effect.root), archivedExists: existsSync(path.join(state, 'worktrees', 'archived', `task-${effect.task_id}`)) });
    }
  });
  const started = await service.command({ op: 'create_worktree_task', profile: 'fixture', reasoning: 'default',
    message: 'Use this project in its own Git worktree.', settings });
  assert.equal(started.reply.ok, true, JSON.stringify(started.reply));
  taskId = started.reply.result.task_id;
  managedRoot = path.join(state, 'worktrees', `task-${taskId}`);
  managedPrimary = path.join(managedRoot, 'packages', 'app');
  await worktreeStatus(service, taskId, 'ready');
  const page = await taskIdle(service, taskId).catch(error => {
    assert.deepEqual(model.failures, []);
    throw error;
  });
  assert.deepEqual(model.failures, []);
  assert.equal(model.requests.length, 2);
  assert.deepEqual(page.task.settings.workspace, { roots: [extra, managedPrimary], primary_root: managedPrimary });
  assert.equal(page.task.settings.project_id, settings.project_id);
  assert.equal(await readFile(path.join(managedPrimary, 'task-write.txt'), 'utf8'), 'allowed');
  assert.equal(await readFile(path.join(extra, 'task-write.txt'), 'utf8'), 'second');
  for (const directory of [state, siblingRoot, primary]) await assert.rejects(access(path.join(directory, 'forbidden')), { code: 'ENOENT' });
  assert.equal(await readFile(path.join(primary, 'tracked.txt'), 'utf8'), 'uncommitted tracked contents 世界');
  assert.equal(await readFile(path.join(primary, 'ignored.local'), 'utf8'), 'source-only ignored contents');
  assert.deepEqual(effectsAtCommit, [{ kind: 'worktree_create', task_id: taskId, activeExists: false }]);

  await writeFile(path.join(managedPrimary, 'tracked.txt'), 'worktree-only tracked edit');
  await writeFile(path.join(managedPrimary, 'ignored.local'), 'worktree-only ignored output');
  const archive = await service.command({ op: 'archive', task_id: taskId });
  assert.equal(archive.reply.ok, true, JSON.stringify(archive.reply));
  const archived = await worktreeStatus(service, taskId, 'archived');
  const archivedPrimary = path.join(archived.root, 'packages', 'app');
  assert.equal(archived.root, path.join(state, 'worktrees', 'archived', `task-${taskId}`));
  await assert.rejects(access(managedRoot), { code: 'ENOENT' });
  assert.equal(await readFile(path.join(archivedPrimary, 'tracked.txt'), 'utf8'), 'worktree-only tracked edit');
  assert.equal(await readFile(path.join(archivedPrimary, 'staged.txt'), 'utf8'), 'staged local contents');
  assert.equal(await readFile(path.join(archivedPrimary, 'untracked.txt'), 'utf8'), 'untracked local contents');
  assert.equal(await readFile(path.join(archivedPrimary, 'ignored.local'), 'utf8'), 'worktree-only ignored output');
  assert.equal(await readFile(path.join(archivedPrimary, 'task-write.txt'), 'utf8'), 'allowed');
  assert.equal(await git(archived.root, 'rev-parse', '--show-toplevel'), archived.root);
  assert.deepEqual(effectsAtCommit.at(-1), { kind: 'worktree_archive', task_id: taskId, activeExists: true, archivedExists: false });
  const rows = journalRows(state);
  for (const kind of ['worktree_create', 'worktree_archive']) {
    assert.equal(rows.flatMap(row => row.decision.effects).filter(effect => effect.kind === kind && effect.task_id === taskId).length, 1);
  }
  await service.close();
  service = await Service.open({ home: state, cwd: extra, config });
  assert.deepEqual((await service.command({ op: 'read_worktree', task_id: taskId })).reply.result, archived);
  assert.equal((await service.command({ op: 'read', task_id: taskId })).reply.result.task.status, 'archived');
  assert.equal((await worktreeStatus(service, sibling.reply.result.task_id, 'ready')).root, siblingRoot);
  assert.equal(model.requests.length, 2, 'Replay must not start a provider or repeat checkout effects');
  assert.equal(await readFile(path.join(archivedPrimary, 'ignored.local'), 'utf8'), 'worktree-only ignored output');
  assert.equal((await git(root, 'worktree', 'list', '--porcelain')).split('\n').filter(line => line.startsWith('worktree ')).length, 3);
});

test('worktree creation recreates an empty or ignored-only primary directory omitted by Git checkout', { timeout: 20000 }, async t => {
  const { base, root } = await repository(t);
  const primaries = [path.join(root, 'empty primary'), path.join(root, 'ignored primary')];
  await Promise.all(primaries.map(primary => mkdir(primary)));
  await writeFile(path.join(primaries[1], 'ignored.local'), 'keep ignored source setup local');
  const service = await Service.open({ home: path.join(base, 'state'), cwd: root,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  for (const primary of primaries) {
    const started = await service.command({ op: 'create_worktree_task', profile: 'demo', message: 'Use this empty primary.',
      settings: { workspace: { roots: [primary], primary_root: primary } } });
    assert.equal(started.reply.ok, true, JSON.stringify(started.reply));
    const taskId = started.reply.result.task_id;
    const entry = await worktreeStatus(service, taskId, 'ready');
    const expectedPrimary = path.join(entry.root, path.relative(root, primary));
    assert.equal(entry.target_primary, expectedPrimary);
    assert.equal(await realpath(expectedPrimary), expectedPrimary);
    assert.deepEqual(await readdir(expectedPrimary), []);
    assert.deepEqual((await taskIdle(service, taskId)).task.settings.workspace,
      { roots: [expectedPrimary], primary_root: expectedPrimary });
  }
  assert.equal(await readFile(path.join(primaries[1], 'ignored.local'), 'utf8'), 'keep ignored source setup local');
});

test('forked tasks write their shared worktree and keep it active until every user is archived', { timeout: 30000 }, async t => {
  const { base, root, primary } = await repository(t);
  const state = path.join(base, 'state');
  const skillRelative = path.join('.agents', 'skills', 'worktree-guide', 'SKILL.md');
  const skillHeader = '---\nname: worktree-guide\ndescription: Inspect the selected managed checkout.\n---\n';
  const skillBody = 'WORKTREE_SKILL_BODY_ONLY_FROM_ORDINARY_TOOL_READ';
  const changedSkillBody = 'WORKTREE_CHANGED_BODY_REMAINS_OUTSIDE_TRACKED_CONTEXT';
  const rootGuidance = 'Repository guidance stops at this checkout Git marker.';
  const overrideGuidance = 'Use the primary override from this managed checkout.';
  const nestedGuidance = 'Nested source guidance applies inside src.';
  const storageGuidance = 'PRIVATE_STORAGE_GUIDANCE_MUST_NOT_BECOME_A_WORKSPACE_ANCESTOR';
  await Promise.all([mkdir(path.join(root, path.dirname(skillRelative)), { recursive: true }),
    mkdir(path.join(primary, 'src')), mkdir(path.join(state, 'worktrees'), { recursive: true })]);
  await Promise.all([
    writeFile(path.join(root, 'AGENTS.md'), rootGuidance),
    writeFile(path.join(primary, 'AGENTS.override.md'), overrideGuidance),
    writeFile(path.join(primary, 'src', 'AGENTS.md'), nestedGuidance),
    writeFile(path.join(root, skillRelative), skillHeader + skillBody),
    writeFile(path.join(state, 'worktrees', 'AGENTS.md'), storageGuidance),
  ]);
  const contextFiles = ['AGENTS.md', 'packages/app/AGENTS.override.md', 'packages/app/src/AGENTS.md', skillRelative];
  await git(root, 'add', '--', ...contextFiles);
  await git(root, 'commit', '--only', '-m', 'Add hierarchical worktree context', '--', ...contextFiles);
  const contextChanges = messages => messages.filter(item => item.type === 'context_change').map(item => item.change);
  const childMessage = 'Write from the child in the shared worktree.';
  let childTurns = 0;
  let ownerPrimary;
  const model = await responsesServer(t, async (body, index) => {
    if (index === 0) {
      const rows = journalRows(state);
      const created = rows.find(row => row.input.kind === 'worktree_created' && row.input.ok);
      const requested = rows.find(row => row.decision.effects.some(effect => effect.kind === 'model'
        && effect.task_id === created?.input.task_id));
      assert.ok(created, 'Worktree context must be committed before its first model request');
      assert.ok(requested, 'The provider request must have its own committed model effect');
      assert.ok(requested.sequence >= created.sequence);
      const managedRoot = created.input.root;
      const managedPrimary = created.input.workspace.primary_root;
      assert.equal(created.input.guidance.path, path.join(managedPrimary, 'AGENTS.override.md'));
      assert.equal(created.input.guidance.instructions, overrideGuidance);
      assert.match(await readFile(path.join(managedRoot, '.git'), 'utf8'), /^gitdir: /);
      const observed = rows.filter(row => row.input.kind === 'context_observed'
        && row.input.task_id === created.input.task_id).at(-1);
      assert.ok(observed, 'Discovery observations must be durable before model execution');
      const snapshots = observed.input.observations.filter(item => item.type === 'present').map(item => item.snapshot);
      for (const relative of ['AGENTS.md', 'packages/app/AGENTS.override.md', 'packages/app/src/AGENTS.md', skillRelative]) {
        assert.ok(snapshots.some(snapshot => snapshot.value.fields.path === path.join(managedRoot, relative)), relative);
      }
      for (const snapshot of snapshots.filter(snapshot => ['project_guidance', 'directory_guidance', 'workspace_skill_information'].includes(snapshot.key.type))) {
        assert.equal(snapshot.key.identity.workspace, managedPrimary);
        assert.ok(snapshot.value.fields.path.startsWith(managedRoot + path.sep));
      }
      const skill = snapshots.find(snapshot => snapshot.key.type === 'workspace_skill_information');
      assert.ok(skill, 'Repository-level skills are discovered through the managed checkout ancestors');
      assert.equal(skill.value.fields.name, 'worktree-guide');
      assert.equal(skill.value.fields.description, 'Inspect the selected managed checkout.');
      assert.equal(skill.value.fields.applies_to, managedRoot);
      assert.equal(JSON.stringify(snapshots).includes(skillBody), false);
      const input = JSON.stringify(body.input);
      for (const text of [rootGuidance, overrideGuidance, nestedGuidance, 'worktree-guide']) assert.ok(input.includes(text));
      assert.equal(input.includes(storageGuidance), false, 'The worktree .git file stops discovery before private storage');
      assert.equal(input.includes(skillBody), false, 'Skill bodies are absent until an ordinary tool reads them');
    }
    if (!body.input.some(item => item.role === 'user' && item.content === childMessage)) return answer('Owner task is ready.');
    childTurns += 1;
    const output = body.input.find(item => item.type === 'function_call_output' && item.call_id === 'shared-worktree-write');
    if (!output) return [{ type: 'function_call', call_id: 'shared-worktree-write', name: 'bash',
      arguments: JSON.stringify({ command: `set -eu\nprintf child > child-write.txt\npwd\ncat ../../${skillRelative}` }) }];
    const result = JSON.parse(output.output);
    assert.equal(result.is_error, false, JSON.stringify(result));
    assert.ok(result.value.stdout.includes(ownerPrimary));
    assert.ok(result.value.stdout.includes(skillBody), 'A shared borrower reads the body as an ordinary tool result');
    return answer('The child wrote in the shared checkout.');
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    fixture: { provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: credentials(t) },
  } });
  const service = await Service.open({ home: state, cwd: root, config });
  t.after(() => service.close());
  const started = await service.command({ op: 'create_worktree_task', profile: 'fixture', message: 'Keep the shared checkout available.',
    settings: { workspace: { roots: [primary], primary_root: primary } } });
  assert.equal(started.reply.ok, true, JSON.stringify(started.reply));
  const ownerId = started.reply.result.task_id;
  const owner = await worktreeStatus(service, ownerId, 'ready');
  ownerPrimary = owner.target_primary;
  const initialOwner = await taskIdle(service, ownerId);
  const forked = await service.command({ op: 'fork', task_id: ownerId, child_count: 1, messages: [childMessage] });
  assert.equal(forked.reply.ok, true, JSON.stringify(forked.reply));
  const [childId] = forked.reply.result.children;
  const child = await taskIdle(service, childId).catch(error => {
    assert.deepEqual(model.failures, []);
    throw error;
  });
  await taskIdle(service, ownerId);
  assert.deepEqual(model.failures, []);
  assert.equal(childTurns, 2);
  assert.deepEqual(child.task.settings.workspace, { roots: [owner.target_primary], primary_root: owner.target_primary });
  assert.deepEqual(contextChanges(child.messages), contextChanges(initialOwner.messages), 'A shared fork keeps its inherited tracked baselines');
  assert.equal(JSON.stringify(contextChanges(child.messages)).includes(skillBody), false);
  const shared = await service.command({ op: 'read_worktree', task_id: childId });
  assert.equal(shared.reply.ok, true, JSON.stringify(shared.reply));
  assert.equal(shared.reply.result.root, owner.root);
  assert.equal(shared.reply.result.target_primary, owner.target_primary);
  assert.equal(shared.reply.result.status, 'ready');
  assert.equal(await readFile(path.join(owner.target_primary, 'child-write.txt'), 'utf8'), 'child');
  await assert.rejects(access(path.join(primary, 'child-write.txt')), { code: 'ENOENT' });
  const beforeBodyEdit = await taskIdle(service, ownerId);
  await writeFile(path.join(owner.root, skillRelative), skillHeader + changedSkillBody);
  const continued = await service.command({ op: 'send', task_id: ownerId, message: 'Continue after a skill body-only edit.' });
  assert.equal(continued.reply.ok, true, JSON.stringify(continued.reply));
  const afterBodyEdit = await taskIdle(service, ownerId);
  assert.deepEqual(contextChanges(afterBodyEdit.messages.slice(beforeBodyEdit.messages.length)), [],
    'Body-only changes do not amend tracked skill metadata');
  assert.equal(JSON.stringify(contextChanges(afterBodyEdit.messages)).includes(changedSkillBody), false);
  assert.equal(await readFile(path.join(root, skillRelative), 'utf8'), skillHeader + skillBody);
  const blocked = await service.command({ op: 'archive', task_id: ownerId });
  assert.equal(blocked.reply.ok, false, JSON.stringify(blocked.reply));
  assert.equal(blocked.reply.error.code, 'worktree_in_use');
  assert.deepEqual(blocked.effects, []);
  assert.equal((await service.command({ op: 'read', task_id: ownerId })).reply.result.task.status, 'active');
  assert.equal((await worktreeStatus(service, ownerId, 'ready')).root, owner.root);
  await access(owner.root);
  const archivedRoot = path.join(state, 'worktrees', 'archived', `task-${ownerId}`);
  await assert.rejects(access(archivedRoot), { code: 'ENOENT' });
  const childArchive = await service.command({ op: 'archive', task_id: childId });
  assert.equal(childArchive.reply.ok, true, JSON.stringify(childArchive.reply));
  assert.ok(!childArchive.effects.some(effect => effect.kind === 'worktree_archive'));
  assert.equal((await service.command({ op: 'read', task_id: childId })).reply.result.task.status, 'archived');
  assert.equal(await readFile(path.join(owner.target_primary, 'child-write.txt'), 'utf8'), 'child');
  await assert.rejects(access(archivedRoot), { code: 'ENOENT' });
  const ownerArchive = await service.command({ op: 'archive', task_id: ownerId });
  assert.equal(ownerArchive.reply.ok, true, JSON.stringify(ownerArchive.reply));
  const archived = await worktreeStatus(service, ownerId, 'archived');
  assert.equal(archived.root, archivedRoot);
  await assert.rejects(access(owner.root), { code: 'ENOENT' });
  assert.equal(await readFile(path.join(archivedRoot, 'packages', 'app', 'child-write.txt'), 'utf8'), 'child');
  assert.equal(await readFile(path.join(archivedRoot, skillRelative), 'utf8'), skillHeader + changedSkillBody);
  assert.equal(journalRows(state).flatMap(row => row.decision.effects).filter(effect => effect.kind === 'worktree_archive').length, 1);
});

test('non-Git, empty and unborn primary workspaces reject worktree creation without a journal commit', async t => {
  const base = await realpath(await home(t));
  const plain = path.join(base, 'plain');
  const unborn = path.join(base, 'unborn');
  await Promise.all([plain, unborn].map(directory => mkdir(directory)));
  await git(unborn, 'init', '--initial-branch=main');
  const state = path.join(base, 'state');
  const service = await Service.open({ home: state, cwd: plain, config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  for (const settings of [undefined, { workspace: { roots: [] } }, { workspace: { roots: [unborn] } }]) {
    const sequence = service.journal.sequence;
    await assert.rejects(service.command({ op: 'create_worktree_task', profile: 'demo', message: 'No Git checkout.', ...(settings ? { settings } : {}) }), error => {
      assert.ok(error instanceof CommandNotSubmitted);
      assert.match(error.message, /Git repository.*initial commit/);
      return true;
    });
    assert.equal(service.journal.sequence, sequence);
  }
  assert.deepEqual((await service.command({ op: 'list_worktrees' })).reply.result.worktrees, []);
  await assert.rejects(access(path.join(state, 'worktrees')), { code: 'ENOENT' });
});

test('a committed checkout failure blocks send and fork instead of running in the source workspace', { timeout: 20000 }, async t => {
  const { base, root, primary } = await repository(t);
  const state = path.join(base, 'state');
  const movedPrimary = primary + '-temporarily-moved';
  const model = await responsesServer(t, () => answer('A failed checkout must never reach this provider.'));
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    fixture: { provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: credentials(t) },
  } });
  let service = await Service.open({ home: state, cwd: root, config });
  t.after(() => service.close());
  let committedCreation;
  service.journal.on('commit', decision => {
    const effect = decision.effects.find(value => value.kind === 'worktree_create');
    if (!effect) return;
    committedCreation = journalRows(state).find(row => row.sequence === decision.sequence);
    // The host has yielded while locating its storage, after SQLite committed
    // the accepted creation. Moving the source now forces a real filesystem fault.
    renameSync(primary, movedPrimary);
  });
  const started = await service.command({ op: 'create_worktree_task', profile: 'fixture',
    message: 'Create an isolated checkout.', settings: { workspace: { roots: [primary], primary_root: primary } } });
  assert.equal(started.reply.ok, true, JSON.stringify(started.reply));
  const taskId = started.reply.result.task_id;
  const failed = await worktreeStatus(service, taskId, 'create_failed');
  assert.ok(committedCreation.decision.effects.some(effect => effect.kind === 'worktree_create' && effect.task_id === taskId));
  assert.equal(failed.root, null);
  assert.match(failed.message, /creation failed/);
  const stopped = (await service.command({ op: 'read', task_id: taskId })).reply.result;
  assert.equal(stopped.task.status, 'stopped');
  assert.equal(stopped.task.phase, 'idle');
  assert.deepEqual(stopped.task.operations, []);
  assert.equal(model.requests.length, 0);

  await rename(movedPrimary, primary);
  assert.equal(await readFile(path.join(primary, 'tracked.txt'), 'utf8'), 'uncommitted tracked contents 世界');
  const sourceStatus = await git(root, 'status', '--porcelain');
  for (const command of [
    { op: 'send', task_id: taskId, message: 'Continue after the source returns.' },
    { op: 'fork', task_id: taskId, child_count: 1, messages: ['Do not inherit the source workspace.'] },
  ]) {
    const rejected = await service.command(command);
    assert.equal(rejected.reply.ok, false, JSON.stringify(rejected.reply));
    assert.equal(rejected.reply.error.code, 'worktree_creation_failed');
    assert.deepEqual(rejected.effects, []);
  }
  assert.deepEqual((await service.command({ op: 'read', task_id: taskId })).reply.result, stopped);
  assert.equal(await git(root, 'status', '--porcelain'), sourceStatus);
  assert.equal(journalRows(state).flatMap(row => row.decision.effects).some(effect => effect.kind === 'model'), false);
  assert.equal(model.requests.length, 0);
  const archived = await service.command({ op: 'archive', task_id: taskId });
  assert.equal(archived.reply.ok, true, JSON.stringify(archived.reply));
  assert.equal((await service.command({ op: 'read', task_id: taskId })).reply.result.task.status, 'archived');
  await service.close();
  service = await Service.open({ home: state, cwd: root, config });
  assert.equal((await worktreeStatus(service, taskId, 'create_failed')).root, null);
  assert.equal(model.requests.length, 0, 'Reopening a failed checkout must not retry creation or start execution');
  await assert.rejects(access(path.join(state, 'worktrees', `task-${taskId}`)), { code: 'ENOENT' });
});

test('managed worktrees preserve raw edits without executing repository filters or checkout hooks', async t => {
  const { base, root } = await repository(t);
  const state = path.join(base, 'state');
  const marker = path.join(base, 'project-program-ran');
  await mkdir(state);
  await writeFile(path.join(root, '.gitattributes'), 'filtered.txt filter=fixture\n');
  await writeFile(path.join(root, 'filtered.txt'), 'committed raw text\n');
  await git(root, 'add', '.gitattributes', 'filtered.txt');
  await git(root, 'commit', '-m', 'Declare an external content filter');
  const filter = `printf filter >> ${shellQuote(marker)}; cat`;
  await git(root, 'config', 'filter.fixture.clean', filter);
  await git(root, 'config', 'filter.fixture.smudge', filter);
  await git(root, 'config', 'filter.fixture.required', 'true');
  const hook = path.join(root, '.git', 'hooks', 'post-checkout');
  await writeFile(hook, `#!/bin/sh\nprintf hook >> ${shellQuote(marker)}\n`);
  await chmod(hook, 0o700);
  const edited = 'working raw text 世界\n';
  await writeFile(path.join(root, 'filtered.txt'), edited);
  const created = await createManagedWorktree({ task_id: 45, source_root: root,
    workspace: { roots: [root], primary_root: root } }, { home: state, limits: contextLimits });
  assert.equal(created.ok, true, JSON.stringify(created));
  assert.equal(await readFile(path.join(created.root, 'filtered.txt'), 'utf8'), edited);
  await assert.rejects(access(marker), { code: 'ENOENT' });
  const archived = await archiveManagedWorktree({ task_id: 45, source_root: root, root: created.root }, { home: state });
  assert.equal(archived.ok, true, JSON.stringify(archived));
  assert.equal(await readFile(path.join(archived.root, 'filtered.txt'), 'utf8'), edited);
  assert.equal(await readFile(path.join(root, 'filtered.txt'), 'utf8'), edited);
  await assert.rejects(access(marker), { code: 'ENOENT' });
});

test('a service home within the source repository is rejected before checkout or private-file copying', async t => {
  for (const nested of [false, true]) {
    const { root, primary } = await repository(t);
    const state = nested ? path.join(root, '.selvedge') : root;
    await mkdir(state, { recursive: true });
    const privateFile = path.join(state, 'private-service-state');
    await writeFile(privateFile, 'private service sentinel');
    const sourceStatus = await git(root, 'status', '--porcelain');
    const created = await createManagedWorktree({ task_id: 46, source_root: primary,
      workspace: { roots: [primary], primary_root: primary } }, { home: state, limits: contextLimits });
    assert.equal(created.ok, false, JSON.stringify(created));
    assert.equal(created.root, null);
    assert.match(created.message, /service home outside the source Git repository/);
    assert.equal(await readFile(privateFile, 'utf8'), 'private service sentinel');
    assert.equal(await readFile(path.join(primary, 'tracked.txt'), 'utf8'), 'uncommitted tracked contents 世界');
    assert.equal(await git(root, 'status', '--porcelain'), sourceStatus);
    await assert.rejects(access(path.join(state, 'worktrees', 'task-46')), { code: 'ENOENT' });
    assert.equal((await git(root, 'worktree', 'list', '--porcelain')).split('\n').filter(line => line.startsWith('worktree ')).length, 1);
  }
});

test('workspace receipts larger than 64 KiB survive worktree creation, archive and recovery', async t => {
  const { base, root } = await repository(t);
  const state = path.join(base, 'state');
  const prefix = path.join(base, 'long-workspace-roots', ...Array.from({ length: 12 }, (_, index) => `${index}-${'x'.repeat(182)}`));
  try { await mkdir(prefix, { recursive: true }); }
  catch (error) {
    if (error.code !== 'ENAMETOOLONG') throw error;
    t.skip('The filesystem cannot represent workspace roots longer than 2 KiB.');
    return;
  }
  const additionalRoots = Array.from({ length: 31 }, (_, index) => path.join(prefix, `root-${index}`));
  await Promise.all([mkdir(state), ...additionalRoots.map(directory => mkdir(directory))]);
  const created = await createManagedWorktree({ task_id: 47, source_root: root,
    workspace: { roots: [root, ...additionalRoots], primary_root: root } }, { home: state, limits: contextLimits });
  assert.equal(created.ok, true, JSON.stringify(created));
  const receipt = path.join(state, 'worktrees', 'receipts', 'task-47.json');
  assert.ok((await readFile(receipt)).byteLength > 65536, 'The fixture must exercise a receipt beyond the old 64 KiB limit');
  assert.deepEqual(created.workspace, { roots: [created.root, ...additionalRoots], primary_root: created.root });
  const recovered = await reconcileManagedWorktree({ task_id: 47, source_root: root, root: null, status: 'creating' },
    { home: state, limits: contextLimits });
  assert.equal(recovered.ok, true, JSON.stringify(recovered));
  assert.deepEqual(recovered.workspace, created.workspace);
  await writeFile(path.join(created.root, 'retained.txt'), 'retain the large workspace contract');
  const archived = await archiveManagedWorktree({ task_id: 47, source_root: root, root: created.root }, { home: state });
  assert.equal(archived.ok, true, JSON.stringify(archived));
  const stored = await readFile(receipt);
  assert.ok(stored.byteLength > 65536);
  assert.deepEqual(JSON.parse(stored).workspace, { roots: [archived.root, ...additionalRoots], primary_root: archived.root });
  const restored = await reconcileManagedWorktree({ task_id: 47, source_root: root, root: created.root, status: 'archiving' },
    { home: state, limits: contextLimits });
  assert.equal(restored.ok, true, JSON.stringify(restored));
  assert.equal(restored.root, archived.root);
  assert.equal(await readFile(path.join(archived.root, 'retained.txt'), 'utf8'), 'retain the large workspace contract');
});

test('worktree recovery observes completed Git effects and refuses forged or symlinked storage', async t => {
  const { base, root, primary } = await repository(t);
  const state = path.join(base, 'state');
  await mkdir(state);
  const effect = { kind: 'worktree_create', task_id: 42, source_root: primary,
    workspace: { roots: [primary], primary_root: primary } };
  assert.equal(await observeWorkspaceGit(primary), true);
  const created = await createManagedWorktree(effect, { home: state, limits: contextLimits });
  assert.equal(created.ok, true, JSON.stringify(created));
  const marker = path.join(created.workspace.primary_root, 'recover.txt');
  await writeFile(marker, 'preserve this existing checkout');
  const recovered = await reconcileManagedWorktree({ task_id: 42, source_root: primary, root: null, status: 'creating' },
    { home: state, limits: contextLimits });
  assert.equal(recovered.ok, true, JSON.stringify(recovered));
  assert.equal(recovered.root, created.root);
  assert.equal(await readFile(marker, 'utf8'), 'preserve this existing checkout');
  const forged = await archiveManagedWorktree({ task_id: 42, source_root: primary, root }, { home: state });
  assert.equal(forged.ok, false);
  assert.match(forged.message, /unmanaged worktree path/);
  assert.equal(await git(root, 'rev-parse', '--show-toplevel'), root);

  const archivedRoot = path.join(state, 'worktrees', 'archived', 'task-42');
  await git(root, 'worktree', 'move', created.root, archivedRoot);
  const moved = await reconcileManagedWorktree({ task_id: 42, source_root: primary, root: created.root, status: 'archiving' },
    { home: state, limits: contextLimits });
  assert.equal(moved.ok, true, JSON.stringify(moved));
  assert.equal(moved.root, archivedRoot);
  assert.equal(await readFile(path.join(archivedRoot, 'packages', 'app', 'recover.txt'), 'utf8'), 'preserve this existing checkout');
  const absent = await reconcileManagedWorktree({ task_id: 43, source_root: primary, root: null, status: 'creating' },
    { home: state, limits: contextLimits });
  assert.equal(absent.ok, false);
  assert.equal(absent.root, null);
  await assert.rejects(access(path.join(state, 'worktrees', 'task-43')), { code: 'ENOENT' });

  const receipt = path.join(state, 'worktrees', 'receipts', 'task-42.json');
  await rename(receipt, receipt + '.saved');
  await symlink(receipt + '.saved', receipt);
  const linkedReceipt = await reconcileManagedWorktree({ task_id: 42, source_root: primary, root: archivedRoot, status: 'archiving' },
    { home: state, limits: contextLimits });
  assert.equal(linkedReceipt.ok, false);
  const otherState = path.join(base, 'other-state');
  const outside = path.join(base, 'outside-storage');
  await Promise.all([otherState, outside].map(directory => mkdir(directory)));
  await symlink(outside, path.join(otherState, 'worktrees'));
  const linkedStorage = await createManagedWorktree({ ...effect, task_id: 44 }, { home: otherState, limits: contextLimits });
  assert.equal(linkedStorage.ok, false);
  assert.match(linkedStorage.message, /symbolic links/);
  await assert.rejects(access(path.join(outside, 'task-44')), { code: 'ENOENT' });
});

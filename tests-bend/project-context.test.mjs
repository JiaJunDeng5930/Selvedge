import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile, symlink, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { snapshotProject } from '../host/file-tools.mjs';
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
  }
  const linked = path.join(directory, 'linked');
  await mkdir(linked);
  await symlink(path.join(directory, 'AGENTS.md'), path.join(linked, 'AGENTS.md'));
  await assert.rejects(snapshotProject(linked, limits), error => ['ELOOP', 'EMLINK'].includes(error.code));
  const nonfile = path.join(directory, 'nonfile');
  await mkdir(path.join(nonfile, 'AGENTS.md'), { recursive: true });
  await assert.rejects(snapshotProject(nonfile, limits), /regular file/);
});

test('the actual native contract freezes project context across configure, checkpoint and branch', async t => {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = value => input({ kind: 'command', command: value });
  const configure = project => input({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture' }],
    tools: [], max_fork: 4, max_descendants: 8, project });
  const first = { workspace: '/project', instructions: 'Original project instructions', revision: 'a'.repeat(64) };
  const second = { ...first, instructions: 'New instructions apply to new tasks', revision: 'b'.repeat(64) };
  assert.equal((await configure(first)).reply.ok, true);
  const original = await command({ op: 'create', profile: 'fixture', message: 'work' });
  assert.deepEqual(original.effects[0].model.project, { ...first, source: 'AGENTS.md' });
  await input({ kind: 'model', task_id: 0, ticket: original.effects[0].ticket, ok: true, items: [{ type: 'text', text: 'done' }] });
  await command({ op: 'compact', task_id: 0, summary: 'The task completed its first objective.' });
  await configure(second);
  const branch = await command({ op: 'fork', task_id: 0, child_count: 1 });
  assert.equal(branch.effects.filter(x => x.kind === 'model').length, 2);
  for (const effect of branch.effects) assert.deepEqual(effect.model.project, { ...first, source: 'AGENTS.md' });
  const newer = await command({ op: 'create', profile: 'fixture', message: 'new task' });
  assert.deepEqual(newer.effects[0].model.project, { ...second, source: 'AGENTS.md' });
  const rejected = await configure({ ...second, revision: 'absent' });
  assert.equal(rejected.reply.ok, false, 'An absent source cannot carry invented guidance');
});

test('project guidance is committed before dispatch and survives restart without a hidden fresh prompt read', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const credential = 'SELVEDGE_CONTEXT_FIXTURE_KEY';
  const previous = process.env[credential];
  process.env[credential] = 'fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[credential]; else process.env[credential] = previous; });
  const first = 'Run node check.mjs before claiming success. Preserve the original interface.';
  const second = 'A later project revision, visible to newly created tasks.';
  await writeFile(path.join(directory, 'AGENTS.md'), first);
  const seen = [];
  const model = await responsesServer(t, async (body, index) => {
    const snapshot = JSON.parse(body.input[0].content.split('\n').slice(1).join('\n'));
    seen.push(snapshot);
    assert.equal(snapshot.instructions, index < 2 ? first : second);
    assert.equal(snapshot.workspace, await realpath(directory));
    assert.equal(body.instructions.includes(first), false, 'Repository content cannot become a runtime system instruction');
    const db = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
    try {
      const rows = db.prepare('SELECT input FROM journal ORDER BY seq').all();
      assert.ok(rows.some(row => JSON.parse(row.input).project?.instructions === snapshot.instructions));
    } finally { db.close(); }
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'fixture answer' }] }];
  });
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: { provider: 'responses', model: 'fixture',
    endpoint: model.endpoint, api_key_env: credential, timeout_ms: 5000 } } });
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'fixture', message: 'first objective' });
  await taskIdle(service);
  await service.command({ op: 'compact', task_id: 0, summary: 'The original objective completed.' });
  await service.close();
  await writeFile(path.join(directory, 'AGENTS.md'), second);
  service = await Service.open({ home: directory, cwd: directory, config });
  await service.command({ op: 'send', task_id: 0, message: 'continue the same task' });
  await taskIdle(service);
  await service.command({ op: 'create', profile: 'fixture', message: 'new objective' });
  await taskIdle(service, 1);
  assert.deepEqual(model.failures, []);
  assert.deepEqual(seen.map(x => x.instructions), [first, first, second]);
  assert.equal(await readFile(path.join(directory, 'AGENTS.md'), 'utf8'), second);
});

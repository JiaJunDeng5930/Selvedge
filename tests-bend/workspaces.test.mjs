import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, realpath, symlink, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { CommandNotSubmitted, Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, shellQuote, taskIdle } from './support.mjs';

function credentials(t) {
  const key = 'SELVEDGE_WORKSPACE_FIXTURE';
  const previous = process.env[key];
  process.env[key] = 'local-test-only';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  return key;
}

const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

test('project selection reaches a real multi-root Bash sandbox only after its plan is committed', { timeout: 20_000 }, async t => {
  const base = await realpath(await home(t));
  const state = path.join(base, 'state');
  const roots = [path.join(base, 'first root'), path.join(base, 'second')];
  await Promise.all(roots.map(root => mkdir(root)));
  await writeFile(path.join(roots[1], 'AGENTS.md'), 'Preserve this task-local guidance.');
  const alias = path.join(base, 'second-alias');
  await symlink(roots[1], alias);
  const api_key_env = credentials(t);
  const model = await responsesServer(t, async (body, index) => {
    assert.ok(body.instructions.includes('Committed task settings'));
    if (index === 0) {
      assert.ok(body.instructions.includes(roots[0]));
      assert.ok(body.instructions.includes(roots[1]));
      const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
      const recorded = JSON.parse(db.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 1').get().decision);
      db.close();
      assert.equal(recorded.effects.find(effect => effect.kind === 'model').settings.workspace.primary_root, roots[1]);
      return [{ type: 'function_call', call_id: 'workspace-io', name: 'bash', arguments: JSON.stringify({
        command: `pwd; printf first > ${shellQuote(path.join(roots[0], 'written'))}; printf second > written; ` +
          `cat AGENTS.md; ! (printf denied > ${shellQuote(path.join(base, 'outside'))})`,
      }) }];
    }
    assert.equal(index, 1);
    const result = JSON.parse(body.input.find(item => item.type === 'function_call_output' && item.call_id === 'workspace-io').output);
    assert.equal(result.is_error, false, JSON.stringify(result));
    assert.ok(result.value.stdout.includes(roots[1]));
    assert.ok(result.value.stdout.includes('Preserve this task-local guidance.'));
    return answer('Both workspace roots were used.');
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    fixture: { provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env },
  } });
  let service = await Service.open({ home: state, cwd: roots[0], config });
  t.after(() => service.close());
  const project = await service.command({ op: 'create_project', name: 'Multiple roots',
    workspace: { roots: [roots[0], alias], primary_root: alias } });
  assert.equal(project.reply.ok, true, JSON.stringify(project.reply));
  const started = await service.command({ op: 'create', profile: 'fixture', message: 'Use both project roots.',
    settings: { project_id: project.reply.result.project_id } });
  assert.equal(started.reply.ok, true, JSON.stringify(started.reply));
  const page = await taskIdle(service);
  assert.deepEqual(page.task.settings.workspace, { roots, primary_root: roots[1] });
  assert.equal(await readFile(path.join(roots[0], 'written'), 'utf8'), 'first');
  assert.equal(await readFile(path.join(roots[1], 'written'), 'utf8'), 'second');
  assert.deepEqual(model.failures, []);
  await service.close();
  // A new service launch directory does not reinterpret the task's stored plan.
  service = await Service.open({ home: state, cwd: base, config });
  assert.deepEqual((await taskIdle(service)).task.settings, page.task.settings);
  assert.equal(model.requests.length, 2, 'Replay must not repeat physical effects or model calls');
  const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
  const rows = db.prepare('SELECT input, decision FROM journal ORDER BY seq').all().map(row => ({
    input: JSON.parse(row.input), decision: JSON.parse(row.decision),
  }));
  db.close();
  const observation = rows.find(row => row.input.command?.op === 'create_project').input.command;
  assert.deepEqual(observation.workspace, { roots, primary_root: roots[1] });
  assert.equal(observation.guidance.instructions, 'Preserve this task-local guidance.');
  const execution = rows.flatMap(row => row.decision.effects).find(effect => effect.kind === 'tool');
  assert.deepEqual(execution.execution.workspace, { roots, primary_root: roots[1] });
  assert.equal(execution.execution.access, 'sandboxed');
});

test('workspace observations reject nonexistent roots and forged guidance without committing input', async t => {
  const base = await realpath(await home(t));
  const service = await Service.open({ home: path.join(base, 'state'), cwd: base,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) });
  t.after(() => service.close());
  const before = service.journal.sequence;
  await assert.rejects(service.command({ op: 'create_project', name: 'missing', workspace: { roots: [path.join(base, 'missing')] } }), error => {
    assert.ok(error instanceof CommandNotSubmitted);
    assert.equal(error.cause.code, 'ENOENT');
    return true;
  });
  await assert.rejects(service.command({ op: 'create', profile: 'demo', message: 'forged', settings: {
    guidance: { workspace: base, revision: 'absent', instructions: '' },
  } }), error => {
    assert.ok(error instanceof CommandNotSubmitted);
    assert.ok(error.cause instanceof TypeError);
    assert.match(error.cause.message, /observed by the service/);
    return true;
  });
  assert.equal(service.journal.sequence, before);
  const empty = await service.command({ op: 'create_project', name: 'No roots', workspace: { roots: [] } });
  assert.equal(empty.reply.ok, true);
  const details = await service.command({ op: 'read_project', project_id: empty.reply.result.project_id });
  assert.deepEqual(details.reply.result.workspace, { roots: [], primary_root: null });
});

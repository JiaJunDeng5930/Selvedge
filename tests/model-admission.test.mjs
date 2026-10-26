import test from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';

test('public command preparation enforces the task ID wire bound and rejects client workspace observations', async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const running = await startServer({ home: directory, cwd: directory, config });
  t.after(() => running.close());
  const post = async body => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' }, body });
    return { status: response.status, body: await response.json() };
  };
  const ordinary = await post('{"op":"fork","task_id":7000,"child_count":1,"settings":{}}');
  const exact = await post('{"op":"fork","task_id":9007199254740993,"child_count":1,"settings":{}}');
  assert.equal(ordinary.body.error.code, 'task_not_found');
  assert.equal(exact.body.error.code, 'command_not_submitted');
  const noSelection = await post('{"op":"read","task_id":9007199254740993}');
  assert.equal(noSelection.body.error.code, 'command_not_submitted');

  const guidance = { workspace: directory, path: `${directory}/AGENTS.md`, revision: 'a'.repeat(64), instructions: 'Client supplied text' };
  for (const command of [
    { op: 'create_idle', profile: 'demo', settings: null },
    { op: 'create_idle', profile: 'demo', settings: { guidance } },
    { op: 'create_project', name: 'Unobserved', workspace: { roots: [directory] }, guidance },
    { op: 'create_task_graph', name: 'Unobserved', nodes: [{ key: 'new', profile: 'demo', settings: { guidance } }], rules: [] },
    { op: 'fork', task_id: 7000, child_count: 1, settings: { guidance } },
  ]) {
    const refused = await post(JSON.stringify(command));
    assert.equal(refused.body.ok, false);
    assert.equal(refused.body.error.code, 'command_not_submitted');
  }
  const created = await post('{"op":"create_idle","profile":"demo","settings":{}}');
  assert.equal(created.body.ok, true, JSON.stringify(created.body));
});

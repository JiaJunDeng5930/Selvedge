import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home } from './support.mjs';

const entry = fileURLToPath(new URL('../host/cli.mjs', import.meta.url));

test('terminal users observe and assess a card move, then receive the shared command feedback', async t => {
  const directory = await home(t);
  const state = path.join(directory, 'state');
  const running = await startServer({ home: state, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0 }) });
  t.after(() => running.close());

  async function terminal(...args) {
    const child = Bun.spawn([process.execPath, entry, '--home', state, ...args], { stdout: 'pipe', stderr: 'pipe' });
    const [status, output, diagnostic] = await Promise.all([
      child.exited, new Response(child.stdout).text(), new Response(child.stderr).text(),
    ]);
    assert.ok(output, diagnostic);
    return { status, value: JSON.parse(output) };
  }

  async function successful(...args) {
    const { status, value } = await terminal(...args);
    assert.equal(status, 0, JSON.stringify(value));
    assert.equal(value.ok, true, JSON.stringify(value));
    return value.result;
  }

  const created = await successful('create_card', '--title', '共同观察', '--status', 'backlog');
  const id = String(created.card_id);
  const card = await successful('observe', 'card', id);
  assert.equal(card.title, '共同观察');
  assert.equal(card.stage, 'backlog');
  const decisions = await successful('observe', 'card-decisions', id);
  const endOfTodo = decisions.move_card.find(choice => choice.status === 'todo' && choice.before_card === '');
  assert.ok(endOfTodo);

  const fields = ['--card-id', id, '--revision', String(decisions.revision), '--status', endOfTodo.status, '--before-card', endOfTodo.before_card];
  const assessment = await terminal('assess', 'move_card', ...fields);
  assert.equal(assessment.status, 0, JSON.stringify(assessment.value));
  assert.equal(assessment.value.admitted, true);
  assert.equal((await successful('observe', 'card', id)).stage, 'backlog');
  await successful('move_card', ...fields);
  assert.equal((await successful('observe', 'card', id)).stage, 'todo');

  const stale = await terminal('assess', 'move_card', ...fields);
  assert.equal(stale.status, 1);
  assert.equal(stale.value.admitted, false);
  const rejected = await terminal('move_card', ...fields);
  assert.equal(rejected.status, 1);
  assert.equal(rejected.value.ok, false);
  assert.deepEqual(rejected.value.error, stale.value.refusal);

  const browser = await fetch(`${running.address}/api/browser/command`, {
    method: 'POST',
    headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ command: { op: 'move_card', card_id: created.card_id,
      revision: decisions.revision, status: endOfTodo.status, before_card: endOfTodo.before_card } }),
  });
  assert.equal(browser.status, 400);
  assert.deepEqual((await browser.json()).reply.error, stale.value.refusal);

  const actions = await successful('observe', 'card-actions', id);
  const pin = actions.find(action => action.key === 'pin').command;
  assert.equal(pin.op, 'pin_card');
  assert.equal(pin.card_id, created.card_id);
  await successful(pin.op, '--card-id', id, '--revision', String(pin.revision), '--pinned', String(pin.pinned));
  assert.equal((await successful('observe', 'card', id)).pinned, true);

  const work = await successful('create_work', '--name', 'Shared Work');
  const observed = await successful('observe', 'work', String(work.work_id));
  assert.equal(observed.name, 'Shared Work');
  assert.ok((await successful('observe', 'works')).some(value => value.id === observed.id));
});

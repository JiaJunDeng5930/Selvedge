import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { journalFixture, model, modelEffect, say } from './fixtures/task-graph.mjs';

const result = decision => {
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
};

test('Work commands round-trip through the generated kernel and journal without changing ordinary Task creation', async t => {
  const fixture = await journalFixture(t);
  const work_id = result(await fixture.command({ op: 'create_work', name: '登录功能\n"世界" 😀' })).work_id;
  assert.deepEqual(result(await fixture.command({ op: 'read_work', work_id })), {
    work_id, name: '登录功能\n"世界" 😀', task_ids: [], graph_ids: [],
  });
  assert.deepEqual(result(await fixture.command({ op: 'list' })).tasks, [],
    'Creating a Work must not start an implicit Task');
  const second = result(await fixture.command({ op: 'create_work' })).work_id;
  assert.equal(result(await fixture.command({ op: 'read_work', work_id: second })).name, `Work #${second}`);
  result(await fixture.command({ op: 'rename_work', work_id, name: '登录功能 / revised' }));

  const independent = result(await fixture.command({ op: 'create', profile: 'fixture', message: 'Independent Task' })).task_id;
  const started = await fixture.command({ op: 'create_work_task', work_id, profile: 'fixture', message: 'Discuss and arrange the work' });
  const parent = result(started).task_id;
  await fixture.send(model(modelEffect(started, parent), [say('Ready to branch.')]));
  const fork = result(await fixture.command({ op: 'fork', task_id: parent, child_count: 2,
    messages: ['Implementation', 'Review'] }));
  assert.equal(fork.children.length, 2);
  const expected = [parent, ...fork.children];
  for (const task_id of expected) {
    assert.equal(result(await fixture.command({ op: 'read', task_id })).task.work_id, work_id);
  }
  assert.equal(result(await fixture.command({ op: 'read', task_id: independent })).task.work_id, null);
  assert.deepEqual(result(await fixture.command({ op: 'read_work', work_id })), {
    work_id, name: '登录功能 / revised', task_ids: expected, graph_ids: [],
  });
  assert.deepEqual(result(await fixture.command({ op: 'list_works' })).works.map(work => work.work_id), [work_id, second]);
  assert.deepEqual(result(await fixture.command({ op: 'list' })).tasks.map(task => task.id),
    [independent, ...expected]);

  const beforeTasks = result(await fixture.command({ op: 'list' })).tasks;
  const beforeWorks = result(await fixture.command({ op: 'list_works' })).works;
  for (const command of [
    { op: 'create_work_task', work_id: 999, profile: 'fixture', message: 'Must not allocate a Task' },
    { op: 'create_work_task', work_id, profile: 'missing', message: 'Invalid profile' },
    { op: 'rename_work', work_id: 999, name: 'Missing Work' },
    { op: 'create_work', name: 'Unknown field', project_id: 0 },
  ]) {
    assert.equal((await fixture.command(command)).reply.ok, false, JSON.stringify(command));
  }
  assert.deepEqual(result(await fixture.command({ op: 'list' })).tasks, beforeTasks);
  assert.deepEqual(result(await fixture.command({ op: 'list_works' })).works, beforeWorks);
});

test('a failed Work Task journal commit leaves neither a Task nor a Work membership after reopen', async t => {
  const fixture = await journalFixture(t);
  const work_id = result(await fixture.command({ op: 'create_work', name: 'Commit boundary' })).work_id;
  const before = fixture.journal.sequence;
  const database = new DatabaseSync(fixture.filename);
  database.exec("CREATE TRIGGER reject_work_write BEFORE INSERT ON journal BEGIN SELECT RAISE(ABORT, 'Work commit failure'); END");
  let publications = 0;
  fixture.journal.on('commit', () => publications++);
  try {
    await assert.rejects(fixture.command({ op: 'create_work_task', work_id,
      profile: 'fixture', message: 'Must not escape a failed commit' }), /Work commit failure/);
    assert.equal(publications, 0);
    assert.equal(database.prepare('SELECT count(*) AS n FROM journal WHERE seq > ?').get(before).n, 0);
  } finally {
    database.exec('DROP TRIGGER reject_work_write');
    database.close();
  }
  await fixture.reopen();
  assert.deepEqual(result(await fixture.command({ op: 'list' })).tasks, []);
  assert.deepEqual(result(await fixture.command({ op: 'read_work', work_id })).task_ids, []);
  const created = result(await fixture.command({ op: 'create_work_task', work_id,
    profile: 'fixture', message: 'Retry after rollback' }));
  assert.deepEqual(result(await fixture.command({ op: 'read_work', work_id })).task_ids, [created.task_id]);
});

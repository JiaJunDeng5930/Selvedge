import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import {
  journalFixture, install, node, rule, action, concat,
  model, say, modelEffect, taskId, page, readGraph,
} from './fixtures/task-graph.mjs';

test('one SQLite commit preserves the accepted reply and graph handoff across reopen', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture,
    [node('tests'), node('implementation')], [rule('handoff', 'tests', action('implementation'))]);
  const source = taskId(graph, 'tests');
  const target = taskId(graph, 'implementation');
  const completion = model(modelEffect(decision, source), [say('adversarial test\n"世界" 😀')]);
  const before = fixture.journal.sequence;
  const accepted = await fixture.send(completion);
  assert.equal(accepted.reply.result.accepted, true);
  assert.equal(accepted.sequence, before + 1);
  assert.equal((await page(fixture, source)).messages.at(-1).content, completion.items[0].text);
  assert.equal((await page(fixture, target)).task.queued, 1);
  const observed = await readGraph(fixture, graph.graph_id);
  assert.equal(observed.receipts.length, 1);
  assert.deepEqual(observed.receipts[0], {
    source_task_id: source, rule: 'handoff', target_task_id: target,
    reply: observed.receipts[0].reply,
  });
  assert.equal(observed.receipts[0].reply.ok, true);
  const db = new DatabaseSync(fixture.filename, { readOnly: true });
  try {
    assert.equal(db.prepare('SELECT count(*) AS n FROM journal WHERE seq > ?').get(before).n, 1);
    assert.equal(JSON.parse(db.prepare('SELECT input FROM journal WHERE seq = ?').get(accepted.sequence).input).kind, 'model');
  } finally { db.close(); }
  const savedSource = await page(fixture, source);
  const savedTarget = await page(fixture, target);
  await fixture.reopen();
  assert.deepEqual(await readGraph(fixture, graph.graph_id), observed);
  assert.deepEqual(await page(fixture, source), savedSource);
  assert.deepEqual(await page(fixture, target), savedTarget);
  const duplicate = await fixture.send(completion);
  assert.equal(duplicate.reply.result.accepted, false);
  assert.equal((await page(fixture, target)).task.queued, 1);
});

test('a failed SQLite commit rolls back both source acceptance and graph delivery before retry', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture,
    [node('tests'), node('implementation')], [rule('handoff', 'tests', action('implementation'))]);
  const source = taskId(graph, 'tests');
  const target = taskId(graph, 'implementation');
  const completion = model(modelEffect(decision, source), [say('must be committed together')]);
  const db = new DatabaseSync(fixture.filename);
  db.exec("CREATE TRIGGER reject_write BEFORE INSERT ON journal BEGIN SELECT RAISE(ABORT, 'graph commit failure'); END");
  let publications = 0;
  fixture.journal.on('commit', () => publications++);
  await assert.rejects(fixture.send(completion), /graph commit failure/);
  assert.equal(publications, 0);
  db.exec('DROP TRIGGER reject_write');
  db.close();
  await fixture.reopen();
  assert.equal((await page(fixture, source)).messages.some(message => message.content === completion.items[0].text), false);
  assert.equal((await page(fixture, target)).task.queued, 0);
  assert.deepEqual((await readGraph(fixture, graph.graph_id)).receipts, []);
  assert.equal((await fixture.send(completion)).reply.result.accepted, true);
  assert.equal((await page(fixture, target)).task.queued, 1);
});

test('raw graph JSON rejects unknown nested settings and overdeep message templates', async t => {
  const fixture = await journalFixture(t);
  let deep = { kind: 'output' };
  for (let index = 0; index < 20; index++) deep = concat(deep);
  const invalid = [
    { nodes: [node('first'), node('second', 'second', { settings: { unknown_setting: true } })], rules: [] },
    { nodes: [node('first'), node('second')], rules: [rule('too deep', 'first', action('second', deep))] },
  ];
  for (const declaration of invalid) {
    const rejected = await fixture.command({ op: 'create_task_graph', name: 'Malformed source data', ...declaration });
    assert.equal(rejected.reply.ok, false, JSON.stringify(declaration));
    assert.equal(rejected.reply.error.code, 'invalid_input');
  }
});

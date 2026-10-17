import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import {
  journalFixture, install, node, reference, rule, action, literal, concat,
  model, say, modelEffect, taskId, page, readGraph,
} from './fixtures/task-graph.mjs';

test('graph installation precedes immediate output, and one SQLite commit contains the accepted reply and handoff', async t => {
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
  const resumed = await fixture.send(model(modelEffect(decision, target), [say('implementation draft')]));
  assert.deepEqual(modelEffect(resumed, target).history.filter(message => message.role === 'user').map(message => message.content),
    ['implementation', completion.items[0].text]);
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

test('ordered multi-part replies use ordinary busy and frozen Task inboxes', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture, [node('tests'), node('busy'), node('frozen')], [
    rule('first', 'tests', action('busy', concat(literal('tests: '), { kind: 'output' })), action('frozen')),
    rule('second', 'tests', action('busy', literal('please use these tests'))),
  ]);
  const source = taskId(graph, 'tests');
  const busy = taskId(graph, 'busy');
  const frozen = taskId(graph, 'frozen');
  assert.equal((await fixture.command({ op: 'freeze', task_id: frozen })).reply.ok, true);
  const accepted = await fixture.send(model(modelEffect(decision, source), [say('left'), say(''), say('right')]));
  assert.equal(accepted.effects.some(effect => effect.kind === 'model' && effect.task_id === frozen), false);
  assert.equal((await page(fixture, busy)).task.queued, 4);
  assert.equal((await page(fixture, frozen)).task.queued, 2);
  const received = await fixture.send(model(modelEffect(decision, busy), [say('initial draft')]));
  assert.deepEqual(modelEffect(received, busy).history.filter(message => message.role === 'user').map(message => message.content),
    ['busy', 'tests: left', 'please use these tests', 'tests: right', 'please use these tests']);
  const released = await fixture.command({ op: 'unfreeze', task_id: frozen });
  // A pending model is preserved while frozen; finish that request to drain its inbox.
  const frozenRequest = released.effects.find(effect => effect.kind === 'model' && effect.task_id === frozen);
  const pending = frozenRequest ?? modelEffect(decision, frozen);
  const next = await fixture.send(model(pending, [say('frozen draft')]));
  assert.deepEqual(modelEffect(next, frozen).history.filter(message => message.role === 'user').map(message => message.content),
    ['frozen', 'left', 'right']);
  assert.equal((await readGraph(fixture, graph.graph_id)).receipts.length, 6);
});

test('replacing a graph while its source runs changes the next delivery; deleting it preserves Tasks', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture, [node('tests'), node('old'), node('new')],
    [rule('handoff', 'tests', action('old'))]);
  const source = taskId(graph, 'tests');
  const old = taskId(graph, 'old');
  const next = taskId(graph, 'new');
  const replaced = await fixture.command({ op: 'update_task_graph', graph_id: graph.graph_id, name: 'Revised pairing',
    nodes: graph.nodes, rules: [rule('handoff', 'tests', action('new'))] });
  assert.equal(replaced.reply.ok, true, JSON.stringify(replaced.reply));
  await fixture.send(model(modelEffect(decision, source), [say('new requirements')]));
  assert.equal((await page(fixture, old)).task.queued, 0);
  assert.equal((await page(fixture, next)).task.queued, 1);
  assert.equal((await fixture.command({ op: 'delete_task_graph', graph_id: graph.graph_id })).reply.ok, true);
  assert.equal((await fixture.command({ op: 'read_task_graph', graph_id: graph.graph_id })).reply.ok, false);
  const continued = await fixture.command({ op: 'send', task_id: source, message: 'continue independently' });
  await fixture.send(model(modelEffect(continued, source), [say('after deletion')]));
  assert.equal((await page(fixture, next)).task.queued, 1);
  assert.equal((await page(fixture, source)).task.status, 'active');
  assert.equal((await page(fixture, old)).task.status, 'active');
  assert.equal((await page(fixture, next)).task.status, 'active');
});

test('installing a connection to an existing Task does not replay historical output', async t => {
  const fixture = await journalFixture(t);
  const source = await fixture.command({ op: 'create', profile: 'fixture', message: 'old task' });
  const effect = source.effects.find(effect => effect.kind === 'model');
  await fixture.send(model(effect, [say('historical output')]));
  const { graph } = await install(fixture, [reference('tests', effect.task_id), node('implementation')],
    [rule('handoff', 'tests', action('implementation'))]);
  assert.equal((await page(fixture, taskId(graph, 'implementation'))).task.queued, 0);
  assert.deepEqual(graph.receipts, []);
});

test('tool continuations and compaction summaries do not escape through the output hook', async t => {
  const fixture = await journalFixture(t);
  await fixture.send({ kind: 'compaction_configure', now: 0, policy: { enabled: false,
    background_percent: 65, blocking_percent: 90, idle_lead_ms: 0, targets: [{ profile: 'fixture',
      window_tokens: 65536, output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'summary' }] } });
  const { decision, graph } = await install(fixture, [node('tests'), node('implementation')],
    [rule('handoff', 'tests', action('implementation'))]);
  const source = taskId(graph, 'tests');
  const target = taskId(graph, 'implementation');
  const continuation = await fixture.send(model(modelEffect(decision, source), [say('draft before inspection'),
    { type: 'call', id: 'inspect', name: 'read_task', arguments: { task_id: source } }]));
  assert.equal((await page(fixture, target)).task.queued, 0);
  assert.deepEqual((await readGraph(fixture, graph.graph_id)).receipts, []);
  await fixture.send(model(modelEffect(continuation, source), [say('final test result')]));
  assert.equal((await page(fixture, target)).task.queued, 1);
  const compacted = await fixture.command({ op: 'compact', task_id: source });
  assert.equal(compacted.reply.ok, true, JSON.stringify(compacted.reply));
  const scope = modelEffect(compacted, source, 'context_scope');
  const inspected = await fixture.send({ kind: 'compaction_measured', task_id: source, ticket: scope.ticket,
    error: false, result: { scope: 'fixture-scope', now: 1 } });
  const initialMeasure = modelEffect(inspected, source, 'context_measure');
  const prepared = await fixture.send({ kind: 'compaction_measured', task_id: source, ticket: initialMeasure.ticket,
    error: false, result: { scope: 'fixture-scope', input_tokens: 100, window_tokens: 65536,
      output_reserve_tokens: 1024, now: 1 } });
  const summary = modelEffect(prepared, source, 'context_compaction');
  const summarized = await fixture.send({ kind: 'compaction_completed', task_id: source, ticket: summary.ticket,
    error: false, result: { scope: 'fixture-scope', summary_text: 'private continuation summary' } });
  const validationScope = modelEffect(summarized, source, 'context_scope');
  const validation = await fixture.send({ kind: 'compaction_measured', task_id: source, ticket: validationScope.ticket,
    error: false, result: { scope: 'fixture-scope', now: 2 } });
  const measured = modelEffect(validation, source, 'context_measure');
  const adopted = await fixture.send({ kind: 'compaction_measured', task_id: source, ticket: measured.ticket,
    error: false, result: { scope: 'fixture-scope', input_tokens: 100, window_tokens: summary.plan.window_tokens,
      output_reserve_tokens: summary.plan.output_reserve_tokens, now: 2 } });
  assert.equal(adopted.reply.ok, true, JSON.stringify(adopted.reply));
  assert.equal((await page(fixture, target)).task.queued, 1);
  assert.equal((await readGraph(fixture, graph.graph_id)).receipts.length, 1);
});

test('stale tickets and accepted model failures do not produce handoffs', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture, [node('tests'), node('implementation')],
    [rule('handoff', 'tests', action('implementation'))]);
  const source = taskId(graph, 'tests');
  const target = taskId(graph, 'implementation');
  const pending = modelEffect(decision, source);
  const stale = await fixture.send(model({ ...pending, ticket: pending.ticket + 100 }, [say('unaccepted stale output')]));
  assert.equal(stale.reply.result.accepted, false);
  const failed = await fixture.send({ kind: 'model', task_id: source, ticket: pending.ticket, ok: false, message: 'fixture failure' });
  assert.equal(failed.reply.result.accepted, true);
  assert.equal((await page(fixture, target)).task.queued, 0);
  assert.deepEqual((await readGraph(fixture, graph.graph_id)).receipts, []);
  const resumed = await fixture.command({ op: 'send', task_id: source, message: 'retry the task' });
  await fixture.send(model(modelEffect(resumed, source), [say('accepted after retry')]));
  assert.equal((await page(fixture, target)).task.queued, 1);
});

test('an archived recipient produces a visible Send rejection while retaining the accepted source output', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture, [node('tests'), node('implementation'), node('observer')],
    [rule('handoff', 'tests', action('implementation'), action('observer'))]);
  const source = taskId(graph, 'tests');
  const target = taskId(graph, 'implementation');
  assert.equal((await fixture.command({ op: 'archive', task_id: target })).reply.ok, true);
  const accepted = await fixture.send(model(modelEffect(decision, source), [say('retained even if delivery fails')]));
  assert.equal(accepted.reply.result.accepted, true);
  assert.equal((await page(fixture, source)).messages.at(-1).content, 'retained even if delivery fails');
  assert.equal((await page(fixture, target)).task.queued, 0);
  assert.equal((await page(fixture, taskId(graph, 'observer'))).task.queued, 1);
  const receipts = (await readGraph(fixture, graph.graph_id)).receipts;
  assert.equal(receipts.length, 2);
  assert.equal(receipts[0].target_task_id, target);
  assert.equal(receipts[0].reply.ok, false);
  assert.ok(receipts[0].reply.error, JSON.stringify(receipts[0]));
  assert.equal(receipts[1].reply.ok, true);
});

test('a self-connection appends its input to the accepted current Task instead of overwriting its reply', async t => {
  const fixture = await journalFixture(t);
  const { decision, graph } = await install(fixture, [node('worker')],
    [rule('continue', 'worker', action('worker', concat(literal('review: '), { kind: 'output' })))]);
  const source = taskId(graph, 'worker');
  const continued = await fixture.send(model(modelEffect(decision, source), [say('candidate implementation')]));
  assert.equal(continued.reply.result.accepted, true);
  assert.deepEqual(modelEffect(continued, source).history.filter(message => ['user', 'assistant'].includes(message.role))
    .map(message => [message.role, message.content]), [
    ['user', 'worker'], ['assistant', 'candidate implementation'], ['user', 'review: candidate implementation'],
  ]);
  assert.equal((await readGraph(fixture, graph.graph_id)).receipts.length, 1);
});

test('malformed graph bindings and ordinary Task settings reject the whole installation without allocating Tasks', async t => {
  const fixture = await journalFixture(t);
  let deep = { kind: 'output' };
  for (let index = 0; index < 20; index++) deep = concat(deep);
  const invalid = [
    { nodes: [node('first'), node('second')], rules: [rule('bad source', 'missing', action('second'))] },
    { nodes: [node('first'), node('second')], rules: [rule('bad target', 'first', action('missing'))] },
    { nodes: [node('same'), node('same')], rules: [] },
    { nodes: [node('first')], rules: [rule('same', 'first', action('first')), rule('same', 'first', action('first'))] },
    { nodes: [node('first'), reference('missing task', 999)], rules: [] },
    { nodes: [node('first'), node('second', 'second', { profile: 'unknown' })], rules: [] },
    { nodes: [node('first'), node('second', 'second', { settings: { unknown_setting: true } })], rules: [] },
    { nodes: [node('first'), node('second')], rules: [rule('too deep', 'first', action('second', deep))] },
  ];
  for (const declaration of invalid) {
    const rejected = await fixture.command({ op: 'create_task_graph', name: 'Must be atomic', ...declaration });
    assert.equal(rejected.reply.ok, false, JSON.stringify(declaration));
    assert.deepEqual(rejected.effects, []);
    assert.deepEqual((await fixture.command({ op: 'list' })).reply.result.tasks, []);
    assert.deepEqual((await fixture.command({ op: 'list_task_graphs' })).reply.result.graphs, []);
  }
  const { graph } = await install(fixture, [node('first')], []);
  assert.equal(taskId(graph, 'first'), 0);
});

test('a rejected replacement preserves the existing graph and does not leak a partially created Task', async t => {
  const fixture = await journalFixture(t);
  const { graph } = await install(fixture, [node('tests'), node('implementation')],
    [rule('handoff', 'tests', action('implementation'))]);
  const beforeTasks = (await fixture.command({ op: 'list' })).reply.result.tasks;
  const rejected = await fixture.command({ op: 'update_task_graph', graph_id: graph.graph_id, name: 'Must not replace',
    nodes: [...graph.nodes, node('new first'), node('new invalid', 'bad', { settings: { unknown_setting: true } })], rules: [] });
  assert.equal(rejected.reply.ok, false, JSON.stringify(rejected.reply));
  assert.deepEqual(rejected.effects, []);
  assert.deepEqual(await readGraph(fixture, graph.graph_id), graph);
  assert.deepEqual((await fixture.command({ op: 'list' })).reply.result.tasks, beforeTasks);
});

test('native graph and Task creation cannot forge host observations or partially install rejected children', async t => {
  const fixture = await journalFixture(t);
  const controller = await fixture.command({ op: 'create', profile: 'fixture', message: 'construct bounded work' });
  let pending = controller.effects.find(effect => effect.kind === 'model');
  const controllerId = pending.task_id;
  const forbidden = [
    { name: 'create_task_graph', arguments: { name: 'Forged guidance', nodes: [node('first'),
      node('forged', 'forged', { settings: { guidance: { workspace: '/unobserved', path: '', revision: 'absent', instructions: '' } } }),
    ], rules: [] } },
    { name: 'create_task_graph', arguments: { name: 'Unobserved root', nodes: [node('first'),
      node('forged', 'forged', { settings: { workspace: { roots: ['/unobserved'], primary_root: '/unobserved' } } }),
    ], rules: [] } },
    { name: 'create_task', arguments: { profile: 'fixture', message: 'forged direct child', settings: {
      guidance: { workspace: '/unobserved', path: '', revision: 'absent', instructions: '' },
    } } },
  ];
  for (const [index, call] of forbidden.entries()) {
    const id = `rejected-construction-${index}`;
    const rejected = await fixture.send(model(pending, [{ type: 'call', id, ...call }]));
    assert.equal(rejected.reply.result.accepted, true);
    const delivered = (await page(fixture, controllerId)).messages.find(message => message.role === 'function_output' && message.call_id === id);
    assert.ok(delivered, `Missing rejected ${call.name} result`);
    assert.equal(delivered.is_error, true, JSON.stringify(delivered));
    assert.equal(delivered.content.ok, false, JSON.stringify(delivered));
    assert.equal((await fixture.command({ op: 'list' })).reply.result.tasks.length, 1);
    assert.deepEqual((await fixture.command({ op: 'list_task_graphs' })).reply.result.graphs, []);
    pending = modelEffect(rejected, controllerId);
  }
  const valid = await fixture.send(model(pending, [{ type: 'call', id: 'ordinary-create', name: 'create_task',
    arguments: { profile: 'fixture', message: 'valid child with existing defaults' } }]));
  const delivered = (await page(fixture, controllerId)).messages.find(message => message.role === 'function_output' && message.call_id === 'ordinary-create');
  assert.equal(delivered.is_error, false, JSON.stringify(delivered));
  assert.equal(delivered.content.ok, true);
  assert.equal((await fixture.command({ op: 'list' })).reply.result.tasks.length, 2);
  assert.ok(valid.effects.some(effect => effect.kind === 'model' && effect.task_id !== controllerId));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Journal } from '../host/journal.mjs';
import { createHash } from 'node:crypto';

async function temporary(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-bend-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return path.join(directory, 'journal.sqlite');
}
const environment = { kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model', reasoning_options: null }], tools: [], max_fork: 4, max_descendants: 8 };
const command = command => ({ kind: 'command', command });
const model = (task_id, ticket, calls = []) => ({ kind: 'model', task_id, ticket, ok: true, items: calls.map(call => ({ type: 'call', ...call })) });

test('committed inputs reconstruct the actual Bend state; recovery does not reissue a pending unsafe effect', async t => {
  const filename = await temporary(t);
  let journal = await Journal.open(filename);
  t.after(() => journal.close());
  await journal.execute(environment);
  await journal.execute(command({ op: 'create', profile: 'fixture', message: 'once' }));
  const intent = await journal.execute(model(0, 0, [{ id: 'external', name: 'bash', arguments: { command: 'printf once' } }]));
  assert.equal(intent.effects[0].kind, 'tool');
  const before = await journal.execute(command({ op: 'read', task_id: 0 }));
  assert.equal(before.sequence, 3);
  await journal.close();
  journal = await Journal.open(filename);
  assert.deepEqual((await journal.execute(command({ op: 'read', task_id: 0 }))).reply, before.reply);
  const recovered = await journal.execute({ kind: 'recover' });
  assert.equal(recovered.effects.some(effect => effect.kind === 'tool'), false);
  const after = await journal.execute(command({ op: 'read', task_id: 0 }));
  assert.equal(after.reply.result.messages.at(-1).content.error.code, 'outcome_unknown');
  assert.deepEqual(journal.events(2), [{ sequence: 3 }, { sequence: 4 }]);
});

test('an actual SQLite commit failure publishes no decision and discards the advanced kernel', async t => {
  const filename = await temporary(t);
  let journal = await Journal.open(filename);
  t.after(() => journal.close());
  await journal.execute(environment);
  const database = new DatabaseSync(filename);
  database.exec("CREATE TRIGGER reject_write BEFORE INSERT ON journal BEGIN SELECT RAISE(ABORT, 'simulated disk write failure'); END");
  let publications = 0;
  journal.on('commit', () => publications++);
  await assert.rejects(journal.execute(command({ op: 'create', profile: 'fixture', message: 'must not start' })), /simulated disk write failure/);
  assert.equal(publications, 0);
  assert.equal(database.prepare('SELECT count(*) AS n FROM journal').get().n, 1);
  await journal.close();
  database.exec('DROP TRIGGER reject_write');
  database.close();
  journal = await Journal.open(filename);
  assert.deepEqual((await journal.execute(command({ op: 'list' }))).reply.result.tasks, []);
});

test('one journal has one owner, and the OS-backed lock is released on close', async t => {
  const filename = await temporary(t);
  const first = await Journal.open(filename);
  t.after(() => first.close());
  await assert.rejects(Journal.open(filename), /locked|busy/i);
  await first.close();
  const second = await Journal.open(filename);
  await second.close();
});

test('obsolete schemas and unknown journal formats fail without changing saved data', async t => {
  const filename = await temporary(t);
  const old = new DatabaseSync(filename);
  old.exec('CREATE TABLE obsolete (value TEXT)');
  old.close();
  await assert.rejects(Journal.open(filename), /current Selvedge Bend journal schema/);
  const untouched = new DatabaseSync(filename);
  assert.equal(untouched.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE name='obsolete'").get().n, 1);
  untouched.close();
  const currentFile = `${filename}.current`;
  const current = await Journal.open(currentFile);
  await current.close();
  const database = new DatabaseSync(currentFile);
  database.prepare("UPDATE meta SET value = ? WHERE key='format'").run('unknown-format');
  database.close();
  const before = savedJournal(currentFile);
  await assert.rejects(Journal.open(currentFile), /supported Selvedge Bend journal format/);
  assert.deepEqual(savedJournal(currentFile), before);
});

test('journal corruption is detected before any saved effect is published', async t => {
  const filename = await temporary(t);
  const journal = await Journal.open(filename);
  await journal.execute(environment);
  await journal.close();
  const db = new DatabaseSync(filename);
  db.prepare('UPDATE journal SET input = ? WHERE seq=1').run(JSON.stringify({ ...environment, profiles: ['changed'] }));
  db.close();
  await assert.rejects(Journal.open(filename), /integrity failure/);
});

test('the journal stores task workspaces rather than a service-wide cwd identity', async t => {
  const filename = await temporary(t);
  const first = await Journal.open(filename);
  await first.execute(environment);
  await first.execute(command({ op: 'create', profile: 'fixture', message: 'task-local directory',
    settings: { workspace: { roots: ['/stable'], primary_root: '/stable' } } }));
  const original = await first.execute(command({ op: 'read', task_id: 0 }));
  await first.close();
  const reopened = await Journal.open(filename);
  assert.equal(reopened.sequence, 2);
  assert.deepEqual((await reopened.execute(command({ op: 'read', task_id: 0 }))).reply, original.reply);
  assert.deepEqual(savedJournal(filename).meta.map(({ key, value }) => ({ key, value })), [{ key: 'format', value: 'selvedge-bend-journal-3' }]);
  await reopened.close();
});

test('public observations leave pending work and the SQLite journal unchanged, including failed queries', async t => {
  const filename = await temporary(t);
  const journal = await Journal.open(filename);
  t.after(() => journal.close());
  await journal.execute(environment);
  await journal.execute(command({ op: 'create', profile: 'fixture', message: 'still pending' }));
  const before = await journal.execute(command({ op: 'read', task_id: 0 }));
  let commits = 0;
  journal.on('commit', () => commits++);
  for (const query of [
    { op: 'list' }, { op: 'describe' }, { op: 'read', task_id: 0 },
    { op: 'read', task_id: 0, after: 100 }, { op: 'read', task_id: 99 },
  ]) {
    const result = await journal.execute(command(query));
    assert.equal(result.sequence, before.sequence);
    assert.deepEqual(result.effects, []);
  }
  assert.equal(commits, 0);
  assert.deepEqual((await journal.execute(command({ op: 'read', task_id: 0 }))).reply, before.reply);
  const database = new DatabaseSync(filename, { readOnly: true });
  try { assert.equal(database.prepare('SELECT count(*) AS n FROM journal').get().n, before.sequence); }
  finally { database.close(); }
  const settled = await journal.execute(model(0, 0));
  assert.equal(settled.reply.result.accepted, true);
  assert.equal(settled.sequence, before.sequence + 1);
});


function savedJournal(filename) {
  const database = new DatabaseSync(filename, { readOnly: true });
  try {
    return {
      meta: database.prepare('SELECT key, value FROM meta ORDER BY key').all(),
      rows: database.prepare('SELECT * FROM journal ORDER BY seq').all(),
    };
  } finally { database.close(); }
}

async function previousFormatJournal(filename, transform = text => text) {
  const journal = await Journal.open(filename);
  await journal.execute(environment);
  await journal.execute(command({ op: 'create', profile: 'fixture', message: 'saved history 世界' }));
  await journal.execute(model(0, 0, [
    { id: 'first', name: 'bash', arguments: { command: 'printf first' } },
    { id: 'second', name: 'bash', arguments: { command: 'printf second' } },
  ]));
  const observed = await journal.execute(command({ op: 'read', task_id: 0 }));
  await journal.close();
  const database = new DatabaseSync(filename);
  try {
    const format = 'selvedge-bend-journal-2';
    const fingerprint = 'ab'.repeat(32);
    database.exec('DELETE FROM meta');
    const insert = database.prepare('INSERT INTO meta (key, value) VALUES (?, ?)');
    for (const [key, value] of Object.entries({ format, compiler: '0.0.1', fingerprint })) insert.run(key, value);
    let previous = createHash('sha256').update(format).update(fingerprint).digest('hex');
    const update = database.prepare('UPDATE journal SET decision = ?, previous = ?, digest = ? WHERE seq = ?');
    for (const row of database.prepare('SELECT * FROM journal ORDER BY seq').all()) {
      const decision = transform(row.decision, row.seq);
      const digest = createHash('sha256').update(previous).update('\0').update(String(row.seq))
        .update('\0').update(row.input).update('\0').update(decision).digest('hex');
      update.run(decision, previous, digest, row.seq);
      previous = digest;
    }
  } finally { database.close(); }
  return observed;
}

test('a prior journal replays committed history independently of its old compiler and build fingerprint', async t => {
  const filename = await temporary(t);
  const observed = await previousFormatJournal(filename);
  const legacy = savedJournal(filename);
  let journal = await Journal.open(filename);
  t.after(() => journal.close());
  assert.equal(journal.sequence, observed.sequence);
  assert.deepEqual((await journal.execute(command({ op: 'read', task_id: 0 }))).reply, observed.reply);
  const converted = savedJournal(filename);
  assert.deepEqual(converted.meta.map(({ key, value }) => ({ key, value })), [{ key: 'format', value: 'selvedge-bend-journal-3' }]);
  assert.deepEqual(converted.rows.map(({ input, decision }) => ({ input, decision })),
    legacy.rows.map(({ input, decision }) => ({ input, decision })));
  assert.equal(converted.rows[0].previous, createHash('sha256').update('selvedge-bend-journal-3').digest('hex'));
  const appended = await journal.execute(command({ op: 'create', profile: 'fixture', message: 'after conversion' }));
  assert.equal(appended.sequence, observed.sequence + 1);
  await journal.close();
  journal = await Journal.open(filename);
  assert.equal(journal.sequence, appended.sequence);
  assert.deepEqual((await journal.execute(command({ op: 'read', task_id: 0 }))).reply, observed.reply);
  assert.equal((await journal.execute(command({ op: 'read', task_id: 1 }))).reply.result.messages[0].content, 'after conversion');
});

test('a corrupt prior journal fails integrity before changing its metadata or committed rows', async t => {
  const filename = await temporary(t);
  await previousFormatJournal(filename);
  const database = new DatabaseSync(filename);
  database.prepare('UPDATE journal SET decision = ? WHERE seq = 2').run('{}');
  database.close();
  const before = savedJournal(filename);
  await assert.rejects(Journal.open(filename), /integrity failure at sequence 2/);
  assert.deepEqual(savedJournal(filename), before);
});

test('validly hashed prior decisions must preserve the complete committed meaning before conversion', async t => {
  for (const [name, sequence, change] of [
    ['reply', 2, decision => { decision.reply.ok = !decision.reply.ok; }],
    ['effects', 2, decision => { decision.effects = []; }],
    ['durability', 2, decision => { decision.durable = false; }],
    ['effect ordering', 3, decision => {
      assert.equal(decision.effects.length, 2);
      decision.effects.reverse();
    }],
  ]) {
    const filename = await temporary(t);
    await previousFormatJournal(filename, (text, rowSequence) => {
      if (rowSequence !== sequence) return text;
      const decision = JSON.parse(text);
      change(decision);
      return JSON.stringify(decision);
    });
    const before = savedJournal(filename);
    await assert.rejects(Journal.open(filename), new RegExp(`Committed decision incompatibility at sequence ${sequence}`), name);
    assert.deepEqual(savedJournal(filename), before, name);
  }
});

test('equivalent parsed prior decisions accept different object ordering and whitespace while retaining saved bytes', async t => {
  const filename = await temporary(t);
  const reorder = value => Array.isArray(value) ? value.map(reorder) : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.entries(value).reverse().map(([key, item]) => [key, reorder(item)])) : value;
  const observed = await previousFormatJournal(filename, text => JSON.stringify(reorder(JSON.parse(text)), null, 2));
  const before = savedJournal(filename);
  const journal = await Journal.open(filename);
  t.after(() => journal.close());
  assert.deepEqual((await journal.execute(command({ op: 'read', task_id: 0 }))).reply, observed.reply);
  assert.deepEqual(savedJournal(filename).rows.map(row => row.decision), before.rows.map(row => row.decision));
});

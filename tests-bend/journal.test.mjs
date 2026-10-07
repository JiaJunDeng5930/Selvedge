import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Journal } from '../host/journal.mjs';
import { buildIdentity } from '../host/kernel.mjs';

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

test('obsolete schemas and incompatible kernel fingerprints fail without migration', async t => {
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
  const identity = await buildIdentity();
  await assert.rejects(Journal.open(currentFile, { identity: { ...identity, fingerprint: 'different' } }), /different kernel/);
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
  assert.equal(reopened.identity.workspace, undefined);
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

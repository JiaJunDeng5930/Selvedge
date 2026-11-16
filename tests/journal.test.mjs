import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile, rm } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { gunzipSync } from 'node:zlib';
import { Service } from '../host/service.mjs';
import { Journal, journalFormat } from '../host/journal.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

test('a failed SQLite commit cannot start a paid drafting request', async t => {
  const directory = await home(t);
  const key = 'SELVEDGE_BOARD_COMMIT_FIXTURE_KEY';
  const previous = process.env[key];
  process.env[key] = 'loopback-fixture';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  const upstream = await responsesServer(t, () => [{ type: 'message', role: 'assistant', content: [{
    type: 'output_text', text: '{"title":"not requested","description":"not requested"}',
  }] }]);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    draft: { provider: 'responses', model: 'draft-model', endpoint: upstream.endpoint,
      api_key_env: key, timeout_ms: 5000 },
  } });
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  const database = new DatabaseSync(path.join(directory, 'journal.sqlite'));
  t.after(() => database.close());
  const before = database.prepare('SELECT count(*) AS count FROM journal').get().count;
  const sequence = service.journal.sequence;
  let publications = 0;
  service.journal.on('commit', () => publications++);
  database.exec("CREATE TRIGGER reject_board_write BEFORE INSERT ON journal BEGIN SELECT RAISE(ABORT, 'board disk write failed'); END");
  await assert.rejects(service.command({ op: 'create_card', title: 'Do not dispatch',
    assisted: true, draft_profile: 'draft' }), error => {
      assert.match(error.message, /board disk write failed/);
      return true;
    });
  assert.equal(publications, 0);
  assert.equal(upstream.requests.length, 0);
  assert.equal(database.prepare('SELECT count(*) AS count FROM journal').get().count, before);
  assert.equal(service.journal.sequence, sequence);
  await assert.rejects(service.command({ op: 'list_cards' }), /board disk write failed/);

  await service.close();
  database.exec('DROP TRIGGER reject_board_write');
  service = await Service.open({ home: directory, cwd: directory, config });
  const cards = await service.command({ op: 'list_cards' });
  assert.equal(cards.reply.ok, true);
  assert.deepEqual(cards.reply.result.cards, []);
  assert.equal(upstream.requests.length, 0);
});

test('the OS journal lock excludes a second owner and releases on close', async t => {
  const directory = await home(t);
  const options = { home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) };
  const first = await Service.open(options);
  const namespace = first.browserSnapshot().namespace;
  t.after(() => first.close());
  await assert.rejects(Service.open(options), error => error instanceof Error && error.message.trim() !== '');
  await first.close();
  const second = await Service.open(options);
  t.after(() => second.close());
  assert.equal(second.browserSnapshot().namespace, namespace);
  await second.close();
});


test('a lost SQLite commit acknowledgement retires the service and the committed input replays once', async t => {
  const directory = await home(t);
  const options = { home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) };
  let service = await Service.open(options);
  t.after(() => service.close());
  let publications = 0;
  service.journal.on('commit', () => publications++);
  const exec = DatabaseSync.prototype.exec;
  let armed = true;
  // Fault at the physical SQLite boundary: the write commits, but its acknowledgement is lost.
  DatabaseSync.prototype.exec = function (sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (armed && sql === 'COMMIT') {
      armed = false;
      throw new Error('SQLite COMMIT acknowledgement lost');
    }
    return result;
  };
  try {
    await assert.rejects(service.command({ op: 'create_card', title: 'Durably accepted card' }), error => {
      assert.match(error.message, /COMMIT acknowledgement lost/);
      return true;
    });
  } finally { DatabaseSync.prototype.exec = exec; }
  assert.equal(armed, false);
  assert.equal(publications, 0);
  await assert.rejects(service.command({ op: 'list_cards' }), /COMMIT acknowledgement lost/);
  await service.close();

  service = await Service.open(options);
  const listed = await service.command({ op: 'list_cards' });
  assert.equal(listed.reply.ok, true);
  assert.deepEqual(listed.reply.result.cards.map(card => card.title), ['Durably accepted card']);
});


test('format 28 upgrades through the normal handoff and preserves conversations and cursor identities', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  // A real CLI session recorded before managed updates added the schema marker.
  const original = gunzipSync(await readFile(new URL('./fixtures/journal-format28-unversioned.sqlite.gz', import.meta.url)));
  await writeFile(filename, original, { mode: 0o600 });
  const readPrefix = () => {
    const database = new DatabaseSync(filename);
    try { return database.prepare('SELECT seq, input, observed_at FROM journal ORDER BY seq').all(); }
    finally { database.close(); }
  };
  const history = readPrefix();
  const initial = await Journal.open(filename, { waitForOwnership: async () => {
    assert.deepEqual(await readFile(filename), original, 'Read-only replay must leave the live database intact');
  } });
  const readTask = journal => journal.execute({ kind: 'command', command: { op: 'read', task_id: 0 } });
  let conversation;
  try {
    assert.equal(initial.sequence, history.at(-1).seq);
    assert.deepEqual(readPrefix(), history);
    conversation = (await readTask(initial)).reply.result;
    assert.match(JSON.stringify(conversation.messages), /History recorded before managed updates/);
    const sent = await initial.execute({ kind: 'command', command: { op: 'send', task_id: 0, message: 'Message after upgrade' } });
    assert.equal(sent.reply.ok, true, JSON.stringify(sent.reply));
    assert.equal(sent.sequence, history.at(-1).seq + 1);
    const db = new DatabaseSync(filename);
    try {
      assert.equal(db.prepare("SELECT value FROM meta WHERE key = 'format'").get().value, journalFormat);
      assert.deepEqual(db.prepare('SELECT DISTINCT replay_version FROM journal ORDER BY replay_version').all().map(row => row.replay_version), [28, 30]);
    } finally { db.close(); }
  } finally { await initial.close(); }

  const reopened = await Journal.open(filename);
  try {
    const restored = (await readTask(reopened)).reply.result;
    assert.match(JSON.stringify(restored), /Message after upgrade/);
    assert.deepEqual(restored.messages.slice(0, conversation.messages.length), conversation.messages);
  } finally { await reopened.close(); }
});

for (const { version, fixtureName, recordedText, existed } of [
  // Actual sessions from b56ad975 and 79eebf7e with a failed git worktree add.
  { version: 28, fixtureName: 'journal-format28-refused-send', recordedText: 'Historically refused message', existed: false },
  { version: 29, fixtureName: 'journal-format29-accepted-send', recordedText: 'Accepted in format 29', existed: true },
]) {
  test(`format ${version} keeps the original send outcome and new messages survive replay`, async t => {
    const directory = await home(t);
    const filename = path.join(directory, 'journal.sqlite');
    const fixture = new URL(`./fixtures/${fixtureName}.sqlite.gz`, import.meta.url);
    await writeFile(filename, gunzipSync(await readFile(fixture)), { mode: 0o600 });
    const history = await Journal.open(filename);
    const readMessages = async journal => (await journal.execute({
      kind: 'command', command: { op: 'read', task_id: 0 },
    })).reply.result.messages;
    let newSequence;
    try {
      const before = JSON.stringify(await readMessages(history));
      assert.match(before, /Original message before upgrade/);
      assert.equal(before.includes(recordedText), existed);
      const accepted = await history.execute({
        kind: 'command', command: { op: 'send', task_id: 0, message: 'Accepted after upgrade' },
      });
      assert.equal(accepted.reply.ok, true);
      assert.equal(accepted.durable, true);
      newSequence = accepted.sequence;
    } finally { await history.close(); }
    await rm(`${filename}.checkpoint`);
    const replayed = await Journal.open(filename);
    try {
      assert.equal(replayed.sequence, newSequence);
      // The legacy task can still be waiting on a provider reply, so an
      // accepted message may have been queued rather than visible in history.
      const interrupted = await replayed.execute({ kind: 'command', command: { op: 'interrupt', task_id: 0 } });
      assert.equal(interrupted.reply.ok, true);
      const resumed = await replayed.execute({
        kind: 'command', command: { op: 'send', task_id: 0, message: 'Resume restored task' },
      });
      assert.equal(resumed.reply.ok, true);
      const after = JSON.stringify(await readMessages(replayed));
      assert.match(after, /Original message before upgrade/);
      assert.match(after, /Accepted after upgrade/);
      assert.equal(after.includes(recordedText), existed);
    } finally { await replayed.close(); }
  });
}

test('an unsuccessful migration leaves the historical format intact', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  const fixture = new URL('./fixtures/journal-format28-refused-send.sqlite.gz', import.meta.url);
  await writeFile(filename, gunzipSync(await readFile(fixture)), { mode: 0o600 });
  const db = new DatabaseSync(filename);
  try {
    db.prepare('UPDATE journal SET input = ? WHERE seq = (SELECT MAX(seq) FROM journal)')
      .run(JSON.stringify({ kind: 'unrecognized_fixture_input' }));
  } finally { db.close(); }
  const before = await readFile(filename);
  await assert.rejects(Journal.open(filename), /Committed input incompatibility/);
  assert.deepEqual(await readFile(filename), before);
});

test('an unsupported durable journal is rejected without conversion', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  const original = gunzipSync(await readFile(new URL('./fixtures/journal-format13.sqlite.gz', import.meta.url)));
  await writeFile(filename, original, { mode: 0o600 });
  await assert.rejects(Journal.open(filename), /Unsupported Selvedge Rocq journal format/);
  assert.deepEqual(await readFile(filename), original);
});

test('local refusals, stale results and unchanged successes do not write journal rows', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  const journal = await Journal.open(filename);
  t.after(() => journal.close());
  let publications = 0;
  journal.on('commit', () => publications++);
  const before = journal.sequence;
  const refused = await journal.execute({ kind: 'command', command: { op: 'send', task_id: 42, message: 'Do not retain this text' } });
  assert.equal(refused.reply.error.code, 'task_not_found');
  const stale = await journal.execute({ kind: 'model', task_id: 42, ticket: 0, ok: true, items: [] });
  assert.equal(stale.reply.ok, true);
  const unchanged = await journal.execute({ kind: 'command', command: { op: 'remote_disable' } });
  assert.equal(unchanged.reply.ok, true);
  const emptyWork = await journal.execute({ kind: 'continue' });
  assert.equal(emptyWork.reply.ok, true);
  for (const result of [refused, stale, unchanged, emptyWork]) {
    assert.equal(result.durable, false);
    assert.equal(result.sequence, before);
  }
  assert.equal(publications, 0);
  const db = new DatabaseSync(filename);
  try { assert.equal(db.prepare('SELECT count(*) AS count FROM journal').get().count, before); }
  finally { db.close(); }
});

test('a prepared restart includes commits made while the current service still owns the journal', async t => {
  const directory = await home(t);
  const options = { home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) };
  const previous = await Service.open(options);
  t.after(() => previous.close());
  assert.equal((await previous.command({ op: 'create_card', title: 'Before preparation' })).reply.ok, true);

  const journal = await Journal.open(path.join(directory, 'journal.sqlite'), { waitForOwnership: async () => {
    const committed = await previous.command({ op: 'create_card', title: 'During handoff' });
    assert.equal(committed.reply.ok, true);
    await previous.close();
  } });
  t.after(() => journal.close());
  const next = await Service.open({ ...options, journal });
  t.after(() => next.close());
  const listed = await next.command({ op: 'list_cards' });
  assert.equal(listed.reply.ok, true);
  assert.deepEqual(new Set(listed.reply.result.cards.map(card => card.title)),
    new Set(['Before preparation', 'During handoff']));
});

test('a prepared restart rejects a changed committed prefix at the same sequence', async t => {
  const directory = await home(t);
  const options = { home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) };
  const previous = await Service.open(options);
  t.after(() => previous.close());
  const committed = await previous.command({ op: 'create_card', title: 'Original title' });
  assert.equal(committed.reply.ok, true);

  await assert.rejects(async () => {
    const next = await Journal.open(path.join(directory, 'journal.sqlite'), { waitForOwnership: async () => {
      await previous.close();
      const database = new DatabaseSync(path.join(directory, 'journal.sqlite'));
      try {
        const replace = database.prepare('UPDATE journal SET input = ? WHERE seq = ?');
        replace.run(JSON.stringify({ kind: 'command', command: { op: 'create_card', title: 'Replaced title' } }), committed.sequence);
      } finally { database.close(); }
    } });
    await next.close();
  }, /committed journal prefix changed during update preparation/);
});

test('a journal reopens from its committed state and ignores a stale or damaged checkpoint', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  const checkpoint = `${filename}.checkpoint`;
  const card = title => ({ kind: 'command', command: { op: 'create_card', title } });
  const expectCards = async titles => {
    const journal = await Journal.open(filename);
    try {
      const listed = await journal.execute({ kind: 'command', command: { op: 'list_cards' } });
      assert.equal(listed.reply.ok, true);
      assert.deepEqual(new Set(listed.reply.result.cards.map(entry => entry.title)), new Set(titles));
    } finally { await journal.close(); }
  };

  const writer = await Journal.open(filename);
  t.after(() => writer.close());
  const first = await writer.execute(card('检查点里的卡片 🌲'));
  assert.equal(first.reply.ok, true);
  assert.equal((await writer.execute(card('Checkpoint suffix'))).reply.ok, true);
  await writer.close();
  const saved = await readFile(checkpoint);
  assert.ok(saved.length > 0);
  await expectCards(['检查点里的卡片 🌲', 'Checkpoint suffix']);

  const database = new DatabaseSync(filename);
  try {
    database.prepare('UPDATE journal SET input = ? WHERE seq = ?')
      .run(JSON.stringify(card('Replacement prefix')), first.sequence);
  } finally { database.close(); }
  await expectCards(['Replacement prefix', 'Checkpoint suffix']);

  const damaged = await readFile(checkpoint);
  damaged[damaged.length - 1] ^= 1;
  await writeFile(checkpoint, damaged);
  await expectCards(['Replacement prefix', 'Checkpoint suffix']);
});

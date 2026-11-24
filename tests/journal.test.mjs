import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { gunzipSync } from 'node:zlib';
import { Service } from '../host/service.mjs';
import { Journal } from '../host/journal.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

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
  const before = database.prepare('SELECT sequence FROM state').get().sequence;
  const sequence = service.journal.sequence;
  let publications = 0;
  service.journal.on('commit', () => publications++);
  database.exec("CREATE TRIGGER reject_board_write BEFORE UPDATE ON state BEGIN SELECT RAISE(ABORT, 'board disk write failed'); END");
  await assert.rejects(service.command({ op: 'create_card', title: 'Do not dispatch',
    assisted: true, draft_profile: 'draft' }), error => {
      assert.match(error.message, /board disk write failed/);
      return true;
    });
  assert.equal(publications, 0);
  assert.equal(upstream.requests.length, 0);
  assert.equal(database.prepare('SELECT sequence FROM state').get().sequence, before);
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

test('a task write and its shared state roll back together', async t => {
  const directory = await home(t);
  const options = { home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, profiles: { demo: { provider: 'echo', model: 'echo' } },
  }) };
  let service = await Service.open(options);
  t.after(() => service.close());
  const database = new DatabaseSync(path.join(directory, 'journal.sqlite'));
  t.after(() => database.close());
  database.exec("CREATE TRIGGER reject_state_write BEFORE UPDATE ON state BEGIN SELECT RAISE(ABORT, 'state disk write failed'); END");
  await assert.rejects(service.command({ op: 'create_idle', profile: 'demo' }), /state disk write failed/);
  await service.close();

  database.exec('DROP TRIGGER reject_state_write');
  service = await Service.open(options);
  const listed = await service.command({ op: 'list' });
  assert.equal(listed.reply.ok, true);
  assert.deepEqual(listed.reply.result.tasks, []);
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


test('a lost SQLite commit acknowledgement retires the service and reopening exposes the committed state once', async t => {
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


test('an earlier input journal is refused without modifying it', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  const original = gunzipSync(await readFile(new URL('./fixtures/journal-format28-unversioned.sqlite.gz', import.meta.url)));
  await writeFile(filename, original, { mode: 0o600 });
  await assert.rejects(Journal.open(filename), /Unsupported Selvedge SQLite state schema version/);
  assert.deepEqual(await readFile(filename), original);
});

test('local refusals, stale results and unchanged successes do not advance the stored state', async t => {
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
  try { assert.equal(db.prepare('SELECT sequence FROM state').get().sequence, before); }
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

test('a prepared restart rejects a different service identity', async t => {
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
        database.prepare('UPDATE state SET namespace = ? WHERE id = 1').run('0'.repeat(32));
      } finally { database.close(); }
    } });
    await next.close();
  }, /state database changed during update preparation/);
});

test('the service opens committed task and shared records directly', async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'journal.sqlite');
  const options = { home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, profiles: { demo: { provider: 'echo', model: 'echo' } },
  }) };
  let service = await Service.open(options);
  t.after(() => service.close());
  const command = async input => {
    const { reply } = await service.command(input);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const { task_id: untouched } = await command({ op: 'create_idle', profile: 'demo' });
  const { task_id: task } = await command({ op: 'create_idle', profile: 'demo' });
  await command({ op: 'create_card', title: 'Saved card' });
  const db = new DatabaseSync(filename);
  try {
    // Insist on updating only the task that actually changed.
    db.exec(`CREATE TRIGGER untouched_task BEFORE UPDATE ON tasks WHEN old.id = ${untouched}
      BEGIN SELECT RAISE(ABORT, 'unrelated task rewrite'); END`);
    await command({ op: 'send', task_id: task, message: '保留对话 🌲' });
    const before = await taskIdle(service, task);
    assert.match(JSON.stringify(before.messages), /保留对话 🌲/);
    const tables = db.prepare("SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name").all();
    assert.deepEqual(tables.map(row => row.name), ['state', 'tasks']);
    await service.close();

    service = await Service.open(options);
    assert.deepEqual((await command({ op: 'read', task_id: task })).messages, before.messages);
    assert.deepEqual((await command({ op: 'list_cards' })).cards.map(card => card.title), ['Saved card']);
    await command({ op: 'send', task_id: task, message: '继续执行' });
    const after = await taskIdle(service, task);
    assert.match(JSON.stringify(after.messages), /继续执行/);

    await service.close();
    db.prepare('UPDATE tasks SET data = ? WHERE id = ?').run(Buffer.alloc(0), task);
    await assert.rejects(Service.open(options), /Invalid Selvedge stored state/);
  } finally { db.close(); }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Service } from '../host/service.mjs';
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
  await assert.rejects(Service.open(options), /locked|busy/i);
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


test('the previous durable journal format is rejected without replay or conversion', async t => {
  const directory = await home(t);
  const options = { home: directory, cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false }) };
  const service = await Service.open(options);
  await service.command({ op: 'create_card', title: 'Retain the previous journal' });
  await service.close();
  const filename = path.join(directory, 'journal.sqlite');
  const database = new DatabaseSync(filename);
  const rows = database.prepare('SELECT * FROM journal ORDER BY seq').all();
  database.prepare('UPDATE meta SET value = ? WHERE key = ?').run('selvedge-rocq-journal-6', 'format');
  database.close();

  await assert.rejects(Service.open(options), /current Selvedge Rocq journal format/);
  const retained = new DatabaseSync(filename);
  try {
    assert.equal(retained.prepare('SELECT value FROM meta WHERE key = ?').get('format').value,
      'selvedge-rocq-journal-6');
    assert.deepEqual(retained.prepare('SELECT * FROM journal ORDER BY seq').all(), rows);
  } finally { retained.close(); }
});

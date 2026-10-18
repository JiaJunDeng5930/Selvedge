import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Service } from '../host/service.mjs';
import { Journal } from '../host/journal.mjs';
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
    assisted: true, draft_profile: 'draft' }), /board disk write failed/);
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
  const filename = path.join(await home(t), 'journal.sqlite');
  const first = await Journal.open(filename);
  const namespace = first.namespace;
  t.after(() => first.close());
  await assert.rejects(Journal.open(filename), /locked|busy/i);
  await first.close();
  const second = await Journal.open(filename);
  assert.equal(second.namespace, namespace);
  await second.close();
});

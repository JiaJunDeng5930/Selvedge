import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const assistant = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const offline = () => validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
const okay = decision => {
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
};
const card = async (service, id = 0) => okay(await service.command({ op: 'read_card', card_id: id }));

test('manual ordering preserves other cards, guards revisions and survives journal replay', async t => {
  const directory = await home(t), config = offline();
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  for (const title of ['first', 'second', 'third', 'fourth']) okay(await service.command({ op: 'create_card', title, status: 'todo' }));
  const order = async () => okay(await service.command({ op: 'list_cards' })).cards.map(card => card.card_id);
  assert.deepEqual(await order(), [0, 1, 2, 3]);
  const move = await service.command({ op: 'move_card', card_id: 3, revision: 0, status: 'todo', before_card: '1' });
  assert.deepEqual(okay(move), { card_id: 3, revision: 1 }); assert.deepEqual(move.effects, []);
  assert.deepEqual(await order(), [0, 3, 1, 2]);
  okay(await service.command({ op: 'update_card', card_id: 1, revision: 0, title: 'edited in place' }));
  assert.deepEqual(await order(), [0, 3, 1, 2]);
  assert.equal((await service.command({ op: 'move_card', card_id: 3, revision: 0, status: 'todo', before_card: '' })).reply.ok, false);
  assert.equal((await service.command({ op: 'move_card', card_id: 3, revision: 1, status: 'backlog', before_card: '1' })).reply.ok, false);
  assert.equal((await service.command({ op: 'move_card', card_id: 3, revision: 1, status: 'todo', before_card: '3' })).reply.ok, false);
  assert.deepEqual(await order(), [0, 3, 1, 2]);
  await service.close(); service = await Service.open({ home: directory, cwd: directory, config });
  assert.deepEqual(await order(), [0, 3, 1, 2]);
  okay(await service.command({ op: 'move_card', card_id: 0, revision: 0, status: 'backlog', before_card: '' }));
  assert.deepEqual(await order(), [3, 1, 2, 0]);
  assert.equal((await card(service, 0)).status, 'backlog');
  assert.equal((await card(service, 1)).title, 'edited in place');
  assert.equal(okay(await service.command({ op: 'list' })).tasks.length, 0);
});

async function waitUntil(read, predicate, description) {
  const deadline = Date.now() + 10_000;
  let value;
  do {
    value = await read();
    if (predicate(value)) return value;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`${description}: ${JSON.stringify(value)}`);
}

function effects(directory) {
  const database = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
  try { return database.prepare('SELECT decision FROM journal ORDER BY seq').all().flatMap(row => JSON.parse(row.decision).effects); }
  finally { database.close(); }
}

function connected(t, endpoint) {
  const previous = process.env.SELVEDGE_BOARD_SERVICE_KEY;
  process.env.SELVEDGE_BOARD_SERVICE_KEY = 'loopback-fixture';
  t.after(() => {
    if (previous === undefined) delete process.env.SELVEDGE_BOARD_SERVICE_KEY;
    else process.env.SELVEDGE_BOARD_SERVICE_KEY = previous;
  });
  const profile = model => ({ provider: 'responses', model, endpoint,
    api_key_env: 'SELVEDGE_BOARD_SERVICE_KEY', timeout_ms: 10_000 });
  return validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    ...defaultConfig.profiles, worker: profile('worker-model'), draft: profile('draft-model'),
  } });
}

async function hanging(t) {
  const arrived = Promise.withResolvers(), disconnected = Promise.withResolvers();
  let requests = 0;
  const server = http.createServer((request, response) => {
    requests++;
    request.resume();
    response.once('close', disconnected.resolve);
    arrived.resolve();
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return { endpoint: `http://127.0.0.1:${server.address().port}/responses`, arrived: arrived.promise,
    disconnected: disconnected.promise, count: () => requests };
}

test('board capture, revision conflicts and archive survive a real journal restart without creating a conversation', async t => {
  const directory = await home(t), config = offline();
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  const created = await service.command({ op: 'create_card', title: '持久保存', description: '原始需求', status: 'backlog', labels: ['review'] });
  assert.deepEqual(created.effects, []);
  assert.deepEqual(okay(created), { card_id: 0, revision: 0 });
  const before = await card(service);
  assert.notEqual(before.created_at, '0');
  const sequence = service.journal.sequence;
  await service.command({ op: 'list_cards' });
  assert.equal(service.journal.sequence, sequence);
  okay(await service.command({ op: 'update_card', card_id: 0, revision: 0, title: '已编辑', priority: 'high' }));
  const rejected = await service.command({ op: 'update_card', card_id: 0, revision: 0, title: '过期覆盖' });
  assert.equal(rejected.reply.error.code, 'card_conflict');
  const edited = await card(service);
  okay(await service.command({ op: 'archive_card', card_id: 0, revision: edited.revision }));
  const archived = await card(service);
  await service.close();
  service = await Service.open({ home: directory, cwd: directory, config });
  assert.deepEqual(await card(service), archived);
  assert.equal(archived.title, '已编辑');
  assert.equal(archived.archived, true);
  assert.equal(archived.created_at, before.created_at);
  assert.equal(archived.task_id, null);
  assert.deepEqual(okay(await service.command({ op: 'list' })).tasks, []);
  okay(await service.command({ op: 'restore_card', card_id: 0, revision: archived.revision }));
  assert.equal((await card(service)).status, 'backlog');
});

test('automatic board execution commits before HTTP, respects agent capacity and freezes each born conversation', async t => {
  const directory = await home(t);
  const first = Promise.withResolvers(), second = Promise.withResolvers();
  const started = [Promise.withResolvers(), Promise.withResolvers()];
  const upstream = await responsesServer(t, async (body, index) => {
    assert.ok(index < 2, 'A card must never be started twice');
    assert.equal(effects(directory).filter(effect => effect.kind === 'model').length, index + 1);
    started[index].resolve();
    await [first, second][index].promise;
    return assistant(`Completed ${index}`);
  });
  const service = await Service.open({ home: directory, cwd: directory, config: connected(t, upstream.endpoint) });
  t.after(() => service.close());
  const agent = { op: 'save_board_agent', agent: '', revision: 0, name: 'Implementer', profile: 'worker',
    reasoning: 'medium', instructions: 'Frozen role A.', settings: {}, concurrency: 1 };
  okay(await service.command(agent));
  okay(await service.command({ op: 'create_card', title: 'First', status: 'todo', priority: 'high', assignee: 'agent/0' }));
  okay(await service.command({ op: 'create_card', title: 'Second', status: 'todo', priority: 'low', assignee: 'agent/0' }));
  okay(await service.command({ op: 'board_settings', automatic: true, draft_profile: 'draft' }));
  await started[0].promise;
  const working = await card(service);
  assert.equal(working.task_id, 0);
  assert.equal(working.status, 'in_progress');
  assert.equal((await card(service, 1)).task_id, null);
  assert.equal(upstream.requests.length, 1);
  assert.equal((await service.command({ op: 'run_card', card_id: 0, revision: working.revision })).reply.ok, false);
  okay(await service.command({ ...agent, agent: '0', instructions: 'Future role B.' }));
  first.resolve();
  await started[1].promise;
  const reviewing = await waitUntil(() => card(service), value => value.status === 'in_review', 'First card did not reach review');
  assert.equal((await card(service, 1)).task_id, 1);
  assert.match(JSON.stringify(upstream.requests[0].input), /Frozen role A\./);
  assert.doesNotMatch(JSON.stringify(upstream.requests[0].input), /Future role B\./);
  assert.match(JSON.stringify(upstream.requests[1].input), /Future role B\./);
  second.resolve();
  await taskIdle(service, 1);
  okay(await service.command({ op: 'update_card', card_id: 0, revision: reviewing.revision, status: 'done' }));
  assert.equal((await card(service)).task_id, 0);
  assert.equal((await card(service)).status, 'done');
  assert.equal(effects(directory).filter(effect => effect.kind === 'model').length, 2);
  assert.deepEqual(upstream.failures, []);
});

test('assisted capture and retitle use committed independent requests; malformed replies preserve the saved requirement', async t => {
  const directory = await home(t);
  const upstream = await responsesServer(t, (_, index) => {
    assert.equal(effects(directory).filter(effect => effect.kind === 'board_text').length, index + 1);
    if (index === 2) return [{ type: 'function_call', call_id: 'not-authorized', name: 'bash', arguments: '{"command":"echo forbidden"}' }];
    return assistant(JSON.stringify(index === 0 ? { title: 'Generated title', description: 'Generated description' } :
      { title: 'Retitled', description: 'Must not replace the existing description' }));
  });
  const service = await Service.open({ home: directory, cwd: directory, config: connected(t, upstream.endpoint) });
  t.after(() => service.close());
  const creation = await service.command({ op: 'create_card', title: '', description: '用户的原始需求', assisted: true, draft_profile: 'draft' });
  okay(creation);
  assert.deepEqual(creation.effects.map(effect => effect.kind), ['board_text']);
  let current = await waitUntil(() => card(service), value => value.enrichment.status === 'idle', 'Draft did not finish');
  assert.equal(current.title, 'Generated title');
  assert.equal(current.task_id, null);
  okay(await service.command({ op: 'regenerate_card_title', card_id: 0, revision: current.revision, draft_profile: 'draft' }));
  current = await waitUntil(() => card(service), value => value.enrichment.status === 'idle', 'Retitle did not finish');
  assert.equal(current.title, 'Retitled');
  assert.equal(current.description, 'Generated description');
  okay(await service.command({ op: 'regenerate_card_title', card_id: 0, revision: current.revision, draft_profile: 'draft' }));
  current = await waitUntil(() => card(service), value => value.enrichment.status === 'failed', 'Malformed drafting output was not rejected');
  assert.equal(current.title, 'Retitled');
  assert.equal(current.description, 'Generated description');
  assert.equal(effects(directory).some(effect => effect.kind === 'tool'), false);
  okay(await service.command({ op: 'create', profile: 'demo', message: 'The service remains usable.' }));
  await taskIdle(service);
  assert.deepEqual(upstream.failures, []);
});

test('restart marks unknown drafting as failed and never repeats a paid request', async t => {
  const directory = await home(t), upstream = await hanging(t), config = connected(t, upstream.endpoint);
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  okay(await service.command({ op: 'create_card', title: 'Original title', description: 'Original description', assisted: true, draft_profile: 'draft' }));
  await upstream.arrived;
  assert.equal((await card(service)).enrichment.status, 'running');
  await service.close();
  await upstream.disconnected;
  service = await Service.open({ home: directory, cwd: directory, config });
  const recovered = await card(service);
  assert.equal(recovered.enrichment.status, 'failed');
  assert.match(recovered.enrichment.reason, /restarted/);
  assert.equal(recovered.title, 'Original title');
  assert.equal(recovered.description, 'Original description');
  assert.equal(upstream.count(), 1);
  assert.equal(effects(directory).filter(effect => effect.kind === 'board_text').length, 1);
});

test('a failed SQLite commit cannot start a board drafting request', async t => {
  const directory = await home(t);
  const upstream = await responsesServer(t, () => assistant('{"title":"not requested","description":"not requested"}'));
  const service = await Service.open({ home: directory, cwd: directory, config: connected(t, upstream.endpoint) });
  t.after(() => service.close());
  const database = new DatabaseSync(path.join(directory, 'journal.sqlite'));
  t.after(() => database.close());
  database.exec("CREATE TRIGGER reject_board_write BEFORE INSERT ON journal BEGIN SELECT RAISE(ABORT, 'board disk write failed'); END");
  await assert.rejects(service.command({ op: 'create_card', title: 'Do not dispatch', assisted: true, draft_profile: 'draft' }), /board disk write failed/);
  assert.equal(upstream.requests.length, 0);
  assert.equal(effects(directory).filter(effect => effect.kind === 'board_text').length, 0);
});

test('archiving an executing card cancels its actual HTTP request, and restore does not replay it', async t => {
  const directory = await home(t), upstream = await hanging(t);
  const service = await Service.open({ home: directory, cwd: directory, config: connected(t, upstream.endpoint) });
  t.after(() => service.close());
  okay(await service.command({ op: 'create_card', title: 'Running card', status: 'todo', assignee: 'profile/worker' }));
  okay(await service.command({ op: 'run_card', card_id: 0, revision: 0 }));
  await upstream.arrived;
  const current = await card(service);
  const archived = await service.command({ op: 'archive_card', card_id: 0, revision: current.revision });
  okay(archived);
  assert.ok(archived.effects.some(effect => effect.kind === 'cancel' && effect.task_id === 0));
  await upstream.disconnected;
  const saved = await card(service);
  assert.equal(saved.archived, true);
  okay(await service.command({ op: 'restore_card', card_id: 0, revision: saved.revision }));
  assert.equal((await card(service)).task_id, 0);
  assert.equal(upstream.count(), 1);
  assert.equal(effects(directory).filter(effect => effect.kind === 'model').length, 1);
});

test('authenticated attachment HTTP transport binds uploaded bytes to the native card and isolates untrusted MIME', async t => {
  const directory = await home(t);
  const site = await startServer({ home: directory, cwd: directory, config: offline() });
  t.after(() => site.close());
  const upload = `${site.address}/api/board/attachments?name=${encodeURIComponent('notes.svg')}`;
  const headers = { authorization: `Bearer ${site.token}` };
  const data = '<svg onload="alert(1)">private requirement</svg>';
  assert.equal((await fetch(upload, { method: 'POST', body: data })).status, 401);
  const response = await fetch(upload, { method: 'POST', headers, body: data });
  assert.equal(response.status, 201);
  const attachment = (await response.json()).result;
  assert.equal(attachment.mime, 'application/octet-stream');
  const file = `${site.address}/api/board/attachments/${attachment.id}`;
  assert.equal((await fetch(file)).status, 401);
  const downloaded = await fetch(file, { headers });
  assert.match(downloaded.headers.get('content-disposition'), /^attachment;/);
  assert.equal(downloaded.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(await downloaded.text(), data);
  const create = await fetch(`${site.address}/api/commands`, { method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify({ op: 'create_card', title: 'Read attachments', attachments: [{ id: attachment.id }] }),
  });
  assert.equal(create.status, 200);
  assert.deepEqual((await card(site.service)).attachments, [attachment]);
  assert.equal((await fetch(file, { headers: { ...headers, origin: 'https://not-this-service.invalid' } })).status, 403);
});

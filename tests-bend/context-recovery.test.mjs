import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import path from 'node:path';
import { readFile, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { Kernel } from '../host/kernel.mjs';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, taskIdle } from './support.mjs';

async function native(t, overrides = {}) {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const description = await kernel.initialize();
  const input = async value => (await kernel.request(value)).value;
  const command = value => input({ kind: 'command', command: value });
  const configured = await input({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture' }],
    tools: [], max_fork: 4, max_descendants: 8, ...overrides });
  assert.equal(configured.reply.ok, true);
  return { input, command, description };
}

const overflow = ticket => ({ kind: 'model', task_id: 0, ticket, ok: false, failure_kind: 'context_limit', message: 'structured context limit' });
const answer = (ticket, text) => ({ kind: 'model', task_id: 0, ticket, ok: true, items: [{ type: 'text', text }] });

test('native overflow recovery uses one checkpoint, fresh tickets, and stops when the checkpoint still cannot fit', async t => {
  const { input, command } = await native(t);
  const started = (await command({ op: 'create', profile: 'fixture', message: 'a request below the byte threshold' })).effects[0];
  assert.equal(started.kind, 'model');
  const summarizing = await input(overflow(started.ticket));
  assert.deepEqual(summarizing.effects.map(x => x.kind), ['summary']);
  const summary = summarizing.effects[0];
  assert.deepEqual(summary.tools, []);
  assert.deepEqual(summary.callable, []);
  assert.notEqual(summary.ticket, started.ticket);
  const stale = await input(overflow(started.ticket));
  assert.equal(stale.reply.result.accepted, false);
  assert.deepEqual(stale.effects, []);
  const resumed = await input(answer(summary.ticket, 'Retain the objective and the verified state.'));
  assert.deepEqual(resumed.effects.map(x => x.kind), ['model']);
  assert.notEqual(resumed.effects[0].ticket, summary.ticket);
  assert.equal(resumed.effects[0].history.length, 1);
  const failed = await input(overflow(resumed.effects[0].ticket));
  assert.deepEqual(failed.effects, [], 'An irreducible checkpoint must not enter an automatic summarize/retry cycle');
  assert.deepEqual((await input({ kind: 'continue' })).effects, []);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.task.phase, 'idle');
  assert.equal(page.messages[0].content, 'a request below the byte threshold');
  assert.match(page.messages.at(-1).content, /persists after compaction/);
});

test('overflow summary recovery survives restart, honors freeze, and rejects interrupted results', async t => {
  const { input, command } = await native(t);
  const started = (await command({ op: 'create', profile: 'fixture', message: 'work' })).effects[0];
  const first = (await input(overflow(started.ticket))).effects[0];
  const restored = (await input({ kind: 'recover' })).effects[0];
  assert.equal(restored.kind, 'summary');
  assert.notEqual(restored.ticket, first.ticket);
  assert.equal((await input(answer(first.ticket, 'stale checkpoint'))).reply.result.accepted, false);
  await command({ op: 'freeze', task_id: 0 });
  assert.deepEqual((await input(answer(restored.ticket, 'current checkpoint'))).effects, []);
  const thawed = (await command({ op: 'unfreeze', task_id: 0 })).effects[0];
  assert.equal(thawed.kind, 'model');
  await command({ op: 'interrupt', task_id: 0 });
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal((await input(overflow(thawed.ticket))).reply.result.accepted, false);
  assert.deepEqual((await command({ op: 'read', task_id: 0 })).reply.result, page);
});

test('a summary that also overflows retains history and permits an explicit supplied checkpoint', async t => {
  const { input, command } = await native(t);
  const started = (await command({ op: 'create', profile: 'fixture', message: 'important original request' })).effects[0];
  const summary = (await input(overflow(started.ticket))).effects[0];
  assert.deepEqual((await input(overflow(summary.ticket))).effects, []);
  const page = (await command({ op: 'read', task_id: 0 })).reply.result;
  assert.equal(page.task.phase, 'idle');
  assert.equal(page.messages[0].content, 'important original request');
  assert.match(page.messages.at(-1).content, /supply a bounded checkpoint/);
  const manual = await command({ op: 'compact', task_id: 0, summary: 'An explicit replacement context supplied by the user.' });
  assert.equal(manual.reply.ok, true);
  assert.deepEqual(manual.effects, []);
  const continued = await command({ op: 'send', task_id: 0, message: 'continue' });
  assert.deepEqual(continued.effects.map(x => x.kind), ['model']);
  assert.equal(continued.effects[0].history.length, 2);
});

test('failed summaries do not strand new FIFO input, and cannot authorize their own tool calls', async t => {
  for (const [name, completion] of [
    ['transport failure', ticket => ({ kind: 'model', task_id: 0, ticket, ok: false, message: 'summary transport failed' })],
    ['invalid tool-bearing summary', ticket => ({ kind: 'model', task_id: 0, ticket, ok: true,
      items: [{ type: 'call', id: 'not-authorized', name: 'bash', arguments: { command: 'must not execute' } }] })],
    ['context overflow', overflow],
  ]) {
    await t.test(name, async t => {
      const { input, command } = await native(t);
      const initial = (await command({ op: 'create', profile: 'fixture', message: 'first objective' })).effects[0];
      await input(answer(initial.ticket, 'first answer'));
      const summary = (await command({ op: 'compact', task_id: 0 })).effects[0];
      await command({ op: 'send', task_id: 0, message: 'queued one' });
      await command({ op: 'send', task_id: 0, message: 'queued two' });
      const continued = await input(completion(summary.ticket));
      assert.deepEqual(continued.effects.map(x => x.kind), ['model']);
      assert.deepEqual(continued.effects[0].history.slice(-2).map(x => x.content), ['queued one', 'queued two']);
      const page = (await command({ op: 'read', task_id: 0 })).reply.result;
      assert.equal(page.task.queued, 0);
      assert.equal(page.messages.some(x => x.call_id === 'not-authorized'), false);
      await input(answer(continued.effects[0].ticket, 'new input processed'));
      assert.deepEqual((await input({ kind: 'continue' })).effects, []);
    });
  }
});

test('a large frozen tool catalog cannot repeatedly compact a checkpoint with no new work', async t => {
  const { input, command } = await native(t, { tools: [{ name: 'mcp__fixture__large', server: 'fixture', remote: 'large',
    description: 'x'.repeat(132000), schema: { type: 'object' } }] });
  const created = await command({ op: 'create', profile: 'fixture', message: 'small objective' });
  assert.deepEqual(created.effects.map(x => x.kind), ['summary']);
  const resumed = await input(answer(created.effects[0].ticket, 'small checkpoint'));
  assert.deepEqual(resumed.effects.map(x => x.kind), ['model']);
  assert.deepEqual((await input(overflow(resumed.effects[0].ticket))).effects, []);
});

test('the service commits overflow and summary before retrying, without repeating a completed file mutation on restart', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const key = 'SELVEDGE_OVERFLOW_FIXTURE_KEY';
  const old = process.env[key];
  process.env[key] = 'fixture';
  t.after(() => { if (old === undefined) delete process.env[key]; else process.env[key] = old; });
  await writeFile(path.join(directory, 'AGENTS.md'), 'Keep completed writes; verify the resulting artifact.');
  const requests = [], failures = [], committedKinds = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks));
      const index = requests.length;
      requests.push(body);
      const db = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
      let record;
      try { record = db.prepare('SELECT input, decision FROM journal ORDER BY seq DESC LIMIT 1').get(); }
      finally { db.close(); }
      const committed = JSON.parse(record.decision).effects;
      const kind = index === 2 ? 'summary' : 'model';
      assert.ok(committed.some(effect => effect.kind === kind));
      committedKinds.push(kind);
      assert.match(body.input[0].content, /Keep completed writes/);
      if (index === 1) {
        assert.ok(body.input.some(item => item.type === 'function_call_output' && item.call_id === 'only-write'));
        response.writeHead(400, { 'content-type': 'application/json' });
        response.end(JSON.stringify({ error: { code: 'context_length_exceeded', message: 'upstream-private-diagnostic' } }));
        return;
      }
      let output;
      if (index === 0) {
        output = [{ type: 'function_call', call_id: 'only-write', name: 'bash',
          arguments: JSON.stringify({ command: "printf 'committed once' > result.txt" }) }];
      } else if (index === 2) {
        assert.equal(JSON.parse(record.input).failure_kind, 'context_limit');
        assert.deepEqual(body.tools, []);
        assert.equal(body.tool_choice, 'none');
        output = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'result.txt was written successfully; do not repeat the write.' }] }];
      } else {
        assert.equal(index, 3, 'A stopped recovery must not silently retry again');
        assert.equal(body.input.length, 2, 'Project snapshot plus committed checkpoint is the new context');
        assert.match(JSON.stringify(body.input), /do not repeat the write/);
        output = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'completed' }] }];
      }
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\n\n`);
    })().catch(error => { failures.push(error); response.writeHead(500); response.end('fixture failure'); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: { provider: 'responses', model: 'fixture',
    endpoint: `http://127.0.0.1:${server.address().port}/responses`, api_key_env: key, timeout_ms: 5000 } } });
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'fixture', message: 'write the artifact and complete the objective' });
  const page = await taskIdle(service);
  assert.deepEqual(failures, []);
  assert.deepEqual(committedKinds, ['model', 'model', 'summary', 'model']);
  assert.equal(await readFile(path.join(directory, 'result.txt'), 'utf8'), 'committed once');
  assert.equal(JSON.stringify(page).includes('upstream-private-diagnostic'), false);
  assert.equal(page.messages.filter(x => x.role === 'function_output').length, 1);
  await service.close();
  service = await Service.open({ home: directory, cwd: directory, config });
  assert.deepEqual((await taskIdle(service)).messages, page.messages);
  assert.equal(requests.length, 4);
  assert.equal(await readFile(path.join(directory, 'result.txt'), 'utf8'), 'committed once');
});

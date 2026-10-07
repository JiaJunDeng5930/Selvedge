import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import path from 'node:path';
import { readFile, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, taskIdle } from './support.mjs';

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
      const db = new DatabaseSync(path.join(directory, 'state', 'journal.sqlite'), { readOnly: true });
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
  let service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'fixture', message: 'write the artifact and complete the objective' });
  const page = await taskIdle(service);
  assert.deepEqual(failures, []);
  assert.deepEqual(committedKinds, ['model', 'model', 'summary', 'model']);
  assert.equal(await readFile(path.join(directory, 'result.txt'), 'utf8'), 'committed once');
  assert.equal(JSON.stringify(page).includes('upstream-private-diagnostic'), false);
  assert.equal(page.messages.filter(x => x.role === 'function_output').length, 1);
  await service.close();
  service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  assert.deepEqual((await taskIdle(service)).messages, page.messages);
  assert.equal(requests.length, 4);
  assert.equal(await readFile(path.join(directory, 'result.txt'), 'utf8'), 'committed once');
});

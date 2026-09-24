import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { writeAtomic } from '../host/files.mjs';
import { home, taskIdle } from './support.mjs';

async function until(label, condition) {
  const deadline = Date.now() + 5000;
  do {
    if (await condition()) return;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Did not observe ${label}`);
}

test('shutdown interrupts a remote request; recovery retries it and a truncated stream settles as failure', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const started = Promise.withResolvers();
  const disconnected = Promise.withResolvers();
  const failures = [];
  let requests = 0;
  const upstream = http.createServer((request, response) => {
    void (async () => {
      for await (const chunk of request) { /* Drain the request before replying. */ }
      requests += 1;
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.write('data: {"type":"response.output_text.delta","delta":"transient"}\n\n');
      if (requests === 1) {
        response.once('close', () => disconnected.resolve());
        started.resolve();
      } else if (requests === 2) response.end();
      else response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed',
        output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'recovered' }] }] } })}\n\n`);
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { upstream.closeAllConnections(); upstream.close(resolve); }));
  const previousKey = process.env.SELVEDGE_RECOVERY_KEY;
  process.env.SELVEDGE_RECOVERY_KEY = 'fixture-key';
  t.after(() => {
    if (previousKey === undefined) delete process.env.SELVEDGE_RECOVERY_KEY;
    else process.env.SELVEDGE_RECOVERY_KEY = previousKey;
  });
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: { provider: 'responses', model: 'fixture',
    endpoint: `http://127.0.0.1:${upstream.address().port}/responses`, api_key_env: 'SELVEDGE_RECOVERY_KEY' } } });
  let service = await Service.open({ home: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'fixture', message: 'keep this request' });
  await started.promise;
  const closing = service.close();
  assert.equal(service.close(), closing);
  await closing;
  await disconnected.promise;
  service = await Service.open({ home: directory, config });
  const failed = await taskIdle(service);
  assert.equal(requests, 2);
  assert.equal(failed.messages.length, 2);
  assert.equal(failed.messages.at(-1).role, 'error');
  assert.match(failed.messages.at(-1).content, /without a completed response/);
  await service.command({ op: 'send', task_id: 0, message: 'retry now' });
  const completed = await taskIdle(service);
  assert.equal(requests, 3);
  assert.equal(completed.messages.at(-1).content.content[0].text, 'recovered');
  assert.equal(completed.messages.filter(message => message.role === 'error').length, 1);
  await service.close();
  service = await Service.open({ home: directory, config });
  assert.deepEqual((await taskIdle(service)).messages, completed.messages);
  assert.equal(requests, 3);
  assert.deepEqual(failures, []);
  await service.close();
});

test('MCP notifications update availability without rewriting contracts, including discovery during shutdown', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'catalog.json');
  const definition = { name: 'inspect', description: 'Original definition', inputSchema: { type: 'object' } };
  await writeAtomic(filename, { tools: [definition] });
  const config = validateConfig({ ...defaultConfig, mcp: { fixture: {
    command: process.execPath, args: [fileURLToPath(new URL('./fixtures/catalog.mjs', import.meta.url))],
    env: { SELVEDGE_FIXTURE_CATALOG: filename }, timeout_ms: 1000,
  } } });
  let service = await Service.open({ home: directory, config });
  t.after(() => service.close());
  const requests = [];
  service.journal.on('commit', decision => requests.push(...decision.effects.filter(effect => effect.kind === 'model')));
  await service.command({ op: 'create', profile: 'demo', message: 'original task' });
  await taskIdle(service);
  const frozen = requests[0].tools.find(tool => tool.name === 'mcp__fixture__inspect');
  assert.equal(frozen.description, definition.description);
  await writeAtomic(filename, { tools: [] });
  await until('the catalog removal', async () => !(await service.command({ op: 'list' })).reply.result.tools.some(tool => tool.name === frozen.name));
  await service.command({ op: 'send', task_id: 0, message: 'same contract' });
  const settled = await taskIdle(service);
  assert.deepEqual(requests[1].tools.find(tool => tool.name === frozen.name), frozen);
  assert.equal(requests[1].callable.includes(frozen.name), false);
  await service.command({ op: 'create', profile: 'demo', message: 'new task' });
  await taskIdle(service, 1);
  assert.equal(requests[2].tools.some(tool => tool.name === frozen.name), false);
  await writeAtomic(filename, { tools: [], block: true });
  await until('an in-flight catalog discovery', async () => {
    try { return (await readFile(`${filename}.blocked`, 'utf8')).length > 0; }
    catch (error) { if (error.code === 'ENOENT') return false; throw error; }
  });
  const closing = service.close();
  assert.equal(service.close(), closing);
  await closing;
  await writeAtomic(filename, { tools: [] });
  service = await Service.open({ home: directory, config });
  assert.deepEqual((await taskIdle(service)).messages, settled.messages);
  await service.close();
});

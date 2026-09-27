import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { startServer } from '../host/server.mjs';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { events } from '../host/network.mjs';
import { home, taskIdle, responsesServer, shellQuote } from './support.mjs';

test('HTTP, event delivery, CLI discovery, and restart use the native task service', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, port: 0 });
  let running = await startServer({ home: directory, config, cwd: directory });
  t.after(() => running.close());
  const headers = { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' };
  const post = body => fetch(`${running.address}/api/commands`, { method: 'POST', headers, body: JSON.stringify(body) });
  assert.equal((await fetch(`${running.address}/api/health`)).status, 401);
  const page = await fetch(running.address);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /app\.mjs/);
  assert.equal((await fetch(`${running.address}/api/health`, { headers: { ...headers, origin: 'http://untrusted.invalid' } })).status, 403);
  const initial = running.service.journal.sequence;
  assert.equal((await post({ kind: 'model', task_id: 0, ticket: 0, ok: true, items: [] })).status, 400);
  assert.equal(running.service.journal.sequence, initial);
  const created = await post({ op: 'create', profile: 'demo', message: 'hello 世界' });
  assert.equal(created.status, 200);
  const settled = await taskIdle(running.service);
  assert.deepEqual(settled.messages.map(message => message.content), ['hello 世界', '[Offline demo] hello 世界']);
  const sequence = running.service.journal.sequence;
  const read = await post({ op: 'read', task_id: 0 });
  assert.equal((await read.json()).sequence, sequence);
  const controller = new AbortController();
  const stream = await fetch(`${running.address}/api/events?after=0`, { headers, signal: controller.signal });
  const iterator = events(stream.body, running.service.limits.frame_bytes);
  try { assert.deepEqual(JSON.parse((await iterator.next()).value), { type: 'commit', sequence }); }
  finally {
    controller.abort();
    await iterator.return().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
  const eventPage = await fetch(`${running.address}/api/event-page?after=0`, { headers });
  assert.equal((await eventPage.json()).result.at(-1).sequence, sequence);
  const cli = fileURLToPath(new URL('../host/cli.mjs', import.meta.url));
  const described = await promisify(execFile)(process.execPath, [cli, '--home', directory, 'describe'], { timeout: 5000 });
  assert.deepEqual(JSON.parse(described.stdout), running.service.description);
  await running.close();
  running = await startServer({ home: directory, config, cwd: directory });
  assert.deepEqual((await taskIdle(running.service)).messages, settled.messages);
});

test('real model, MCP, and Bash effects start after SQLite commit and are not repeated on restart', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const filename = path.join(directory, 'state', 'journal.sqlite');
  const marker = path.join(directory, 'effects.txt');
  const fixture = fileURLToPath(new URL('./fixtures/committed-tool.mjs', import.meta.url));
  const command = [process.execPath, fixture, filename, marker].map(shellQuote).join(' ');
  const previousKey = process.env.SELVEDGE_FIXTURE_KEY;
  process.env.SELVEDGE_FIXTURE_KEY = 'fixture-not-a-secret';
  t.after(() => {
    if (previousKey === undefined) delete process.env.SELVEDGE_FIXTURE_KEY;
    else process.env.SELVEDGE_FIXTURE_KEY = previousKey;
  });
  const reasoning = { type: 'reasoning', id: 'r1', encrypted_content: 'opaque-fixture', summary: [] };
  const model = await responsesServer(t, (body, index, request) => {
    assert.equal(request.headers.authorization, 'Bearer fixture-not-a-secret');
    const database = new DatabaseSync(filename, { readOnly: true });
    const committed = database.prepare('SELECT decision FROM journal ORDER BY seq').all().flatMap(row => JSON.parse(row.decision).effects);
    database.close();
    assert.ok(committed.some(effect => effect.kind === 'model'));
    if (index === 0) return [reasoning,
      { type: 'function_call', call_id: 'mcp-1', name: 'mcp__fixture__inspect', arguments: JSON.stringify({ text: 'MCP 世界' }) },
      { type: 'function_call', call_id: 'bash-1', name: 'bash', arguments: JSON.stringify({ command }) },
    ];
    assert.ok(index <= 2, 'Only completed operations may wake another model turn');
    assert.deepEqual(body.input.find(item => item.type === 'reasoning'), reasoning);
    const outputs = body.input.filter(item => item.type === 'function_call_output');
    assert.deepEqual(outputs.map(item => item.call_id).sort(), ['bash-1', 'mcp-1']);
    const final = new Map(outputs.map(item => [item.call_id, JSON.parse(item.output)]));
    for (const item of body.input) {
      if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith('Asynchronous operation completed')) {
        const result = JSON.parse(item.content.slice(item.content.indexOf('\n') + 1));
        final.set(result.call_id, result);
      }
    }
    const mcp = final.get('mcp-1');
    const bash = final.get('bash-1');
    if (mcp.value.status !== 'running') { assert.equal(mcp.is_error, false); assert.equal(mcp.value.content[0].text, 'MCP 世界'); }
    if (bash.value.status !== 'running') { assert.equal(bash.is_error, false); assert.equal(bash.value.stdout, 'Bash result 世界 😀'); }
    const finished = mcp.value.status !== 'running' && bash.value.status !== 'running';
    return [{ type: 'message', role: 'assistant', phase: 'final_answer', content: [{ type: 'output_text', text: finished ? 'Both tools completed.' : 'Waiting for the remaining operation.' }] }];
  });
  const config = validateConfig({ ...defaultConfig,
    profiles: { fixture: { provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: 'SELVEDGE_FIXTURE_KEY' } },
    mcp: { fixture: { command: process.execPath, args: [fileURLToPath(new URL('./fixtures/mcp.mjs', import.meta.url))],
      env: { SELVEDGE_FIXTURE_JOURNAL: filename, SELVEDGE_FIXTURE_MARKER: marker }, timeout_ms: 2000 } },
  });
  let service = await Service.open({ home: path.join(directory, 'state'), config, cwd: directory });
  t.after(() => service.close());
  const notices = [];
  service.on('notice', event => notices.push(event));
  const created = await service.command({ op: 'create', profile: 'fixture', message: 'Use both tools.' });
  assert.equal(created.reply.ok, true);
  const settled = await taskIdle(service);
  assert.deepEqual(model.failures, []);
  assert.ok(model.requests.length >= 2 && model.requests.length <= 3);
  const completedRequests = model.requests.length;
  assert.equal(settled.messages.at(-1).content.phase, 'final_answer');
  assert.deepEqual((await readFile(marker, 'utf8')).trim().split('\n').sort(), ['bash', 'mcp']);
  assert.ok(notices.some(event => event.type === 'delta' && event.text === '处理中 😀'));
  await service.close();
  service = await Service.open({ home: path.join(directory, 'state'), config, cwd: directory });
  assert.deepEqual((await taskIdle(service)).messages, settled.messages);
  assert.equal(model.requests.length, completedRequests);
  assert.deepEqual((await readFile(marker, 'utf8')).trim().split('\n').sort(), ['bash', 'mcp']);
});

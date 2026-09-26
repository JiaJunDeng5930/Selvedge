import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { home, taskIdle, responsesServer, shellQuote } from './support.mjs';
import { settings, logs, journal, waitFor, configure, call, answer } from './plugin-support.mjs';

const after = (directory, name, decision = 'allow', extra = {}) => settings(directory, name, 'observer', {
  PLUGIN_AFTER: 'true', PLUGIN_AFTER_MODE: decision, PLUGIN_EVENTS: 'none', ...extra,
});
const read = async (service, task_id = 0) => (await service.command({ op: 'read', task_id })).reply.result;
const delivered = (page, id) => page.messages.findLast(message =>
  ['function_output', 'operation_result'].includes(message.role) && message.call_id === id);

test('after chains cross stdio, native execution, SQLite and provider encoding without exposing raw audit records', { timeout: 20_000 }, async t => {
  const directory = await home(t);
  const secret = 'execution-only-secret-not-in-the-model-request';
  const source = path.join(directory, 'input.txt');
  const marker = path.join(directory, 'executions.txt');
  await writeFile(source, secret);
  const provider = await responsesServer(t, (body, index) => index === 0 ? [
    call('bash', 'shell', { command: `printf x >> ${shellQuote(marker)}; cat ${shellQuote(source)}` }),
    call('plugin__first__echo', 'extension', { text: 'probe' }),
    call('read_task', 'internal', { task_id: 0 }),
  ] : answer);
  const config = configure(provider.endpoint, {
    first: after(directory, 'first', 'redact', { PLUGIN_TOOL_SECRET: secret, PLUGIN_TOOL_ERROR: 'true' }),
    second: after(directory, 'second', 'rewrite'),
  });
  const service = await Service.open({ home: directory, config, cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'live', message: 'Exercise committed result processing' });
  const page = await taskIdle(service);
  assert.equal(await readFile(marker, 'utf8'), 'x');
  const recorded = await logs(directory);
  for (const id of ['shell', 'extension', 'internal']) {
    const callbacks = recorded.filter(line => line.method === 'afterTool' && line.call.id === id);
    assert.deepEqual(callbacks.map(line => line.plugin.name), ['first', 'second']);
    assert.notEqual(callbacks[0].ticket, callbacks[0].operation_id);
    assert.deepEqual(callbacks[1].value, { redacted: true, by: 'first' });
    assert.deepEqual(delivered(page, id).content, { by: 'second', previous: { redacted: true, by: 'first' } });
  }
  assert.equal(delivered(page, 'extension').is_error, true, 'rewriting a failed execution cannot turn it into success');
  const raw = page.messages.find(message => message.role === 'tool_receipt' && message.call.id === 'extension');
  assert.deepEqual(raw.content, { secret });
  assert.equal(raw.is_error, true);
  for (const effect of journal(directory).flatMap(row => row.effects).filter(effect => effect.kind === 'model')) {
    assert.ok(effect.history.every(message => !['tool_receipt', 'after_record'].includes(message.role)));
    assert.equal(JSON.stringify(effect.history).includes(secret), false);
  }
  assert.equal(JSON.stringify(provider.requests).includes(secret), false);
  assert.deepEqual(provider.failures, []);
});

test('invalid, timed-out and crashed after RPCs do not repeat an already-executed tool; JSON null remains a valid rewrite', { timeout: 25_000 }, async t => {
  for (const mode of ['malformed', 'hang', 'crash', 'deny', 'null']) await t.test(mode, async t => {
    const directory = await home(t);
    const marker = path.join(directory, 'executions.txt');
    const provider = await responsesServer(t, (body, index) => index === 0 ? [
      call('bash', 'shell', { command: `printf x >> ${shellQuote(marker)}; printf raw` }),
    ] : answer);
    const config = configure(provider.endpoint, { policy: { ...after(directory, 'policy', mode), timeout_ms: 150 } });
    const service = await Service.open({ home: directory, config, cwd: directory });
    t.after(() => service.close());
    await service.command({ op: 'create', profile: 'live', message: 'Check a plugin boundary failure' });
    const page = await taskIdle(service);
    assert.equal(await readFile(marker, 'utf8'), 'x');
    assert.ok(page.messages.some(message => message.role === 'tool_receipt' && message.content.stdout === 'raw'));
    const result = delivered(page, 'shell');
    if (mode === 'null') {
      assert.equal(result.content, null);
      assert.equal(result.is_error, false);
    } else {
      assert.equal(result.is_error, true);
      assert.equal(result.content.error.code, mode === 'deny' ? 'after_hook_denied' : 'after_hook_failed');
    }
    assert.equal((await logs(directory)).filter(line => line.method === 'afterTool').length, 1);
    assert.deepEqual(provider.failures, []);
  });
});

test('cancelling a result operation addresses its live plugin RPC rather than its retired execution ticket', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const marker = path.join(directory, 'executions.txt');
  const provider = await responsesServer(t, (body, index) => index === 0 ? [
    call('bash', 'shell', { command: `printf x >> ${shellQuote(marker)}` }),
  ] : answer);
  const config = configure(provider.endpoint, { policy: { ...after(directory, 'policy', 'hang'), timeout_ms: 10_000 } });
  const service = await Service.open({ home: directory, config, cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'live', message: 'Cancel result processing' });
  const entries = await waitFor(() => logs(directory), lines => lines.some(line => line.method === 'afterTool'), 'No live result RPC');
  const callback = entries.find(line => line.method === 'afterTool');
  const cancelled = await service.command({ op: 'cancel_operation', task_id: 0, operation_id: callback.operation_id });
  assert.ok(cancelled.effects.some(effect => effect.kind === 'cancel_ticket' && effect.ticket === callback.ticket));
  await waitFor(() => logs(directory), lines => lines.some(line => line.method === 'notifications/cancelled'), 'Plugin RPC did not receive cancellation');
  await taskIdle(service);
  assert.equal(await readFile(marker, 'utf8'), 'x');
});

test('a result callback completing during a real pending provider request preserves that request and its late-result notification', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const gateFile = path.join(directory, 'release-result');
  let releaseModel;
  const modelGate = new Promise(resolve => { releaseModel = resolve; });
  const provider = await responsesServer(t, async (body, index) => {
    if (index === 0) return [call('bash', 'held-result', { command: 'printf late' }), call('bash', 'early-result', { command: 'printf early' })];
    if (index === 1) await modelGate;
    return answer;
  });
  const config = configure(provider.endpoint, { policy: { ...after(directory, 'policy', 'allow',
    { PLUGIN_AFTER_GATE: gateFile }), timeout_ms: 10_000 } });
  const service = await Service.open({ home: directory, config, cwd: directory });
  t.after(async () => { releaseModel(); await service.close(); });
  await service.command({ op: 'create', profile: 'live', message: 'Let results arrive during a model stream' });
  await waitFor(() => provider.requests, requests => requests.length === 2, 'The partial result did not start a real provider request');
  const before = await read(service);
  assert.equal(before.task.phase, 'model_pending');
  assert.equal(before.task.operations.length, 1);
  const modelTicket = journal(directory).flatMap(row => row.effects).filter(effect => effect.kind === 'model').at(-1).ticket;
  await writeFile(gateFile, 'release');
  const settled = await waitFor(() => read(service), page => page.task.operations.length === 0, 'The held result callback did not complete');
  assert.equal(settled.task.phase, 'model_pending');
  assert.equal(provider.requests.length, 2, 'Completion must not start a competing provider request');
  assert.equal(journal(directory).some(row => row.effects.some(effect => effect.kind === 'cancel_ticket' && effect.ticket === modelTicket)), false);
  releaseModel();
  const page = await taskIdle(service);
  assert.equal(delivered(page, 'held-result').content.stdout, 'late');
  assert.equal(delivered(page, 'early-result').content.stdout, 'early');
  assert.equal(provider.requests.length, 3, 'The late result is delivered after the pending response settles');
  assert.deepEqual(provider.failures, []);
});

test('restart preserves a known execution receipt and never repeats an interrupted result callback', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const marker = path.join(directory, 'executions.txt');
  const provider = await responsesServer(t, (body, index) => index === 0 ? [
    call('bash', 'shell', { command: `printf x >> ${shellQuote(marker)}; printf known` }),
  ] : answer);
  const config = configure(provider.endpoint, { policy: { ...after(directory, 'policy', 'hang'), timeout_ms: 10_000 } });
  let service = await Service.open({ home: directory, config, cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'live', message: 'Restore result processing' });
  await waitFor(() => logs(directory), lines => lines.some(line => line.method === 'afterTool'), 'No committed result callback');
  await service.close();
  service = await Service.open({ home: directory, config, cwd: directory });
  const page = await taskIdle(service);
  assert.equal(await readFile(marker, 'utf8'), 'x');
  assert.equal((await logs(directory)).filter(line => line.method === 'afterTool').length, 1);
  assert.ok(page.messages.some(message => message.role === 'tool_receipt' && message.content.stdout === 'known'));
  assert.equal(delivered(page, 'shell').content.error.code, 'after_hook_interrupted');
  assert.deepEqual(provider.failures, []);
});

test('fork callbacks are not replayed in children and a self-archive can settle its own post-commit result callback', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const provider = await responsesServer(t, body => {
    const branch = body.input.find(item => item.type === 'function_call_output' && item.call_id === 'branch');
    if (!branch) return [call('fork_task', 'branch', { child_count: 1 })];
    if (JSON.parse(branch.output).value === 0 && !body.input.some(item => item.type === 'function_call' && item.call_id === 'seal')) {
      return [call('archive_task', 'seal', { task_id: 0 })];
    }
    return answer;
  });
  const config = configure(provider.endpoint, { policy: after(directory, 'policy') });
  const service = await Service.open({ home: directory, config, cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'live', message: 'Fork then archive the parent' });
  const parent = await waitFor(() => read(service), page => page.task.status === 'archived' && page.task.operations.length === 0,
    'Self-archive stranded its result right');
  await taskIdle(service, 1);
  const callbacks = (await logs(directory)).filter(line => line.method === 'afterTool');
  assert.deepEqual(callbacks.map(line => [line.task_id, line.call.id]), [[0, 'branch'], [0, 'seal']]);
  assert.equal(delivered(parent, 'seal').is_error, false);
  const archive = journal(directory).find(row => row.effects.some(effect => effect.kind === 'after_hook' && effect.call.id === 'seal'));
  assert.ok(archive.effects.findIndex(effect => effect.kind === 'cancel') < archive.effects.findIndex(effect => effect.kind === 'after_hook'));
  assert.deepEqual(provider.failures, []);
});

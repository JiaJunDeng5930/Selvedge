import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { Plugin } from '../host/plugins.mjs';
import { Kernel } from '../host/kernel.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, taskIdle, responsesServer, shellQuote } from './support.mjs';

import { fixture, settings, logs, journal, waitFor, configure, call, answer } from './plugin-support.mjs';

test('configured process order defines the unified chain; plugin tools, Bash and internal calls are committed and observable', { timeout: 20_000 }, async t => {
  const directory = await home(t);
  const original = path.join(directory, 'must-not-exist');
  const rewritten = path.join(directory, 'rewritten.txt');
  const provider = await responsesServer(t, (body, index) => index === 0 ? [
    call('bash', 'shell', { command: `touch ${shellQuote(original)}` }),
    call('plugin__rewrite__echo', 'extension', { text: 'original' }),
    call('fork_task', 'denied-fork', { child_count: 2 }),
    call('read_task', 'internal', { task_id: 0 }),
  ] : answer);
  const config = configure(provider.endpoint, {
    slow: settings(directory, 'slow', 'slow_initialize'),
    rewrite: settings(directory, 'rewrite', 'rewrite', { PLUGIN_COMMAND: `printf revised > ${shellQuote(rewritten)}` }),
    observer: settings(directory, 'observer', 'observer'),
  });
  let service = await Service.open({ home: path.join(directory, 'state'), config, cwd: directory });
  t.after(() => service.close());
  const diagnostics = [];
  service.on('notice', event => { if (event.type === 'diagnostic' || event.type === 'fatal') diagnostics.push(event); });
  const created = await service.command({ op: 'create', profile: 'live', message: 'Exercise extensions' });
  assert.equal(created.reply.ok, true);
  const page = await taskIdle(service);
  await access(original).then(() => assert.fail('Original Bash arguments were executed'), error => assert.equal(error.code, 'ENOENT'));
  assert.equal(await readFile(rewritten, 'utf8'), 'revised');
  assert.equal((await service.command({ op: 'list' })).reply.result.tasks.length, 1);
  assert.ok(page.messages.some(message => message.role === 'hook_record' && message.content.decision === 'rewrite'));
  const expectedEvents = journal(directory).flatMap(row => row.effects.filter(effect => effect.kind === 'plugin_events')
    .flatMap(effect => effect.events.flatMap((event, ordinal) => event.recipients.map(reference => `${reference.name}:${row.sequence}:${ordinal}`))));
  const recorded = await waitFor(() => logs(directory), lines => lines.filter(line => line.method === 'event').length >= expectedEvents.length, 'Observers did not receive committed events');
  assert.deepEqual(recorded.filter(line => line.method === 'event').map(line => `${line.plugin}:${line.sequence}:${line.ordinal}`).sort(), expectedEvents.sort());
  for (const id of ['shell', 'extension', 'internal']) {
    assert.deepEqual(recorded.filter(line => line.method === 'beforeTool' && line.call.id === id).map(line => line.plugin.name), ['slow', 'rewrite']);
  }
  assert.deepEqual(recorded.filter(line => line.method === 'beforeTool' && line.call.id === 'denied-fork').map(line => line.plugin.name), ['slow']);
  const executed = recorded.find(line => line.method === 'callTool');
  assert.equal(executed.arguments.text, 'rewritten by native hook chain');
  const events = recorded.filter(line => line.plugin === 'observer' && line.method === 'event');
  assert.ok(events.some(event => event.type === 'model_completed'));
  assert.ok(events.some(event => event.type === 'model_started'));
  assert.ok(events.some(event => event.type === 'task_changed'));
  for (const id of ['shell', 'extension', 'internal', 'denied-fork']) {
    assert.equal(events.filter(event => event.type === 'tool_completed' && event.payload.call_id === id).length, 1, id);
  }
  const extension = events.find(event => event.type === 'tool_completed' && event.payload.call_id === 'extension');
  assert.equal(extension.payload.value.status, 'running', 'a genuine result containing status=running is still a completion');
  assert.equal(extension.payload.error, false);
  assert.equal(events.filter(event => event.type === 'tool_dispatched').length, 2, 'only actual external dispatch is reported');
  assert.deepEqual(provider.failures, []);
  assert.deepEqual(diagnostics, []);
  const before = (await logs(directory)).filter(line => ['beforeTool', 'callTool'].includes(line.method)).length;
  const oldSequence = service.journal.sequence;
  await service.close();
  service = await Service.open({ home: path.join(directory, 'state'), config, cwd: directory });
  await waitFor(() => logs(directory), lines => lines.some(line => line.method === 'event' && line.type === 'recovered' && line.sequence > oldSequence), 'Recovery event missing');
  assert.equal((await logs(directory)).filter(line => ['beforeTool', 'callTool'].includes(line.method)).length, before, 'replay never reinvokes callbacks');
  assert.deepEqual((await taskIdle(service)).messages, page.messages);
});

test('malformed, timed-out and crashed hooks fail closed without dispatching their tools', { timeout: 20_000 }, async t => {
  for (const mode of ['malformed', 'hang', 'crash']) await t.test(mode, async t => {
    const directory = await home(t);
    const marker = path.join(directory, 'forbidden');
    const provider = await responsesServer(t, (body, index) => index === 0 ? [call('bash', 'shell', { command: `touch ${shellQuote(marker)}` })] : answer);
    const config = configure(provider.endpoint, { guard: { ...settings(directory, 'guard', mode), timeout_ms: 120 } });
    const service = await Service.open({ home: path.join(directory, 'state'), config, cwd: directory });
    t.after(() => service.close());
    await service.command({ op: 'create', profile: 'live', message: 'Fail closed' });
    const page = await taskIdle(service);
    assert.ok(page.messages.some(message => message.role === 'hook_record' && message.content.decision === 'failed'));
    assert.equal(page.messages.find(message => message.role === 'function_output').content.error.code, 'hook_failed');
    assert.equal(journal(directory).flatMap(row => row.effects).some(effect => effect.kind === 'tool'), false);
    await access(marker).then(() => assert.fail('Unapproved tool ran'), error => assert.equal(error.code, 'ENOENT'));
    assert.deepEqual(provider.failures, []);
  });
});

test('slow and failing observers cannot delay authorization or roll back work; bounded queues report delivery loss', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const provider = await responsesServer(t, (body, index) => index === 0 ? [call('plugin__slow__echo', 'extension', { text: 'continue independently' })] : answer);
  const config = configure(provider.endpoint, {
    slow: { ...settings(directory, 'slow', 'event_hang'), event_timeout_ms: 100, event_queue: 1 },
    broken: { ...settings(directory, 'broken', 'event_error'), event_timeout_ms: 100, event_queue: 1 },
  });
  const service = await Service.open({ home: path.join(directory, 'state'), config, cwd: directory });
  t.after(() => service.close());
  const notices = [];
  service.on('notice', notice => notices.push(notice));
  await service.command({ op: 'create', profile: 'live', message: 'Observers are not gates' });
  const page = await taskIdle(service);
  assert.ok(page.messages.some(message => message.role === 'function_output' && message.content.text === 'continue independently') ||
    page.messages.some(message => message.role === 'operation_result' && message.content.text === 'continue independently'));
  await waitFor(async () => notices, items => items.some(item => /queue is full/.test(item.message ?? '')) && items.some(item => /observer failed/.test(item.message ?? '')), 'Delivery diagnostics missing');
  assert.equal(notices.some(notice => notice.type === 'fatal'), false);
  assert.equal(journal(directory).filter(row => row.input.kind === 'hook').length, 2);
  assert.deepEqual(provider.failures, []);
});

test('plugin registration rejects unsupported schemas, ambiguous names and invalid manifests without leaving the journal locked', { timeout: 20_000 }, async t => {
  for (const mode of ['unsupported_schema', 'duplicate_tools', 'bad_manifest', 'bad_name', 'missing_name', 'null_name', 'boolean_name']) await t.test(mode, async t => {
    const directory = await home(t);
    const config = validateConfig({ ...defaultConfig, plugins: { guard: settings(directory, 'guard', mode) } });
    await assert.rejects(Service.open({ home: path.join(directory, 'state'), config, cwd: directory }), /Catalog rejected|invalid|collision/i);
    const service = await Service.open({ home: path.join(directory, 'state'), config: validateConfig(defaultConfig), cwd: directory });
    await service.close();
  });
  for (const plugins of [{ 'a-b': { command: 'node' } }, { valid: { command: 'node', event_queue: 0 } }, { valid: { command: 'node', env: { VALUE: 4 } } }]) {
    assert.throws(() => validateConfig({ ...defaultConfig, plugins }), /plugin/i);
  }
});

test('closing a plugin aborts a hung request and reaps the process transport', { timeout: 5000 }, async t => {
  const kernel = new Kernel();
  const description = await kernel.initialize();
  await kernel.close();
  const plugin = new Plugin('hung', { command: process.execPath, args: [fixture], env: { PLUGIN_NAME: 'hung', PLUGIN_MODE: 'hang', PLUGIN_EVENTS: 'none' } }, description.limits, description.plugins);
  t.after(() => plugin.close());
  await plugin.initialize();
  const pending = plugin.before({ task_id: 0, ticket: 1, plugin: { name: 'hung', revision: '1' }, tool: { name: 'bash' }, call: { id: 'call', name: 'bash', arguments: {} } });
  const rejected = assert.rejects(pending, /closed|cancel|stopped/i);
  await plugin.close();
  await rejected;
});

test('Unicode observer payload limits survive serialization to a real plugin, with the durable value accessible by cursor', async t => {
  const directory = await home(t);
  const text = '数据'.repeat(10_000);
  const provider = await responsesServer(t, (body, index) => index === 0 ? [call('plugin__observer__echo', 'large', { text })] : answer);
  const service = await Service.open({ home: path.join(directory, 'state'), config: configure(provider.endpoint,
    { observer: settings(directory, 'observer', 'observer') }), cwd: directory });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'live', message: 'Deliver an oversized observation' });
  await taskIdle(service);
  const delivered = await waitFor(() => logs(directory), records => records.some(record =>
    record.method === 'event' && record.type === 'tool_completed'), 'No observer process received completion');
  const event = delivered.find(record => record.method === 'event' && record.type === 'tool_completed');
  assert.equal(event.payload, null);
  assert.equal(event.payload_omitted, true);
  const page = (await service.command({ op: 'read', task_id: 0, after: event.cursor - 1, limit: 1 })).reply.result;
  assert.equal(page.messages[0].content.text, text);
  assert.deepEqual(provider.failures, []);
});

test('the distributed example registers its real tool and returns schema-compatible deadline rewrites', async t => {
  const directory = await home(t);
  const kernel = new Kernel();
  const description = await kernel.initialize();
  t.after(() => kernel.close());
  const client = new Plugin('audit', {
    command: process.execPath, args: [fileURLToPath(new URL('../examples/plugins/audit.mjs', import.meta.url))],
    cwd: directory, env: { SELVEDGE_BASH_DEADLINE_MS: '1000' },
  }, description.limits, description.plugins);
  t.after(() => client.close());
  const descriptor = await client.initialize();
  const configured = (await kernel.request({ kind: 'configure', profiles: [{ key: 'demo', provider: 'echo', name: 'echo', reasoning_options: null }],
    tools: client.tools, plugins: [descriptor], max_fork: 4, max_descendants: 64 })).value;
  assert.equal(configured.reply.ok, true);
  const rewritten = await client.before({ task_id: 0, ticket: 1, plugin: client.reference, tool: { name: 'bash' },
    call: { id: 'call', name: 'bash', arguments: { command: 'printf hello', timeout_ms: 5000 } } });
  assert.deepEqual(rewritten, { decision: 'rewrite', arguments: { command: 'printf hello', timeout_ms: 1000 } });
  const result = await client.call({ task_id: 0, ticket: 2, tool: { source: { plugin: client.reference, name: 'text_metrics' } },
    call: { id: 'metrics', arguments: { text: 'A中🌍' } } });
  assert.deepEqual(result, { value: { code_points: 3, utf8_bytes: 8 }, error: false });
});

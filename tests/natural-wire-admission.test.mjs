import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { asyncToolResult, home, responsesServer } from './support.mjs';

async function fixture(t, directory, config = {}) {
  const running = await startServer({ home: path.join(directory, 'state'), cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, port: 0, ...config }) });
  t.after(() => running.close());
  const headers = { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' };
  const post = async command => {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST', headers,
      body: typeof command === 'string' ? command : JSON.stringify(command) });
    return response.json();
  };
  const successful = async command => {
    const reply = await post(command);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  return { running, headers, post, successful };
}

test('public integer command fields admit equal JSON number values with their declared bounds', async t => {
  const { running, headers, post, successful } = await fixture(t, await home(t));
  const descriptionReply = await (await fetch(`${running.address}/api/describe`, { headers })).json();
  assert.equal(descriptionReply.ok, true);
  const commands = descriptionReply.result.commands;
  const readFields = commands.find(command => command.name === 'read').schema.properties;
  assert.equal(readFields.task_id.type, 'integer');
  assert.equal(readFields.task_id.minimum, 0);
  assert.equal(readFields.task_id.maximum, 4294967295);
  assert.equal(readFields.limit.minimum, 1);
  assert.equal(readFields.limit.maximum, 100);
  const revision = commands.find(command => command.name === 'configure_title_settings').schema.properties.revision;
  assert.equal(revision.type, 'integer');
  assert.equal(revision.minimum, 0);
  assert.equal(Object.hasOwn(revision, 'maximum'), false);

  const first = await successful({ op: 'create_idle', profile: 'demo' });
  const second = await successful({ op: 'create_idle', profile: 'demo' });
  assert.equal(first.task_id, 0);
  assert.equal(second.task_id, 1);
  for (const [token, id] of [['0.0', 0], ['0e0', 0], ['-0', 0], ['-0.000e+12', 0],
    ['1.0', 1], ['1E+0', 1], ['100e-2', 1], ['0.1e1', 1]]) {
    const canonical = await successful({ op: 'read', task_id: id, after: 0, limit: 1 });
    const same = await successful(`{"op":"read","task_id":${token},"after":-0.0,"limit":0.1e1}`);
    assert.equal(same.task.id, id);
    assert.deepEqual(same.messages, canonical.messages);
  }
  const upper = await post('{"op":"read","task_id":4294967295}');
  assert.equal(upper.ok, false);
  assert.notEqual(upper.error.code, 'command_not_submitted');
  const upperAlias = await post('{"op":"read","task_id":42949672950e-1}');
  assert.equal(upperAlias.error.code, upper.error.code);
  for (const fields of ['"task_id":"1"', '"task_id":-1', '"task_id":1.1',
    '"task_id":1.0000000000000000001', '"task_id":4294967296',
    '"task_id":4294967295.0000000001', '"task_id":0,"after":-1',
    '"task_id":0,"limit":0', '"task_id":0,"limit":101e0']) {
    const refused = await post(`{"op":"read",${fields}}`);
    assert.equal(refused.ok, false, fields);
    assert.equal(refused.error.code, 'command_not_submitted', fields);
  }

  const save = token => `{"op":"configure_title_settings","revision":${token},` +
    '"task_prompt":"Use a short title.","agent_prompt":"Describe the goal."}';
  for (const [token, expected] of [['-0.0', 1], ['0.1e1', 2], ['200e-2', 3]]) {
    await successful(save(token));
    assert.equal((await successful({ op: 'read_title_settings' })).revision, expected);
  }
  const retained = await successful({ op: 'read_title_settings' });
  for (const [canonical, alternate] of [['9007199254740993', '9007199254740993e0'],
    ['9007199254740993', '90071992547409930e-1'],
    ['1000000000000000000000000000000', '1e30']]) {
    const stale = await post(save(canonical));
    assert.equal(stale.ok, false);
    assert.notEqual(stale.error.code, 'command_not_submitted');
    const same = await post(save(alternate));
    assert.equal(same.ok, false);
    assert.equal(same.error.code, stale.error.code);
  }
  for (const token of ['"3"', '-1', '3.1', '3.0000000000000000001']) {
    const refused = await post(save(token));
    assert.equal(refused.ok, false);
    assert.equal(refused.error.code, 'command_not_submitted');
  }
  assert.deepEqual(await successful({ op: 'read_title_settings' }), retained);
});

test('extension integer arguments keep exact value admission through model output and physical RPC', { timeout: 30000 }, async t => {
  const directory = await home(t), log = path.join(directory, 'natural-calls.jsonl');
  await writeFile(log, '');
  const key = `SELVEDGE_NATURAL_WIRE_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-natural-wire';
  t.after(() => { delete process.env[key]; });
  const argumentsFor = (count, offset = '0', index = '2') =>
    `{"count":${count},"offset":${offset},"nested":[{"index":${index}}]}`;
  const examples = [
    ['canonical', argumentsFor('1'), { count: 1, offset: 0, nested: [{ index: 2 }] }],
    ['decimal', argumentsFor('1.0', '-0.0', '2.000'), { count: 1, offset: 0, nested: [{ index: 2 }] }],
    ['exponent', argumentsFor('1e0', '0E+12', '20e-1'), { count: 1, offset: 0, nested: [{ index: 2 }] }],
    ['compensated', argumentsFor('0.7e1', '42949672950e-1', '0.9e1'), { count: 7, offset: 4294967295, nested: [{ index: 9 }] }],
    ['nested-zero', argumentsFor('7', '0', '-0e0'), { count: 7, offset: 0, nested: [{ index: 0 }] }],
    ['string', argumentsFor('"1"')], ['negative', argumentsFor('-1')],
    ['fraction', argumentsFor('1.1')], ['rounded-fraction', argumentsFor('1.0000000000000000001')],
    ['below-minimum', argumentsFor('0')], ['above-maximum', argumentsFor('8e0')],
    ['negative-offset', argumentsFor('1', '-1')], ['offset-overflow', argumentsFor('1', '4294967296')],
    ['rounded-boundary', argumentsFor('1', '4294967295.0000000001')],
    ['nested-fraction', argumentsFor('1', '0', '0.1')],
    ['nested-overflow', argumentsFor('1', '0', '10')], ['nested-string', argumentsFor('1', '0', '"2"')],
  ];
  const seen = new Map();
  let issued = false;
  const upstream = await responsesServer(t, body => {
    for (const item of body.input) {
      if (item.type === 'function_call_output') seen.set(item.call_id, JSON.parse(item.output));
      const result = asyncToolResult(item);
      if (result) seen.set(result.call_id, result);
    }
    if (issued) return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'The argument checks are recorded.' }] }];
    issued = true;
    const tool = body.tools.find(tool => tool.name === 'plugin__natural__capture');
    assert.ok(tool, 'The real model request advertises the registered extension');
    return examples.map(([id, arguments_]) => ({ type: 'function_call', call_id: id,
      name: tool.name, arguments: arguments_ }));
  });
  const { successful } = await fixture(t, directory, {
    profiles: { fixture: { provider: 'responses', model: 'natural-argument-model', endpoint: upstream.endpoint, api_key_env: key } },
    plugins: { natural: { command: process.execPath,
      args: [fileURLToPath(new URL('./fixtures/natural-parameter-plugin.mjs', import.meta.url)), log] } },
  });
  const { task_id } = await successful({ op: 'create', profile: 'fixture', message: 'Capture the declared integer argument cases.' });
  const terminal = id => seen.has(id) && seen.get(id).value?.status !== 'running';
  const deadline = Date.now() + 20000;
  let page;
  do {
    assert.deepEqual(upstream.failures, []);
    page = await successful({ op: 'read', task_id });
    if (examples.every(([id]) => terminal(id)) && page.task.phase === 'idle' && page.task.operations.length === 0) break;
    await delay(20);
  } while (Date.now() < deadline);
  assert.deepEqual(upstream.failures, []);
  assert.equal(issued, true);
  assert.equal(page.task.phase, 'idle');
  assert.equal(page.task.operations.length, 0);
  const calls = (await readFile(log, 'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);
  assert.deepEqual(calls.map(call => call.context.call_id).sort(),
    examples.filter(([, , expected]) => expected !== undefined).map(([id]) => id).sort());
  for (const [id, , expected] of examples) {
    assert.equal(terminal(id), true, `The public workflow did not settle ${id}`);
    assert.equal(seen.get(id).is_error, expected === undefined, id);
    if (expected !== undefined) {
      assert.deepEqual(calls.find(call => call.context.call_id === id).arguments, expected, id);
      assert.deepEqual(seen.get(id).value, expected, id);
    }
  }
});

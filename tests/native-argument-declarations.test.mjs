import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];

test('public title settings cross the UTF-8 boundary while model requests exclude owner management', async t => {
  const directory = await home(t);
  const key = `SELVEDGE_ARGUMENT_DECLARATION_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  const taskPrompt = '请用简短中文为任务命名。';
  const agentPrompt = '请概括这段对话的主要目标。';
  let advertised;
  let sent = false;
  const upstream = await responsesServer(t, body => {
    if (sent) return done;
    sent = true;
    advertised = body.tools.find(tool => tool.name === 'configure_title_settings');
    assert.equal(advertised, undefined, 'The real model request excludes owner title management');
    return [{ type: 'function_call', call_id: 'native-title-settings', name: 'configure_title_settings',
      arguments: JSON.stringify({ revision: 1, task_prompt: taskPrompt, agent_prompt: agentPrompt }) }];
  });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false,
    profiles: { fixture: { provider: 'responses', model: 'argument-declaration-fixture', endpoint: upstream.endpoint, api_key_env: key } },
  }) });
  t.after(() => service.close());
  const command = async input => (await service.command(input)).reply;
  const read = async () => {
    const reply = await command({ op: 'read_title_settings' });
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };

  const publicTaskPrompt = '为任务保留清楚的标题。';
  const publicSaved = await command({ op: 'configure_title_settings', revision: 0,
    task_prompt: publicTaskPrompt, agent_prompt: agentPrompt });
  assert.equal(publicSaved.ok, true, JSON.stringify(publicSaved));
  assert.deepEqual(await read(), { revision: 1, task_prompt: publicTaskPrompt, agent_prompt: agentPrompt });
  const created = await command({ op: 'create', profile: 'fixture', message: 'Configure the title instructions through the native tool.' });
  assert.equal(created.ok, true, JSON.stringify(created));
  await taskIdle(service, created.result.task_id);
  assert.deepEqual(upstream.failures, []);
  assert.equal(advertised, undefined);
  assert.deepEqual(await read(), { revision: 1, task_prompt: publicTaskPrompt, agent_prompt: agentPrompt });

  const remote = service.description.commands.find(command => command.name === 'remote_grant');
  assert.ok(remote, 'The public command vocabulary declares remote controller grants');
  const controller = remote.schema.properties.controller_id;
  assert.equal(controller.minLength, 64);
  assert.equal(controller.maxLength, 64);
  assert.equal(new RegExp(controller.pattern).test('a'.repeat(64)), true);
  assert.equal(new RegExp(controller.pattern).test('A'.repeat(64)), false);
});


test('extension registration and invocation share the closed bounded natural dialect', async t => {
  const directory = await home(t);
  const peer = path.join(directory, 'argument-declaration-peer.mjs');
  const log = path.join(directory, 'arguments.json');
  await writeFile(peer, String.raw`
import { writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
const log = process.argv[2];
createInterface({ input: process.stdin }).on('line', line => {
  const request = JSON.parse(line);
  if (!Object.hasOwn(request, 'id')) return;
  const result = request.method === 'initialize'
    ? { protocolVersion: request.params.protocolVersion, revision: 'argument-declaration-1',
        beforeTool: false, afterTool: false, events: [], tools: [{ name: 'echo',
          description: 'Record an integer admitted by a maximum-only extension declaration.',
          inputSchema: { type: 'object', properties: { count: { type: 'integer', maximum: 9 } }, required: ['count'] } }] }
    : (writeFileSync(log, JSON.stringify(request.params.arguments)), { error: false, value: 'RECORDED' });
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: request.id, result }) + '\n');
});
`);
  const key = `SELVEDGE_EXTERNAL_DECLARATION_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  const arguments_ = { count: 7 };
  let sent = false;
  const upstream = await responsesServer(t, () => {
    if (sent) return done;
    sent = true;
    return [{ type: 'function_call', call_id: 'external-schema', name: 'plugin__declaration__echo',
      arguments: JSON.stringify(arguments_) }];
  });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false,
    profiles: { fixture: { provider: 'responses', model: 'external-declaration-fixture', endpoint: upstream.endpoint, api_key_env: key } },
    plugins: { declaration: { command: process.execPath, args: [peer, log] } },
  }) });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'fixture', message: 'Call the registered extension echo tool.' });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  await taskIdle(service, created.reply.result.task_id);
  assert.deepEqual(upstream.failures, []);
  assert.equal(sent, true);
  assert.deepEqual(JSON.parse(await readFile(log, 'utf8')), arguments_);
});

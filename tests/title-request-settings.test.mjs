import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

test('an adaptive Task generates its independent title with default reasoning and no title evaluation', async t => {
  const directory = await home(t), modelRequests = [], evaluations = [], failures = [];
  const suffix = randomBytes(8).toString('hex');
  const modelKey = `SELVEDGE_TITLE_MODEL_${suffix}`, evaluatorKey = `SELVEDGE_TITLE_EVALUATOR_${suffix}`;
  process.env[modelKey] = 'title-model-fixture';
  process.env[evaluatorKey] = 'title-evaluator-fixture';
  t.after(() => { delete process.env[modelKey]; delete process.env[evaluatorKey]; });
  const evaluator = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      evaluations.push(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ model: 'test-jev', provider: 'TypeSafe', answers: {
        effort: { type: 'choice', choice: 'high' }, lease: { type: 'choice', choice: '1' },
      } }));
    // DEFENSE: A malformed evaluator HTTP request must fail the fixture instead of leaving a real Task waiting.
    })().catch(error => { failures.push(error); response.writeHead(500); response.end('fixture failure'); });
  });
  await new Promise((resolve, reject) => { evaluator.once('error', reject); evaluator.listen(0, '127.0.0.1', resolve); });
  t.after(async () => { evaluator.closeAllConnections(); await new Promise(resolve => evaluator.close(resolve)); });
  const model = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: 'The requested Task is complete.' }] }],
  { observeRequest: body => modelRequests.push(body) });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, reasoning_evaluators: { jev: { provider: 'openrouter', model: 'test-jev',
      endpoint: `http://127.0.0.1:${evaluator.address().port}/decision`, api_key_env: evaluatorKey, timeout_ms: 1000, max_attempts: 1 } },
    profiles: { adaptive: { provider: 'responses', model: 'adaptive-title-task', endpoint: model.endpoint, api_key_env: modelKey,
      adaptive_reasoning: { evaluator: 'jev', efforts: ['low', 'high'], baseline: 'low', transport: 'request_effort', max_lease: 1 } } },
  }) });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'adaptive', reasoning: 'auto',
    message: 'Complete this ordinary Task and give it a short independent title.' });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  await taskIdle(service, created.reply.result.task_id);
  const deadline = Date.now() + 5000;
  let read;
  do {
    read = await service.command({ op: 'read', task_id: created.reply.result.task_id });
    assert.equal(read.reply.ok, true, JSON.stringify(read.reply));
    if (read.reply.result.task.title === 'Name the task') break;
    await delay(10);
  } while (Date.now() < deadline);
  const titles = modelRequests.filter(body => body.text?.format?.name === 'task_title');
  assert.equal(titles.length, 1, 'The actual model endpoint receives one independent title request');
  assert.equal(Object.hasOwn(titles[0], 'reasoning'), false, 'Default reasoning leaves the upstream reasoning option unspecified');
  assert.equal(model.requests.length, 1);
  assert.equal(model.requests[0].reasoning.effort, 'high', 'The actual Task still uses its evaluator-selected reasoning');
  assert.equal(evaluations.length, 1, 'The evaluator serves the Task, never its independent title generation');
  assert.equal(read.reply.result.task.title, 'Name the task', 'The public read exposes the title returned by the independent provider');
  assert.deepEqual(failures, []);
  assert.deepEqual(model.failures, []);
});

test('Agent session title settings route only title requests and persist across a service restart', async t => {
  const directory = await home(t), suffix = randomBytes(8).toString('hex');
  const mainKey = `SELVEDGE_MAIN_MODEL_${suffix}`, titleKey = `SELVEDGE_AGENT_TITLE_MODEL_${suffix}`;
  process.env[mainKey] = 'main-model-fixture';
  process.env[titleKey] = 'agent-title-model-fixture';
  t.after(() => { delete process.env[mainKey]; delete process.env[titleKey]; });

  const mainRequests = [], titleRequests = [];
  const main = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: 'The requested Task is complete.' }] }], {
    observeRequest: (body, request) => { if (!request.url.endsWith('/input_tokens')) mainRequests.push(body); },
  });
  const title = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: 'This endpoint serves title requests only.' }] }], {
    observeRequest: (body, request) => { if (!request.url.endsWith('/input_tokens')) titleRequests.push(body); },
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    main: { provider: 'responses', model: 'main-task-model', endpoint: main.endpoint, api_key_env: mainKey },
    'agent-title': { provider: 'responses', model: 'agent-session-title-model', endpoint: title.endpoint, api_key_env: titleKey },
  } });
  const open = () => Service.open({ home: directory, cwd: directory, config });
  let service = await open();
  t.after(() => service?.close());
  const command = async input => (await service.command(input)).reply;
  const readSettings = async () => {
    const reply = await command({ op: 'read_title_settings' });
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const createTask = async message => {
    const created = await command({ op: 'create', profile: 'main', message });
    assert.equal(created.ok, true, JSON.stringify(created));
    await taskIdle(service, created.result.task_id);
    return command({ op: 'read', task_id: created.result.task_id });
  };

  const initial = await readSettings();
  assert.equal(initial.agent_profile, null, 'The default title model is automatic');
  const saved = await command({ op: 'configure_title_settings', revision: initial.revision,
    task_prompt: initial.task_prompt, agent_prompt: initial.agent_prompt, agent_profile: 'agent-title' });
  assert.equal(saved.ok, true, JSON.stringify(saved));
  assert.equal((await readSettings()).agent_profile, 'agent-title');

  await service.close();
  service = await open();
  assert.equal((await readSettings()).agent_profile, 'agent-title', 'The selected connection survives a service restart');
  const selectedTask = await createTask('Complete a task with a separately configured title model.');
  assert.equal(selectedTask.ok, true, JSON.stringify(selectedTask));
  assert.equal(selectedTask.result.task.title, 'Name the task');
  assert.equal(mainRequests.filter(body => body.text?.format?.name === 'task_title').length, 0,
    'A selected title connection receives no title request through the Task connection');
  assert.equal(mainRequests.filter(body => body.text?.format?.name !== 'task_title').length, 1);
  assert.equal(mainRequests.find(body => body.text?.format?.name !== 'task_title').model, 'main-task-model',
    'The main Task continues to use its own configured connection');
  assert.equal(titleRequests.filter(body => body.text?.format?.name === 'task_title').length, 1,
    'The configured title connection receives the Agent session title request');
  assert.equal(titleRequests.find(body => body.text?.format?.name === 'task_title').model, 'agent-session-title-model');

  const current = await readSettings();
  const automatic = await command({ op: 'configure_title_settings', revision: current.revision,
    task_prompt: current.task_prompt, agent_prompt: current.agent_prompt });
  assert.equal(automatic.ok, true, JSON.stringify(automatic));
  assert.equal((await readSettings()).agent_profile, null, 'Omitting the optional connection restores automatic selection');
  await createTask('Complete another task after restoring automatic title selection.');
  assert.equal(mainRequests.filter(body => body.text?.format?.name !== 'task_title').length, 2);
  assert.equal(mainRequests.filter(body => body.text?.format?.name === 'task_title').length, 1,
    'Automatic selection returns title generation to the Task connection');
  assert.equal(titleRequests.filter(body => body.text?.format?.name === 'task_title').length, 1,
    'The selected title connection is no longer used after automatic selection is restored');
  assert.deepEqual(main.failures, []);
  assert.deepEqual(title.failures, []);
});

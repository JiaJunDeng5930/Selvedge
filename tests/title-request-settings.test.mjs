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
  while (!modelRequests.some(body => body.text?.format?.name === 'task_title') && Date.now() < deadline) await delay(10);
  const titles = modelRequests.filter(body => body.text?.format?.name === 'task_title');
  assert.equal(titles.length, 1, 'The actual model endpoint receives one independent title request');
  assert.equal(Object.hasOwn(titles[0], 'reasoning'), false, 'Default reasoning leaves the upstream reasoning option unspecified');
  assert.equal(model.requests.length, 1);
  assert.equal(model.requests[0].reasoning.effort, 'high', 'The actual Task still uses its evaluator-selected reasoning');
  assert.equal(evaluations.length, 1, 'The evaluator serves the Task, never its independent title generation');
  assert.deepEqual(failures, []);
  assert.deepEqual(model.failures, []);
});

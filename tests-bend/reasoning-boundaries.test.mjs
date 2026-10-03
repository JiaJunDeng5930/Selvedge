import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';
import { providerInput, responseBody } from '../host/providers.mjs';

const policy = (transport = 'configuration_update', extra = {}) => ({ evaluator: 'separate-evaluator',
  efforts: ['low', 'medium', 'high'], baseline: 'medium', transport, max_lease: 10, ...extra });
const profile = (adaptive = policy()) => ({ key: 'automatic', provider: 'responses', name: 'a-manually-configured-model', adaptive_reasoning: adaptive });
const readCall = (id, task_id = 0) => ({ type: 'call', id, name: 'read_task', arguments: { task_id, after: 0, limit: 1 } });
const effect = (decision, kind, task = 0) => {
  const found = decision.effects.find(item => item.kind === kind && item.task_id === task);
  assert.ok(found, `Expected ${kind} for task ${task}: ${JSON.stringify(decision)}`);
  return found;
};

async function kernel(t, adaptive = policy()) {
  const k = new Kernel({ timeout: 5000 });
  t.after(() => k.close());
  await k.initialize();
  const send = async input => (await k.request(input)).value;
  const command = command => send({ kind: 'command', command });
  const configured = await send({ kind: 'configure', profiles: [
    { key: 'fixed', provider: 'responses', name: 'ordinary-model' }, profile(adaptive),
  ], tools: [], max_fork: 4, max_descendants: 8 });
  assert.equal(configured.reply.ok, true, JSON.stringify(configured));
  return { send, command,
    page: async (id = 0) => {
      const result = await command({ op: 'read', task_id: id });
      assert.equal(result.reply.ok, true, JSON.stringify(result));
      return result.reply.result;
    },
    create: () => command({ op: 'create', profile: 'automatic', message: 'Complete the original task, preserving its constraints.' }),
    choose: (pending, effort = 'low', generations = 2) => send({ kind: 'reasoning', task_id: pending.task_id, ticket: pending.ticket, ok: true, effort, generations }),
    model: (pending, items = [{ type: 'text', text: 'Finished.' }]) => send({ kind: 'model', task_id: pending.task_id, ticket: pending.ticket, ok: true, items }),
  };
}

test('Bend-generated JavaScript generation records encode exact Responses prefixes and never leak audit records into provider input', async t => {
  const k = await kernel(t);
  const pending = effect(await k.create(), 'reasoning');
  const first = effect(await k.choose(pending, 'low', 2), 'model');
  const firstInput = providerInput(first.history);
  assert.deepEqual(firstInput.at(-1), { type: 'configuration_update', reasoning: { effort: 'low' } });
  const second = effect(await k.model(first, [readCall('read-one'), readCall('read-two')]), 'model');
  assert.deepEqual(providerInput(second.history).slice(0, firstInput.length), firstInput);
  const exhausted = await k.model(second, [readCall('read-three')]);
  const again = effect(exhausted, 'reasoning');
  const third = effect(await k.choose(again, 'high', 1), 'model');
  assert.deepEqual(providerInput(third.history).slice(0, providerInput(second.history).length), providerInput(second.history));
  assert.deepEqual(providerInput(third.history).at(-1), { type: 'configuration_update', reasoning: { effort: 'high' } });
  const body = responseBody(third, { provider: 'responses' });
  assert.equal(body.reasoning.effort, 'medium');
  assert.ok(!body.input.some(item => item.role === 'reasoning_record'));
  assert.ok(!body.input.some((item, index) => item.type === 'configuration_update' && body.input[index + 1]?.type === 'configuration_update'));
});

test('request-effort transport is independent of ChatGPT and never emits a configuration update', async t => {
  const k = await kernel(t, policy('request_effort'));
  const first = effect(await k.choose(effect(await k.create(), 'reasoning'), 'high', 1), 'model');
  assert.equal(responseBody(first).reasoning.effort, 'high');
  assert.ok(!providerInput(first.history).some(item => item.type === 'configuration_update'));
  const pending = effect(await k.model(first, [readCall('next')]), 'reasoning');
  const second = effect(await k.choose(pending, 'low', 1), 'model');
  assert.equal(responseBody(second).reasoning.effort, 'low');
  assert.ok(!providerInput(second.history).some(item => item.type === 'configuration_update'));
});

test('Bend-generated JavaScript evaluator wire omits private continuation even when it is nested inside a tool result', async t => {
  const k = await kernel(t);
  const first = effect(await k.choose(effect(await k.create(), 'reasoning'), 'low', 10), 'model');
  const result = await k.model(first, [
    { type: 'context', value: { type: 'reasoning', encrypted_content: 'PRIVATE-CONTINUATION-NEVER-FOR-JEV',
      summary: [{ type: 'summary_text', text: 'Public progress summary.' }] } },
    { ...readCall('self-with-private-history'), arguments: { task_id: 0, after: 0, limit: 32 } }, readCall('missing', 999),
  ]);
  const pending = effect(result, 'reasoning');
  assert.equal(JSON.stringify(pending).includes('PRIVATE-CONTINUATION-NEVER-FOR-JEV'), false);
  assert.ok(JSON.stringify(pending).includes('Public progress summary.'));
  assert.ok(pending.history.some(item => item.role === 'function_output' && item.is_error));
  assert.ok((await k.page()).messages.some(item => item.role === 'model_context'));
});


import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';
import { parseJson, stringifyJson, JsonNumber } from '../host/codec.mjs';

const remote = { name: 'mcp__fixture__inspect', description: 'Inspect input', schema: { type: 'object' }, server: 'fixture', remote: 'inspect' };

async function kernel(t, overrides = {}) {
  const k = new Kernel({ timeout: 5000 });
  t.after(() => k.close());
  await k.initialize();
  const send = async input => (await k.request(input)).value;
  const command = body => send({ kind: 'command', command: body });
  const configure = config => send({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model' }], tools: [], max_fork: 4, max_descendants: 8, ...config });
  assert.equal((await configure(overrides)).reply.ok, true);
  return { k, send, command, configure };
}

function model(task_id, ticket, text = 'done', calls = []) {
  return { kind: 'model', task_id, ticket, ok: true,
    items: [...(text ? [{ type: 'text', text }] : []), ...calls.map(call => ({ type: 'call', ...call }))] };
}

test('compiled native transport preserves Unicode, embedded controls and exact JSON numeric lexemes', async t => {
  const { k, send, command } = await kernel(t, { tools: [remote] });
  const text = 'hello\n"\\\0 世界 😀';
  const created = await command({ op: 'create', profile: 'fixture', message: text });
  assert.equal(created.effects[0].history[0].content, text);
  const arguments_ = parseJson('{"huge":9007199254740993,"fraction":1.2300,"nested":[null,true,{"0":"x"}]}');
  const result = await send(model(0, 0, '', [{ id: 'inspect', name: remote.name, arguments: arguments_ }]));
  assert.equal(result.effects[0].kind, 'tool');
  assert.equal(stringifyJson(result.effects[0].call.arguments), stringifyJson(arguments_));
  await send({ kind: 'tool', task_id: 0, ticket: 1, value: arguments_, error: false });
  const page = await command({ op: 'read', task_id: 0 });
  const output = page.reply.result.messages.find(x => x.role === 'function_output');
  assert.ok(output.content.huge instanceof JsonNumber);
  assert.equal(output.content.huge.source, '9007199254740993');
  assert.equal(page.durable, false);
  assert.deepEqual(page.effects, []);
  assert.equal((await command({ op: 'read', task_id: 0, limit: 0 })).reply.ok, false);
  assert.equal((await command({ op: 'create', profile: 'fixture', message: 'x', unknown: 1 })).reply.ok, false);
});

test('native hook envelopes reject unknown authority fields and malformed identities at the process boundary', async t => {
  const { send } = await kernel(t);
  for (const packet of [
    { kind: 'hook', task_id: 0, ticket: 0, outcome: { decision: 'rewrite', arguments: {}, name: 'bash' } },
    { kind: 'hook', task_id: 0, ticket: 0, outcome: { decision: 'allow', value: 'not an argument decision' } },
    { kind: 'after_hook', task_id: 0, operation_id: 0, ticket: 1, outcome: { decision: 'rewrite', value: null, error: false } },
    { kind: 'after_hook', task_id: 0, operation_id: 0, ticket: 1, outcome: { decision: 'rewrite' } },
    { kind: 'after_hook', task_id: 0, operation_id: 0, ticket: 1, outcome: { decision: 'allow', arguments: {} } },
    { kind: 'after_hook', task_id: 0, operation_id: -1, ticket: 1, outcome: { decision: 'allow' } },
    { kind: 'after_hook', task_id: 0, operation_id: 0, ticket: '1', outcome: { decision: 'allow' } },
    { kind: 'after_hook', task_id: 0, ticket: 1, outcome: { decision: 'allow' } },
  ]) {
    const result = await send(packet);
    assert.equal(result.reply.ok, false, JSON.stringify(packet));
    assert.deepEqual(result.effects, []);
  }
  // A JSON null value is present, unlike a missing property. The unknown
  // operation is immaterial: this assertion distinguishes wire validation.
  assert.equal((await send({ kind: 'after_hook', task_id: 0, operation_id: 0, ticket: 1,
    outcome: { decision: 'rewrite', value: null } })).reply.ok, true);
});

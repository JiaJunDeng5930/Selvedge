import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { validateConfig, defaultConfig } from '../host/config.mjs';
import { home, taskIdle, responsesServer } from './support.mjs';
import { longRunningCommand, readHostPid } from './process-identity.mjs';

const call = (id, command) => ({ type: 'function_call', call_id: id, name: 'bash', arguments: JSON.stringify({ command }) });
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

async function eventual(predicate, message) {
  const deadline = Date.now() + 6000;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await delay(10);
  }
  assert.fail(message);
}

async function pidFile(directory, name) {
  return eventual(() => readHostPid(directory, name), `Missing process identity ${name}`);
}

async function gone(pid) {
  return eventual(() => {
    try { process.kill(pid, 0); return false; }
    catch (error) { if (error.code !== 'ESRCH') throw error; return true; }
  }, `The cancelled process ${pid} survived`);
}

async function fixture(t, directory, handler) {
  const name = `SELVEDGE_ASYNC_${process.pid}_${Math.random().toString(16).slice(2)}`;
  process.env[name] = 'fixture-not-a-secret';
  t.after(() => { delete process.env[name]; });
  const model = await responsesServer(t, handler);
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env: name,
  } } });
  const service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  return { model, service };
}

test('real same-task Bash commands overlap and a partial result can resume the model before its sibling completes', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  let sawPartial = false;
  const { model, service } = await fixture(t, directory, async (body, index) => {
    assert.equal(body.parallel_tool_calls, true);
    if (index === 0) return [
      call('left', 'printf left > left.started; while [ ! -f right.started ]; do sleep 0.01; done; printf left-result'),
      call('right', 'printf right > right.started; while [ ! -f release.right ]; do sleep 0.01; done; printf right-result'),
    ];
    if (index === 1) {
      const results = new Map(body.input.filter(item => item.type === 'function_call_output')
        .map(item => [item.call_id, JSON.parse(item.output)]));
      assert.equal(results.get('left').value.stdout, 'left-result');
      assert.equal(results.get('right').value.status, 'running');
      assert.equal(await readFile(path.join(directory, 'right.started'), 'utf8'), 'right');
      sawPartial = true;
      await writeFile(path.join(directory, 'release.right'), 'release only after the partial model request');
      return answer('The left command completed; the right operation is still running.');
    }
    assert.equal(index, 2);
    assert.ok(body.input.some(item => item.role === 'user' && item.content.includes('Asynchronous operation completed') && item.content.includes('right-result')));
    return answer('Both commands completed.');
  });
  await service.command({ op: 'create', profile: 'fixture', message: 'Run independent work concurrently.' });
  const page = await taskIdle(service, 0, 8000);
  assert.equal(sawPartial, true);
  assert.equal(model.requests.length, 3);
  assert.deepEqual(model.failures, []);
  assert.equal(page.messages.filter(message => message.role === 'operation_result').length, 1);
  assert.deepEqual(page.task.operations, []);
});

test('real operation cancellation and model steering preserve an unrelated running process', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  let releaseOld;
  const oldRequest = new Promise(resolve => { releaseOld = resolve; });
  t.after(() => releaseOld());
  const { model, service } = await fixture(t, directory, async (_, index) => {
    if (index === 0) return [call('left', longRunningCommand('left.pid')),
      call('right', longRunningCommand('right.pid'))];
    if (index === 1) { await oldRequest; return answer('STALE MODEL REPLY MUST NOT APPEAR'); }
    if (index === 2) { releaseOld(); return answer('The higher-priority instruction is current.'); }
    assert.equal(index, 3);
    return answer('All requested cancellation is settled.');
  });
  await service.command({ op: 'create', profile: 'fixture', message: 'Start two independent long operations.' });
  const leftPid = await pidFile(directory, 'left.pid');
  const rightPid = await pidFile(directory, 'right.pid');
  const page = async () => (await service.command({ op: 'read', task_id: 0 })).reply.result;
  const operations = (await page()).task.operations;
  assert.equal(operations.length, 2);
  const first = await service.command({ op: 'cancel_operation', task_id: 0, operation_id: operations[0].operation_id });
  assert.equal(first.reply.ok, true);
  await gone(leftPid);
  process.kill(rightPid, 0);
  await eventual(() => model.requests.length === 2, 'The partial cancellation did not resume the model');
  assert.equal((await service.command({ op: 'steer', task_id: 0, message: 'Use this instruction instead.' })).reply.ok, true);
  await eventual(async () => (await page()).task.phase === 'idle', 'Steered model reply did not settle');
  process.kill(rightPid, 0);
  assert.equal((await page()).task.operations.length, 1);
  const last = await service.command({ op: 'cancel_operation', task_id: 0, operation_id: operations[1].operation_id });
  assert.equal(last.reply.ok, true);
  await gone(rightPid);
  const settled = await taskIdle(service, 0, 6000);
  assert.equal(JSON.stringify(settled).includes('STALE MODEL REPLY'), false);
  assert.deepEqual(model.failures, []);
  assert.equal(model.requests.length, 4);
});

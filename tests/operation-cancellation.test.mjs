import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, shellQuote, taskIdle } from './support.mjs';

const continuation = 'I continued after the cancellation.';
const message = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

async function fixture(t, makeScenario) {
  const root = await home(t);
  const workspace = path.join(root, 'workspace');
  await mkdir(workspace);
  const { command, ...scenario } = makeScenario({ root, workspace });

  const apiKey = `SELVEDGE_OPERATION_CANCEL_${randomBytes(8).toString('hex').toUpperCase()}`;
  const previous = process.env[apiKey];
  process.env[apiKey] = 'loopback-fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[apiKey]; else process.env[apiKey] = previous; });

  const arguments_ = {
    command,
    sandbox_permissions: 'require_escalated',
    justification: 'Run the requested cancellation fixture.',
    timeout_ms: 30000,
  };
  const upstream = await responsesServer(t, (_, index) => index === 0
    ? [{ type: 'function_call', call_id: 'cancel-operation', name: 'bash', arguments: JSON.stringify(arguments_) }]
    : message(continuation));
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    worker: { provider: 'responses', model: 'worker-model', endpoint: upstream.endpoint, api_key_env: apiKey },
  } });
  const service = await Service.open({ home: path.join(root, 'state'), cwd: workspace, config });
  t.after(() => service.close());

  const created = await service.command({ op: 'create', profile: 'worker', message: 'Run the requested command.', settings: {
    workspace: { roots: [workspace], primary_root: workspace },
    approval: { mode: 'ask-for-approval' },
  } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  return { service, taskId: created.reply.result.task_id, arguments: arguments_, upstream, workspace, ...scenario };
}

async function readTask(service, taskId) {
  const result = await service.command({ op: 'read', task_id: taskId });
  assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
  return result.reply.result;
}

async function waitForOperation(service, taskId, accepts) {
  const deadline = Date.now() + 10000;
  let page;
  do {
    page = await readTask(service, taskId);
    const operation = page.task.operations.find(accepts);
    if (operation) return { page, operation };
    await delay(10);
  } while (Date.now() < deadline);

  // DEFENSE: A provider or executor regression can fail to expose the public operation state required by this acceptance.
  assert.fail(`Expected operation state was not reached: ${JSON.stringify(page?.task)}`);
}

async function waitForFile(file) {
  const deadline = Date.now() + 10000;
  do {
    try {
      await access(file);
      return;
    } catch (error) {
      // DEFENSE: ENOENT is the expected state until the approved child process creates its start marker.
      if (error.code !== 'ENOENT') throw error;
    }
    await delay(10);
  } while (Date.now() < deadline);
  assert.fail(`Approved command did not create its start marker: ${file}`);
}

function assertContinued(page, upstream) {
  assert.equal(page.task.phase, 'idle');
  assert.deepEqual(page.task.operations, []);
  assert.ok(upstream.requests.length > 1, 'The provider must receive another turn after cancellation');
  assert.ok(page.messages.some(entry => entry.role === 'model_context'
    && entry.content?.item?.content?.some(part => part.text === continuation)));
}

test('cancelling an approval-pending operation reports that it never ran and continues the task', async t => {
  const { service, taskId, arguments: arguments_, upstream, marker } = await fixture(t, ({ workspace }) => {
    const marker = path.join(workspace, 'must-not-exist');
    return { command: `printf unexpected > ${shellQuote(marker)}`, marker };
  });
  const { operation } = await waitForOperation(service, taskId, value => value.status === 'awaiting_approval');

  assert.equal(operation.announced, false);
  assert.deepEqual(operation.arguments, arguments_);
  const cancelled = await service.command({ op: 'cancel_operation', task_id: taskId, operation_id: operation.operation_id });
  assert.equal(cancelled.reply.ok, true, JSON.stringify(cancelled.reply));
  assert.deepEqual(cancelled.reply.result, { task_id: taskId, operation_id: operation.operation_id });

  const page = await taskIdle(service, taskId);
  const outcome = page.messages.find(entry => entry.role === 'function_output' && entry.content?.error?.code === 'cancelled');
  assert.ok(outcome, 'The task history must say that cancellation was applied');
  assert.match(outcome.content.error.message, /did not start and made no external changes/);
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  assertContinued(page, upstream);
  assert.deepEqual(upstream.failures, []);
});

test('an approved executing operation retains its announcement, ticket and arguments when cancelled', async t => {
  const { service, taskId, arguments: arguments_, upstream, ready, release, completed } = await fixture(t, ({ workspace }) => {
    const ready = path.join(workspace, 'ready');
    const release = path.join(workspace, 'release');
    const completed = path.join(workspace, 'completed');
    const command = `printf ready > ${shellQuote(ready)}; while [ ! -e ${shellQuote(release)} ]; do sleep 0.01; done; printf completed > ${shellQuote(completed)}`;
    return { command, ready, release, completed };
  });
  const { operation: pending } = await waitForOperation(service, taskId, value => value.status === 'awaiting_approval');
  assert.equal(pending.announced, false);
  assert.deepEqual(pending.arguments, arguments_);

  const approved = await service.command({ op: 'review_approval', task_id: taskId, operation_id: pending.operation_id,
    decision: 'allow', reason: 'Approve this cancellation fixture.' });
  assert.equal(approved.reply.ok, true, JSON.stringify(approved.reply));
  await waitForFile(ready);
  const { operation: executing } = await waitForOperation(service, taskId,
    value => value.operation_id === pending.operation_id && value.status === 'running');
  assert.equal(executing.announced, true);
  assert.ok(Number.isInteger(executing.execution_ticket));
  assert.deepEqual(executing.call.arguments, arguments_);

  const cancelled = await service.command({ op: 'cancel_operation', task_id: taskId, operation_id: executing.operation_id });
  assert.equal(cancelled.reply.ok, true, JSON.stringify(cancelled.reply));
  assert.deepEqual(cancelled.reply.result, { task_id: taskId, operation_id: executing.operation_id });
  await writeFile(release, 'release');

  const page = await taskIdle(service, taskId);
  const outcome = page.messages.find(entry => entry.role === 'operation_result'
    && entry.operation_id === executing.operation_id && entry.content?.error?.code === 'cancelled');
  assert.ok(outcome, 'The task history must contain the cancelled execution result');
  assert.match(outcome.content.error.message, /may already have made changes/);
  await delay(100);
  await assert.rejects(readFile(completed), { code: 'ENOENT' });
  assertContinued(page, upstream);
  assert.deepEqual(upstream.failures, []);
});

test('a frozen idle task processes an owned operation result after unfreeze', async t => {
  const { service, taskId, upstream, ready, release } = await fixture(t, ({ workspace }) => {
    const ready = path.join(workspace, 'frozen-ready');
    const release = path.join(workspace, 'frozen-release');
    return { ready, release, command: `printf ready > ${shellQuote(ready)}; while [ ! -e ${shellQuote(release)} ]; do sleep 0.01; done; printf frozen-result` };
  });
  const { operation } = await waitForOperation(service, taskId, value => value.status === 'awaiting_approval');
  assert.equal((await service.command({ op: 'review_approval', task_id: taskId,
    operation_id: operation.operation_id, decision: 'allow', reason: 'Run the frozen result fixture.' })).reply.ok, true);
  await waitForFile(ready);

  async function waitForState(accepts) {
    const deadline = Date.now() + 10000;
    let page;
    do {
      page = await readTask(service, taskId);
      if (accepts(page.task)) return page;
      await delay(10);
    } while (Date.now() < deadline);
    assert.fail(`The expected frozen result state was not reached: ${JSON.stringify(page?.task)}`);
  }
  await waitForState(task => task.phase === 'idle' && task.operations.length === 1);
  assert.equal((await service.command({ op: 'freeze', task_id: taskId })).reply.ok, true);
  const beforeResult = upstream.requests.length;
  await writeFile(release, 'complete while frozen');
  const frozen = await waitForState(task => task.status === 'frozen' && task.operations.length === 0);
  assert.equal(frozen.task.phase, 'ready');
  assert.equal(upstream.requests.length, beforeResult);
  assert.ok(frozen.messages.some(entry => entry.role === 'operation_result'
    && entry.operation_id === operation.operation_id));
  const configured = await service.command({ op: 'configure_task_execution', task_id: taskId });
  assert.equal(configured.reply.error.code, 'task_busy');

  assert.equal((await service.command({ op: 'unfreeze', task_id: taskId })).reply.ok, true);
  await taskIdle(service, taskId);
  assert.equal(upstream.requests.length, beforeResult + 1);
  assert.deepEqual(upstream.failures, []);
});

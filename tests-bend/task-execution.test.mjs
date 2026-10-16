import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { webServer, answer } from './fixtures/chatgpt-web.mjs';

function credential(t, name, value) {
  const previous = process.env[name];
  process.env[name] = value;
  t.after(() => { if (previous === undefined) delete process.env[name]; else process.env[name] = previous; });
  return name;
}

async function observed(predicate, message) {
  const deadline = Date.now() + 5000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error(message);
    await delay(10);
  }
}

const execution = (task_id, profile) => ({ op: 'configure_task_execution', task_id, profile, reasoning: 'medium',
  sandbox: { mode: 'read-only', network_access: false }, approval: { mode: 'ask-for-approval' } });
const read = async (service, task_id = 0) => {
  const result = await service.command({ op: 'read', task_id });
  assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
  return result.reply.result;
};

function assertSettingsAppended(before, after, configuration) {
  assert.equal(after.task.cursor, before.task.cursor + 1);
  assert.deepEqual(after.messages, [...before.messages, {
    role: 'task_context', type: 'settings', profile: configuration.profile, reasoning: configuration.reasoning,
    content: {
      project_id: before.task.settings.project_id,
      workspace: before.task.settings.workspace,
      sandbox: configuration.sandbox,
      approval: { mode: configuration.approval.mode, reviewer_profile: '', reviewer: null },
    },
  }]);
}

test('HTTP execution configuration rejects in-flight work and changes only a settled task execution plan', { timeout: 20_000 }, async t => {
  const base = await realpath(await home(t));
  const workspace = path.join(base, 'workspace');
  await mkdir(workspace);
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  t.after(() => release());
  const upstream = await responsesServer(t, async (body, index) => {
    if (index === 0) await gate;
    return answer(`Reply from ${body.model}`);
  });
  const api_key_env = credential(t, 'SELVEDGE_EXECUTION_FIXTURE', 'local-fixture-only');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    a: { provider: 'responses', model: 'model-a', endpoint: upstream.endpoint, api_key_env },
    b: { provider: 'responses', model: 'model-b', endpoint: upstream.endpoint, api_key_env },
  } });
  const server = await startServer({ home: path.join(base, 'state'), cwd: workspace, config });
  t.after(() => server.close());
  const post = async command => {
    const response = await fetch(`${server.address}/api/browser/command`, { method: 'POST',
      headers: { authorization: `Bearer ${server.token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ command }) });
    return { status: response.status, body: await response.json() };
  };
  const project = await server.service.command({ op: 'create_project', name: 'Execution configuration project',
    workspace: { roots: [workspace], primary_root: workspace } });
  assert.equal(project.reply.ok, true, JSON.stringify(project.reply));
  const created = await server.service.command({ op: 'create', profile: 'a', reasoning: 'medium', message: 'First request.',
    settings: { project_id: project.reply.result.project_id } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  await observed(() => upstream.requests.length === 1, 'Initial model request did not reach the provider');
  assert.equal(upstream.requests[0].model, 'model-a');
  const pending = await read(server.service);
  assert.equal(pending.task.phase, 'model_pending');
  const refused = await post(execution(0, 'b'));
  assert.equal(refused.body.reply.ok, false, JSON.stringify(refused));
  assert.deepEqual(await read(server.service), pending);
  release();
  const before = await taskIdle(server.service);
  const configured = await post(execution(0, 'b'));
  assert.equal(configured.status, 200, JSON.stringify(configured));
  assert.equal(configured.body.reply.ok, true, JSON.stringify(configured));
  const after = await read(server.service);
  assert.equal(after.task.profile, 'b');
  assert.equal(after.task.model, 'model-b');
  assert.equal(after.task.reasoning, 'medium');
  assert.equal(after.task.settings.sandbox.mode, 'read-only');
  assert.equal(after.task.settings.sandbox.network_access, false);
  assert.equal(after.task.settings.approval.mode, 'ask-for-approval');
  assertSettingsAppended(before, after, execution(0, 'b'));
  // Compare every unrelated public task field, including lineage, queue and leases.
  const { profile: oldProfile, provider: oldProvider, model: oldModel, reasoning: oldReasoning, settings: oldSettings, cursor: oldCursor, ...oldTask } = before.task;
  const { profile: newProfile, provider: newProvider, model: newModel, reasoning: newReasoning, settings: newSettings, cursor: newCursor, ...newTask } = after.task;
  assert.deepEqual(newTask, oldTask);
  const { sandbox: oldSandbox, approval: oldApproval, ...oldContext } = oldSettings;
  const { sandbox: newSandbox, approval: newApproval, ...newContext } = newSettings;
  assert.deepEqual(newContext, oldContext);
  assert.equal(after.task.settings.project_id, project.reply.result.project_id);
  assert.deepEqual(after.task.settings.workspace, { roots: [workspace], primary_root: workspace });

  const unknown = await post(execution(0, 'absent-profile'));
  assert.equal(unknown.body.reply.ok, false, JSON.stringify(unknown));
  assert.deepEqual(await read(server.service), after);
  for (const malformed of [
    { sandbox: { mode: 'unknown-mode', network_access: false } },
    { approval: { mode: 'unknown-policy' } },
    { sandbox: { mode: 'read-only', network_access: 'false' } },
  ]) {
    const response = await post({ ...execution(0, 'a'), ...malformed });
    assert.ok(response.status >= 400 || response.body.reply?.ok === false, JSON.stringify(response));
    assert.deepEqual(await read(server.service), after);
  }
  assert.equal((await server.service.command({ op: 'send', task_id: 0, message: 'Use the new model.' })).reply.ok, true);
  await taskIdle(server.service);
  assert.equal(upstream.requests.length, 2);
  assert.equal(upstream.requests[1].model, 'model-b');
  assert.ok(upstream.requests[1].input.some(item => item.role === 'user' && JSON.stringify(item).includes('Use the new model.')));
  assert.deepEqual(upstream.failures, []);
});

test('task model and policy changes restart ChatGPT Web roots while no-op configuration and other tasks retain continuation', { timeout: 20_000 }, async t => {
  const directory = await home(t);
  const upstream = await webServer(t, (_, index) => ({ output: answer(`Answer ${index}`) }));
  const api_key_env = credential(t, 'SELVEDGE_EXECUTION_WEB_FIXTURE', 'local-web-fixture');
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    a: { provider: 'chatgpt-web', model: 'chatgpt-web/high', endpoint: upstream.endpoint, api_key_env, timeout_ms: 5000 },
    b: { provider: 'chatgpt-web', model: 'chatgpt-web/light', endpoint: upstream.endpoint, api_key_env, timeout_ms: 5000 },
  } });
  const service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  assert.equal((await service.command({ op: 'create', profile: 'a', message: 'First task.' })).reply.ok, true);
  const first = await taskIdle(service, 0);
  assert.equal((await service.command({ op: 'create', profile: 'a', message: 'Other task.' })).reply.ok, true);
  await taskIdle(service, 1);
  const receipt = first.messages.find(item => item.role === 'model_context' && item.content.type === 'provider_receipt');
  assert.ok(receipt, JSON.stringify(first));
  const modelConfiguration = { ...execution(0, 'b'), reasoning: 'default' };
  assert.equal((await service.command(modelConfiguration)).reply.ok, true);
  assertSettingsAppended(first, await read(service, 0), modelConfiguration);
  assert.equal((await service.command({ op: 'send', task_id: 0, message: 'New model root.' })).reply.ok, true);
  await taskIdle(service, 0);
  assert.equal(upstream.requests[2].body.model, 'chatgpt-web/light');
  assert.equal(upstream.requests[2].body.previous_response_id, undefined);
  // Historical receipts remain input data; only the protocol predecessor selects continuation.
  assert.ok(JSON.stringify(upstream.requests[2].body.input).includes(receipt.content.response_id));
  assert.equal((await service.command({ op: 'send', task_id: 1, message: 'Continue other task.' })).reply.ok, true);
  await taskIdle(service, 1);
  assert.ok(upstream.requests[3].body.previous_response_id);
  assert.equal((await read(service, 1)).task.profile, 'a');

  const beforePolicy = await read(service, 0);
  const oldPolicyReceipt = beforePolicy.messages.findLast(item => item.role === 'model_context' && item.content.type === 'provider_receipt');
  assert.ok(oldPolicyReceipt, JSON.stringify(beforePolicy));
  const otherBeforePolicy = await read(service, 1);
  const otherReceipt = otherBeforePolicy.messages.findLast(item => item.role === 'model_context' && item.content.type === 'provider_receipt');
  assert.ok(otherReceipt, JSON.stringify(otherBeforePolicy));
  const policy = { ...execution(0, 'b'), reasoning: 'default',
    sandbox: { mode: 'workspace-write', network_access: false } };
  const configured = await service.command(policy);
  assert.equal(configured.reply.ok, true, JSON.stringify(configured.reply));
  const afterPolicy = await read(service, 0);
  assert.equal(afterPolicy.task.profile, 'b');
  assert.equal(afterPolicy.task.model, 'chatgpt-web/light');
  assert.equal(afterPolicy.task.reasoning, 'default');
  assert.deepEqual(afterPolicy.task.settings.sandbox, policy.sandbox);
  assert.deepEqual(afterPolicy.task.settings.approval, beforePolicy.task.settings.approval);
  assert.equal(afterPolicy.task.settings.approval.mode, policy.approval.mode);
  assertSettingsAppended(beforePolicy, afterPolicy, policy);
  assert.deepEqual(await read(service, 1), otherBeforePolicy);
  assert.equal((await service.command({ op: 'send', task_id: 0, message: 'New policy root.' })).reply.ok, true);
  const policyRoot = await taskIdle(service, 0);
  assert.equal(upstream.requests.length, 5);
  assert.equal(upstream.requests[4].body.model, 'chatgpt-web/light');
  assert.equal(upstream.requests[4].body.previous_response_id, undefined);
  assert.ok(JSON.stringify(upstream.requests[4].body.input).includes(oldPolicyReceipt.content.response_id));
  const rootInput = JSON.stringify(upstream.requests[4].body.input);
  for (const content of ['First task.', 'New model root.', 'Answer 2', 'New policy root.']) {
    assert.ok(rootInput.includes(content), rootInput);
  }
  assert.deepEqual(policyRoot.messages.slice(0, beforePolicy.messages.length), beforePolicy.messages);
  assert.ok(policyRoot.messages.some(item => item.role === 'assistant' && item.content === 'Answer 4'), JSON.stringify(policyRoot));
  assert.ok(!policyRoot.messages.some(item => item.role === 'error'), JSON.stringify(policyRoot));
  const policyReceipt = policyRoot.messages.findLast(item => item.role === 'model_context' && item.content.type === 'provider_receipt');
  assert.ok(policyReceipt, JSON.stringify(policyRoot));

  const unchanged = await service.command(policy);
  assert.equal(unchanged.reply.ok, true, JSON.stringify(unchanged.reply));
  assert.deepEqual((await read(service, 0)).messages, policyRoot.messages);
  assert.equal((await service.command({ op: 'send', task_id: 0, message: 'Continue unchanged policy.' })).reply.ok, true);
  const continued = await taskIdle(service, 0);
  assert.equal(upstream.requests.length, 6);
  assert.equal(upstream.requests[5].body.previous_response_id, policyReceipt.content.response_id);
  assert.ok(continued.messages.some(item => item.role === 'assistant' && item.content === 'Answer 5'), JSON.stringify(continued));
  assert.ok(!continued.messages.some(item => item.role === 'error'), JSON.stringify(continued));

  assert.equal((await service.command({ op: 'send', task_id: 1, message: 'Continue other task after policy change.' })).reply.ok, true);
  const otherContinued = await taskIdle(service, 1);
  assert.equal(upstream.requests.length, 7);
  assert.equal(upstream.requests[6].body.previous_response_id, otherReceipt.content.response_id);
  assert.equal(otherContinued.task.profile, 'a');
  assert.ok(otherContinued.messages.some(item => item.role === 'assistant' && item.content === 'Answer 6'), JSON.stringify(otherContinued));
  assert.ok(!otherContinued.messages.some(item => item.role === 'error'), JSON.stringify(otherContinued));
  assert.deepEqual(upstream.failures, []);
});

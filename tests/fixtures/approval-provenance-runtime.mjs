import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../../host/config.mjs';
import { startServer } from '../../host/server.mjs';
import { home, responsesServer, shellQuote } from '../support.mjs';

export const originalReviewerModel = 'audit-reviewer-before-reconfiguration';
export const replacementReviewerModel = 'audit-reviewer-after-reconfiguration';
export const denialReason = 'Only the requested workspace may be changed.';

const message = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

export async function eventually(observe, accepts, description) {
  const deadline = Date.now() + 10000;
  let observed;
  do {
    observed = await observe();
    if (accepts(observed)) return observed;
    await delay(10);
  } while (Date.now() < deadline);
  // DEFENSE: A real asynchronous HTTP/provider regression can fail to reach the required public state.
  assert.fail(`${description}: ${JSON.stringify(observed)}`);
}

export async function approvalFixture(t, kind) {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const state = path.join(directory, 'state');
  const marker = path.join(directory, 'must-not-be-written.txt');
  await mkdir(workspace);
  const apiKey = `SELVEDGE_APPROVAL_PROVENANCE_${randomBytes(8).toString('hex').toUpperCase()}`;
  process.env[apiKey] = 'loopback-fixture-only';
  t.after(() => { delete process.env[apiKey]; });
  let release;
  const reviewerGate = new Promise(resolve => { release = resolve; });
  t.after(() => release());
  let workerCalls = 0;
  const commandText = `printf 'unexpected execution' > ${shellQuote(marker)}`;
  const upstream = await responsesServer(t, async body => {
    if (body.model === originalReviewerModel) {
      await reviewerGate;
      return message(JSON.stringify({ decision: 'deny', reason: denialReason }));
    }
    if (body.model === replacementReviewerModel) return message('The new reviewer configuration is active.');
    assert.equal(body.model, 'audit-worker');
    if (workerCalls++ > 0) return message('The denied command was not executed.');
    return [{ type: 'function_call', call_id: 'audit-native-call', name: 'bash', arguments: JSON.stringify({
      command: commandText, sandbox_permissions: 'require_escalated',
      justification: 'Write the exact requested marker outside the workspace.', timeout_ms: 5000,
    }) }];
  });
  const configFor = model => validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    worker: { provider: 'responses', model: 'audit-worker', endpoint: upstream.endpoint, api_key_env: apiKey },
    judge: { provider: 'responses', model, endpoint: upstream.endpoint, api_key_env: apiKey },
  } });
  let running = await startServer({ home: state, cwd: workspace, config: configFor(originalReviewerModel) });
  t.after(() => running.close());
  async function command(body) {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    return { status: response.status, reply: await response.json() };
  }
  async function successful(body) {
    const result = await command(body);
    assert.equal(result.reply.ok, true, JSON.stringify(result));
    assert.ok(result.status >= 200 && result.status < 300, JSON.stringify(result));
    return result.reply.result;
  }
  const { task_id } = await successful({ op: 'create', profile: 'worker', message: 'Review the exact requested command.', settings: {
    workspace: { roots: [workspace], primary_root: workspace },
    approval: kind === 'human' ? { mode: 'ask-for-approval' } : { mode: 'approval-for-me', reviewer_profile: 'judge' },
  } });
  const read = () => successful({ op: 'read', task_id });
  return {
    taskId: task_id, commandText, upstream, command, successful, read, releaseReviewer: release,
    get running() { return running; },
    pending: () => eventually(read, value => value.task.operations.some(op => op.status === 'awaiting_approval'), 'Approval must become publicly pending'),
    idle: () => eventually(read, value => value.task.phase === 'idle' && value.task.operations.length === 0, 'Approval must settle'),
    markerAbsent: () => assert.rejects(readFile(marker), { code: 'ENOENT' }),
    async reconfigureReviewer() {
      await running.close();
      running = await startServer({ home: state, cwd: workspace, config: configFor(replacementReviewerModel) });
    },
  };
}

export function auditRecord(page, taskId, operationId, commandText, reviewer) {
  const records = page.messages.filter(value => value.role === 'approval_record' && value.operation_id === operationId);
  assert.equal(records.length, 1, 'The completed approval must have one persistent audit record');
  const [record] = records;
  assert.equal(record.task_id, taskId);
  assert.equal(record.call.id, 'audit-native-call');
  assert.equal(record.call.name, 'bash');
  assert.deepEqual(record.call.arguments, {
    command: commandText, sandbox_permissions: 'require_escalated',
    justification: 'Write the exact requested marker outside the workspace.', timeout_ms: 5000,
  });
  assert.deepEqual(record.content, { decision: 'deny', reason: denialReason });
  assert.deepEqual(record.reviewer, reviewer, 'History must identify the actual reviewer and its frozen profile');
  return record;
}

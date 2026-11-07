import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../../host/config.mjs';
import { startServer } from '../../host/server.mjs';
import { home, responsesServer, shellQuote } from '../support.mjs';

export const denialReason = 'Only the requested workspace may be changed.';

const message = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

async function eventually(observe, accepts, description) {
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

export async function approvalFixture(t) {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const state = path.join(directory, 'state');
  const marker = path.join(directory, 'must-not-be-written.txt');
  await mkdir(workspace);
  const apiKey = `SELVEDGE_APPROVAL_${randomBytes(8).toString('hex').toUpperCase()}`;
  process.env[apiKey] = 'loopback-fixture-only';
  t.after(() => { delete process.env[apiKey]; });
  let workerCalls = 0;
  const commandText = `printf 'unexpected execution' > ${shellQuote(marker)}`;
  const upstream = await responsesServer(t, async body => {
    assert.equal(body.model, 'approval-worker');
    if (workerCalls++ > 0) return message('The denied command was not executed.');
    return [{ type: 'function_call', call_id: 'approval-native-call', name: 'bash', arguments: JSON.stringify({
      command: commandText, sandbox_permissions: 'require_escalated',
      justification: 'Write the exact requested marker outside the workspace.', timeout_ms: 5000,
    }) }];
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    worker: { provider: 'responses', model: 'approval-worker', endpoint: upstream.endpoint, api_key_env: apiKey },
  } });
  const running = await startServer({ home: state, cwd: workspace, config });
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
    approval: { mode: 'ask-for-approval' },
  } });
  const read = () => successful({ op: 'read', task_id });
  return {
    taskId: task_id, commandText, upstream, command, successful, read,
    get running() { return running; },
    pending: () => eventually(read, value => value.task.operations.some(op => op.status === 'awaiting_approval'), 'Approval must become publicly pending'),
    idle: () => eventually(read, value => value.task.phase === 'idle' && value.task.operations.length === 0, 'Approval must settle'),
    markerAbsent: () => assert.rejects(readFile(marker), { code: 'ENOENT' }),
  };
}

export function approvalRecord(page, taskId, operationId, commandText) {
  const records = page.messages.filter(value => value.role === 'approval_record' && value.operation_id === operationId);
  assert.equal(records.length, 1, 'The completed approval must retain its command and decision');
  const [record] = records;
  assert.equal(record.task_id, taskId);
  assert.equal(record.call.id, 'approval-native-call');
  assert.equal(record.call.name, 'bash');
  assert.deepEqual(record.call.arguments, {
    command: commandText, sandbox_permissions: 'require_escalated',
    justification: 'Write the exact requested marker outside the workspace.', timeout_ms: 5000,
  });
  assert.deepEqual(record.content, { decision: 'deny', reason: denialReason });
  return record;
}

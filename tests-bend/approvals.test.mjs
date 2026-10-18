import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, realpath } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, shellQuote, taskIdle } from './support.mjs';

const probe = fileURLToPath(new URL('./fixtures/approved-tool.mjs', import.meta.url));

test('a real process sees its committed grant and intent, and journal reopen never executes it again', async t => {
  const base = await realpath(await home(t));
  const workspace = path.join(base, 'workspace');
  const state = path.join(base, 'state');
  const marker = path.join(base, 'outside-workspace.txt');
  await mkdir(workspace);
  const key = 'SELVEDGE_APPROVAL_FIXTURE';
  const previous = process.env[key];
  process.env[key] = 'local-fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  const command = [process.execPath, probe, path.join(state, 'journal.sqlite'), marker, 'approval-shell']
    .map(shellQuote).join(' ');
  const upstream = await responsesServer(t, (_, index) => index === 0 ? [
    { type: 'function_call', call_id: 'approval-shell', name: 'bash', arguments: JSON.stringify({ command,
      sandbox_permissions: 'require_escalated', justification: 'Write the requested file outside the workspace.', timeout_ms: 5000 }) },
  ] : [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }]);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    worker: { provider: 'responses', model: 'worker-model', endpoint: upstream.endpoint, api_key_env: key },
  } });
  const options = { home: state, cwd: workspace, config };
  let service = await Service.open(options);
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'worker', message: 'Write the requested file.', settings: {
    workspace: { roots: [workspace], primary_root: workspace }, approval: { mode: 'ask-for-approval' },
  } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  let operation;
  for (let attempt = 0; attempt < 500 && !operation; attempt++) {
    const page = (await service.command({ op: 'read', task_id: 0 })).reply.result;
    operation = page.task.operations.find(value => value.status === 'awaiting_approval');
    if (!operation) await delay(10);
  }
  assert.ok(operation, 'The real provider must reach the approval boundary');
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  const approved = await service.command({ op: 'review_approval', task_id: 0, operation_id: operation.operation_id,
    decision: 'allow', reason: 'The user requested this exact file.' });
  assert.equal(approved.reply.ok, true, JSON.stringify(approved.reply));
  const completed = await taskIdle(service);
  assert.equal(await readFile(marker, 'utf8'), 'ran\n');
  const requests = upstream.requests.length;
  await service.close();
  service = await Service.open(options);
  assert.deepEqual((await taskIdle(service)).messages, completed.messages);
  assert.equal(await readFile(marker, 'utf8'), 'ran\n');
  assert.equal(upstream.requests.length, requests);
  assert.deepEqual(upstream.failures, []);
});

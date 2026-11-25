import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { responsesServer, shellQuote, taskIdle } from './support.mjs';

test('shared execution preserves task permissions and resumes receiver operations', async t => {
  const directory = await realpath(await mkdtemp(path.join(tmpdir(), 'selvedge-shared-execution-')));
  const root = path.join(directory, 'receiver-workspace');
  const cert = path.join(directory, 'receiver.pem');
  const key = path.join(directory, 'receiver-key.pem');
  const token = path.join(directory, 'execution-token');
  await mkdir(root);
  await writeFile(token, randomBytes(32).toString('base64url'), { mode: 0o600 });
  await writeFile(path.join(root, 'AGENTS.md'), 'Receiver-only project guidance.\n');
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=127.0.0.1', '-addext', 'subjectAltName=IP:127.0.0.1', '-keyout', key, '-out', cert], { stdio: 'pipe' });
  const receiver = Bun.spawn([process.execPath, 'host/cli.mjs', '--home', path.join(directory, 'receiver-home'),
    'receive-execution', '--host', '127.0.0.1', '--port', '0', '--cert-file', cert, '--key-file', key, '--token-file', token], {
    env: { ...process.env, SELVEDGE_EXECUTION_FIXTURE: 'receiver-process' }, stdout: 'pipe', stderr: 'inherit',
  });
  let service;
  t.after(async () => {
    await service?.close();
    receiver.kill();
    await receiver.exited;
    delete process.env.SELVEDGE_SHARED_EXECUTION_TEST_API_KEY;
    await rm(directory, { recursive: true, force: true });
  });
  const stdout = receiver.stdout.getReader();
  const ready = await stdout.read();
  stdout.releaseLock();
  const port = /listening on 127\.0\.0\.1:(\d+)/.exec(new TextDecoder().decode(ready.value))?.[1];
  assert.ok(port, 'The receiver CLI must bind its TLS listener');
  process.env.SELVEDGE_SHARED_EXECUTION_TEST_API_KEY = 'local-responses-fixture';
  let launches = 0;
  let argumentsForTask;
  const provider = await responsesServer(t, async body => {
    if (argumentsForTask) {
      assert.ok(JSON.stringify(body.input).includes('Receiver-only project guidance.'));
      const args = argumentsForTask;
      argumentsForTask = undefined;
      return [{ type: 'function_call', name: 'bash', call_id: `shared-${++launches}`,
        arguments: JSON.stringify(args) }];
    }
    return [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Finished.' }] }];
  });
  service = await Service.open({ home: path.join(directory, 'task-home'), cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false,
      execution_environments: [{ id: 'receiver', url: `wss://127.0.0.1:${port}/execution`,
        token_file: token, ca_file: cert }],
      profiles: { worker: { provider: 'responses', model: 'shared-execution', endpoint: provider.endpoint,
        api_key_env: 'SELVEDGE_SHARED_EXECUTION_TEST_API_KEY' } },
    }),
  });
  const create = async (mode, args) => {
    argumentsForTask = args;
    const created = await service.command({ op: 'create', profile: 'worker', message: `Run with ${mode}`,
      settings: { workspace: { roots: [root], environment: 'receiver' },
        approval: { mode: 'ask-for-approval' }, sandbox: { mode, network_access: false } } });
    assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
    return created.reply.result.task_id;
  };
  const launch = async mode => {
    const task = await create(mode, { command: 'printf "%s" "$SELVEDGE_EXECUTION_FIXTURE"; printf x > created-by-task' });
    const page = await taskIdle(service, task);
    assert.equal(page.task.settings.workspace.environment, 'receiver');
    assert.equal(page.task.settings.sandbox.mode, mode);
    const toolResult = page.messages.find(item => item.role === 'operation_result');
    assert.equal(toolResult?.content.stdout, 'receiver-process', toolResult?.content.stderr);
  };
  await launch('read-only');
  await assert.rejects(readFile(path.join(root, 'created-by-task')), { code: 'ENOENT' });
  await launch('workspace-write');
  assert.equal(await readFile(path.join(root, 'created-by-task'), 'utf8'), 'x');
  await assert.rejects(readFile(path.join(directory, 'created-by-task')), { code: 'ENOENT' });
  const marker = path.join(directory, 'approved-at-a');
  const approvalTask = await create('read-only', {
    command: `printf '%s' "$SELVEDGE_EXECUTION_FIXTURE" > ${shellQuote(marker)}`,
    sandbox_permissions: 'require_escalated', justification: 'Write the marker exactly once.',
  });
  let pending;
  for (let attempt = 0; attempt < 500 && !pending; attempt++) {
    const page = (await service.command({ op: 'read', task_id: approvalTask })).reply.result;
    pending = page.task.operations.find(value => value.status === 'awaiting_approval');
    if (!pending) await delay(10);
  }
  assert.ok(pending, 'The task must wait for its existing approval flow on A');
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  const approved = await service.command({ op: 'review_approval', task_id: approvalTask,
    operation_id: pending.operation_id, decision: 'allow', reason: 'Approve the exact marker write.' });
  assert.equal(approved.reply.ok, true, JSON.stringify(approved.reply));
  await taskIdle(service, approvalTask);
  assert.equal(await readFile(marker, 'utf8'), 'receiver-process');
  assert.equal(provider.failures.length, 0);

  const workspace = { roots: [root], primary_root: root, environment: 'receiver' };
  const probe = () => service.browserObservation({ kind: 'workspace-git', primary: root, environment: 'receiver' });
  assert.equal((await probe()).available, false);
  const git = (...args) => execFileSync('git', ['-C', root, '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Receiver fixture', '-c', 'user.email=receiver@example.test', ...args], { stdio: 'pipe' });
  git('init', '--initial-branch=main');
  git('add', 'AGENTS.md');
  git('commit', '-m', 'Prepare receiver repository');
  assert.equal((await probe()).available, true);
  argumentsForTask = { command: 'printf "%s" "$SELVEDGE_EXECUTION_FIXTURE" > worktree-only' };
  const created = await service.command({ op: 'create_worktree_task', profile: 'worker', message: 'Run in a receiver worktree.',
    settings: { workspace, approval: { mode: 'ask-for-approval' }, sandbox: { mode: 'workspace-write', network_access: false } } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const task_id = created.reply.result.task_id;
  async function checkoutWithStatus(status) {
    let checkout;
    for (let attempt = 0; attempt < 500; attempt++) {
      checkout = (await service.command({ op: 'read_worktree', task_id })).reply.result;
      if (checkout.status === status) return checkout;
      assert.ok(!checkout.status.endsWith('_failed'), JSON.stringify(checkout));
      await delay(20);
    }
    assert.fail(JSON.stringify(checkout));
  }
  const worktree = await checkoutWithStatus('ready');
  assert.equal(worktree.environment, 'receiver');
  assert.equal(path.dirname(worktree.root), path.join(directory, 'receiver-home', 'worktrees'));
  const working = await taskIdle(service, task_id);
  assert.equal(working.task.settings.workspace.environment, 'receiver');
  assert.equal(working.task.settings.workspace.primary_root, worktree.root);
  assert.equal(await readFile(path.join(worktree.root, 'worktree-only'), 'utf8'), 'receiver-process');
  await assert.rejects(readFile(path.join(root, 'worktree-only')), { code: 'ENOENT' });
  assert.equal((await service.command({ op: 'archive', task_id })).reply.ok, true);
  const archived = await checkoutWithStatus('archived');
  assert.equal(path.dirname(archived.root), path.join(directory, 'receiver-home', 'worktrees', 'archived'));
  assert.equal(await readFile(path.join(archived.root, 'worktree-only'), 'utf8'), 'receiver-process');

  const connection = { tls: { ca: await readFile(cert), rejectUnauthorized: true },
    protocols: ['selvedge-execution-v1'], headers: { Authorization: `Bearer ${await readFile(token, 'utf8')}` } };
  const connect = async () => {
    const socket = new WebSocket(`wss://127.0.0.1:${port}/execution`, connection);
    t.after(() => socket.terminate());
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
    return socket;
  };
  const rpc = (socket, id, method, params) => new Promise(resolve => {
    function receive({ data }) {
      const reply = JSON.parse(data);
      if (reply.id !== id) return;
      socket.removeEventListener('message', receive);
      resolve(reply);
    }
    socket.addEventListener('message', receive);
    socket.send(JSON.stringify({ id, method, params }));
  });
  const replay = { operation_id: 'lost-response', tool: 'bash',
    arguments: { command: 'printf x >> replay-marker' },
    execution: { resource: null, workspace: { roots: [root], primary_root: root, environment: 'receiver' },
      sandbox: { mode: 'workspace-write', network_access: false }, access: 'sandboxed' },
  };
  const original = await connect();
  assert.deepEqual((await rpc(original, 'first', 'execution.start', replay)).result, { accepted: true });
  original.terminate();
  const recovered = await connect();
  assert.deepEqual((await rpc(recovered, 'again', 'execution.start', replay)).result, { accepted: true });
  const completion = await rpc(recovered, 'recover', 'execution.wait', { operation_id: replay.operation_id });
  assert.equal(completion.result.value.value.exit_code, 0);
  assert.equal(await readFile(path.join(root, 'replay-marker'), 'utf8'), 'x');
  const cancelled = { ...replay, operation_id: 'cancelled-before-arrival' };
  await rpc(recovered, 'cancel', 'execution.cancel', { operation_id: cancelled.operation_id });
  assert.equal((await rpc(recovered, 'late', 'execution.start', cancelled)).error.code, 'execution_cancelled');
  assert.equal(await readFile(path.join(root, 'replay-marker'), 'utf8'), 'x');

  const terminal = { ...replay, operation_id: 'live-input',
    arguments: { command: 'printf ready; IFS= read -r line; printf "%s" "$line"', timeout_ms: 5000 } };
  const output = Promise.withResolvers();
  recovered.addEventListener('message', ({ data }) => {
    const frame = JSON.parse(data);
    if (frame.method === 'execution.output' && frame.params.operation_id === terminal.operation_id) {
      output.resolve(frame.params.output);
    }
  });
  assert.ok((await rpc(recovered, 'term-start', 'execution.start', terminal)).result.accepted);
  assert.equal(await output.promise, 'ready');
  const input = await rpc(recovered, 'term-write', 'execution.write',
    { operation_id: terminal.operation_id, input: { input: '远程输入\n' } });
  assert.ok(input.result, JSON.stringify(input));
  const terminalDone = await rpc(recovered, 'term-result', 'execution.wait', { operation_id: terminal.operation_id });
  assert.equal(terminalDone.result.value.value.stdout, 'ready远程输入');
});

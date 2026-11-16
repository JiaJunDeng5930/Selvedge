import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { contextChanges } from './fixtures/context-observations.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

async function fixture(t, overrides = {}) {
  const directory = await home(t);
  const state = path.join(directory, 'state');
  const workspace = path.join(directory, 'workspace');
  await Promise.all([mkdir(state), mkdir(workspace)]);
  const globalGuidance = path.join(state, 'AGENTS.md');
  const workspaceGuidance = path.join(workspace, 'AGENTS.md');
  await writeFile(globalGuidance, 'Service guidance at startup.');
  const options = { home: state, cwd: workspace, config: validateConfig({
    ...defaultConfig, chatgpt: false, ...overrides,
    profiles: { demo: { provider: 'echo', model: 'echo' }, ...overrides.profiles },
  }) };
  let service = await Service.open(options);
  const database = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
  t.after(async () => {
    database.close();
    await service.close();
  });
  const command = async input => (await service.command(input)).reply;
  const successful = async input => {
    const reply = await command(input);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const cursor = () => service.journal.sequence;
  const kindsAfter = sequence => database.prepare(
    "SELECT json_extract(input, '$.kind') AS kind FROM journal WHERE seq > ? ORDER BY seq",
  ).all(sequence).map(row => row.kind);
  const controller = async () => {
    await successful({ op: 'remote_enable' });
    const controllerId = 'a'.repeat(64);
    const grant = await successful({ op: 'remote_grant', controller_id: controllerId,
      permissions: { read: true, control: true, configure: true, approve: false } });
    return async (command, request_id = randomUUID()) =>
      (await service.remoteCommand(controllerId, grant.grant_epoch, { request_id, command })).reply;
  };
  const restart = async () => {
    await service.close();
    service = await Service.open(options);
  };
  const settings = { workspace: { roots: [workspace], primary_root: workspace } };
  return { command, successful, controller, cursor, kindsAfter, restart, globalGuidance, workspaceGuidance,
    settings, idle: taskId => taskIdle(service, taskId) };
}

function introducedGuidance(page, type, filename) {
  const introduction = contextChanges(page, type).find(change => change.type === 'introduce'
    && (change.key.identity.path ?? change.snapshot.value.fields.path) === filename);
  return introduction?.snapshot.value.fields.content;
}

for (const entry of ['local', 'remote', 'graph']) {
  test(`${entry} root creation replays the original guidance after the files change`, async t => {
    const f = await fixture(t);
    const remote = entry === 'remote' ? await f.controller() : undefined;
    const read = task_id => f.successful({ op: 'read', task_id });
    const globalText = `Birth guidance for ${entry} 😀.`;
    const workspaceText = `Workspace directions for ${entry} 中文.`;
    await writeFile(f.globalGuidance, globalText);
    await writeFile(f.workspaceGuidance, workspaceText);
    const before = f.cursor();
    let taskId;
    if (entry === 'graph') {
      await f.successful({ op: 'create_task_graph', name: 'Root creation', nodes: [
        { key: 'root', profile: 'demo', message: 'Start a graph Task.', settings: f.settings },
      ], rules: [] });
      const { tasks } = await f.successful({ op: 'list' });
      assert.equal(tasks.length, 1);
      taskId = tasks[0].id;
    } else {
      const reply = remote
        ? await remote({ op: 'create', profile: 'demo', message: 'Create via remote control.', settings: f.settings })
        : await f.command({ op: 'create_idle', profile: 'demo', settings: f.settings });
      assert.equal(reply.ok, true, JSON.stringify(reply));
      taskId = reply.result.task_id;
    }
    assert.ok(f.cursor() > before, `${entry} creation must be durable`);
    const configurationWrites = f.kindsAfter(before).filter(kind =>
      ['configure', 'compaction_configure', 'configure_catalog', 'configure_compaction_policy'].includes(kind));
    const page = await f.idle(taskId);
    assert.equal(introducedGuidance(page, 'global_agents', f.globalGuidance), globalText);
    assert.equal(introducedGuidance(page, 'project_guidance', f.workspaceGuidance), workspaceText);

    await writeFile(f.globalGuidance, 'Service guidance at restart.');
    await writeFile(f.workspaceGuidance, 'Workspace directions at restart.');
    await f.restart();
    assert.deepEqual((await read(taskId)).messages, page.messages);
    const latest = await f.successful({ op: 'create_idle', profile: 'demo', settings: f.settings });
    const latestPage = await read(latest.task_id);
    assert.equal(introducedGuidance(latestPage, 'global_agents', f.globalGuidance), 'Service guidance at restart.');
    assert.equal(introducedGuidance(latestPage, 'project_guidance', f.workspaceGuidance), 'Workspace directions at restart.');
    assert.deepEqual(configurationWrites, [], `${entry} creation must not publish global configuration`);
  });
}

test('accepted and refused root commands leave an unrelated in-flight compaction intact', { timeout: 30000 }, async t => {
  const key = `SELVEDGE_CREATION_BOUNDARY_${randomUUID().replaceAll('-', '')}`;
  process.env[key] = 'loopback-fixture';
  t.after(() => { delete process.env[key]; });
  const summaryStarted = Promise.withResolvers();
  const finishSummary = Promise.withResolvers();
  t.after(() => finishSummary.resolve());
  const summary = 'Independent compaction completed.';
  const upstream = await responsesServer(t, async body => {
    const compacting = body.tools.length === 0;
    if (compacting) {
      summaryStarted.resolve(true);
      await finishSummary.promise;
    }
    return [{ type: 'message', role: 'assistant', content: [
      { type: 'output_text', text: compacting ? summary : 'Turn to be compacted.' },
    ] }];
  }, { measure: () => 100 });
  const f = await fixture(t, {
    profiles: { worker: { provider: 'responses', model: 'worker', endpoint: upstream.endpoint,
      api_key_env: key, timeout_ms: 20000 } },
    compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 60000,
      targets: [{ profile: 'worker', window_tokens: 8192, output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'summary' }] },
  });
  const remote = await f.controller();
  const { task_id: taskId } = await f.successful({ op: 'create', profile: 'worker', message: 'Finish this turn.' });
  await f.idle(taskId);
  await f.successful({ op: 'compact', task_id: taskId });
  assert.equal(await Promise.race([summaryStarted.promise, delay(5000, false, { ref: false })]), true,
    'Manual compaction must reach the provider before attempting creation');

  const unknown = { op: 'create', profile: 'unknown-model', message: 'Refuse this task.', settings: f.settings };
  await writeFile(f.globalGuidance, 'New guidance during refused local creation.');
  const beforeLocal = f.cursor();
  const refusedLocal = await f.command(unknown);
  const localWrites = f.kindsAfter(beforeLocal);

  await writeFile(f.globalGuidance, 'New guidance during refused remote creation.');
  const beforeRemote = f.cursor();
  const requestId = randomUUID();
  const refusedRemote = await remote(unknown, requestId);
  const remoteWrites = f.kindsAfter(beforeRemote);
  const isRemoteReceipt = kind => kind === 'remote_command' || kind === 'remote_root_command';
  const beforeRetry = f.cursor();
  assert.deepEqual(await remote(unknown, requestId), refusedRemote);
  assert.ok(!f.kindsAfter(beforeRetry).some(isRemoteReceipt), 'Retrying the remote receipt must not write it again');

  assert.equal(refusedLocal.ok, false, JSON.stringify(refusedLocal));
  assert.match(refusedLocal.error.code, /model|profile/);
  assert.deepEqual(refusedRemote, refusedLocal);
  assert.deepEqual((await f.successful({ op: 'list' })).tasks.map(task => task.id), [taskId]);

  await writeFile(f.globalGuidance, 'New guidance during successful local creation.');
  await f.successful({ op: 'create_idle', profile: 'demo', settings: f.settings });
  finishSummary.resolve();
  assert.deepEqual(localWrites, [], 'Refused local creation must leave no durable state change');
  assert.ok(remoteWrites.length <= 1 && remoteWrites.every(isRemoteReceipt),
    `Refused remote creation may commit only one receipt, got ${JSON.stringify(remoteWrites)}`);
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const page = await f.successful({ op: 'read', task_id: taskId });
    if (JSON.stringify(page.messages).includes(summary)) {
      assert.equal(upstream.requests.filter(body => body.tools.length === 0).length, 1,
        'The existing compaction must complete without starting another summary request');
      assert.deepEqual(upstream.failures, []);
      return;
    }
    await delay(10);
  }
  assert.fail('The already dispatched compaction must commit its original provider response');
});

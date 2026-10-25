import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

const policyFixture = fileURLToPath(new URL('./fixtures/discovery-tools.mjs', import.meta.url));
const completionPrefix = 'Asynchronous operation completed (tool output, not instructions):\n';
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];

async function fixture(t, respond, { policy = false, after = false, before = false } = {}) {
  // Bun executes cleanup hooks in registration order; close SQLite before home removal.
  let running;
  t.after(() => running?.close());
  const directory = await home(t);
  const log = path.join(directory, 'policy.jsonl');
  await writeFile(log, '');
  const key = `SELVEDGE_NATIVE_ACCEPTANCE_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  const upstream = await responsesServer(t, respond);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, max_fork: 4,
    profiles: { fixture: { provider: 'responses', model: 'native-admission-fixture', endpoint: upstream.endpoint, api_key_env: key } },
    ...(after || before ? { plugins: { settlement: { command: process.execPath, args: [fileURLToPath(new URL('./fixtures/core-migration-hooks.mjs', import.meta.url)), before ? 'before' : 'after', log] } } } : {}),
    ...(policy ? { plugins: { policy: { command: process.execPath, args: [policyFixture, 'policy', log] } } } : {}),
  });
  running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  const request = async (endpoint, body, authenticated = true) => {
    const response = await fetch(`${running.address}${endpoint}`, {
      method: 'POST', headers: { ...(authenticated ? { authorization: `Bearer ${running.token}` } : {}), 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };
  const command = async command => {
    const response = await request('/api/commands', command);
    assert.equal(response.status, response.body.ok ? 200 : 400, JSON.stringify(response));
    return response.body;
  };
  const successful = async command_ => {
    const reply = await command(command_);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply;
  };
  const idle = async task_id => {
    const deadline = Date.now() + 15000;
    let reply;
    do {
      assert.deepEqual(upstream.failures, [], 'The controlled model peer must complete its protocol assertions');
      reply = await successful({ op: 'read', task_id });
      if (reply.result.task.phase === 'idle' && reply.result.task.operations.length === 0) return reply;
      await delay(15);
    } while (Date.now() < deadline);
    // DEFENSE: A real provider or subprocess regression must fail within the fixture deadline.
    assert.fail(`Task did not settle: ${JSON.stringify(reply)}`);
  };
  const hooks = async () => (await readFile(log, 'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse);
  const snapshot = async () => {
    const response = await fetch(`${running.address}/api/browser/state`, { headers: { authorization: `Bearer ${running.token}` } });
    assert.equal(response.status, 200);
    return (await response.json()).program;
  };
  return { directory, upstream, request, command, successful, idle, hooks, snapshot, releaseHooks: () => writeFile(`${log}.release`, '') };
}

test('manual fork receipts cannot complete provider calls awaiting human approval', { timeout: 30000 }, async t => {
  let service;
  let callIds;
  service = await fixture(t, async () => {
    if (callIds) return done;
    const task = (await service.snapshot()).tasks[0];
    const ticket = task.model_pending.ticket;
    callIds = [ticket + 2, ticket + 3].map(value => `manual-fork-${value}`);
    return callIds.map(call_id => ({ type: 'function_call', call_id, name: 'bash',
      arguments: JSON.stringify({ command: 'printf WAITING-FOR-HUMAN', sandbox_permissions: 'require_escalated',
        justification: 'The fixture requires a real human approval boundary.' }) }));
  });
  const created = await service.successful({ op: 'create', profile: 'fixture', message: 'Wait for human approval.',
    settings: { approval: { mode: 'ask-for-approval' } } });
  const task_id = created.result.task_id;
  let before;
  for (let attempt = 0; attempt < 500; attempt++) {
    assert.deepEqual(service.upstream.failures, [], 'The controlled provider must accept the complete public request');
    before = (await service.successful({ op: 'read', task_id })).result.task;
    if (before.phase === 'idle' && before.operations.length === 2) break;
    await delay(10);
  }
  assert.equal(before.phase, 'idle');
  assert.deepEqual(before.operations.map(operation => operation.call_id), callIds);
  assert.ok(before.operations.every(operation => operation.status === 'awaiting_approval'));
  const forked = await service.successful({ op: 'fork', task_id, child_count: 1 });
  assert.equal(forked.result.children.length, 1);
  const afterRead = await service.successful({ op: 'read', task_id });
  const after = afterRead.result.task;
  assert.deepEqual(after.operations.map(operation => operation.operation_id), before.operations.map(operation => operation.operation_id));
  assert.ok(after.operations.every(operation => operation.status === 'awaiting_approval'));
  assert.deepEqual(afterRead.result.messages.filter(message => message.receipt_kind === 'fork_result' && callIds.includes(message.call_id)), [],
    'A manual fork has no authority to publish a result for either provider invocation');
  for (const operation of after.operations) await service.successful({ op: 'review_approval', task_id,
    operation_id: operation.operation_id, decision: 'deny', reason: 'The fixture leaves both commands unexecuted.' });
  await service.idle(task_id);
});

test('model native admission rejects final invalid arguments after hooks and preserves real fork returns', { timeout: 30000 }, async t => {
  let service;
  let frozenTools;
  let step = 0;
  let invalidCall;
  const branches = new Set();
  const invalidCalls = [
    { id: 'fork-over-limit', name: 'fork_task', arguments: { child_count: 5 } },
    { id: 'primitive-null', name: 'bash', arguments: { command: 'printf NATIVE-OMITTED-OK', mode: null } },
    { id: 'unknown-settings', name: 'fork_task', arguments: { child_count: 1, settings: { unexpected: true } } },
  ];
  const calls = [
    { id: 'primitive-omitted', name: 'bash', arguments: { command: 'printf NATIVE-OMITTED-OK' } },
    { id: 'fork-two', name: 'fork_task', arguments: { child_count: 2 } },
  ];
  service = await fixture(t, async body => {
    if (frozenTools) assert.deepEqual(body.tools, frozenTools, 'Parent and children retain the advertised frozen contracts');
    else {
      frozenTools = body.tools;
      const fork = body.tools.find(tool => tool.name === 'fork_task');
      assert.ok(fork, 'The actual model request advertises the native fork tool');
      assert.equal(fork.parameters.properties.child_count.minimum, 1);
      assert.equal(fork.parameters.properties.child_count.maximum, 4);
      const objectSchema = schema => [schema, ...(schema.anyOf ?? [])].find(branch => branch.type === 'object');
      const settings = objectSchema(fork.parameters.properties.settings);
      assert.equal(settings.additionalProperties, false);
      for (const field of ['workspace', 'sandbox', 'approval']) {
        assert.equal(objectSchema(settings.properties[field]).additionalProperties, false);
      }
    }
    if (invalidCall) return [{ type: 'function_call', call_id: invalidCall.id,
      name: invalidCall.name, arguments: JSON.stringify(invalidCall.arguments) }];
    const outputs = new Map();
    for (const item of body.input) {
      if (item.type === 'function_call_output') outputs.set(item.call_id, JSON.parse(item.output));
      if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith(completionPrefix)) {
        const result = JSON.parse(item.content.slice(completionPrefix.length));
        outputs.set(result.call_id, result);
      }
    }
    if (outputs.has('fork-two')) {
      const result = outputs.get('fork-two');
      assert.equal(result.is_error, false, JSON.stringify(result));
      assert.ok([0, 1, 2].includes(result.value), 'The fork returns the parent or its own child ordinal');
      branches.add(result.value);
      return done;
    }
    if (step > 0) {
      const previous = calls[step - 1];
      const result = outputs.get(previous.id);
      if (!result || result.value?.status === 'running') return done;
      assert.equal(result.is_error, false, JSON.stringify(result));
      assert.equal(result.value.exit_code, 0, JSON.stringify(result));
      assert.equal(result.value.stdout, 'NATIVE-OMITTED-OK');
    }
    const call = calls[step++];
    assert.ok(call, 'The parent reaches the valid fork only once');
    return [{ type: 'function_call', call_id: call.id, name: call.name, arguments: JSON.stringify(call.arguments) }];
  }, { policy: true });
  for (const [index, call] of invalidCalls.entries()) {
    invalidCall = call;
    const created = await service.successful({ op: 'create', profile: 'fixture', message: `Reject ${call.id}.` });
    const page = await service.idle(created.result.task_id);
    assert.ok(page.result.messages.some(message => message.role === 'error'),
      'Rejected model arguments are reported through public task history');
    assert.equal((await service.hooks()).some(event => event.call.id === call.id), true,
      'Object arguments pass through the frozen policy chain before final admission');
    const tasks = (await service.successful({ op: 'list' })).result.tasks;
    assert.equal(tasks.length, index + 1, 'Rejected native calls must not allocate children');
    assert.ok(tasks.every(task => task.parent === null));
  }
  invalidCall = null;
  const created = await service.successful({ op: 'create', profile: 'fixture', message: 'Exercise native argument admission.' });
  try {
    await service.idle(created.result.task_id);
    const tasks = (await service.successful({ op: 'list' })).result.tasks;
    assert.equal(tasks.length, invalidCalls.length + 3);
    await Promise.all(tasks.map(task => service.idle(task.id)));
  } finally {
    // DEFENSE: A controlled provider assertion can otherwise appear only as a later task timeout.
    assert.deepEqual(service.upstream.failures, []);
  }
  assert.deepEqual([...branches].sort(), [0, 1, 2]);
  assert.deepEqual((await service.hooks()).map(event => event.call.id), [...invalidCalls.map(call => call.id), 'primitive-omitted', 'fork-two']);
});

test('authenticated assessment is read-only and shares trusted preparation and command admission', { timeout: 30000 }, async t => {
  const service = await fixture(t, async () => done);
  const workspace = path.join(service.directory, 'project 工作区');
  await mkdir(workspace);
  const guidance = path.join(workspace, 'AGENTS.md');
  await writeFile(guidance, 'Original trusted Project guidance.');
  const createProject = { op: 'create_project', name: 'Assessment Project',
    workspace: { roots: [workspace], primary_root: workspace } };
  const projectsBefore = await service.successful({ op: 'list_projects' });
  const creationAssessment = await service.request('/api/assess', { command: createProject,
    editor: 'new-project', revision: 1, sequence: projectsBefore.sequence });
  assert.equal(creationAssessment.status, 200);
  assert.equal(creationAssessment.body.admitted, true, JSON.stringify(creationAssessment.body));
  assert.deepEqual(await service.successful({ op: 'list_projects' }), projectsBefore);
  const project = await service.successful(createProject);
  const project_id = project.result.project_id;
  assert.equal((await service.successful({ op: 'read_project', project_id })).result.guidance.instructions,
    'Original trusted Project guidance.');

  await writeFile(guidance, 'Updated trusted Project guidance.');
  const updateProject = { op: 'update_project', project_id, name: 'Assessment Project revised',
    workspace: { roots: [workspace], primary_root: workspace }, create_worktree: false };
  const projectBefore = await service.successful({ op: 'read_project', project_id });
  const updateAssessment = await service.request('/api/assess', { command: updateProject,
    editor: { project_id, occurrence: 'project-settings' }, revision: 2, sequence: projectBefore.sequence });
  assert.equal(updateAssessment.status, 200);
  assert.equal(updateAssessment.body.admitted, true, JSON.stringify(updateAssessment.body));
  assert.deepEqual(await service.successful({ op: 'read_project', project_id }), projectBefore,
    'Project preparation must not publish observed guidance before submission');
  const saved = await service.request('/api/browser/command', { command: updateProject });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  const updatedProject = (await service.successful({ op: 'read_project', project_id })).result;
  assert.equal(updatedProject.name, 'Assessment Project revised');
  assert.equal(updatedProject.guidance.path, guidance);
  assert.equal(updatedProject.guidance.instructions, 'Updated trusted Project guidance.',
    'The saved Project uses service-observed guidance without a client-supplied snapshot');

  const missingWorkspace = path.join(service.directory, 'missing-project');
  const unavailableProject = { op: 'create_project', name: 'Unavailable Project',
    workspace: { roots: [missingWorkspace], primary_root: missingWorkspace } };
  const beforeUnavailable = await service.successful({ op: 'list_projects' });
  const unavailableAssessment = await service.request('/api/assess', { command: unavailableProject,
    editor: 'unavailable-project', revision: 3, sequence: beforeUnavailable.sequence });
  assert.ok(unavailableAssessment.status === 400
    || (unavailableAssessment.status === 200 && unavailableAssessment.body.admitted === false),
  `An absent workspace must fail preparation or admission: ${JSON.stringify(unavailableAssessment)}`);
  assert.equal((await service.command(unavailableProject)).ok, false);
  assert.deepEqual(await service.successful({ op: 'list_projects' }), beforeUnavailable,
    'Failed filesystem preparation does not create a Project or commit a sequence');

  const created = await service.successful({ op: 'create_idle', profile: 'fixture' });
  const parent = created.result.task_id;
  const read = await service.successful({ op: 'read', task_id: parent });
  assert.equal(read.result.task.phase, 'idle');
  const before = await service.successful({ op: 'list' });
  const invalid = { op: 'fork', task_id: parent, child_count: 2, messages: ['wrong cardinality'] };
  const valid = { op: 'create', profile: 'fixture', message: 'ASSESSMENT-MUST-NOT-EXECUTE' };
  const requests = Array.from({ length: 6 }, (_, index) => ({
    command: index % 2 ? invalid : valid,
    editor: { object: 'draft', occurrence: `editor-${index}` }, revision: index + 1, sequence: 0,
  }));
  const unauthorized = await service.request('/api/assess', requests[0], false);
  assert.equal(unauthorized.status, 401);
  const assessments = await Promise.all(requests.map(request => service.request('/api/assess', request)));
  for (const [index, response] of assessments.entries()) {
    assert.equal(response.status, 200, JSON.stringify(response));
    assert.deepEqual(response.body.editor, requests[index].editor);
    assert.equal(response.body.revision, requests[index].revision);
    assert.equal(response.body.sequence, before.sequence, 'Assessment reports the actual worker revision, not the stale requested revision');
    assert.equal(response.body.admitted, index % 2 === 0);
    if (response.body.admitted) assert.equal(response.body.refusal, null);
  }
  assert.deepEqual(await service.successful({ op: 'list' }), before,
    'Concurrent assessments preserve tasks and the committed sequence');
  assert.equal(service.upstream.requests.length, 0, 'Assessment does not dispatch a model effect');
  const refused = await service.command(invalid);
  assert.equal(refused.ok, false);
  assert.deepEqual(refused.error, assessments[1].body.refusal);
  assert.equal((await service.successful({ op: 'list' })).result.tasks.length, 1);

  const messages = ['ONLY-CHILD-ONE 😀', 'ONLY-CHILD-TWO'];
  const forked = await service.successful({ op: 'fork', task_id: parent, child_count: 2, messages });
  assert.deepEqual(forked.result.children, [parent + 1, parent + 2], 'Read-only and rejected requests consume no child identity');
  for (const [index, task_id] of forked.result.children.entries()) {
    const page = await service.idle(task_id);
    const userMessages = page.result.messages.filter(message => message.role === 'user');
    assert.deepEqual(userMessages, [{ role: 'user', content: [{ type: 'text', text: messages[index] }] }]);
  }
  assert.deepEqual(service.upstream.failures, []);
  assert.equal((await service.successful({ op: 'list' })).result.tasks.length, 3);
});

test('manual fork keeps the parent settings and native fork accepts other unfinished operations', { timeout: 30000 }, async t => {
  const branches = new Set();
  let allowCalls = false;
  const service = await fixture(t, async body => {
    const outputs = new Map(body.input.filter(item => item.type === 'function_call_output')
      .map(item => [item.call_id, JSON.parse(item.output)]));
    if (outputs.has('fork-with-running-operation')) {
      branches.add(outputs.get('fork-with-running-operation').value);
      return done;
    }
    if (!allowCalls) return done;
    return [
      { type: 'function_call', call_id: 'unfinished-operation', name: 'bash',
        arguments: JSON.stringify({ command: 'sleep 0.2; printf OPERATION-COMPLETED' }) },
      { type: 'function_call', call_id: 'fork-with-running-operation', name: 'fork_task',
        arguments: JSON.stringify({ child_count: 1 }) },
    ];
  });
  const created = await service.successful({ op: 'create_idle', profile: 'fixture',
    settings: { sandbox: { mode: 'read-only', network_access: false } } });
  const parent = created.result.task_id;
  const before = (await service.successful({ op: 'read', task_id: parent })).result.task.settings;
  const forked = await service.successful({ op: 'fork', task_id: parent, child_count: 1,
    settings_origin: 'environment' });
  await service.idle(parent);
  const after = (await service.successful({ op: 'read', task_id: parent })).result.task.settings;
  assert.deepEqual(after, before, 'Selecting environment settings configures the child and preserves its parent');
  const child = (await service.successful({ op: 'read', task_id: forked.result.children[0] })).result.task;
  assert.notDeepEqual(child.settings.sandbox, before.sandbox);

  allowCalls = true;
  const active = await service.successful({ op: 'create', profile: 'fixture', message: 'Fork while Bash is unfinished.' });
  const task = await service.idle(active.result.task_id);
  const tasks = (await service.successful({ op: 'list' })).result.tasks;
  await Promise.all(tasks.map(entry => service.idle(entry.id)));
  assert.deepEqual([...branches].sort(), [0, 1], 'The native caller and its child receive their own successful fork results');
  assert.equal(task.result.task.operations.length, 0);
});

test('native independent creation uses ordinary defaults when settings are omitted', { timeout: 30000 }, async t => {
  const service = await fixture(t, async body => {
    const created = body.input.find(item => item.type === 'function_call_output' && item.call_id === 'independent-defaults');
    if (created || body.input.some(item => item.role === 'user' && JSON.stringify(item.content).includes('INDEPENDENT-CHILD'))) return done;
    return [{ type: 'function_call', call_id: 'independent-defaults', name: 'create_task',
      arguments: JSON.stringify({ profile: 'fixture', message: 'INDEPENDENT-CHILD' }) }];
  });
  const workspace = path.join(service.directory, 'caller-only');
  await mkdir(workspace);
  const parent = await service.successful({ op: 'create', profile: 'fixture', message: 'Create the independent task.',
    settings: { workspace: { roots: [workspace], primary_root: workspace }, approval: { mode: 'full-access' } } });
  await service.idle(parent.result.task_id);
  const tasks = (await service.successful({ op: 'list' })).result.tasks;
  assert.equal(tasks.length, 2);
  const child = tasks.find(task => task.id !== parent.result.task_id);
  const read = (await service.idle(child.id)).result.task;
  assert.deepEqual(read.settings.workspace.roots, [service.directory]);
  assert.equal(read.settings.approval.mode, 'ask-for-approval');
});

test('a managed task completes every after hook after it archives itself', { timeout: 30000 }, async t => {
  let owner;
  const service = await fixture(t, async body => {
    if (owner === undefined) return done;
    return [{ type: 'function_call', call_id: 'archive-self', name: 'archive_task',
      arguments: JSON.stringify({ task_id: owner }) }];
  }, { after: true });
  const repository = path.join(service.directory, 'source');
  await mkdir(repository);
  const git = (...args) => promisify(execFile)('git', ['-C', repository, ...args]);
  await git('init', '--initial-branch=main');
  await writeFile(path.join(repository, 'README.md'), 'Core migration archive fixture.\n');
  await git('add', 'README.md');
  await git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-m', 'initial');
  const created = await service.successful({ op: 'create_idle', profile: 'fixture', create_worktree: true,
    settings: { workspace: { roots: [repository], primary_root: repository } } });
  owner = created.result.task_id;
  await service.successful({ op: 'send', task_id: owner, message: 'Archive this task after processing the result.' });
  const deadline = Date.now() + 15000;
  let observed;
  do {
    observed = (await service.successful({ op: 'read', task_id: owner })).result.task;
    if (observed.status === 'archived' && observed.operations.length === 0) break;
    await delay(15);
  } while (Date.now() < deadline);
  assert.equal(observed.status, 'archived');
  assert.equal(observed.operations.length, 0, 'Archive preserves the executing native result until its after hook settles');
  const hooks = await service.hooks();
  assert.equal(hooks.length, 1, 'The real plugin receives the archived native result once');
  assert.equal(hooks[0].call.id, 'archive-self');
  assert.deepEqual(service.upstream.failures, []);
});

test('a native fork accepted before Stop still runs after its authorization callback', { timeout: 30000 }, async t => {
  const service = await fixture(t, async body => {
    if (body.input.some(item => item.type === 'function_call_output' && item.call_id === 'stopped-fork')) return done;
    return [{ type: 'function_call', call_id: 'stopped-fork', name: 'fork_task', arguments: JSON.stringify({ child_count: 1 }) }];
  }, { before: true });
  const created = await service.successful({ op: 'create', profile: 'fixture', message: 'Fork after the pending policy finishes.' });
  const owner = created.result.task_id;
  const deadline = Date.now() + 15000;
  while ((await service.hooks()).length === 0 && Date.now() < deadline) await delay(15);
  assert.equal((await service.hooks()).length, 1, 'The native invocation reaches the actual policy peer before Stop');
  await service.successful({ op: 'stop', task_id: owner });
  await service.releaseHooks();
  await service.idle(owner);
  const tasks = (await service.successful({ op: 'list' })).result.tasks;
  assert.equal(tasks.length, 2, 'Stopping new inference preserves the accepted native fork');
  const parent = (await service.successful({ op: 'read', task_id: owner })).result.task;
  assert.equal(parent.status, 'stopped');
  await Promise.all(tasks.filter(task => task.id !== owner).map(task => service.idle(task.id)));
});

test('provider duplicate argument members survive allowing hooks, history and provider replay until final admission', { timeout: 30000 }, async t => {
  const arguments_json = '{"command":"printf DUPLICATE-FIRST","command":"printf DUPLICATE-LAST"}';
  let requested = false;
  let replayed = false;
  const service = await fixture(t, async body => {
    if (!requested) {
      requested = true;
      return [{ type: 'function_call', call_id: 'duplicate-arguments', name: 'bash', arguments: arguments_json }];
    }
    const call = body.input.find(item => item.type === 'function_call' && item.call_id === 'duplicate-arguments');
    assert.equal(call?.arguments, arguments_json, 'Provider history must retain both original member occurrences');
    replayed = true;
    return done;
  }, { policy: true });
  const created = await service.successful({ op: 'create', profile: 'fixture', message: 'Exercise final tool argument admission.' });
  const settled = await service.idle(created.result.task_id);
  assert.equal(replayed, true);
  const messages = settled.result.messages;
  const call = messages.find(item => item.role === 'function_call');
  assert.equal(call.content.arguments_json, arguments_json);
  const failure = messages.find(item => item.role === 'function_output' && item.call_id === 'duplicate-arguments');
  assert.equal(failure?.is_error, true, 'Allow must retain duplicate members for the final native rejection');
  assert.ok((await service.hooks()).some(item => item.method === 'beforeTool' && item.call.id === 'duplicate-arguments'));
});

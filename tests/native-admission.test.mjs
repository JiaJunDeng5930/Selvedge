import test from 'node:test';
import assert from 'node:assert/strict';
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

async function fixture(t, respond, { policy = false } = {}) {
  const directory = await home(t);
  const log = path.join(directory, 'policy.jsonl');
  await writeFile(log, '');
  const key = `SELVEDGE_NATIVE_ACCEPTANCE_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  const upstream = await responsesServer(t, respond);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, max_fork: 4,
    profiles: { fixture: { provider: 'responses', model: 'native-admission-fixture', endpoint: upstream.endpoint, api_key_env: key } },
    ...(policy ? { plugins: { policy: { command: process.execPath, args: [policyFixture, 'policy', log] } } } : {}),
  });
  const running = await startServer({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => running.close());
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
  return { directory, upstream, request, command, successful, idle, hooks };
}

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

  const created = await service.successful({ op: 'create_idle', profile: 'fixture', settings: null });
  const parent = created.result.task_id;
  const read = await service.successful({ op: 'read', task_id: parent, after: null, limit: null });
  assert.equal(read.result.task.phase, 'idle', 'Nullable public command options retain their default meaning');
  assert.deepEqual(read, await service.successful({ op: 'read', task_id: parent }));
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

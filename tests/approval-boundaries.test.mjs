import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import { imagesFixture } from './fixtures/images.mjs';
import { home, responsesServer, shellQuote } from './support.mjs';

const workerModel = 'approval-boundary-worker';
const reviewerModel = 'approval-boundary-reviewer';
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

async function serviceFixture(t, respond) {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const state = path.join(directory, 'state');
  const marker = path.join(directory, 'outside-workspace.txt');
  await mkdir(workspace);
  const apiKey = `SELVEDGE_APPROVAL_BOUNDARIES_${randomBytes(8).toString('hex').toUpperCase()}`;
  process.env[apiKey] = 'loopback-fixture-only';
  t.after(() => { delete process.env[apiKey]; });

  const upstream = await responsesServer(t, respond);
  const running = await startServer({ home: state, cwd: workspace, config: validateConfig({
    ...defaultConfig, chatgpt: false, port: 0, profiles: {
      worker: { provider: 'responses', model: workerModel, endpoint: upstream.endpoint, api_key_env: apiKey },
      judge: { provider: 'responses', model: reviewerModel, endpoint: upstream.endpoint, api_key_env: apiKey },
    },
  }) });
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
  async function create(message, approval) {
    return successful({ op: 'create', profile: 'worker', message, settings: {
      workspace: { roots: [workspace], primary_root: workspace }, approval,
    } });
  }
  async function read(task_id) { return successful({ op: 'read', task_id }); }
  async function until(observe, accepts, description) {
    const deadline = Date.now() + 10000;
    let value;
    do {
      value = await observe();
      if (accepts(value)) return value;
      await delay(10);
    } while (Date.now() < deadline);
    // DEFENSE: A real service or provider regression can prevent the public workflow from reaching its accepted state.
    assert.fail(`${description}: ${JSON.stringify(value)}`);
  }

  return { directory, workspace, marker, upstream, command, successful, create, read, until };
}

function toolResponse(marker, state) {
  if (state.model === reviewerModel) {
    state.reviewerRequests.push(state.body);
    return answer(state.reviewerAnswer);
  }
  assert.equal(state.model, workerModel);
  if (++state.workerCalls === state.toolCallAt) {
    return [{ type: 'function_call', call_id: 'approval-boundary-call', name: 'bash', arguments: JSON.stringify({
      command: `printf 'ran\\n' > ${shellQuote(marker)}`,
      sandbox_permissions: 'require_escalated', justification: 'Write the requested marker outside the workspace.', timeout_ms: 5000,
    }) }];
  }
  return answer('The reviewed command did not change the task request.');
}

function inputImages(value) {
  if (Array.isArray(value)) return value.flatMap(inputImages);
  if (value === null || typeof value !== 'object') return [];
  if (value.type === 'input_image') return [value];
  return Object.values(value).flatMap(inputImages);
}

function advertisedFunctions(tools, namespace) {
  return tools.flatMap(tool => tool.type === 'namespace'
    ? advertisedFunctions(tool.tools, tool.name) : [{ ...tool, namespace }]);
}

for (const [description, reviewerAnswer] of [
  ['a missing reason', '{"decision":"allow"}'],
  ['an empty reason', '{"decision":"allow","reason":""}'],
]) {
  test(`a reviewer allow with ${description} cannot authorize an escalated command`, async t => {
    const state = { model: '', body: null, reviewerAnswer, reviewerRequests: [], workerCalls: 0, toolCallAt: 1 };
    const fixture = await serviceFixture(t, body => {
      state.model = body.model;
      state.body = body;
      return toolResponse(fixture.marker, state);
    });
    const { task_id } = await fixture.create('Write the requested marker.', {
      mode: 'approval-for-me', reviewer_profile: 'judge',
    });
    const page = await fixture.until(
      () => fixture.read(task_id),
      value => value.task.phase === 'idle' && value.task.operations.length === 0,
      'The reviewed task must settle',
    );

    assert.equal(state.reviewerRequests.length, 1, 'The configured independent reviewer must receive the request');
    const records = page.messages.filter(value => value.role === 'approval_record' && value.call.id === 'approval-boundary-call');
    assert.equal(records.length, 1);
    assert.notEqual(records[0].content.decision, 'allow');
    assert.equal(typeof records[0].content.reason, 'string');
    assert.ok(records[0].content.reason.length > 0);
    await assert.rejects(readFile(fixture.marker), { code: 'ENOENT' });
    assert.deepEqual(fixture.upstream.failures, []);
  });
}

test('the independent reviewer receives only the latest four user text requests, each bounded by 4096 Unicode code points', async t => {
  const state = {
    model: '', body: null, reviewerAnswer: '{"decision":"deny","reason":"Inspect only."}',
    reviewerRequests: [], workerCalls: 0, toolCallAt: 5,
  };
  let fixture;
  fixture = await serviceFixture(t, body => {
    state.model = body.model;
    state.body = body;
    return toolResponse(fixture.marker, state);
  });
  const edgeRequest = `${'界'.repeat(4095)}😀OMITTED_SUFFIX`;
  const messages = [
    'Omitted oldest request.',
    'Second request 😀',
    edgeRequest,
    'Fourth request: inspect only.',
    'Latest request: inspect the directory without changing files.',
  ];
  const { task_id } = await fixture.create(messages[0], {
    mode: 'approval-for-me', reviewer_profile: 'judge',
  });
  await fixture.until(
    () => fixture.read(task_id),
    value => value.task.phase === 'idle' && value.task.operations.length === 0,
    'The initial request must settle',
  );
  for (const message of messages.slice(1)) {
    await fixture.successful({ op: 'send', task_id, message });
    await fixture.until(
      () => fixture.read(task_id),
      value => value.task.phase === 'idle' && value.task.operations.length === 0,
      'The user request must settle',
    );
  }

  assert.equal(state.reviewerRequests.length, 1, 'One escalated tool call must produce one actual reviewer request');
  const request = state.reviewerRequests[0];
  const userMessage = request.input.find(value => value.role === 'user');
  const content = typeof userMessage.content === 'string' ? userMessage.content
    : userMessage.content.filter(value => value.type === 'input_text').map(value => value.text).join('');
  const excerpt = JSON.parse(content).recent_user_requests_newest_first;
  assert.deepEqual(excerpt, [messages[4], messages[3], `${'界'.repeat(4095)}😀`, messages[1]]);
  assert.equal(JSON.parse(content).command.arguments.command,
    `printf 'ran\\n' > ${shellQuote(fixture.marker)}`);
  assert.equal(request.model, reviewerModel);
  await assert.rejects(readFile(fixture.marker), { code: 'ENOENT' });
  assert.deepEqual(fixture.upstream.failures, []);
});

test('an uploaded image reaches the worker and stays out of the reviewer request', async t => {
  const apiKey = `SELVEDGE_APPROVAL_IMAGE_BOUNDARY_${randomBytes(8).toString('hex').toUpperCase()}`;
  process.env[apiKey] = 'loopback-fixture-only';
  t.after(() => { delete process.env[apiKey]; });
  const reviewerRequests = [];
  const reviewer = await responsesServer(t, body => {
    reviewerRequests.push(body);
    return answer('{"decision":"deny","reason":"Inspect only."}');
  });
  const message = 'Inspect this image and workspace without changing files.';
  let workerCalls = 0;
  let marker;
  const fixture = await imagesFixture(t, {
    includeTextProfile: false,
    respond: body => {
      const bash = advertisedFunctions(body.tools).find(tool => tool.name === 'bash');
      assert.ok(bash, 'The public worker request must advertise its Bash tool');
      if (++workerCalls !== 1) return answer('The reviewed command did not change the task request.');
      return [{ type: 'function_call', call_id: 'approval-image-call', name: bash.name,
        namespace: bash.namespace, arguments: JSON.stringify({
          command: `printf 'ran\\n' > ${shellQuote(marker)}`,
          sandbox_permissions: 'require_escalated',
          justification: 'Write the requested marker outside the workspace.',
          timeout_ms: 5000,
        }) }];
    },
    configOverrides: { profiles: {
      judge: { provider: 'responses', model: reviewerModel, endpoint: reviewer.endpoint,
        api_key_env: apiKey, timeout_ms: 5000 },
    } },
  });
  const workspace = path.join(fixture.workspace, 'workspace');
  await mkdir(workspace);
  marker = path.join(fixture.workspace, 'outside-workspace.txt');
  const uploaded = await fixture.upload('approval-boundary.png');
  const { task_id } = await fixture.command({
    op: 'create', profile: fixture.profile, message, images: [uploaded], settings: {
      workspace: { roots: [workspace], primary_root: workspace },
      approval: { mode: 'approval-for-me', reviewer_profile: 'judge' },
    },
  });

  async function untilIdle() {
    const deadline = Date.now() + 10000;
    let current;
    do {
      current = await fixture.command({ op: 'read', task_id });
      if (current.task.phase === 'idle' && current.task.operations.length === 0) return current;
      await delay(10);
    } while (Date.now() < deadline);
    assert.fail(`The reviewed task must settle: ${JSON.stringify(current)}`);
  }
  await untilIdle();

  assert.ok(fixture.requests.some(request => inputImages(request.input).length === 1),
    'The public task request must deliver its uploaded image to the worker model');
  assert.equal(reviewerRequests.length, 1, 'One escalated tool call must produce one actual reviewer request');
  const request = reviewerRequests[0];
  assert.deepEqual(inputImages(request), [], 'The reviewer request must contain no image blocks');
  assert.equal(JSON.stringify(request).includes('data:image/png;base64,'), false,
    'The reviewer request must contain no encoded image data');
  const userMessage = request.input.find(value => value.role === 'user');
  const content = typeof userMessage.content === 'string' ? userMessage.content
    : userMessage.content.filter(value => value.type === 'input_text').map(value => value.text).join('');
  const excerpt = JSON.parse(content).recent_user_requests_newest_first;
  assert.deepEqual(excerpt, [message],
    'The reviewer receives the admitted text without an image placeholder or attachment data');
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  assert.deepEqual(reviewer.failures, []);
  assert.deepEqual(fixture.upstream.failures, []);
});

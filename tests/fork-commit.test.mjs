import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const completion = 'Continued after the committed fork.';

async function fixture(t) {
  const directory = await home(t);
  const key = `SELVEDGE_FORK_COMMIT_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  const upstream = await responsesServer(t, () => [{ type: 'message', role: 'assistant',
    content: [{ type: 'output_text', text: completion }] }]);
  const options = { home: path.join(directory, 'state'), cwd: directory,
    config: validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
      worker: { provider: 'responses', model: 'fork-commit-fixture',
        endpoint: upstream.endpoint, api_key_env: key },
    } }) };
  let service = await Service.open(options);
  t.after(() => service.close());
  return { upstream, get service() { return service; },
    async reopen() { service = await Service.open(options); } };
}

async function successful(service, command) {
  const result = await service.command(command);
  assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
  return result.reply.result;
}

async function completed(service, taskId) {
  const page = await taskIdle(service, taskId);
  assert.ok(page.messages.some(message => message.role === 'model_context'
    && message.content?.item?.content?.some(part => part.text === completion)),
  `Task ${taskId} must receive its own model completion after the fork commit`);
}

test('a committed manual fork automatically continues the parent and each child without another command', async t => {
  const fixture_ = await fixture(t);
  const { task_id: parent } = await successful(fixture_.service, { op: 'create_idle', profile: 'worker' });
  const forked = await successful(fixture_.service, { op: 'fork', task_id: parent,
    child_count: 2, messages: ['Continue the first child.', 'Continue the second child.'] });
  assert.equal(forked.children.length, 2);

  await Promise.all([parent, ...forked.children].map(taskId => completed(fixture_.service, taskId)));
  assert.equal(fixture_.upstream.requests.length, 3,
    'The host must consume the committed continuation for all three tasks');
  assert.deepEqual(fixture_.upstream.failures, []);
});

test('closing immediately after a fork commit retains births and resumes work that has not reached the provider', async t => {
  const fixture_ = await fixture(t);
  const { task_id: parent } = await successful(fixture_.service, { op: 'create_idle', profile: 'worker' });
  const forked = await successful(fixture_.service, { op: 'fork', task_id: parent,
    child_count: 1, messages: ['Continue this durably committed child after reopening.'] });

  // Keep shutdown in the continuation that receives the durable fork acknowledgement.
  await fixture_.service.close();
  const sentBeforeClose = fixture_.upstream.requests.length;
  t.diagnostic(`Model requests observed before shutdown: ${sentBeforeClose}`);
  await fixture_.reopen();
  const tasks = (await successful(fixture_.service, { op: 'list' })).tasks;
  assert.deepEqual(tasks.map(task => task.id), [parent, ...forked.children],
    'Journal reopen must retain the committed parent and the returned child references');
  const child = await successful(fixture_.service, { op: 'read', task_id: forked.children[0] });
  const parentPage = await successful(fixture_.service, { op: 'read', task_id: parent });
  for (const page of [parentPage, child]) {
    assert.ok(page.messages.some(message => message.receipt_kind === 'fork_result'),
      'Journal reopen must retain the committed fork receipt in each conversation');
  }
  assert.ok(child.messages.some(message => message.role === 'user'
    && message.content?.some(part => part.text === 'Continue this durably committed child after reopening.')));

  if (sentBeforeClose === 0) {
    await Promise.all([parent, ...forked.children].map(taskId => completed(fixture_.service, taskId)));
    assert.equal(fixture_.upstream.requests.length, 2,
      'Unsent work must continue after reopening without a client mutation');
  }
  assert.deepEqual(fixture_.upstream.failures, []);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';
import { approvalFixture } from './fixtures/approval-provenance-runtime.mjs';

const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];

for (const [description, reason] of [['an overlong UTF-8 reason', '界'.repeat(683)], ['a NUL in the reason', 'Allow\u0000trailing']]) {
  test(`a human approval with ${description} settles as failed without executing the command`, async t => {
    const fixture = await approvalFixture(t, 'human');
    const pending = await fixture.pending();
    const operation = pending.task.operations.find(value => value.status === 'awaiting_approval');
    await fixture.successful({ op: 'review_approval', task_id: fixture.taskId,
      operation_id: operation.operation_id, decision: 'allow', reason });
    const page = await fixture.idle();
    const records = page.messages.filter(value => value.role === 'approval_record' && value.operation_id === operation.operation_id);
    assert.equal(records.length, 1);
    assert.deepEqual(records[0].content, { decision: 'failed', reason: 'The review response exceeded its bounded decision contract' });
    assert.ok(JSON.stringify(page.messages).includes('approval_denied'), 'The original pending tool receives a denial result');
    await fixture.markerAbsent();
    assert.deepEqual(fixture.upstream.failures, []);
  });
}

test('an actual approval reviewer receives only the latest four bounded Unicode user requests', async t => {
  const directory = await home(t), reviews = [];
  const key = `SELVEDGE_APPROVAL_EXCERPTS_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture';
  t.after(() => { delete process.env[key]; });
  let workerCalls = 0;
  const upstream = await responsesServer(t, body => {
    if (body.model === 'excerpt-reviewer') {
      const message = body.input.find(value => value.role === 'user');
      const content = typeof message.content === 'string' ? message.content
        : message.content.filter(value => value.type === 'input_text').map(value => value.text).join('');
      reviews.push(JSON.parse(content));
      return answer('{"decision":"deny","reason":"The request permits inspection only."}');
    }
    assert.equal(body.model, 'excerpt-worker');
    if (++workerCalls === 5) return [{ type: 'function_call', call_id: 'excerpt-approval', name: 'bash',
      arguments: JSON.stringify({ command: 'pwd', sandbox_permissions: 'require_escalated',
        justification: 'Inspect the workspace directory.', timeout_ms: 5000 }) }];
    return answer('ASSISTANT_CONTENT_MUST_NOT_BECOME_APPROVAL_AUTHORITY');
  });
  const service = await Service.open({ home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false, profiles: {
      worker: { provider: 'responses', model: 'excerpt-worker', endpoint: upstream.endpoint, api_key_env: key },
      judge: { provider: 'responses', model: 'excerpt-reviewer', endpoint: upstream.endpoint, api_key_env: key },
    },
  }) });
  t.after(() => service.close());
  const messages = ['oldest request must be omitted', 'Second request 😀',
    'Third request: ' + '海😀'.repeat(2200) + 'OMITTED_SUFFIX', 'Fourth request: inspect only.',
    'Latest request: inspect the directory without changing files.'];
  const created = await service.command({ op: 'create', profile: 'worker', message: messages[0],
    settings: { approval: { mode: 'approval-for-me', reviewer_profile: 'judge' } } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const task_id = created.reply.result.task_id;
  await taskIdle(service, task_id);
  for (const message of messages.slice(1)) {
    const sent = await service.command({ op: 'send', task_id, message });
    assert.equal(sent.reply.ok, true, JSON.stringify(sent.reply));
    await taskIdle(service, task_id);
  }
  assert.equal(reviews.length, 1, 'One actual tool exception requests one review');
  assert.deepEqual(reviews[0].recent_user_requests_newest_first,
    [messages[4], messages[3], Array.from(messages[2]).slice(0, 4096).join(''), messages[1]]);
  assert.equal(Array.from(reviews[0].recent_user_requests_newest_first[2]).length, 4096,
    'The limit counts Unicode code points without splitting supplementary characters');
  assert.equal(reviews[0].command.arguments.command, 'pwd');
  assert.deepEqual(upstream.failures, []);
});

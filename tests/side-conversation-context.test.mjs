import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { interactiveMarkdownFixture } from './fixtures/interactive-markdown.mjs';
import { taskIdle } from './support.mjs';

async function nextRequest(fixture, offset) {
  const deadline = Date.now() + 10_000;
  while (fixture.requests.length <= offset && Date.now() < deadline) await delay(10);
  assert.ok(fixture.requests.length > offset, 'An independent Task must dispatch its provider request');
  return fixture.requests[offset].input;
}

const texts = request => request.input.map(item => typeof item.content === 'string' ? item.content : JSON.stringify(item.content)).join('\n');

test('side conversations receive trusted guidance and return only their new conversation content', async t => {
  const fixture = await interactiveMarkdownFixture();
  t.after(() => fixture.close());
  async function command(value) {
    const response = await fetch(`${fixture.running.address}/api/commands`, {
      method: 'POST', headers: { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(value),
    });
    assert.equal(response.status, 200);
    const reply = await response.json();
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  }
  const parent = await command({ op: 'create', profile: 'interactive', message: 'Continue the parent investigation independently.' });
  await nextRequest(fixture, 0);
  const side = await command({ op: 'open_side_conversation', task_id: parent.task_id,
    message: 'Check the distinct side question.' });
  const sideRequest = await nextRequest(fixture, 1);
  assert.equal(fixture.requests[0].closed, false,
    'The side provider request must start while the parent request remains in progress');
  const guidance = sideRequest.input.find(item => item.role === 'developer'
    && typeof item.content === 'string' && /Side conversation context/.test(item.content));
  assert.ok(guidance, 'The provider must receive the side context as trusted developer guidance');
  assert.match(guidance.content, /parent continues independently/i);
  assert.match(guidance.content, /Closing the side window sends nothing to the parent/i);
  assert.match(guidance.content, /Only the user.s explicit return action appends new side content to the parent/i);
  assert.ok(sideRequest.input.some(item => item.role === 'developer' && /task_lifecycle/.test(item.content)),
    'The side also receives observed parent lifecycle context');

  fixture.finish(0, { text: 'Parent investigation completed its first turn.' });
  fixture.finish(1, { text: 'The distinct side answer is cobalt-73.' });
  await Promise.all([
    taskIdle(fixture.running.service, parent.task_id), taskIdle(fixture.running.service, side.task_id),
  ]);
  const beforeReturn = await command({ op: 'read', task_id: parent.task_id });
  assert.ok(!JSON.stringify(beforeReturn).includes('cobalt-73'),
    'Finishing a side answer must not silently return it to the parent');

  await command({ op: 'send', task_id: side.task_id, message: 'Add the follow-up side finding.' });
  const continuedSide = await nextRequest(fixture, 2);
  assert.ok(continuedSide.input.some(item => item.role === 'developer' && /task_lifecycle/.test(item.content)),
    'The later side turn still sees current parent observations');
  fixture.finish(2, { text: 'The follow-up side finding is amber-29.' });
  await taskIdle(fixture.running.service, side.task_id);
  await command({ op: 'return_side_conversation', task_id: side.task_id });
  const returnedParent = await nextRequest(fixture, 3);
  const returnedText = texts(returnedParent);
  assert.match(returnedText, /cobalt-73/);
  assert.match(returnedText, /amber-29/);
  assert.match(returnedText, /Check the distinct side question/);
  assert.ok(!returnedText.includes(guidance.content), 'The side birth instructions must not return as conversation content');
  assert.ok(!returnedText.includes('Side conversation context for task'), 'No copy of side birth guidance belongs in the parent request');
  assert.ok(!returnedText.includes('task_lifecycle'), 'Parent lifecycle observations must not return as side conversation content');
  fixture.finish(3, { text: 'Parent received both explicit side findings.' });
  await taskIdle(fixture.running.service, parent.task_id);
  assert.deepEqual(fixture.failures, []);
});

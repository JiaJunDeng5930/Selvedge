import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { interactiveMarkdownFixture } from './fixtures/interactive-markdown.mjs';
import { taskIdle } from './support.mjs';

async function until(observe, description) {
  const deadline = Date.now() + 10_000;
  do {
    const value = observe();
    if (value) return value;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Timed out waiting for ${description}`);
}

test('HTTP and native agent search retain scoped original message locations across a restart', async t => {
  const fixture = await interactiveMarkdownFixture();
  t.after(() => fixture.close());
  const raw = async command => {
    const response = await fetch(`${fixture.running.address}/api/commands`, {
      method: 'POST', headers: { authorization: `Bearer ${fixture.running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(command),
    });
    assert.equal(response.status, 200);
    return response.json();
  };
  const command = async input => {
    const reply = await raw(input);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const requestFor = marker => until(() => fixture.requests.find(request => !request.closed
    && JSON.stringify(request.input.input).includes(marker)), `model request containing ${marker}`);
  const complete = async (task, marker, text) => {
    const request = await requestFor(marker);
    fixture.finish(request.index, { text });
    return taskIdle(fixture.running.service, task);
  };
  const project = async name => {
    const root = path.join(fixture.root, name);
    await mkdir(root);
    return (await command({ op: 'create_project', name, workspace: { roots: [root] } })).project_id;
  };
  const projectA = await project('Alpha Project');
  const projectB = await project('Beta Project');
  const workA = (await command({ op: 'create_work', name: 'First Work' })).work_id;
  const workB = (await command({ op: 'create_work', name: 'Second Work' })).work_id;
  const records = [];
  const create = async (label, project_id, work_id) => {
    const message = `${label} user context before. 星河 NeEdLe user match. Context after.`;
    const { task_id } = await command({ op: 'create_work_task', work_id, profile: 'interactive',
      settings: { project_id }, message });
    const assistant = `${label} assistant context before. 星河 nEeDlE assistant match. Context after.`;
    const page = await complete(task_id, message, assistant);
    for (const [message_index, item] of page.messages.entries()) {
      if (item.content === message || item.content === assistant) {
        records.push({ task_id, message_index, role: item.role, text: item.content, project_id, work_id });
      }
    }
    return task_id;
  };
  const first = await create('First conversation', projectA, workA);
  await create('Second conversation', projectB, workA);
  await create('Third conversation', projectA, workB);
  assert.equal(records.length, 6, 'The real model transport must record each user and assistant message');
  await command({ op: 'send', task_id: first, message: 'Continue the oldest conversation without the keyword.' });
  await complete(first, 'Continue the oldest conversation', 'Later response without the keyword.');

  const expected = records.toSorted((left, right) => right.task_id - left.task_id || right.message_index - left.message_index);
  const identify = hits => hits.map(hit => [hit.task.id, hit.message_index, hit.role]);
  const rows = list => list.map(item => [item.task_id, item.message_index, item.role]);
  const search = args => command({ op: 'search_history', query: 'needle', ...args });
  const all = await search({});
  assert.deepEqual(identify(all.hits), rows(expected));
  assert.equal(all.has_more, false);
  assert.equal(all.next_after, null);
  for (const hit of all.hits) {
    const source = expected.find(item => item.task_id === hit.task.id && item.message_index === hit.message_index);
    assert.equal(hit.task.settings.project_id, source.project_id);
    assert.equal(hit.task.work_id, source.work_id);
    assert.equal(typeof hit.task.title, 'string');
    assert.match(hit.snippet, /needle/i);
    assert.equal(typeof hit.before, 'string');
    assert.equal(typeof hit.after, 'string');
    const original = await command({ op: 'read', task_id: hit.task.id, after: hit.message_index, limit: 1 });
    assert.equal(original.messages.length, 1);
    assert.equal(original.messages[0].content, source.text);
    assert.equal(original.messages[0].role, hit.role);
  }
  const firstAssistant = all.hits.find(hit => hit.task.id === first && hit.role === 'assistant');
  assert.match(firstAssistant.before, /First conversation user/);
  assert.match(firstAssistant.after, /Continue the oldest conversation/);
  assert.deepEqual(identify((await search({ project_id: projectA })).hits), rows(expected.filter(item => item.project_id === projectA)));
  assert.deepEqual(identify((await search({ work_id: workA })).hits), rows(expected.filter(item => item.work_id === workA)));
  const intersection = await search({ project_id: projectA, work_id: workA });
  assert.deepEqual(identify(intersection.hits), rows(expected.filter(item => item.task_id === first)));
  assert.deepEqual(identify((await search({ query: '  星河  ' })).hits), rows(expected));
  const pageOne = await search({ limit: 3 });
  assert.equal(pageOne.has_more, true);
  assert.equal(typeof pageOne.next_after, 'number');
  const pageTwo = await search({ after: pageOne.next_after, limit: 3 });
  assert.deepEqual(identify([...pageOne.hits, ...pageTwo.hits]), rows(expected));
  assert.equal(pageTwo.next_after, null);
  for (const input of [{ query: ' \n ' }, { project_id: 999999 }, { work_id: 999999 }]) {
    const rejected = await raw({ op: 'search_history', query: 'needle', ...input });
    assert.equal(rejected.ok, false, JSON.stringify(rejected));
  }

  await fixture.restart();
  assert.deepEqual(await search({ project_id: projectA, work_id: workA }), intersection,
    'Reopening SQLite preserves searchable original message offsets and task metadata');
  const marker = 'Find the earlier discussion using the native search tool.';
  const { task_id: agent } = await command({ op: 'create', profile: 'interactive', message: marker });
  const request = await requestFor(marker);
  const tool = request.input.tools.find(tool => tool.name === 'search_history');
  assert.ok(tool, 'The actual provider request advertises the native search_history tool');
  assert.ok(tool.parameters.required.includes('query'));
  assert.ok(tool.parameters.properties.project_id);
  assert.ok(tool.parameters.properties.work_id);
  fixture.finish(request.index, { output: [{ type: 'function_call', call_id: 'search-original-history',
    name: 'search_history', arguments: JSON.stringify({ query: 'needle', project_id: projectA, work_id: workA }) }] });
  const continuation = await until(() => fixture.requests.find(item => !item.closed
    && item.input.input.some(input => input.type === 'function_call_output' && input.call_id === 'search-original-history')),
  'the native tool result delivered to the model');
  const output = continuation.input.input.find(item => item.type === 'function_call_output' && item.call_id === 'search-original-history');
  const result = JSON.parse(output.output);
  assert.equal(result.is_error, false, JSON.stringify(result));
  assert.deepEqual(result.value, intersection, 'The UI command and agent tool return the same search result');
  fixture.finish(continuation.index, { text: 'Located the earlier conversation.' });
  await taskIdle(fixture.running.service, agent);
  assert.deepEqual(fixture.failures, []);
});

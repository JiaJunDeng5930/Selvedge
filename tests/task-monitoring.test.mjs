import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const call = (call_id, name, args = {}) =>
  ({ type: 'function_call', call_id, name, arguments: JSON.stringify(args) });
const reply = (text, phase = 'final_answer') =>
  ({ type: 'message', role: 'assistant', phase, content: [{ type: 'output_text', text }] });
const monitored = page => page.messages.filter(message => message.role === 'monitored_output');
const result = (page, id) => page.messages.find(message =>
  message.role === 'function_output' && message.call_id === id);

async function fixture(t, responders) {
  const requests = new Map();
  const upstream = await responsesServer(t, body => {
    const previous = requests.get(body.model) ?? [];
    requests.set(body.model, [...previous, body]);
    const respond = responders[body.model][previous.length];
    assert.ok(respond, `Unexpected request for ${body.model} at index ${previous.length}`);
    return typeof respond === 'function' ? respond(body) : respond;
  }, { measure: () => 100 });
  const credential = 'SELVEDGE_TASK_MONITORING_FIXTURE_KEY';
  process.env[credential] = 'loopback-task-monitoring-fixture';
  t.after(() => { delete process.env[credential]; });
  const directory = await home(t);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    ...defaultConfig.profiles,
    demo: { provider: 'echo', model: 'echo' },
    ...Object.fromEntries(Object.keys(responders).map(model => [model, {
      provider: 'responses', model, endpoint: upstream.endpoint, api_key_env: credential, timeout_ms: 15000,
    }])),
  } });
  const open = () => Service.open({ home: directory, cwd: directory, config });
  let service = await open();
  t.after(() => service.close());
  t.after(() => assert.deepEqual(upstream.failures, []));
  async function command(value) {
    const { reply: response } = await service.command(value);
    assert.equal(response.ok, true, JSON.stringify(response));
    return response.result;
  }
  const read = task_id => command({ op: 'read', task_id });
  const send = (task_id, message) => command({ op: 'send', task_id, message });
  async function until(taskId, accepted) {
    const deadline = Date.now() + 10000;
    let page;
    do {
      page = await read(taskId);
      if (accepted(page)) return page;
      await delay(10);
    } while (Date.now() < deadline);
    // DEFENSE: A missing model callback or wake can leave the task past the fixture deadline.
    assert.fail(`Task ${taskId} did not reach the expected state: ${JSON.stringify(page)}`);
  }
  return {
    command, read, send, until,
    requests: model => requests.get(model),
    idle: id => taskIdle(service, id),
    waiting: id => until(id, page => page.task.phase === 'waiting_for_input'),
    restart: async () => { await service.close(); service = await open(); },
  };
}

function assertModelWake(body, callId, text) {
  const inputs = body.input;
  const delivered = inputs.findIndex(item => item.role === 'user' &&
    JSON.stringify(item.content).includes(text));
  assert.ok(delivered >= 0, `Model request is missing wake input ${text}`);
  if (callId) {
    const output = inputs.findIndex(item => item.type === 'function_call_output' && item.call_id === callId);
    assert.ok(output >= 0 && output < delivered, 'The suspended tool call settles before its wake input');
    assert.deepEqual(JSON.parse(inputs[output].output), { value: 0, is_error: false });
  }
}

test('creation monitoring follows commentary and later turns through final answers and restart', { timeout: 30000 }, async t => {
  const progressGate = Promise.withResolvers();
  const finalGate = Promise.withResolvers();
  const runtime = await fixture(t, {
    observer: [
      [call('create-observed', 'create_task', { profile: 'source', message: 'Start reporting.', monitor: true }),
        call('create-default', 'create_task', { profile: 'demo', message: 'Unmonitored reply.' })],
      [call('wait-for-progress', 'wait')],
      [reply('Observer saw the progress.')],
      [call('wait-before-restart', 'wait')],
      [call('wait-for-user', 'wait')],
      [call('wait-for-direct-message', 'wait')],
      [reply('Observer saw the direct message.')],
    ],
    source: [
      async () => { await progressGate.promise; return [reply('Source progress 😀', 'commentary'), call('read-source', 'read_current_task')]; },
      async () => { await finalGate.promise; return [reply('Source final answer.')]; },
      [reply('Source resumed after restart.')],
      [reply('The archived observer cannot receive this.')],
    ],
    messenger: [[call('send-observer', 'send_message_to_task', { task_id: 0, message: 'Direct message from another task.' })], [reply('Delivered.')]],
  });
  const { task_id: observer } = await runtime.command({ op: 'create', profile: 'observer', message: 'Supervise the source.' });
  assert.equal(observer, 0);
  let page = await runtime.waiting(observer);
  const source = result(page, 'create-observed').content.result.task_id;
  const ignored = result(page, 'create-default').content.result.task_id;
  await runtime.idle(ignored);
  assert.deepEqual(monitored(page), []);
  assert.equal(result(page, 'wait-for-progress'), undefined);
  progressGate.resolve();
  page = await runtime.idle(observer);
  assert.equal(result(page, 'wait-for-progress').content, 0);
  assert.equal(monitored(page)[0].content, 'Source progress 😀');
  assert.equal(monitored(page)[0].phase, 'commentary');
  assert.equal(monitored(page)[0].origin.producer_task, source);
  assert.ok(!page.messages.some(message =>
    message.call_id === 'read-source' || message.content?.id === 'read-source'));
  assertModelWake(runtime.requests('observer')[2], 'wait-for-progress', 'Source progress');

  finalGate.resolve();
  page = await runtime.waiting(observer);
  assert.deepEqual(monitored(page).map(message => message.phase), ['commentary', 'final_answer']);
  assertModelWake(runtime.requests('observer')[3], undefined, 'Source final answer.');
  await runtime.restart();
  page = await runtime.waiting(observer);
  assert.equal(result(page, 'wait-before-restart'), undefined);
  await runtime.send(source, 'Report again.');
  await runtime.until(observer, candidate => candidate.task.phase === 'waiting_for_input' &&
    result(candidate, 'wait-before-restart') !== undefined);
  assertModelWake(runtime.requests('observer')[4], 'wait-before-restart', 'Source resumed after restart.');
  await runtime.send(observer, 'Wake from user input.');
  await runtime.until(observer, candidate => candidate.task.phase === 'waiting_for_input' &&
    result(candidate, 'wait-for-user') !== undefined);
  assertModelWake(runtime.requests('observer')[5], 'wait-for-user', 'Wake from user input.');
  await runtime.command({ op: 'create', profile: 'messenger', message: 'Send the observer a message.' });
  page = await runtime.idle(observer);
  assertModelWake(runtime.requests('observer')[6], 'wait-for-direct-message', 'Direct message from another task.');
  assert.deepEqual(monitored(page).map(message => message.content),
    ['Source progress 😀', 'Source final answer.', 'Source resumed after restart.']);
  await runtime.command({ op: 'archive', task_id: observer });
  await runtime.send(source, 'Report after the observer is archived.');
  await runtime.idle(source);
  assert.deepEqual(monitored(await runtime.read(observer)), monitored(page));
});

test('a monitored native fork follows each child without forwarding inherited history', { timeout: 30000 }, async t => {
  const respond = body => {
    const input = body.input.findLast(item => item.role === 'user' &&
      JSON.stringify(item.content).includes('Fork exercise'));
    assert.ok(input);
    const text = JSON.stringify(input.content);
    if (text.includes('child one')) return [reply('First child reply.')];
    if (text.includes('child two')) return [reply('Second child reply.')];
    if (body.input.some(item => item.type === 'function_call_output' && item.call_id === 'fork-observed')) {
      return [reply('Parent received the fork result.')];
    }
    return [call('fork-observed', 'fork_task', {
      child_count: 2, monitor: true, messages: ['Fork exercise child one', 'Fork exercise child two'],
    })];
  };
  const runtime = await fixture(t, { fork: Array(6).fill(respond) });
  const { task_id: observer } = await runtime.command({ op: 'create', profile: 'fork', message: 'Fork exercise parent' });
  await runtime.until(observer, page => monitored(page).length === 2);
  const page = await runtime.idle(observer);
  assert.deepEqual(monitored(page).map(message => message.content).sort(), ['First child reply.', 'Second child reply.']);
  assert.equal(new Set(monitored(page).map(message => message.origin.producer_task)).size, 2);
});

test('monitoring an existing task never loses input concurrent with wait and can be cancelled', { timeout: 30000 }, async t => {
  const generationStarted = Promise.withResolvers();
  const generationRelease = Promise.withResolvers();
  const runtime = await fixture(t, {
    source: [[reply('Before monitoring.')], [reply('Arrived before wait.')], [reply('After cancellation.')]],
    observer: [
      [call('monitor', 'monitor_task', { task_id: 0 }), call('monitor-again', 'monitor_task', { task_id: 0 })],
      async () => { generationStarted.resolve(); await generationRelease.promise; return [call('racing-wait', 'wait')]; },
      [call('cancel-monitor', 'unmonitor_task', { task_id: 0 })],
      [call('wait-after-cancel', 'wait')],
    ],
  });
  const { task_id: source } = await runtime.command({ op: 'create', profile: 'source', message: 'Speak before registration.' });
  assert.equal(source, 0);
  await runtime.idle(source);
  const { task_id: observer } = await runtime.command({ op: 'create', profile: 'observer', message: 'Monitor an existing task.' });
  await generationStarted.promise;
  await runtime.send(source, 'Speak while the observer is deciding to wait.');
  await runtime.until(observer, page => monitored(page).length === 1);
  generationRelease.resolve();
  const waiting = await runtime.waiting(observer);
  assert.equal(result(waiting, 'racing-wait').content, 0);
  assert.deepEqual(monitored(waiting).map(message => message.content), ['Arrived before wait.']);
  assertModelWake(runtime.requests('observer')[2], undefined, 'Arrived before wait.');
  await runtime.send(source, 'Speak after cancellation.');
  await runtime.idle(source);
  assert.equal((await runtime.read(observer)).task.phase, 'waiting_for_input');
  assert.equal(runtime.requests('observer').length, 4);
  assert.deepEqual(monitored(await runtime.read(observer)).map(message => message.content), ['Arrived before wait.']);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer } from './support.mjs';

const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const uiReply = '```selvedge-ui\n<ui id="graphRouteUi"><stack id="root"><text id="message" label="UI reply" /></stack></ui>\n```';

function assistantTexts(page) {
  return page.messages.flatMap(message => {
    const item = message.content?.type === 'provider_receipt' ? message.content.item : undefined;
    if (message.role !== 'model_context' || item?.role !== 'assistant') return [];
    return item.content.filter(part => part.type === 'output_text').map(part => part.text);
  });
}

function userTexts(page) {
  return page.messages.filter(message => message.role === 'user').flatMap(message =>
    message.content.filter(part => part.type === 'text').map(part => part.text));
}

test('task graphs route ordinary replies, exclude selvedge-ui and retain rejected empty deliveries', { timeout: 30000 }, async t => {
  const directory = await home(t);
  const apiKey = `SELVEDGE_TASK_GRAPH_ROUTING_${randomBytes(8).toString('hex')}`;
  process.env[apiKey] = 'loopback-task-graph-fixture';
  t.after(() => { delete process.env[apiKey]; });

  const responses = ['responses graph route', uiReply, ''];
  const upstream = await responsesServer(t, (_body, index) => {
    assert.ok(index < responses.length, `Unexpected Responses request ${index}`);
    return answer(responses[index]);
  }, { measure: () => 100 });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0,
    profiles: { ...defaultConfig.profiles, routing: {
      provider: 'responses', model: 'task-graph-routing-fixture', endpoint: upstream.endpoint,
      api_key_env: apiKey, timeout_ms: 5000,
    } },
  });
  const running = await startServer({ home: directory, cwd: directory, config });
  t.after(() => running.close());

  async function rawCommand(value) {
    const response = await fetch(`${running.address}/api/commands`, { method: 'POST',
      headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' },
      body: JSON.stringify(value),
    });
    return { status: response.status, body: await response.json() };
  }

  async function command(value) {
    const response = await rawCommand(value);
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assert.equal(response.body.ok, true, JSON.stringify(response.body));
    return response.body.result;
  }

  async function waitForIdleTurn(taskId, completed) {
    const deadline = Date.now() + 10000;
    let page;
    do {
      page = await command({ op: 'read', task_id: taskId });
      if (completed(page) && page.task.phase === 'idle' && page.task.operations.length === 0) return page;
      await delay(10);
    } while (Date.now() < deadline);
    // DEFENSE: A provider or service regression can leave a public task turn unsettled past the fixture deadline.
    assert.fail(`Task ${taskId} did not finish its public turn: ${JSON.stringify(page)}`);
  }

  const echoSource = await command({ op: 'create_idle', profile: 'demo' });
  const echoTarget = await command({ op: 'create_idle', profile: 'demo' });
  const emptySendTarget = await command({ op: 'create_idle', profile: 'demo' });
  const responseSource = await command({ op: 'create_idle', profile: 'routing' });
  const responseTarget = await command({ op: 'create_idle', profile: 'demo' });
  const emptySendBaseline = await rawCommand({ op: 'send', task_id: emptySendTarget.task_id, message: '' });
  assert.equal(emptySendBaseline.status, 400);
  assert.equal(emptySendBaseline.body.ok, false);
  assert.equal(emptySendBaseline.body.error.code, 'invalid_message');
  assert.equal(userTexts(await command({ op: 'read', task_id: emptySendTarget.task_id })).length, 0,
    'The public send contract rejects an empty message without adding Task input');
  const graph = await command({ op: 'create_task_graph', name: 'Provider output routing', nodes: [
    { key: 'echo-source', task_id: echoSource.task_id },
    { key: 'echo-target', task_id: echoTarget.task_id },
    { key: 'responses-source', task_id: responseSource.task_id },
    { key: 'responses-target', task_id: responseTarget.task_id },
  ], rules: [
    { key: 'echo-output', source: 'echo-source', actions: [{ target: 'echo-target', message: { kind: 'output' } }] },
    { key: 'responses-output', source: 'responses-source', actions: [{ target: 'responses-target', message: { kind: 'output' } }] },
  ] });

  const echoBefore = await command({ op: 'read', task_id: echoSource.task_id });
  const echoAssistantCount = assistantTexts(echoBefore).length;
  await command({ op: 'send', task_id: echoSource.task_id, message: 'echo graph route smoke' });
  const echoReply = await waitForIdleTurn(echoSource.task_id,
    page => assistantTexts(page).length > echoAssistantCount);
  const echoText = assistantTexts(echoReply).at(-1);
  assert.ok(echoText.includes('echo graph route smoke'));
  const echoDelivery = await command({ op: 'read', task_id: echoTarget.task_id });
  assert.ok(userTexts(echoDelivery).includes(echoText),
    'The local echo assistant reply reaches its ordinary target Task');

  const responseRequestsBefore = upstream.requests.length;
  await command({ op: 'send', task_id: responseSource.task_id, message: 'return ordinary assistant text' });
  const ordinaryReply = await waitForIdleTurn(responseSource.task_id,
    () => upstream.requests.length > responseRequestsBefore);
  const ordinaryText = assistantTexts(ordinaryReply).at(-1);
  assert.ok(ordinaryText.includes('responses graph route'));
  let responseDelivery = await command({ op: 'read', task_id: responseTarget.task_id });
  assert.ok(userTexts(responseDelivery).includes(ordinaryText),
    'A Responses assistant text reply reaches the graph target Task');

  const responseRequestsBeforeUi = upstream.requests.length;
  await command({ op: 'send', task_id: responseSource.task_id, message: 'return a selvedge-ui interface' });
  const uiTurn = await waitForIdleTurn(responseSource.task_id,
    () => upstream.requests.length > responseRequestsBeforeUi);
  assert.ok(assistantTexts(uiTurn).at(-1).includes('<ui id="graphRouteUi">'),
    'The provider fixture returned the actual selvedge-ui fenced reply');
  responseDelivery = await command({ op: 'read', task_id: responseTarget.task_id });
  assert.equal(userTexts(responseDelivery).length, 1,
    'A selvedge-ui assistant reply is not delivered as ordinary text');

  const graphBeforeEmpty = await command({ op: 'read_task_graph', graph_id: graph.graph_id });
  const previousReceipts = graphBeforeEmpty.receipts;
  const responseRequestsBeforeEmpty = upstream.requests.length;
  await command({ op: 'send', task_id: responseSource.task_id, message: 'return an empty assistant reply' });
  await waitForIdleTurn(responseSource.task_id,
    () => upstream.requests.length > responseRequestsBeforeEmpty);
  responseDelivery = await command({ op: 'read', task_id: responseTarget.task_id });
  const deliveredUsersAfterEmpty = userTexts(responseDelivery);
  assert.equal(deliveredUsersAfterEmpty.length, 1,
    'The empty assistant reply is rejected by the same public send contract');
  const graphAfterEmpty = await command({ op: 'read_task_graph', graph_id: graph.graph_id });
  const newReceipts = graphAfterEmpty.receipts.filter(receipt =>
    !previousReceipts.some(previous => JSON.stringify(previous) === JSON.stringify(receipt)));
  const emptyReceipt = newReceipts.find(receipt =>
    receipt.source === responseSource.task_id
      && receipt.rule === 'responses-output'
      && receipt.target === responseTarget.task_id);
  assert.ok(emptyReceipt, `The rejected empty handoff must remain visible as a graph receipt: ${JSON.stringify(newReceipts)}`);
  assert.equal(emptyReceipt.reply.ok, false);
  assert.equal(emptyReceipt.reply.error.code, emptySendBaseline.body.error.code,
    'Graph delivery reports the same failure category as public send of an empty message');

  assert.equal(upstream.requests.length, 3, 'Responses fixture traffic stays bounded to the three requested turns');
  assert.deepEqual(upstream.failures, []);
});

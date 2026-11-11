import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { login } from '../host/chatgpt-account.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import { chatgptFixture } from './fixtures/chatgpt.mjs';
import { taskIdle } from './support.mjs';

const assistant = (id, text) => ({
  type: 'message', id: `msg_${id}`, role: 'assistant',
  content: [{ type: 'output_text', text }],
});

function complete(response, id, output) {
  response.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const item of output) {
    response.write(`data: ${JSON.stringify({ type: 'response.output_item.done', item })}\n\n`);
  }
  const usage = { input_tokens: 75, output_tokens: 8, total_tokens: 83 };
  response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { id, usage } })}\n\n`);
}

test('a discovered Codex model completes multiple turns, independent title generation and native compaction', async t => {
  const upstream = await chatgptFixture(t);
  const model = 'codex-lite-fixture';
  const ordinary = [], titleRequests = [], compactions = [];
  const checkpoint = { type: 'compaction', id: 'cmp_fixture', encrypted_content: 'sealed checkpoint' };
  const reasoning = { type: 'reasoning', id: 'rs_fixture', summary: [], encrypted_content: 'sealed reasoning' };
  upstream.options.respond = (entry, response) => {
    const url = new URL(entry.url, upstream.address);
    if (url.pathname === '/v1/models') {
      assert.match(url.searchParams.get('client_version') ?? '', /^\d+\.\d+\.\d+$/);
      response.writeHead(200, { 'content-type': 'application/json' });
      return response.end(JSON.stringify({ models: [{
        slug: model, visibility: 'list', use_responses_lite: true,
        context_window: null, max_context_window: 128000,
        default_reasoning_level: 'low', multi_agent_reasoning_effort: 'xhigh',
        supported_reasoning_levels: ['low', 'xhigh', 'ultra'].map(effort => ({ effort })),
      }] }));
    }
    // All inference, including checkpoint creation, goes through one Codex SSE endpoint.
    assert.equal(url.pathname, '/v1/responses');
    assert.equal(entry.headers['x-openai-internal-codex-responses-lite'], 'true');
    const body = entry.body;
    assert.equal(body.model, model);
    assert.equal(body.stream, true);
    assert.equal(body.store, false);
    assert.equal(body.instructions, undefined);
    assert.equal(body.max_output_tokens, undefined);
    assert.equal(body.tools, undefined);
    assert.equal(body.tool_choice, 'auto');
    assert.equal(body.parallel_tool_calls, false);
    assert.equal(body.reasoning.context, 'all_turns');
    const toolDeclaration = body.input.find(item => item.type === 'additional_tools');
    if (body.text?.format?.name === 'task_title') {
      assert.equal(toolDeclaration, undefined);
      titleRequests.push(body);
      return complete(response, 'resp_title', [assistant('title', '{"title":"A Codex task"}')]);
    }
    if (body.input.at(-1)?.type === 'compaction_trigger') {
      assert.equal(toolDeclaration, undefined);
      compactions.push(body);
      return complete(response, 'resp_compact', [checkpoint]);
    }
    assert.equal(toolDeclaration?.role, 'developer');
    assert.ok(toolDeclaration.tools.some(tool => tool.type === 'namespace' && tool.name === 'selvedge'));
    assert.equal(body.reasoning.effort, 'xhigh');
    ordinary.push(body);
    const turn = ordinary.length;
    return complete(response, `resp_${turn}`, [
      ...(turn === 1 ? [reasoning] : []), assistant(turn, `Codex reply ${turn} 😀`),
    ]);
  };
  await login(upstream.profile, upstream.directory, { onAuthorize: upstream.authorize });
  const config = validateConfig({ ...defaultConfig, port: 0, profiles: {}, chatgpt: upstream.profile });
  const running = await startServer({ home: upstream.directory, cwd: upstream.directory, config });
  t.after(() => running.close());
  const refresh = await fetch(`${running.address}/api/accounts/refresh`, { method: 'POST',
    headers: { authorization: `Bearer ${running.token}`, 'content-type': 'application/json' }, body: '{}' });
  const catalog = await refresh.json();
  assert.equal(catalog.ok, true, JSON.stringify(catalog));
  const profile = catalog.result.profiles.find(profile => profile.name === model);
  assert.ok(profile);
  const command = async input => {
    const { reply } = await running.service.command(input);
    assert.equal(reply.ok, true, JSON.stringify(reply));
    return reply.result;
  };
  const { task_id } = await command({ op: 'create', profile: profile.key, reasoning: 'ultra', message: 'First request 😀.' });
  const first = await taskIdle(running.service, task_id);
  assert.match(JSON.stringify(first.messages), /Codex reply 1 😀/);
  await command({ op: 'send', task_id, message: 'Continue from the first answer.' });
  const second = await taskIdle(running.service, task_id);
  assert.match(JSON.stringify(second.messages), /Codex reply 2 😀/);
  assert.ok(ordinary[1].input.some(item => item.encrypted_content === reasoning.encrypted_content));
  assert.ok(ordinary[0].input.some(item => item.type === 'message' && item.role === 'user'
    && item.content[0].type === 'input_text' && item.content[0].text === 'First request 😀.'));
  await command({ op: 'compact', task_id });
  const deadline = Date.now() + 10000;
  let compacted;
  do {
    compacted = await command({ op: 'read', task_id });
    if (compacted.task.title === 'A Codex task' && JSON.stringify(compacted.messages).includes(checkpoint.encrypted_content)) break;
    await delay(20);
  } while (Date.now() < deadline);
  assert.equal(compacted.task.title, 'A Codex task');
  assert.ok(JSON.stringify(compacted.messages).includes(checkpoint.encrypted_content), 'The accepted native checkpoint enters task history');
  assert.equal(titleRequests.length, 1);
  assert.equal(compactions.length, 1);
  await command({ op: 'send', task_id, message: 'Resume from the new checkpoint.' });
  const resumed = await taskIdle(running.service, task_id);
  assert.match(JSON.stringify(resumed.messages), /Codex reply 3 😀/);
  const resumedInput = ordinary[2].input;
  assert.ok(resumedInput.some(item => item.encrypted_content === checkpoint.encrypted_content));
  assert.ok(resumedInput.some(item => item.role === 'user' && item.content[0].text === 'First request 😀.'));
  assert.ok(!resumedInput.some(item => item.encrypted_content === reasoning.encrypted_content));
  assert.deepEqual(upstream.failures, []);
});

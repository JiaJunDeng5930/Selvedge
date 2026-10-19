import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

const assistant = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const okay = decision => {
  assert.equal(decision.reply.ok, true, JSON.stringify(decision.reply));
  return decision.reply.result;
};
const read = async (service, task = 0) => okay(await service.command({ op: 'read', task_id: task }));

function configured(t, endpoint, extra = {}) {
  const key = 'SELVEDGE_TASK_TITLE_TEST_KEY';
  const previous = process.env[key];
  process.env[key] = 'loopback-only';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  return validateConfig({ ...defaultConfig, chatgpt: false, profiles: { ...defaultConfig.profiles,
    worker: { provider: 'responses', model: 'worker-model', endpoint, api_key_env: key, timeout_ms: 10_000 }, ...extra } });
}

async function waitFor(read, predicate) {
  const deadline = Date.now() + 10_000;
  do {
    const value = await read();
    if (predicate(value)) return value;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error('Task title did not settle');
}

function recordedEffects(directory) {
  const db = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
  try { return db.prepare('SELECT decision FROM journal ORDER BY seq').all().flatMap(row => JSON.parse(row.decision).effects); }
  finally { db.close(); }
}

test('independent title prompts cross committed HTTP requests and SQLite reopen', async t => {
  const directory = await home(t);
  const taskPrompt = 'TASK_TITLE_RULE: 用中文描述看板上的计划工作。';
  const agentPrompt = 'AGENT_TITLE_RULE: 用中文描述执行会话。' + '保留要求。'.repeat(120) + 'AGENT_RULE_END';
  const upstream = await responsesServer(t, body => {
    if (body.text?.format?.name === 'board_text') {
      assert.ok(body.input[0].content.startsWith(taskPrompt));
      assert.equal(body.input[0].content.includes('AGENT_TITLE_RULE'), false);
      return assistant(JSON.stringify({ title: '规划看板任务', description: '保留这个完整的原始要求。' }));
    }
    return assistant('Done');
  }, { title: body => {
    assert.ok(recordedEffects(directory).some(effect => effect.kind === 'task_title'), 'The title request must be durable before HTTP dispatch');
    assert.ok(body.input[0].content.startsWith(agentPrompt));
    assert.ok(body.input[0].content.includes('AGENT_RULE_END'));
    assert.equal(body.input[0].content.includes('TASK_TITLE_RULE'), false);
    assert.ok(body.input[0].content.includes('AGENT_REQUEST_START'));
    assert.equal(body.input[0].content.includes('\ufffd'), false);
    return assistant('{"title":"分析独立会话"}');
  } });
  const config = configured(t, upstream.endpoint);
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  const defaults = okay(await service.command({ op: 'read_title_settings' }));
  const saved = okay(await service.command({ op: 'configure_title_settings', revision: defaults.revision,
    task_prompt: taskPrompt, agent_prompt: agentPrompt }));
  assert.deepEqual(saved, { revision: defaults.revision + 1, task_prompt: taskPrompt, agent_prompt: agentPrompt });
  okay(await service.command({ op: 'create', profile: 'worker', message: 'AGENT_REQUEST_START 😀' + '详细需求。'.repeat(500) }));
  await waitFor(() => read(service), value => value.task.title === '分析独立会话');
  const card = () => service.command({ op: 'read_card', card_id: 0 }).then(okay);
  okay(await service.command({ op: 'create_card', description: '规划工作', assisted: true, draft_profile: 'worker', assignee: 'profile/worker', status: 'todo' }));
  await waitFor(card, value => value.enrichment.status === 'idle');
  await taskIdle(service);
  await service.close();
  service = await Service.open({ home: directory, cwd: directory, config });
  assert.deepEqual(okay(await service.command({ op: 'read_title_settings' })), saved);
  assert.equal((await read(service)).task.title, '分析独立会话');
  assert.equal(upstream.titleRequests.length, 1);
  assert.deepEqual(upstream.failures, []);
});

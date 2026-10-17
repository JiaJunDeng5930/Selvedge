import assert from 'node:assert/strict';
import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../../host/service.mjs';
import { defaultConfig, validateConfig } from '../../host/config.mjs';
import { chatgptFixture, jsonResponse, inputTokensResponse } from './chatgpt.mjs';

const compact = request => request.url === '/v1/responses/compact';
let diagnostics = 0;

function retainRejectedInput(service) {
  const recent = [];
  service.journal.on('commit', decision => {
    recent.push(decision.effects);
    if (recent.length > 3) recent.shift();
  });
  const execute = service.journal.execute.bind(service.journal);
  service.journal.execute = async input => {
    let decision;
    try { decision = await execute(input); }
    catch (error) {
      const directory = path.resolve('.workpad/automatic-context-compaction');
      await mkdir(directory, { recursive: true });
      await writeFile(path.join(directory, `failed-input-${process.pid}-${++diagnostics}.json`),
        JSON.stringify({ input, error: error.stack, preceding_effects: recent }, null, 2));
      throw error;
    }
    if (decision.reply.ok === false) {
      const directory = path.resolve('.workpad/automatic-context-compaction');
      await mkdir(directory, { recursive: true });
      await writeFile(path.join(directory, `rejected-input-${process.pid}-${++diagnostics}.json`),
        JSON.stringify({ input, reply: decision.reply, preceding_effects: recent }, null, 2));
    }
    return decision;
  };
}

export async function accountCompactionService(t, handle, { compaction = {}, measure = () => 100, profiles = {} } = {}) {
  const upstream = await chatgptFixture(t, async (request, response) => {
    if (request.method === 'GET') return jsonResponse(response, {
      models: [{ slug: 'fixture-model', display_name: 'Fixture model', visibility: 'list' }],
    });
    const db = new DatabaseSync(path.join(upstream.directory, 'state', 'journal.sqlite'), { readOnly: true });
    let effects;
    try { effects = db.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 20').all()
      .flatMap(record => JSON.parse(record.decision).effects); }
    finally { db.close(); }
    const measuring = request.url === '/v1/responses/input_tokens';
    const compacting = compact(request) || request.body?.tool_choice === 'none';
    const kinds = measuring ? ['context_measure', 'context_compaction'] : [compacting ? 'context_compaction' : 'model'];
    assert.ok(effects.some(effect => kinds.includes(effect.kind)),
      'An external request must follow its committed effect');
    if (measuring) return inputTokensResponse(response, await measure(request));
    return handle(request, response);
  });
  let config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { fixture: {
    ...upstream.profile, model: 'fixture-model', auth_file: path.join(upstream.directory, upstream.profile.auth_file),
  }, ...profiles }, compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 0,
    targets: [{ profile: 'fixture', window_tokens: 100_000, output_reserve_tokens: 1024,
      cache_ttl_ms: null, method: 'auto' }], ...compaction } });
  let service = await Service.open({ home: path.join(upstream.directory, 'state'), config, cwd: upstream.directory });
  retainRejectedInput(service);
  t.after(() => service.close());
  return { ...upstream, get service() { return service; },
    restart: async (configure = value => value) => {
      await service.close();
      config = validateConfig(configure(config));
      service = await Service.open({ home: path.join(upstream.directory, 'state'), config, cwd: upstream.directory });
      retainRejectedInput(service);
    },
  };
}

export async function until(label, condition, timeout = 5000) {
  const deadline = Date.now() + timeout;
  do {
    if (await condition()) return;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Did not observe ${label}`);
}

export async function contextReplaced(service, count = 1, taskId = 0, timeout = 5000) {
  let page;
  await until(`context replacement ${count}`, async () => {
    const result = await service.command({ op: 'read', task_id: taskId });
    assert.equal(result.reply.ok, true);
    page = result.reply.result;
    return page.messages.filter(message => message.role === 'context_replacement').length >= count;
  }, timeout);
  return page;
}

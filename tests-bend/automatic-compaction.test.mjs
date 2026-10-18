import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import path from 'node:path';
import { writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { encode } from 'gpt-tokenizer';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, taskIdle } from './support.mjs';
import { accountCompactionService, contextReplaced, until } from './fixtures/compaction.mjs';
import { modelResponse, compactResponse, inputTokensResponse, jsonResponse } from './fixtures/chatgpt.mjs';

const assistant = text => ({ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] });
const checkpoint = id => ({ type: 'compaction', id, encrypted_content: `opaque-${id}` });
const policy = cache_ttl_ms => ({ enabled: true, background_percent: 65, blocking_percent: 90, idle_lead_ms: 0,
  targets: [{ profile: 'fixture', window_tokens: 10_000, output_reserve_tokens: 1000, cache_ttl_ms, method: 'auto' }] });

// The meter is an external oracle here. These values exercise dispatch order;
// tokenizer correctness belongs to the separate real transport boundary checks.
test('background compaction permits work until the hard threshold, then installs the snapshot plus its concurrent suffix', { timeout: 15_000 }, async t => {
  const softAnswer = 'SOFT_CONTEXT_MARKER';
  const hardAnswer = 'HARD_CONTEXT_MARKER';
  const backgroundMessage = 'Continue while compaction is running.';
  const blockedMessage = 'Continue after the hard threshold.';
  const originalGuidance = 'Keep the original workspace guidance. Use npm.\n';
  const updatedGuidance = 'Keep the original workspace guidance. Use bun.\n';
  let pending, compactions = 0, models = 0, hardMeasurements = 0, resumedInput;
  const running = await accountCompactionService(t, (request, response) => {
    if (request.url === '/v1/responses/compact') {
      compactions++;
      assert.ok(JSON.stringify(request.body.input).includes(softAnswer));
      assert.equal(JSON.stringify(request.body.input).includes(backgroundMessage), false);
      pending = response;
      return;
    }
    models++;
    if (models === 3) resumedInput = request.body.input;
    assert.ok(models <= 3, 'Compaction must not start an ordinary turn');
    modelResponse(response, [assistant(models === 1 ? softAnswer : models === 2 ? hardAnswer : 'Finished.')]);
  }, { compaction: policy(null), measure: request => {
    const encoded = JSON.stringify(request.body.input);
    if (request.body.input.some(item => item.type === 'compaction')) return 100;
    if (encoded.includes(hardAnswer)) { hardMeasurements++; return 9500; }
    if (encoded.includes(softAnswer)) return 7000;
    return 100;
  } });
  const agents = path.join(running.directory, 'AGENTS.md');
  await writeFile(agents, originalGuidance);
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Original objective.' });
  await until('the background native request', () => pending !== undefined);
  await writeFile(agents, updatedGuidance);
  await running.service.command({ op: 'send', task_id: 0, message: backgroundMessage });
  await until('ordinary work during background compaction', () => models === 2 && hardMeasurements > 0);
  await running.service.command({ op: 'send', task_id: 0, message: blockedMessage });
  await delay(60);
  assert.equal(models, 2, 'The hard threshold waits for the pending result');
  compactResponse(pending, [checkpoint('background')]);
  const page = await taskIdle(running.service);
  assert.equal(compactions, 1); assert.equal(models, 3);
  assert.deepEqual(resumedInput.find(item => item.type === 'compaction'), checkpoint('background'));
  for (const content of [backgroundMessage, blockedMessage]) {
    assert.equal(resumedInput.filter(item => item.role === 'user' && item.content === content).length, 1);
  }
  assert.equal(resumedInput.filter(item => item.content?.[0]?.text === hardAnswer).length, 1);
  assert.equal(JSON.stringify(resumedInput).includes(softAnswer), false);
  assert.ok(JSON.stringify(page.messages).includes(softAnswer));
  assert.ok(JSON.stringify(page.messages).includes(hardAnswer));
  assert.equal(page.messages.filter(item => item.role === 'context_replacement').length, 1);
  const guidance = page.messages.filter(item => item.type === 'context_change').map(item => item.change)
    .filter(change => (change.type === 'introduce' ? change.snapshot.key : change.key).type === 'project_guidance');
  assert.equal(guidance.length, 2);
  assert.equal(guidance[0].snapshot.value.fields.content, originalGuidance);
  assert.equal(guidance[1].type, 'amend');
  assert.equal(guidance[1].base_revision, guidance[0].snapshot.revision);
  const developer = resumedInput.filter(item => item.role === 'developer').map(item => item.content).join('\n');
  assert.ok(developer.includes('Keep the original workspace guidance. Use npm.'));
  assert.ok(developer.includes('Committed context object update.'));
  for (const edit of guidance[1].patch.fields.find(field => field.field === 'content').edits) {
    assert.ok(developer.includes(`- ${JSON.stringify(edit.removed)}\n+ ${JSON.stringify(edit.inserted)}`),
      'A concurrent context amendment retains both its baseline and its exact edits after native compaction');
  }
  assert.deepEqual(running.failures, []);
});

test('idle compaction captures its original history revision and does not rearm itself', { timeout: 15_000 }, async t => {
  const newWork = 'New useful work while idle compaction is pending.';
  let pending, compactions = 0, models = 0;
  const captured = [];
  const running = await accountCompactionService(t, (request, response) => {
    if (request.url === '/v1/responses/compact') {
      captured.push(request.body.input);
      if (++compactions === 1) pending = response;
      else compactResponse(response, [checkpoint(`idle-${compactions}`)]);
      return;
    }
    models++;
    modelResponse(response, [assistant(`Completed useful work ${models}.`)], [], {
      input_tokens: 100, input_tokens_details: { cached_tokens: 100 }, output_tokens: 10, total_tokens: 110,
    });
  }, { compaction: policy(200) });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Finish this task and keep it available.' });
  await until('the first idle request', () => pending !== undefined);
  await running.service.command({ op: 'send', task_id: 0, message: newWork });
  await until('new useful work while the first idle request is pending', () => models === 2);
  assert.equal(JSON.stringify(captured[0]).includes(newWork), false);
  compactResponse(pending, [checkpoint('idle-1')]);
  await until('maintenance of the later revision', () => compactions === 2);
  assert.ok(JSON.stringify(captured[1]).includes(newWork));
  await contextReplaced(running.service, 2);
  await delay(450);
  assert.equal(compactions, 2, 'Compaction itself does not create useful work to compact again');
  assert.equal(models, 2);
  assert.deepEqual(running.failures, []);
});

test('changing endpoint rebuilds incompatible native context from long local history through bounded calls', { timeout: 20_000 }, async t => {
  const sourceStart = 'SOURCE_START_FOR_ENDPOINT_SWITCH';
  const sourceEnd = 'SOURCE_END_FOR_ENDPOINT_SWITCH';
  const originalSource = `${sourceStart}\n${Array.from({ length: 700 }, (_, index) =>
    `Historic finding ${index}: retain requirement ${index * 17}, result ${index * 31}.`).join('\n')}\n${sourceEnd}`;
  const oldCheckpoint = checkpoint('old-endpoint');
  const summaries = [], resumed = [], failures = [];
  const window = 8192, reserve = 256;
  const measured = body => encode(JSON.stringify({ input: body.input, instructions: body.instructions ?? '', tools: body.tools ?? [] })).length + 100;
  const target = http.createServer((request, response) => {
    void (async () => {
      if (request.method === 'GET') {
        assert.equal(request.url, '/v1/models');
        return jsonResponse(response, { models: [{ slug: 'fixture-model', display_name: 'Fixture model', visibility: 'list' }] });
      }
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      assert.equal(request.headers.authorization, 'Bearer opaque-access-original');
      assert.equal(JSON.stringify(body).includes(oldCheckpoint.encrypted_content), false,
        'An incompatible opaque artifact must not be sent even to the new meter');
      if (request.url === '/v1/responses/input_tokens') return inputTokensResponse(response, measured(body));
      assert.equal(request.url, '/v1/responses');
      assert.ok(measured(body) + reserve <= window, 'Every actual model call fits the new target window');
      if (body.tool_choice === 'none') {
        summaries.push(body.input);
        modelResponse(response, [assistant(`PORTABLE_CONTEXT_${summaries.length}`)]);
      } else {
        resumed.push(body.input);
        modelResponse(response, [assistant('Continued on the new endpoint.')]);
      }
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => target.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { target.closeAllConnections(); target.close(resolve); }));
  const endpoint = `http://127.0.0.1:${target.address().port}/v1/responses`;
  const running = await accountCompactionService(t, (request, response) => request.url === '/v1/responses/compact'
    ? compactResponse(response, [oldCheckpoint]) : modelResponse(response, [assistant('Completed the original work.')]));
  await running.service.command({ op: 'create', profile: 'fixture', message: originalSource });
  await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 });
  await contextReplaced(running.service);
  assert.ok(measured({ input: [{ role: 'assistant', content: originalSource }] }) > window);
  await running.restart(config => ({ ...config, profiles: { ...config.profiles,
    fixture: { ...config.profiles.fixture, endpoint } }, compaction: { ...policy(null),
    targets: [{ profile: 'fixture', window_tokens: window, output_reserve_tokens: reserve, cache_ttl_ms: null, method: 'summary' }] } }));
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue on the new endpoint.' });
  let page;
  await until('bounded reconstruction and continuation', async () => {
    page = (await running.service.command({ op: 'read', task_id: 0 })).reply.result;
    return page.task.phase === 'idle' && page.task.operations.length === 0;
  }, 15_000);
  assert.ok(summaries.length > 1, 'The full source cannot be processed by one model call');
  assert.ok(summaries.some(input => JSON.stringify(input).includes(sourceStart)));
  assert.ok(summaries.some(input => JSON.stringify(input).includes(sourceEnd)));
  assert.equal(resumed.length, 1);
  assert.ok(JSON.stringify(resumed[0]).includes('PORTABLE_CONTEXT_'));
  assert.equal(JSON.stringify(resumed[0]).includes(sourceStart), false);
  assert.ok(page.messages.some(message => message.role === 'user' && message.content === originalSource),
    'The complete source remains in local history');
  assert.deepEqual(failures, []);
  assert.deepEqual(running.failures, []);
});

test('a third-party Responses endpoint without token counting still compacts readable history with a conservative bound', { timeout: 20_000 }, async t => {
  const directory = await home(t);
  const source = 'Retain this original requirement and its recorded constraints. '.repeat(1000);
  const window = 32768, reserve = 512;
  assert.ok(Buffer.byteLength(source) > window);
  const key = 'SELVEDGE_COMPACTION_FALLBACK_KEY';
  const previous = process.env[key]; process.env[key] = 'fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[key]; else process.env[key] = previous; });
  let counts = 0, summaries = 0, ordinary = 0, native = 0;
  const failures = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      assert.equal(request.headers.authorization, 'Bearer fixture-only');
      if (request.url === '/responses/input_tokens') {
        counts++; return jsonResponse(response, { error: { code: 'not_found' } }, 404);
      }
      if (request.url === '/responses/compact') {
        native++; return jsonResponse(response, { error: { code: 'not_found' } }, 404);
      }
      assert.equal(request.url, '/responses');
      assert.ok(Buffer.byteLength(JSON.stringify(body)) + reserve <= window,
        'Every actual call fits the UTF-8 upper bound including its complete encoded request');
      if (body.tool_choice === 'none') {
        summaries++; modelResponse(response, [assistant(`PORTABLE_FALLBACK_${summaries}`)]);
      } else {
        ordinary++;
        assert.ok(JSON.stringify(body.input).includes('PORTABLE_FALLBACK_'));
        assert.equal(body.input.some(item => item.content === source), false);
        modelResponse(response, [assistant('Completed with the third-party endpoint.')]);
      }
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: { third_party: {
    provider: 'responses', model: 'third-party-model', endpoint: `http://127.0.0.1:${server.address().port}/responses`, api_key_env: key,
  } }, compaction: { ...policy(null), targets: [{ profile: 'third_party', window_tokens: window,
    output_reserve_tokens: reserve, cache_ttl_ms: null, method: 'summary' }] } });
  const service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'third_party', message: source });
  let page;
  await until('portable compaction and the ordinary third-party turn', async () => {
    page = (await service.command({ op: 'read', task_id: 0 })).reply.result;
    return ordinary === 1 && page.task.phase === 'idle' && page.task.operations.length === 0;
  }, 15_000);
  assert.ok(counts > 0);
  assert.ok(summaries > 1);
  assert.equal(native, 0);
  assert.ok(page.messages.some(message => message.role === 'user' && message.content === source));
  const database = new DatabaseSync(path.join(directory, 'state', 'journal.sqlite'), { readOnly: true });
  try {
    assert.ok(database.prepare('SELECT input FROM journal').all().some(row => row.input.includes('utf8_upper_bound')),
      'The fallback measurement is an explicit committed observation');
  } finally { database.close(); }
  assert.deepEqual(failures, []);
});

test('freeze and stop quiesce context observations, then returning to active resumes ordinary work', { timeout: 15_000 }, async t => {
  let ordinary = 0, counts = 0;
  const committed = { context_scope: 0, context_measure: 0 };
  const running = await accountCompactionService(t, (request, response) => {
    assert.equal(request.url, '/v1/responses');
    ordinary++; modelResponse(response, [assistant(`Completed ordinary work ${ordinary}.`)]);
  }, { compaction: policy(null), measure: () => { counts++; return 100; } });
  running.service.journal.on('commit', decision => {
    for (const effect of decision.effects) if (Object.hasOwn(committed, effect.kind)) committed[effect.kind]++;
  });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Perform the first unit of work.' });
  await taskIdle(running.service);
  for (const [control, restore] of [['freeze', 'unfreeze'], ['stop', null]]) {
    const controlled = await running.service.command({ op: control, task_id: 0 });
    assert.equal(controlled.reply.ok, true);
    await delay(80);
    const settled = { ...committed, counts };
    await delay(120);
    assert.deepEqual({ ...committed, counts }, settled, `${control} must not reissue scope or token observations indefinitely`);
    if (restore) assert.equal((await running.service.command({ op: restore, task_id: 0 })).reply.ok, true);
    const previous = ordinary;
    assert.equal((await running.service.command({ op: 'send', task_id: 0, message: `Continue after ${control}.` })).reply.ok, true);
    await until(`ordinary work after ${control}`, () => ordinary === previous + 1);
    const page = await taskIdle(running.service);
    assert.equal(page.task.status, 'active');
  }
  assert.equal(ordinary, 3);
  assert.ok(counts > 0);
  assert.deepEqual(running.failures, []);
});

test('an oversized live suffix starts another bounded rebuild and eventually resumes the task', { timeout: 20_000 }, async t => {
  const soft = 'SOFT_SNAPSHOT_BEFORE_LIVE_SUFFIX';
  const liveStart = 'LIVE_SUFFIX_START';
  const liveEnd = 'LIVE_SUFFIX_END';
  const live = `${liveStart}\n${Array.from({ length: 1200 }, (_, index) =>
    `Additional recorded requirement ${index}, with result ${index * 43}.`).join('\n')}\n${liveEnd}`;
  const old = checkpoint('before-live-suffix');
  const window = 10_000, reserve = 1000;
  const units = body => encode(JSON.stringify({ input: body.input, instructions: body.instructions ?? '', tools: body.tools ?? [] })).length + 100;
  let pending, native = 0, ordinary = 0, oversizedRaw = 0, oversizedCandidate = 0;
  const chunks = [];
  const running = await accountCompactionService(t, (request, response) => {
    if (request.url === '/v1/responses/compact') {
      native++;
      assert.ok(units(request.body) + reserve <= window);
      if (native === 1) {
        assert.equal(JSON.stringify(request.body.input).includes(liveStart), false);
        pending = response;
      } else compactResponse(response, [checkpoint(`rebuilt-${native}`)]);
      return;
    }
    assert.ok(units(request.body) + reserve <= window, 'The final request and every rebuilding call must fit');
    if (request.body.tool_choice === 'none') {
      chunks.push(request.body.input);
      modelResponse(response, [assistant(`REBUILT_WITH_LIVE_SUFFIX_${chunks.length}`)]);
    } else {
      ordinary++;
      if (ordinary > 1) {
        assert.ok(JSON.stringify(request.body.input).includes('REBUILT_WITH_LIVE_SUFFIX_'));
        assert.equal(request.body.input.some(item => item.content === live), false);
      }
      modelResponse(response, [assistant(ordinary === 1 ? soft : 'Finished after rebuilding the live suffix.')]);
    }
  }, { compaction: policy(null), measure: request => {
    const encoded = JSON.stringify(request.body.input);
    const size = units(request.body);
    if (encoded.includes(liveStart) && size + reserve > window) {
      if (request.body.input.some(item => item.type === 'compaction' && item.id === old.id)) oversizedCandidate++;
      else oversizedRaw++;
    }
    if (request.body.tools?.length && encoded.includes(soft) && !encoded.includes(liveStart)) return 7000;
    return size;
  } });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Start the original task.' });
  await until('the captured background request', () => pending !== undefined);
  await running.service.command({ op: 'send', task_id: 0, message: live });
  await until('the oversized live message in committed raw history', async () => {
    const page = (await running.service.command({ op: 'read', task_id: 0 })).reply.result;
    return oversizedRaw > 0 && page.messages.some(message => message.role === 'user' && message.content === live);
  });
  assert.equal(ordinary, 1);
  compactResponse(pending, [old]);
  let page;
  await until('a successful rebuild and resumed ordinary turn', async () => {
    page = (await running.service.command({ op: 'read', task_id: 0 })).reply.result;
    return ordinary === 2 && page.task.phase === 'idle' && page.task.operations.length === 0;
  }, 15_000);
  assert.ok(oversizedCandidate > 0, 'The old candidate plus the actual suffix was checked and exceeded the window');
  assert.ok(chunks.length > 1);
  assert.ok(chunks.some(input => JSON.stringify(input).includes(liveStart)));
  assert.ok(chunks.some(input => JSON.stringify(input).includes(liveEnd)));
  assert.ok(page.messages.some(message => message.role === 'user' && message.content === live));
  assert.equal(page.messages.some(message => message.role === 'error'), false);
  assert.deepEqual(running.failures, []);
});

test('output reserve blocks dispatch even when measured input is below the hard percentage', { timeout: 15_000 }, async t => {
  const replacement = 'COMPACTED_FOR_OUTPUT_RESERVE';
  const objective = 'Respect the complete request budget.';
  const observations = [];
  let pending, native = false, ordinary = 0;
  const running = await accountCompactionService(t, (request, response) => {
    if (request.url === '/v1/responses/compact') { pending = response; native = true; return; }
    if (request.body.tool_choice === 'none') { pending = response; return; }
    ordinary++; modelResponse(response, [assistant('Completed within the reserved window.')]);
  }, { compaction: { ...policy(null), targets: [{ profile: 'fixture', window_tokens: 4096,
    output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'auto' }] }, measure: request => {
    if (request.body.input.some(item => item.type === 'compaction') || JSON.stringify(request.body.input).includes(replacement)) return 100;
    // Input alone is 85.4%: below the configured 90% hard threshold. With the
    // output reservation it exceeds the physical window and must still wait.
    const measured = request.body.input.some(item => item.role === 'user' && item.content === objective) ? 3500 : 100;
    observations.push({ request: request.body, measured });
    return measured;
  } });
  await running.service.command({ op: 'create', profile: 'fixture', message: objective });
  try { await until('the prerequisite compaction', () => pending !== undefined); }
  catch (error) {
    const { writeFile } = await import('node:fs/promises');
    const page = (await running.service.command({ op: 'read', task_id: 0, limit: 1 })).reply.result;
    await writeFile('.workpad/automatic-context-compaction/output-reserve-observations.json', JSON.stringify({ observations,
      ordinary, requests: running.requests, page }, null, 2));
    throw error;
  }
  await delay(60);
  assert.equal(ordinary, 0, 'Input percentage cannot override the full request budget');
  if (native) compactResponse(pending, [checkpoint('output-reserve')]);
  else modelResponse(pending, [assistant(replacement)]);
  const page = await taskIdle(running.service);
  assert.equal(ordinary, 1);
  assert.equal(page.messages.some(message => message.role === 'error'), false);
  assert.deepEqual(running.failures, []);
});

test('a large Unicode rebuild keeps actual compact effects within the kernel frame and preserves its carry', { timeout: 180_000 }, async t => {
  const window = 1_048_576, reserve = 65_536;
  const perRecord = 131_072, records = 10, carryCharacters = 10_000;
  const originals = Array.from({ length: records }, (_, index) => `UNICODE_${index}_START` + '🙂'.repeat(perRecord) + `UNICODE_${index}_END`);
  const carryMarker = 'LARGE_CARRY_MUST_BE_PRESERVED';
  const carry = carryMarker + '🙂'.repeat(carryCharacters);
  let seeded = 0, native = 0, summaries = 0, ordinary = 0, carried = 0, seenCharacters = 0;
  const failures = [];
  const target = http.createServer((request, response) => {
    void (async () => {
      if (request.method === 'GET') return jsonResponse(response, {
        models: [{ slug: 'fixture-model', display_name: 'Fixture model', visibility: 'list' }],
      });
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const encoded = JSON.stringify(body);
      assert.equal(encoded.includes('opaque-unicode-old-'), false);
      if (request.url === '/v1/responses/input_tokens') return inputTokensResponse(response, Buffer.byteLength(encoded) + 128);
      assert.equal(request.url, '/v1/responses');
      assert.ok(Buffer.byteLength(encoded) + reserve <= window);
      if (body.tool_choice === 'none') {
        summaries++;
        for (const character of encoded) if (character === '🙂') seenCharacters++;
        if (encoded.includes(carryMarker)) carried++;
        modelResponse(response, [assistant(summaries === 1 ? carry : 'UNICODE_REBUILD_FINISHED')]);
      } else {
        ordinary++;
        assert.ok(encoded.includes('UNICODE_REBUILD_FINISHED'));
        modelResponse(response, [assistant('Continued after the large Unicode rebuild.')]);
      }
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => target.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { target.closeAllConnections(); target.close(resolve); }));
  const api_key_env = 'SELVEDGE_UNICODE_COMPACTION_FIXTURE';
  const previousKey = process.env[api_key_env];
  process.env[api_key_env] = 'local-unicode-fixture-only';
  t.after(() => { if (previousKey === undefined) delete process.env[api_key_env]; else process.env[api_key_env] = previousKey; });
  const running = await accountCompactionService(t, (request, response) => {
    if (request.url === '/v1/responses/compact') return compactResponse(response, [checkpoint(`unicode-old-${++native}`)]);
    seeded++; modelResponse(response, [assistant(`Seeded original Unicode record ${seeded}.`)]);
  }, { profiles: { unicode_target: { provider: 'responses', model: 'fixture-model',
    endpoint: `http://127.0.0.1:${target.address().port}/v1/responses`, api_key_env } },
  compaction: { ...policy(null), enabled: false, targets: [
    { profile: 'fixture', window_tokens: window, output_reserve_tokens: reserve, cache_ttl_ms: null, method: 'auto' },
    { profile: 'unicode_target', window_tokens: window, output_reserve_tokens: reserve, cache_ttl_ms: null, method: 'summary' },
  ] } });
  for (const [index, message] of originals.entries()) {
    assert.ok(Buffer.byteLength(JSON.stringify({ op: 'send', task_id: 0, message })) < running.service.limits.frame_bytes);
    assert.equal((await running.service.command(index === 0
      ? { op: 'create', profile: 'fixture', message } : { op: 'send', task_id: 0, message })).reply.ok, true);
    let cursor;
    await until(`the original Unicode generation ${index + 1}`, async () => {
      const page = (await running.service.command({ op: 'read', task_id: 0, limit: 1 })).reply.result;
      cursor = page.task.cursor;
      return seeded === index + 1 && page.task.phase === 'idle';
    }, 15_000);
    assert.equal((await running.service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
    await until(`the original native Unicode window ${index + 1}`, async () => {
      const page = (await running.service.command({ op: 'read', task_id: 0, limit: 1 })).reply.result;
      if (page.task.cursor <= cursor) return false;
      const last = (await running.service.command({ op: 'read', task_id: 0, after: page.task.cursor - 1, limit: 1 })).reply.result;
      return last.messages.at(-1)?.role === 'context_replacement';
    }, 15_000);
  }
  assert.ok(perRecord * records > window, 'The source exceeds the old one-window character chunk');
  assert.equal((await running.service.command({ op: 'configure_task_execution', task_id: 0,
    profile: 'unicode_target', reasoning: 'medium', sandbox: { mode: 'workspace-write', network_access: false },
    approval: { mode: 'ask-for-approval' } })).reply.ok, true);
  const cursor = (await running.service.command({ op: 'read', task_id: 0, limit: 1 })).reply.result.task.cursor;
  assert.equal((await running.service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
  await until('the final framed Unicode compaction', async () => {
    const page = (await running.service.command({ op: 'read', task_id: 0, limit: 1 })).reply.result;
    if (page.task.cursor <= cursor) return false;
    const last = (await running.service.command({ op: 'read', task_id: 0, after: page.task.cursor - 1, limit: 1 })).reply.result;
    return last.messages.at(-1)?.role === 'context_replacement';
  }, 60_000);
  assert.equal((await running.service.command({ op: 'send', task_id: 0, message: 'Continue after switching the Unicode task endpoint.' })).reply.ok, true);
  await until('the complete framed Unicode reconstruction', async () => {
    const page = (await running.service.command({ op: 'read', task_id: 0, limit: 1 })).reply.result;
    return ordinary === 1 && page.task.phase === 'idle';
  }, 60_000);
  assert.ok(summaries > 1);
  assert.ok(carried > 0);
  assert.equal(seenCharacters - carried * carryCharacters, perRecord * records,
    'Successful model calls process every original Unicode character exactly once, in addition to the complete carry');
  const database = new DatabaseSync(path.join(running.directory, 'state', 'journal.sqlite'), { readOnly: true });
  try {
    const row = database.prepare(`SELECT max(length(CAST(e.value AS BLOB))) AS maximum
      FROM journal j, json_each(j.decision, '$.effects') e
      WHERE json_extract(e.value, '$.kind') = 'context_compaction'`).get();
    assert.ok(row.maximum > 0 && row.maximum <= running.service.limits.frame_bytes,
      'The actual committed compact effect, including metadata and carry, obeys the kernel frame');
  } finally { database.close(); }
  const recovered = [];
  let after = 0;
  do {
    const page = (await running.service.command({ op: 'read', task_id: 0, after, limit: 1 })).reply.result;
    recovered.push(...page.messages.filter(message => message.role === 'user' && message.content.startsWith('UNICODE_')).map(message => message.content));
    if (!page.has_more) break;
    after += page.messages.length;
  } while (true);
  assert.deepEqual(recovered, originals);
  assert.deepEqual(failures, []);
  assert.deepEqual(running.failures, []);
});

test('an account endpoint without native compact completes the same operation through client summaries', { timeout: 20_000 }, async t => {
  const original = 'Retain the original historical requirement and its observed result. '.repeat(250);
  let native = 0, summaries = 0, ordinary = 0;
  const running = await accountCompactionService(t, (request, response) => {
    if (request.url === '/v1/responses/compact') {
      native++;
      assert.ok(JSON.stringify(request.body.input).includes(original));
      return jsonResponse(response, { error: { code: 'unsupported_operation' } }, 405);
    }
    if (request.body.tool_choice === 'none') {
      summaries++;
      return modelResponse(response, [assistant(`NATIVE_UNAVAILABLE_CLIENT_SUMMARY_${summaries}`)]);
    }
    ordinary++;
    if (ordinary > 1) {
      assert.ok(JSON.stringify(request.body.input).includes('NATIVE_UNAVAILABLE_CLIENT_SUMMARY_'));
      assert.equal(JSON.stringify(request.body.input).includes(original), false);
    }
    modelResponse(response, [assistant(ordinary === 1 ? 'Completed the original task.' : 'Continued using the client summary.')]);
  }, { compaction: { ...policy(null), enabled: false, targets: [{ profile: 'fixture', window_tokens: 8192,
    output_reserve_tokens: 512, cache_ttl_ms: null, method: 'auto' }] } });
  await running.service.command({ op: 'create', profile: 'fixture', message: original });
  await taskIdle(running.service);
  assert.equal((await running.service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
  const compacted = await contextReplaced(running.service, 1, 0, 10_000);
  assert.equal(compacted.messages.find(message => message.role === 'context_replacement').content.format, 'portable');
  assert.equal((await running.service.command({ op: 'send', task_id: 0, message: 'Continue after native capability fallback.' })).reply.ok, true);
  const page = await taskIdle(running.service);
  assert.equal(native, 1);
  assert.ok(summaries > 1);
  assert.equal(ordinary, 2);
  assert.ok(JSON.stringify(page.messages).includes(original));
  assert.equal(page.messages.some(message => message.role === 'error'), false);
  assert.deepEqual(running.failures, []);
});

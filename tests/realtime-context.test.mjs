import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { answer, filesystemServer } from './fixtures/filesystem-boundaries-server.mjs';
import { home, responsesServer, taskIdle } from './support.mjs';

function realtimeContext(body) {
  const item = body.input.at(-1);
  assert.equal(item?.role, 'developer', 'Realtime Context is appended as a developer message');
  assert.equal(typeof item.content, 'string');
  const currentTimeMatch = item.content.match(/Current time \(UTC\): ([^\n]+)/);
  const elapsedMatch = item.content.match(/Time since task start: (\d+) ms/);
  assert.ok(currentTimeMatch && elapsedMatch,
    `The provider receives both current Realtime Context values: ${item.content}`);
  const currentTime = Date.parse(currentTimeMatch[1]);
  assert.ok(Number.isFinite(currentTime), 'Current time is an absolute timestamp');
  return { content: item.content, currentTime, elapsedMs: Number(elapsedMatch[1]) };
}

async function waitForCompactionCommit(fixture, taskId, summaryText) {
  const deadline = Date.now() + 10000;
  let page;
  do {
    page = await fixture.command({ op: 'read', task_id: taskId });
    if (page.task.phase === 'idle' && page.task.operations.length === 0 && JSON.stringify(page).includes(summaryText)) {
      return page;
    }
    await delay(20);
  } while (Date.now() < deadline);
  throw new Error(`Manual compaction did not commit its summary: ${JSON.stringify(page)}`);
}

test('Realtime Context defaults to current time and task elapsed time without entering history or starting inference', async t => {
  const fixture = await filesystemServer(t, { respond: () => answer('REALTIME_DEFAULT_REPLY') });
  const created = await fixture.command({ op: 'create', profile: fixture.profile,
    message: 'Check the default live context.' });
  const initialPage = await fixture.idle(created.task_id);

  const firstBody = fixture.upstream.requests[0];
  const first = realtimeContext(firstBody);
  await delay(100);
  assert.equal(fixture.upstream.requests.length, 1,
    'Changing the current time and elapsed duration while idle does not start another model request');
  const idlePage = await fixture.command({ op: 'read', task_id: created.task_id });
  assert.equal(idlePage.messages.length, initialPage.messages.length,
    'Changing Realtime Context while idle does not append a history message');

  await fixture.command({ op: 'send', task_id: created.task_id, message: 'Request a fresh live context.' });
  const page = await fixture.idle(created.task_id);
  const secondBody = fixture.upstream.requests[1];
  const second = realtimeContext(secondBody);
  assert.deepEqual(secondBody.input.slice(0, firstBody.input.length - 1), firstBody.input.slice(0, -1),
    'Realtime Context leaves the existing model input as an unchanged prefix');
  assert.ok(second.currentTime >= first.currentTime);
  assert.ok(second.elapsedMs > first.elapsedMs, 'Elapsed duration is refreshed for each model request');
  assert.doesNotMatch(JSON.stringify(page.messages), /Current time \(UTC\):|Time since task start:/,
    'Realtime values are not added to the task conversation history');

  for (const [sources, expected] of [
    [[], []],
    [['task_elapsed_time'], ['Time since task start:']],
  ]) {
    const configured = await fixture.command({ op: 'create', profile: fixture.profile,
      message: `Check configured sources ${JSON.stringify(sources)}.`, settings: { realtime_context: sources } });
    await fixture.idle(configured.task_id);
    const body = fixture.upstream.requests.at(-1);
    const input = JSON.stringify(body.input);
    for (const label of ['Current time (UTC):', 'Time since task start:']) {
      assert.equal(input.includes(label), expected.includes(label),
        `Realtime Context source selection ${JSON.stringify(sources)} controls ${label}`);
    }
    if (sources.length > 0) {
      const item = body.input.at(-1);
      assert.equal(item.role, 'developer');
      assert.ok(item.content.includes('Time since task start:'));
      assert.ok(!item.content.includes('Current time (UTC):'));
    }
  }
  assert.deepEqual(fixture.upstream.failures, []);
});

test('elapsed-only Realtime Context retains the task start across a public service restart', async t => {
  const directory = await home(t);
  const key = `SELVEDGE_REALTIME_RESTART_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture';
  t.after(() => { delete process.env[key]; });
  const upstream = await responsesServer(t, () => answer('RESTARTED_REALTIME_REPLY'));
  const options = { home: directory, cwd: directory, config: validateConfig({
    ...defaultConfig, chatgpt: false,
    profiles: { fixture: { provider: 'responses', model: 'realtime-restart-fixture',
      endpoint: upstream.endpoint, api_key_env: key } },
    compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 60000,
      targets: [{ profile: 'fixture', window_tokens: 8192, output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'summary' }] },
  }) };
  let service = await Service.open(options);
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'fixture', message: 'Start the elapsed-time task.',
    settings: { realtime_context: ['task_elapsed_time'] } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const task_id = created.reply.result.task_id;
  const firstPage = await taskIdle(service, task_id);
  const firstItem = upstream.requests[0].input.at(-1);
  assert.equal(firstItem.role, 'developer');
  assert.doesNotMatch(firstItem.content, /Current time \(UTC\):/);
  const firstElapsed = Number(firstItem.content.match(/Time since task start: (\d+) ms/)?.[1]);
  assert.ok(Number.isFinite(firstElapsed));
  assert.doesNotMatch(JSON.stringify(firstPage.messages), /Time since task start:/);

  await delay(50);
  await service.close();
  service = await Service.open(options);
  const resumed = await service.command({ op: 'send', task_id, message: 'Continue after the service restart.' });
  assert.equal(resumed.reply.ok, true, JSON.stringify(resumed.reply));
  const resumedPage = await taskIdle(service, task_id);
  const resumedItem = upstream.requests.at(-1).input.at(-1);
  assert.equal(resumedItem.role, 'developer');
  assert.doesNotMatch(resumedItem.content, /Current time \(UTC\):/,
    'The elapsed-only setting persists across service restart');
  const resumedElapsed = Number(resumedItem.content.match(/Time since task start: (\d+) ms/)?.[1]);
  assert.ok(resumedElapsed > firstElapsed, 'Elapsed duration continues from the original task start');
  assert.doesNotMatch(JSON.stringify(resumedPage.messages), /Time since task start:/);
  assert.deepEqual(upstream.failures, []);
});

test('compaction summarizes the full prior context and resumes with the latest tracked context before summary, new history, and Realtime Context', async t => {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const guidance = path.join(workspace, 'AGENTS.md');
  const original = 'AAAAAAAAAAAAAAA';
  const updated = 'ZZZZZZZZZZZZZZZZZZZZZZ';
  await mkdir(path.join(workspace, '.git'), { recursive: true });
  await writeFile(guidance, original);

  const summaryText = 'COMPACTION_SUMMARY_4Q';
  let ordinaryReply = 0;
  const fixture = await filesystemServer(t, { directory, cwd: workspace,
    config: { compaction: { enabled: false, background_percent: 65, blocking_percent: 90, idle_lead_ms: 60000,
      targets: [{ profile: 'fixture', window_tokens: 8192, output_reserve_tokens: 1024, cache_ttl_ms: null, method: 'summary' }] } },
    respond: body => body.tools.length === 0 ? answer(summaryText) : answer(`ORDINARY_REPLY_${++ordinaryReply}`),
  });

  const created = await fixture.command({ op: 'create', profile: fixture.profile, message: 'USER_BEFORE_COMPACTION_1',
    settings: { workspace: { roots: [workspace], primary_root: workspace } } });
  await fixture.idle(created.task_id);
  const firstBody = fixture.upstream.requests[0];
  assert.ok(JSON.stringify(firstBody.input).includes(original), 'The tracked source is part of the model context');

  await writeFile(guidance, updated);
  await fixture.command({ op: 'send', task_id: created.task_id, message: 'USER_BEFORE_COMPACTION_2' });
  await fixture.idle(created.task_id);

  await fixture.command({ op: 'compact', task_id: created.task_id });
  await waitForCompactionCommit(fixture, created.task_id, summaryText);
  const summaryBody = fixture.upstream.requests.findLast(body => body.tools.length === 0);
  assert.ok(summaryBody, 'Manual compaction sends a summary request');
  const latestOrdinaryBody = fixture.upstream.requests.findLast(body => body.tools.length > 0);
  assert.ok(latestOrdinaryBody, 'The task completed a regular request before compaction');
  const latestOrdinaryPrefix = latestOrdinaryBody.input.slice(0, -1);
  assert.deepEqual(summaryBody.input.slice(0, latestOrdinaryPrefix.length), latestOrdinaryPrefix,
    'The summary request preserves the latest ordinary input prefix and omits only its trailing Realtime Context');
  const summaryInput = JSON.stringify(summaryBody.input);
  for (const priorValue of [original, updated, 'USER_BEFORE_COMPACTION_1', 'USER_BEFORE_COMPACTION_2',
    'ORDINARY_REPLY_1', 'ORDINARY_REPLY_2']) {
    assert.ok(summaryInput.includes(priorValue), `The summary request receives prior context value ${priorValue}`);
  }
  assert.ok(summaryInput.indexOf('ORDINARY_REPLY_2') > summaryInput.indexOf('USER_BEFORE_COMPACTION_2'),
    'The summary input continues through the assistant output from the last regular request');
  assert.doesNotMatch(summaryInput, /Current time \(UTC\):|Time since task start:/,
    'Realtime Context is excluded from the compaction input');

  await fixture.command({ op: 'send', task_id: created.task_id, message: 'USER_AFTER_COMPACTION_3' });
  const page = await fixture.idle(created.task_id);
  const resumedBody = fixture.upstream.requests.at(-1);
  const resumedRealtime = resumedBody.input.at(-1);
  assert.equal(resumedRealtime.role, 'developer');
  assert.match(resumedRealtime.content, /Time since task start:/,
    'The resumed request ends with its current Realtime Context');
  const resumedHistory = JSON.stringify(resumedBody.input.slice(0, -1));
  const latestContextPosition = resumedHistory.indexOf(updated);
  const summaryPosition = resumedHistory.indexOf(summaryText);
  const newMessagePosition = resumedHistory.indexOf('USER_AFTER_COMPACTION_3');
  const realtimePosition = JSON.stringify(resumedBody.input).lastIndexOf(JSON.stringify(resumedRealtime));
  assert.ok(latestContextPosition >= 0, 'The post-compaction request includes the latest complete Tracked Context');
  assert.equal(resumedHistory.includes(original), false, 'The replaced window does not retain old Tracked Context content');
  assert.equal(resumedHistory.indexOf(updated, latestContextPosition + updated.length), -1,
    'The latest complete Tracked Context is not repeated as its earlier value plus an update');
  assert.ok(summaryPosition > latestContextPosition, 'The summary follows the latest complete Tracked Context');
  assert.ok(newMessagePosition > summaryPosition, 'Post-compaction conversation follows the summary');
  assert.ok(realtimePosition > newMessagePosition, 'The current Realtime Context follows all history in the request');
  assert.doesNotMatch(JSON.stringify(page.messages), /Current time \(UTC\):|Time since task start:/,
    'Realtime Context remains outside persisted conversation history');
  assert.deepEqual(fixture.upstream.failures, []);
});

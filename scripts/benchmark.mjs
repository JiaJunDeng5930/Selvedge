import assert from 'node:assert/strict';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir, platform, arch } from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { Journal } from '../host/journal.mjs';
import { buildIdentity } from '../host/kernel.mjs';

// Deterministic workload; timing is observational and is never a CI pass criterion.
const historyTurns = 32;
const messageBytes = 1024;
const sizes = [17, 65];
const results = [];
for (const taskCount of sizes) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-benchmark-'));
  const filename = path.join(directory, 'journal.sqlite');
  let journal;
  try {
    journal = await Journal.open(filename);
    const latencies = [];
    const execute = async input => {
      const start = performance.now();
      const result = await journal.execute(input);
      latencies.push(performance.now() - start);
      assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
      return result;
    };
    const settle = async decision => {
      const pending = [...decision.effects];
      while (pending.length) {
        const effect = pending.shift();
        assert.ok(['observe_context', 'model'].includes(effect.kind), `Unexpected benchmark effect: ${effect.kind}`);
        const next = await execute(effect.kind === 'observe_context'
          ? { kind: 'context_observed', task_id: effect.task_id, ticket: effect.ticket, ok: true, observations: [] }
          : { kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true, items: [{ type: 'text', text: 'done' }] });
        pending.push(...next.effects);
      }
    };
    await execute({ kind: 'configure', instructions: { configured: 'Benchmark workload', global: null },
      profiles: [{ key: 'fixture', provider: 'echo', name: 'fixture', reasoning_options: null }],
      tools: [], max_fork: 4, max_descendants: taskCount - 1 });
    await settle(await execute({ kind: 'command', command: { op: 'create', profile: 'fixture', message: 'x'.repeat(messageBytes) } }));
    for (let turn = 1; turn < historyTurns; turn++) {
      await settle(await execute({ kind: 'command', command: { op: 'send', task_id: 0, message: 'x'.repeat(messageBytes) } }));
    }
    for (let parent = 0, count = 1; count < taskCount; parent++, count += 4) {
      await settle(await execute({ kind: 'command', command: { op: 'fork', task_id: parent, child_count: 4 } }));
    }
    const before = (await execute({ kind: 'command', command: { op: 'list' } })).reply.result;
    assert.equal(before.tasks.length, taskCount);
    const sequence = journal.sequence;
    await journal.close();
    const databaseBytes = (await stat(filename)).size;
    let walBytes = 0;
    try { walBytes = (await stat(`${filename}-wal`)).size; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const replayStart = performance.now();
    journal = await Journal.open(filename);
    const replayMs = performance.now() - replayStart;
    assert.equal(journal.sequence, sequence);
    assert.deepEqual((await journal.execute({ kind: 'command', command: { op: 'list' } })).reply.result, before);
    await journal.close();
    latencies.sort((a, b) => a - b);
    results.push({ tasks: taskCount, history_turns_before_fork: historyTurns, message_bytes: messageBytes,
      committed_inputs: sequence, journal_bytes: databaseBytes + walBytes, database_bytes: databaseBytes, wal_bytes: walBytes,
      median_transition_ms: latencies[Math.floor(latencies.length * 0.5)],
      p95_transition_ms: latencies[Math.floor(latencies.length * 0.95)],
      max_transition_ms: latencies.at(-1), replay_ms: replayMs });
  } finally {
    await journal?.close();
    await rm(directory, { recursive: true, force: true });
  }
}
console.log(JSON.stringify({ measured_at: new Date().toISOString(), platform: `${platform()}-${arch()}`, bun: Bun.version,
  kernel: await buildIdentity(), measurements: results,
  scope: 'SQLite journal and compiled Bend JavaScript Worker request latency, including durable commits where required; replay includes Worker startup and committed-input validation. Journal bytes include the database and any retained WAL. Model replies and empty context observations are deterministic fixtures. Measurements do not establish OS process memory use, physical history sharing or asymptotic complexity.' }, null, 2));

import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, stat } from 'node:fs/promises';
import { tmpdir, platform, arch } from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
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
  const resourceFile = path.join(directory, 'native-resources.txt');
  const options = {};
  if (platform() === 'darwin') {
    const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
    const wrapper = path.join(directory, 'timed-kernel.sh');
    const binary = fileURLToPath(new URL('../.build/selvedge-kernel', import.meta.url));
    await writeFile(wrapper, `#!/bin/sh\nexec /usr/bin/time -l ${quote(binary)} 2>${quote(resourceFile)}\n`, { mode: 0o700 });
    options.kernelOptions = { binary: wrapper };
  }
  const nativePeak = async () => {
    if (platform() !== 'darwin') return null;
    const report = await readFile(resourceFile, 'utf8');
    const matched = report.match(/^\s*(\d+)\s+maximum resident set size\s*$/m);
    assert.ok(matched, `macOS time did not report native maximum resident set size:\n${report}`);
    return Number(matched[1]);
  };
  let journal;
  try {
    journal = await Journal.open(filename, options);
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
        assert.equal(effect.kind, 'model');
        const next = await execute({ kind: 'model', task_id: effect.task_id, ticket: effect.ticket,
          ok: true, items: [{ type: 'text', text: 'done' }] });
        pending.push(...next.effects);
      }
    };
    await execute({ kind: 'configure', profiles: [{ key: 'fixture', provider: 'echo', name: 'fixture' }],
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
    const nativePeakBytes = await nativePeak();
    const bytes = (await stat(filename)).size;
    const replayStart = performance.now();
    journal = await Journal.open(filename, options);
    const replayMs = performance.now() - replayStart;
    assert.equal(journal.sequence, sequence);
    assert.deepEqual((await journal.execute({ kind: 'command', command: { op: 'list' } })).reply.result, before);
    await journal.close();
    const replayPeakBytes = await nativePeak();
    latencies.sort((a, b) => a - b);
    results.push({ tasks: taskCount, history_turns_before_fork: historyTurns, message_bytes: messageBytes,
      committed_inputs: sequence, journal_bytes: bytes,
      median_transition_ms: latencies[Math.floor(latencies.length * 0.5)],
      p95_transition_ms: latencies[Math.floor(latencies.length * 0.95)],
      max_transition_ms: latencies.at(-1), replay_ms: replayMs,
      native_peak_rss_bytes: nativePeakBytes, replay_native_peak_rss_bytes: replayPeakBytes });
  } finally {
    await journal?.close();
    await rm(directory, { recursive: true, force: true });
  }
}
console.log(JSON.stringify({ measured_at: new Date().toISOString(), platform: `${platform()}-${arch()}`, node: process.version,
  kernel: await buildIdentity(), measurements: results,
  scope: 'SQLite commit and native kernel latency; replay includes native startup. On macOS, time -l measures native maximum RSS, excluding Node. RSS is null on other platforms. Measurements do not prove physical history sharing or asymptotic complexity.' }, null, 2));

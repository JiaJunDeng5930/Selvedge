import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { arch, platform, release, tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { Journal, journalFormat } from '../host/journal.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function commandVersion(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8' });
  const output = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
  return {
    command: [command, ...args],
    exit_code: result.status,
    output: output || null,
    error: result.error?.message ?? null,
  };
}

function gitValue(args) {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${result.stderr.trim()}`);
  return result.stdout.trim();
}

async function artifactFingerprint(filename, expectedSha256 = null) {
  try {
    const contents = await readFile(path.join(root, filename));
    const sha256 = createHash('sha256').update(contents).digest('hex');
    return { available: true, bytes: contents.length, sha256,
      matches_pin: expectedSha256 === null ? null : sha256 === expectedSha256 };
  } catch (error) {
    // DEFENSE: A runtime-only run can precede build/bootstrap; record absent generated artifacts instead of claiming a version.
    if (error.code === 'ENOENT') return { available: false, error: 'ENOENT' };
    throw error;
  }
}

export async function collectBenchmarkProvenance() {
  const [toolchain, packageInfo] = await Promise.all([
    readFile(path.join(root, 'toolchain.json'), 'utf8').then(JSON.parse),
    readFile(path.join(root, 'package.json'), 'utf8').then(JSON.parse),
  ]);
  const status = gitValue(['status', '--porcelain', '--untracked-files=all']);
  const trackedDiff = gitValue(['diff', 'HEAD', '--binary']);
  const extracted = Object.fromEntries(await Promise.all(['host', 'kernel', 'interaction', 'browser'].map(async target => [target, {
    model: await artifactFingerprint(`.build/${target}-model.mjs`),
    runtime: await artifactFingerprint(`.build/${target}-runtime.js`),
  }])));
  const zarithStubs = Object.fromEntries(await Promise.all(Object.entries(toolchain.zarith_stubs_js_sha256).map(async ([name, expected]) => [name,
    await artifactFingerprint(`.build/deps/zarith_stubs_js/${name}`, expected)])));
  return {
    measured_at: new Date().toISOString(),
    git: {
      revision: gitValue(['rev-parse', 'HEAD']),
      branch: gitValue(['branch', '--show-current']) || null,
      working_tree_dirty: status.length > 0,
      status_entries: status ? status.split('\n').length : 0,
      tracked_diff_sha256: createHash('sha256').update(trackedDiff).digest('hex'),
    },
    system: { platform: platform(), release: release(), arch: arch() },
    runtime: {
      bun: Bun.version,
      node_compatibility: process.versions.node,
      journal_format: journalFormat,
    },
    package: { name: packageInfo.name, version: packageInfo.version ?? null, package_manager: packageInfo.packageManager ?? null },
    benchmark_code: {
      driver: await artifactFingerprint('scripts/benchmark.mjs'),
      runtime: await artifactFingerprint('scripts/runtime-benchmark.mjs'),
      build: await artifactFingerprint('scripts/build.mjs'),
    },
    toolchain: {
      pins: toolchain,
      observed: {
        rocq: commandVersion('rocq', ['--version']),
        ocaml: commandVersion('ocamlc', ['-version']),
        js_of_ocaml: commandVersion('js_of_ocaml', ['--version']),
        metarocq_template: commandVersion('opam', ['var', 'rocq-metarocq-template:version']),
        zarith: commandVersion('ocamlfind', ['query', '-format', '%v', 'zarith']),
        zarith_stubs_js: { source: '.build/deps/zarith_stubs_js', files: zarithStubs },
      },
    },
    extracted_artifacts: extracted,
  };
}

function quantile(sorted, fraction) {
  return sorted[Math.floor(sorted.length * fraction)];
}

async function fileSize(filename) {
  return (await stat(filename)).size;
}

async function retainedWalBytes(filename) {
  try { return await fileSize(`${filename}-wal`); }
  // DEFENSE: SQLite may checkpoint and remove its WAL when the final connection closes.
  catch (error) { if (error.code === 'ENOENT') return 0; throw error; }
}

async function measureWorkload({ taskCount, historyTurns, messageBytes }) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-runtime-benchmark-'));
  const filename = path.join(directory, 'journal.sqlite');
  let journal;
  try {
    journal = await Journal.open(filename);
    const latencies = [];
    const execute = async input => {
      const started = performance.now();
      const result = await journal.execute(input);
      latencies.push(performance.now() - started);
      assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
      return result;
    };
    const settle = async decision => {
      const pending = [...decision.effects];
      while (pending.length > 0) {
        const effect = pending.shift();
        assert.ok(['observe_context', 'model'].includes(effect.kind), `Unexpected benchmark effect: ${effect.kind}`);
        const input = effect.kind === 'observe_context'
          ? { kind: 'context_observed', task_id: effect.task_id, ticket: effect.ticket, ok: true, observations: [] }
          : { kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true,
              items: [{ type: 'text', part: 0, text: 'done' }] };
        pending.push(...(await execute(input)).effects);
      }
    };

    await execute({
      kind: 'configure',
      profiles: [{ key: 'fixture', provider: 'echo', name: 'fixture-model', reasoning_options: null }],
      tools: [],
      plugins: [],
      max_fork: 4,
      max_descendants: taskCount - 1,
      instructions: { configured: 'Benchmark workload', global: null },
    });
    await settle(await execute({ kind: 'command', command: {
      op: 'create', profile: 'fixture', message: 'x'.repeat(messageBytes),
    } }));
    for (let turn = 1; turn < historyTurns; turn++) {
      await settle(await execute({ kind: 'command', command: {
        op: 'send', task_id: 0, message: 'x'.repeat(messageBytes),
      } }));
    }
    for (let parent = 0, count = 1; count < taskCount; parent++, count += 4) {
      await settle(await execute({ kind: 'command', command: { op: 'fork', task_id: parent, child_count: 4 } }));
    }

    const before = (await execute({ kind: 'command', command: { op: 'list' } })).reply.result;
    assert.equal(before.tasks.length, taskCount);
    const sequence = journal.sequence;
    await journal.close();
    const databaseBytes = await fileSize(filename);
    const walBytes = await retainedWalBytes(filename);

    const replayStarted = performance.now();
    journal = await Journal.open(filename);
    const replayMs = performance.now() - replayStarted;
    assert.equal(journal.sequence, sequence);
    assert.deepEqual((await journal.execute({ kind: 'command', command: { op: 'list' } })).reply.result, before);
    await journal.close();

    latencies.sort((left, right) => left - right);
    return {
      tasks: taskCount,
      history_turns_before_fork: historyTurns,
      message_bytes: messageBytes,
      committed_inputs: sequence,
      journal_bytes: databaseBytes + walBytes,
      database_bytes: databaseBytes,
      wal_bytes: walBytes,
      transition_count: latencies.length,
      median_transition_ms: quantile(latencies, 0.5),
      p95_transition_ms: quantile(latencies, 0.95),
      max_transition_ms: latencies.at(-1),
      replay_ms: replayMs,
    };
  } finally {
    await journal?.close();
    await rm(directory, { recursive: true, force: true });
  }
}

export function runtimeWorkloadOptions({ quick = false, tasks, historyTurns, messageBytes } = {}) {
  return {
    tasks: tasks ?? (quick ? [5] : [17, 65]),
    historyTurns: historyTurns ?? (quick ? 2 : 32),
    messageBytes: messageBytes ?? (quick ? 16 : 1024),
  };
}

export async function runRuntimeBenchmark(options = {}) {
  const workload = runtimeWorkloadOptions(options);
  assert.ok(workload.tasks.length > 0 && workload.tasks.every(count => Number.isSafeInteger(count) && count > 1 && count % 4 === 1),
    'Task counts must be 1 plus a positive multiple of four');
  assert.ok(Number.isSafeInteger(workload.historyTurns) && workload.historyTurns > 0, 'History turns must be a positive integer');
  assert.ok(Number.isSafeInteger(workload.messageBytes) && workload.messageBytes > 0, 'Message bytes must be a positive integer');
  const measurements = [];
  for (const taskCount of workload.tasks) {
    measurements.push(await measureWorkload({ taskCount, historyTurns: workload.historyTurns, messageBytes: workload.messageBytes }));
  }
  const report = {
    provenance: options.provenance ?? await collectBenchmarkProvenance(),
    workload: {
      tasks: workload.tasks,
      history_turns: workload.historyTurns,
      message_bytes: workload.messageBytes,
      deterministic_external_responses: { context_observations: [], model_text: 'done' },
    },
    measurements,
    scope: 'Public Journal operations over the current Rocq runtime; each measurement includes SQLite journal commits and deterministic context/model callback inputs. Replay includes Journal.open and committed-input replay. No historical performance threshold is applied.',
  };
  await mkdir(path.join(root, '.workpad'), { recursive: true });
  await writeFile(path.join(root, '.workpad/runtime-benchmark.json'), `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

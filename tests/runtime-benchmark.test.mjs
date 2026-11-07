import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execute = promisify(execFile);
const root = fileURLToPath(new URL('../', import.meta.url));

test('the runtime benchmark CLI completes its requested workload and reports replay timing', { timeout: 120000 }, async () => {
  const taskCount = 5;
  const { stdout } = await execute(process.execPath, ['scripts/benchmark.mjs', '--scenario', 'runtime',
    '--quick', '--tasks', String(taskCount)], { cwd: root, timeout: 90000 });
  const report = JSON.parse(stdout);
  assert.equal(report.scenario, 'runtime');
  assert.deepEqual(report.measurements.map(measurement => measurement.tasks), [taskCount]);
  const [measurement] = report.measurements;
  assert.ok(Number.isFinite(measurement.replay_ms) && measurement.replay_ms >= 0,
    'A completed workload must report the measured journal reopen without a performance threshold');
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { runBash } from '../host/process.mjs';

const limits = { bash_timeout_ms: 1000, tool_output_bytes: 4 };

test('Bash drains both pipes while bounding retained output', async () => {
  const result = await runBash({ command: "printf abcdef; printf uvwxyz >&2" }, limits);
  assert.equal(result.error, false);
  assert.equal(result.value.exit_code, 0);
  assert.equal(result.value.stdout, 'abcd');
  assert.equal(result.value.stderr, 'uvwx');
  assert.equal(result.value.stdout_truncated, true);
  assert.equal(result.value.stderr_truncated, true);
});

test('Bash deadlines and cancellation settle with explicit failure', { timeout: 5000 }, async () => {
  const timed = await runBash({ command: 'exec sleep 10', timeout_ms: 50 }, limits);
  assert.equal(timed.error, true);
  assert.equal(timed.value.error.code, 'command_timed_out');
  const controller = new AbortController();
  const pending = runBash({ command: 'exec sleep 10' }, limits, { signal: controller.signal });
  controller.abort(new Error('fixture cancellation'));
  const cancelled = await pending;
  assert.equal(cancelled.error, true);
  assert.equal(cancelled.value.error.code, 'cancelled');
});

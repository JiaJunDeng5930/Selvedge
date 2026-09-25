import test from 'node:test';
import assert from 'node:assert/strict';
import { runBash } from '../host/process.mjs';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { home } from './support.mjs';

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

test('nonzero Bash exit status is a tool error rather than a successful build', async () => {
  const result = await runBash({ command: 'printf failed >&2; exit 7' }, limits);
  assert.equal(result.error, true);
  assert.equal(result.value.exit_code, 7);
  assert.equal(result.value.error.code, 'command_failed');
});

test('Bash retains bounded, revision-addressed output artifacts and reports artifact truncation honestly', async t => {
  const artifactDirectory = await home(t);
  const result = await runBash({ command: 'printf abcdefghijklmnop; printf uvwxyz >&2' },
    { ...limits, artifact_bytes: 12 }, { artifactDirectory });
  assert.equal(result.error, false, JSON.stringify(result));
  for (const [stream, wanted, total, truncated] of [['stdout', 'abcdefghijkl', 16, true], ['stderr', 'uvwxyz', 6, false]]) {
    const artifact = result.value[`${stream}_artifact`];
    assert.equal(await readFile(artifact.path, 'utf8'), wanted);
    assert.equal(artifact.revision, createHash('sha256').update(wanted).digest('hex'));
    assert.equal(artifact.total_bytes, total);
    assert.equal(artifact.truncated, truncated);
    assert.equal(artifact.persisted, true);
  }
});

test('truncated Bash previews do not emit a broken UTF-8 suffix', async () => {
  const result = await runBash({ command: "printf '😀😀'" }, { ...limits, tool_output_bytes: 5 });
  assert.equal(result.value.stdout, '😀');
  assert.equal(result.value.stdout_truncated, true);
});

test('a capped UTF-8 artifact remains readable and its revision describes the retained bytes', async t => {
  const artifactDirectory = await home(t);
  const result = await runBash({ command: "printf '😀😀'" }, { ...limits, tool_output_bytes: 3, artifact_bytes: 5 }, { artifactDirectory });
  const artifact = result.value.stdout_artifact;
  assert.equal(await readFile(artifact.path, 'utf8'), '😀');
  assert.equal(artifact.bytes, 4);
  assert.equal(artifact.total_bytes, 8);
  assert.equal(artifact.revision, createHash('sha256').update('😀').digest('hex'));
});

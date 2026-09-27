import test from 'node:test';
import assert from 'node:assert/strict';
import { runBash, captureHeadTail } from '../host/process.mjs';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { home } from './support.mjs';

const limits = { bash_timeout_ms: 1000, bash_default_output_length: 4, bash_max_output_length: 65536 };

test('Bash drains both pipes while bounding retained output', async () => {
  const result = await runBash({ command: "printf abcdef; printf uvwxyz >&2" }, limits);
  assert.equal(result.error, false);
  assert.equal(result.value.exit_code, 0);
  assert.equal(result.value.stdout, 'ab\n… [2 Unicode characters omitted] …\nef');
  assert.equal(result.value.stderr, 'uv\n… [2 Unicode characters omitted] …\nyz');
  assert.equal(result.value.stdout_bytes, 6);
  assert.equal(result.value.stdout_omitted_characters, 2);
  assert.equal(result.value.stdout_truncated, true);
  assert.equal(result.value.stderr_truncated, true);
});

test('Bash deadlines and cancellation settle with explicit failure', { timeout: 5000 }, async () => {
  const timed = await runBash({ command: 'exec sleep 10', timeout_ms: 100 }, limits);
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
  const result = await runBash({ command: "printf '😀世界😀'", max_output_length: 2 }, limits);
  assert.equal(result.value.stdout, '😀\n… [2 Unicode characters omitted] …\n😀');
  assert.equal(result.value.stdout_truncated, true);
});

test('a capped UTF-8 artifact remains readable and its revision describes the retained bytes', async t => {
  const artifactDirectory = await home(t);
  const result = await runBash({ command: "printf '😀😀'", max_output_length: 1 }, { ...limits, artifact_bytes: 5 }, { artifactDirectory });
  const artifact = result.value.stdout_artifact;
  assert.equal(await readFile(artifact.path, 'utf8'), '😀');
  assert.equal(artifact.bytes, 4);
  assert.equal(artifact.total_bytes, 8);
  assert.equal(artifact.revision, createHash('sha256').update('😀').digest('hex'));
});

test('Unicode capture is invariant under every UTF-8 pipe split and bounds a one-character preview', () => {
  const bytes = Buffer.from('😀abc世界😀');
  for (const limit of [1, 2, 5, 20]) {
    const whole = captureHeadTail(limit);
    whole.add(bytes); whole.end();
    for (let position = 0; position <= bytes.length; position++) {
      const split = captureHeadTail(limit);
      split.add(bytes.subarray(0, position)); split.add(bytes.subarray(position)); split.end();
      assert.deepEqual(split.result(), whole.result());
    }
  }
});

test('Bash rejects malformed commands and output/deadline bounds before creating artifacts or spawning', async t => {
  const directory = await home(t);
  const { readdir } = await import('node:fs/promises');
  for (const arguments_ of [
    { command: '' }, { command: 'echo\0bad' }, { command: '\ud800' },
    { command: 'true', timeout_ms: 99 }, { command: 'true', timeout_ms: 1800001 },
    { command: 'true', max_output_length: 0 }, { command: 'true', max_output_length: 65537 },
    { command: 'true', unexpected: 1 },
  ]) {
    await assert.rejects(runBash(arguments_, limits, { artifactDirectory: directory }), /Malformed Bash effect/);
  }
  assert.deepEqual(await readdir(directory), []);
});

test('a completed shell cannot leave background descendants mutating the workspace', async t => {
  const directory = await home(t);
  const result = await runBash({ command: '(sleep 0.3; printf escaped > escaped.txt) & printf done' }, limits, { cwd: directory });
  assert.equal(result.error, false);
  assert.equal(result.value.stdout, 'done');
  await new Promise(resolve => setTimeout(resolve, 400));
  await assert.rejects(readFile(path.join(directory, 'escaped.txt')), { code: 'ENOENT' });
});

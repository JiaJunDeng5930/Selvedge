import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { runBash } from '../host/process.mjs';
import { home, shellQuote } from './support.mjs';

const limits = { bash_timeout_ms: 1000, bash_default_output_length: 4, bash_max_output_length: 65536 };

test('real full pipes drain while capped Unicode artifacts retain exact readable bytes and hashes', async t => {
  const artifactDirectory = await home(t);
  const program = "process.stdout.write('🙂'.repeat(32768)); process.stderr.write('界'.repeat(32768));";
  const result = await runBash({ command: `${shellQuote(process.execPath)} -e ${shellQuote(program)}` },
    { ...limits, bash_timeout_ms: 5000, artifact_bytes: 5 }, { artifactDirectory });
  assert.equal(result.error, false, JSON.stringify(result.value));
  for (const [stream, text, total] of [['stdout', '🙂', 131072], ['stderr', '界', 98304]]) {
    const artifact = result.value[`${stream}_artifact`];
    const bytes = await readFile(artifact.path);
    assert.equal(bytes.toString('utf8'), text);
    assert.equal(artifact.revision, createHash('sha256').update(bytes).digest('hex'));
    assert.equal(artifact.total_bytes, total);
    assert.equal(artifact.truncated, true);
    assert.equal(artifact.persisted, true);
    assert.equal(result.value[stream].includes('\ufffd'), false);
  }
});

test('deadline, cancellation and shell exit release owned background processes and pipe handles', async t => {
  const directory = await home(t);
  for (const mode of ['deadline', 'cancellation', 'exit']) {
    const marker = path.join(directory, `${mode}.escaped`);
    const ready = path.join(directory, `${mode}.ready`);
    const controller = new AbortController();
    const command = `printf ready > ${shellQuote(ready)}; (sleep 0.3; printf escaped > ${shellQuote(marker)}) & ` +
      (mode === 'exit' ? 'printf done' : 'exec sleep 60');
    const pending = runBash({ command, timeout_ms: mode === 'deadline' ? 100 : 1000 }, limits, { signal: controller.signal });
    if (mode === 'cancellation') {
      const deadline = Date.now() + 1000;
      while (Date.now() < deadline) {
        try { await access(ready); break; }
        catch (error) { if (error.code !== 'ENOENT') throw error; await delay(10); }
      }
      await access(ready);
      controller.abort();
    }
    const result = await pending;
    assert.equal(result.error, mode !== 'exit');
    await delay(400);
    await assert.rejects(readFile(marker), { code: 'ENOENT' });
  }
});

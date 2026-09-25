import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, open } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';

export function killGroup(child, signal = 'SIGKILL') {
  if (!child.pid) return;
  try { process.kill(-child.pid, signal); }
  catch (error) { if (error.code !== 'ESRCH') throw error; }
}

export function capture(limit) {
  const chunks = [];
  let retained = 0;
  let total = 0;
  return {
    add(chunk) {
      total += chunk.length;
      const keep = Math.min(chunk.length, Math.max(0, limit - retained));
      if (keep) { chunks.push(Buffer.from(chunk.subarray(0, keep))); retained += keep; }
    },
    result() { return { text: new TextDecoder().decode(Buffer.concat(chunks, retained), { stream: total > retained }),
      truncated: total > retained, total_bytes: total }; },
  };
}

async function completeUtf8Prefix(file, length) {
  if (!length) return length;
  const tail = Buffer.alloc(Math.min(4, length));
  await file.read(tail, 0, tail.length, length - tail.length);
  let start = tail.length - 1;
  while (start > 0 && (tail[start] & 0xc0) === 0x80) start--;
  const first = tail[start];
  const wanted = first >= 0xc2 && first <= 0xdf ? 2 : first >= 0xe0 && first <= 0xef ? 3 : first >= 0xf0 && first <= 0xf4 ? 4 : 1;
  if (tail.length - start >= wanted) return length;
  const complete = length - (tail.length - start);
  await file.truncate(complete);
  return complete;
}

async function hashPrefix(file, length) {
  const hash = createHash('sha256');
  const buffer = Buffer.alloc(64 * 1024);
  for (let offset = 0; offset < length;) {
    const { bytesRead } = await file.read(buffer, 0, Math.min(buffer.length, length - offset), offset);
    if (!bytesRead) throw new Error('Output artifact was shortened during capture');
    hash.update(buffer.subarray(0, bytesRead));
    offset += bytesRead;
  }
  return hash;
}

/** Execute an already validated Bend Bash effect, draining both pipes concurrently. */
export async function runBash(arguments_, limits, { signal, cwd = process.cwd(), artifactDirectory } = {}) {
  signal?.throwIfAborted();
  const timeout = arguments_.timeout_ms ?? limits.bash_timeout_ms;
  if (typeof arguments_.command !== 'string' || !Number.isSafeInteger(timeout) || timeout <= 0) {
    throw new TypeError('Malformed Bash effect');
  }
  const artifacts = [];
  let child;
  try {
    if (artifactDirectory) {
      if (!Number.isSafeInteger(limits.artifact_bytes) || limits.artifact_bytes < 1) throw new TypeError('Invalid artifact byte limit');
      await mkdir(artifactDirectory, { recursive: true, mode: 0o700 });
      const directory = await mkdtemp(path.join(artifactDirectory, 'bash-'));
      for (const stream of ['stdout', 'stderr']) {
        const filename = path.join(directory, stream);
        artifacts.push({ path: filename, file: await open(filename, 'wx+', 0o600) });
      }
    }
    signal?.throwIfAborted();
    child = spawn('/bin/bash', ['-c', arguments_.command], { cwd, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    await Promise.allSettled(artifacts.map(artifact => artifact.file.close()));
    throw error;
  }
  const stdout = capture(limits.tool_output_bytes);
  const stderr = capture(limits.tool_output_bytes);
  let reason;
  let forcedClose;
  let closed = false;
  function stop(code, message) {
    reason ??= { code, message };
    if (closed) return;
    try { killGroup(child); }
    catch (error) { reason = { code: 'process_cleanup_failed', message: error.message }; }
    // A descendant that deliberately leaves the process group can retain a pipe.
    // Closing our handles bounds the wait; containment is an OS responsibility.
    forcedClose ??= setTimeout(() => { child.stdout.destroy(); child.stderr.destroy(); }, 2000);
  }
  const onAbort = () => stop('cancelled', 'The task was cancelled');
  signal?.addEventListener('abort', onAbort, { once: true });
  if (signal?.aborted) onAbort();
  const timer = setTimeout(() => stop('command_timed_out', `Command exceeded ${timeout} milliseconds`), timeout);
  async function drain(stream, output, artifact) {
    let hash = createHash('sha256');
    let retained = 0;
    let persisted = false;
    try {
      for await (const chunk of stream) {
        output.add(chunk);
        if (artifact) {
          const bytes = chunk.subarray(0, Math.max(0, Math.min(chunk.length, limits.artifact_bytes - retained)));
          if (bytes.length) {
            await artifact.file.writeFile(bytes);
            hash.update(bytes);
            retained += bytes.length;
          }
        }
      }
      if (artifact) {
        if (output.result().total_bytes > retained) {
          const complete = await completeUtf8Prefix(artifact.file, retained);
          if (complete !== retained) { retained = complete; hash = await hashPrefix(artifact.file, retained); }
        }
        await artifact.file.sync();
        persisted = true;
      }
    } catch (error) {
      stop('output_capture_failed', `Could not retain command output: ${error.message}`);
    } finally {
      if (artifact) {
        try { await artifact.file.close(); }
        catch (error) { persisted = false; stop('output_capture_failed', `Could not close command output: ${error.message}`); }
      }
    }
    return artifact ? { path: artifact.path, revision: hash.digest('hex'), bytes: retained,
      total_bytes: output.result().total_bytes, truncated: retained < output.result().total_bytes, persisted } : undefined;
  }
  const outputTasks = [drain(child.stdout, stdout, artifacts[0]), drain(child.stderr, stderr, artifacts[1])];
  return new Promise(resolve => {
    child.once('error', error => { reason = { code: 'command_start_failed', message: error.message }; });
    child.once('exit', () => {
      // Clean up ordinary background descendants even when the shell exits zero.
      try { killGroup(child); } catch (error) { reason ??= { code: 'process_cleanup_failed', message: error.message }; }
      forcedClose ??= setTimeout(() => { child.stdout.destroy(); child.stderr.destroy(); }, 2000);
    });
    child.once('close', async (exitCode, exitSignal) => {
      closed = true;
      clearTimeout(timer);
      clearTimeout(forcedClose);
      signal?.removeEventListener('abort', onAbort);
      const [outArtifact, errArtifact] = await Promise.all(outputTasks);
      const out = stdout.result();
      const err = stderr.result();
      const value = { exit_code: exitCode, signal: exitSignal, stdout: out.text, stderr: err.text,
        stdout_truncated: out.truncated, stderr_truncated: err.truncated,
        ...(out.truncated && outArtifact ? { stdout_artifact: outArtifact } : {}),
        ...(err.truncated && errArtifact ? { stderr_artifact: errArtifact } : {}) };
      if (!reason && (exitCode !== 0 || exitSignal !== null)) {
        reason = { code: 'command_failed', message: exitSignal ? `Command ended with signal ${exitSignal}` : `Command exited with status ${exitCode}` };
      }
      resolve(reason ? { value: { ...value, error: reason }, error: true } : { value, error: false });
    });
  });
}

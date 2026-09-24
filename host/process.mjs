import { spawn } from 'node:child_process';

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
    result() { return { text: Buffer.concat(chunks, retained).toString('utf8'), truncated: total > retained }; },
  };
}

/** Execute an already validated Bend Bash effect, draining both pipes concurrently. */
export async function runBash(arguments_, limits, { signal, cwd = process.cwd() } = {}) {
  signal?.throwIfAborted();
  const timeout = arguments_.timeout_ms ?? limits.bash_timeout_ms;
  if (typeof arguments_.command !== 'string' || !Number.isSafeInteger(timeout) || timeout <= 0) {
    throw new TypeError('Malformed Bash effect');
  }
  const child = spawn('/bin/bash', ['-lc', arguments_.command], { cwd, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  const stdout = capture(limits.tool_output_bytes);
  const stderr = capture(limits.tool_output_bytes);
  child.stdout.on('data', data => stdout.add(data));
  child.stderr.on('data', data => stderr.add(data));
  let reason;
  let forcedClose;
  function stop(code, message) {
    reason ??= { code, message };
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
  return new Promise(resolve => {
    child.once('error', error => { reason = { code: 'command_start_failed', message: error.message }; });
    child.once('exit', () => {
      // Clean up ordinary background descendants even when the shell exits zero.
      try { killGroup(child); } catch (error) { reason ??= { code: 'process_cleanup_failed', message: error.message }; }
      forcedClose ??= setTimeout(() => { child.stdout.destroy(); child.stderr.destroy(); }, 2000);
    });
    child.once('close', (exitCode, exitSignal) => {
      clearTimeout(timer);
      clearTimeout(forcedClose);
      signal?.removeEventListener('abort', onAbort);
      const out = stdout.result();
      const err = stderr.result();
      const value = { exit_code: exitCode, signal: exitSignal, stdout: out.text, stderr: err.text,
        stdout_truncated: out.truncated, stderr_truncated: err.truncated };
      resolve(reason ? { value: { ...value, error: reason }, error: true } : { value, error: false });
    });
  });
}

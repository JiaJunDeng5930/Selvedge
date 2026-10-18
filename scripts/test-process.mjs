import { compilerEnvironment } from './compiler-memory.mjs';
import { setPriority } from 'node:os';

async function collectTestOutput(stream, target) {
  const decoder = new TextDecoder();
  let output = '';
  for await (const chunk of stream) {
    const text = decoder.decode(chunk, { stream: true });
    output += text;
    target.write(text);
  }
  const tail = decoder.decode();
  output += tail;
  if (tail) target.write(tail);
  return output;
}

export function terminateTestProcessGroup(proc) {
  try {
    process.kill(-proc.pid, 'SIGKILL');
  } catch (error) {
    if (error.code !== 'ESRCH') console.error(`Could not kill test process group ${proc.pid}: ${error.message}`);
    if (proc.exitCode === null) proc.kill('SIGKILL');
  }
}

// Test files and shared compilation both own an isolated process group and watchdog.
export async function runTestProcess(label, command, { cwd, active = new Set(), timeout = 900_000, priority = 0, env = {} }) {
  console.log(`Running ${label}`);
  const started = performance.now();
  let proc;
  let timer;
  let timedOut = false;
  try {
    proc = Bun.spawn(command, { cwd, env: compilerEnvironment(env), stdout: 'pipe', stderr: 'pipe', detached: true });
    active.add(proc);
    if (priority && process.platform !== 'win32') setPriority(proc.pid, priority);
    // Drain both pipes immediately; descendants can keep them open after the parent exits.
    const stdout = collectTestOutput(proc.stdout, process.stdout);
    const stderr = collectTestOutput(proc.stderr, process.stderr);
    const exited = proc.exited.then(code => {
      terminateTestProcessGroup(proc);
      return code;
    });
    timer = setTimeout(() => {
      timedOut = true;
      terminateTestProcessGroup(proc);
    }, timeout);
    const [exitCode, out, err] = await Promise.all([exited, stdout, stderr]);
    return { exitCode, out, err, signal: proc.signalCode, timedOut, pid: proc.pid };
  } finally {
    clearTimeout(timer);
    if (proc) {
      terminateTestProcessGroup(proc);
      active.delete(proc);
    }
    console.log(`Finished ${label} (${((performance.now() - started) / 1000).toFixed(2)}s).`);
  }
}

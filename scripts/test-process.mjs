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
    // DEFENSE: The owned group may already have exited (ESRCH); report other kill failures and terminate a still-running direct child.
    if (error.code !== 'ESRCH') console.error(`Could not kill test process group ${proc.pid}: ${error.message}`);
    if (proc.exitCode === null) proc.kill('SIGKILL');
  }
}

// Each invocation owns its process group, including descendants holding its pipes.
export async function runTestProcess(label, command, { cwd, active = new Set(), env = {} }) {
  console.log(`Running ${label}`);
  const started = performance.now();
  let proc;
  try {
    proc = Bun.spawn(command, { cwd, env: { ...process.env, BEND_NO_TELEMETRY: '1', ...env }, stdout: 'pipe', stderr: 'pipe', detached: true });
    active.add(proc);
    // Drain both pipes immediately; descendants can keep them open after the parent exits.
    const stdout = collectTestOutput(proc.stdout, process.stdout);
    const stderr = collectTestOutput(proc.stderr, process.stderr);
    const exited = proc.exited.then(code => {
      terminateTestProcessGroup(proc);
      return code;
    });
    const [exitCode, out, err] = await Promise.all([exited, stdout, stderr]);
    return { exitCode, out, err, signal: proc.signalCode, pid: proc.pid };
  } finally {
    // DEFENSE: Bun.spawn can fail before allocating the owned subprocess; only terminate a process that was created.
    if (proc) {
      terminateTestProcessGroup(proc);
      active.delete(proc);
    }
    console.log(`Finished ${label} (${((performance.now() - started) / 1000).toFixed(2)}s).`);
  }
}

import { fileURLToPath } from 'node:url';
import { build } from './build.mjs';
import { runTestProcess, terminateTestProcessGroup } from './test-process.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

// Run the complete focused suite through Bun's standard sequential test runner.
export async function runTests() {
  const active = new Set();
  let interrupted = false;
  const handlers = ['SIGINT', 'SIGTERM'].map(signal => {
    const handler = () => {
      interrupted = true;
      process.exitCode = 1;
      for (const child of active) terminateTestProcessGroup(child);
    };
    process.on(signal, handler);
    return [signal, handler];
  });
  try {
    const result = await runTestProcess('focused physical regression suite',
      [process.execPath, 'test', '--timeout', '0', './tests-bend'], { cwd: root, active });
    const output = `${result.out}\n${result.err}`;
    const passes = [...output.matchAll(/^\s*(\d+) pass\s*$/gm)];
    const failures = [...output.matchAll(/^\s*(\d+) fail\s*$/gm)];
    const runs = [...output.matchAll(/^Ran (\d+) tests? across (\d+) files?\./gm)];
    const normal = passes.length === 1 && failures.length === 1 && runs.length === 1
      && Number(passes[0][1]) === Number(runs[0][1]) && Number(failures[0][1]) === 0
      && Number(runs[0][1]) > 0 && Number(runs[0][2]) > 0;
    if (interrupted || result.exitCode !== 0 || result.signal || !normal) {
      throw new Error(`Physical regression suite failed: exit=${result.exitCode}, signal=${result.signal ?? 'none'}, normalFooter=${normal}`);
    }
  } finally {
    for (const [signal, handler] of handlers) process.off(signal, handler);
    for (const child of active) terminateTestProcessGroup(child);
  }
}

if (import.meta.main) {
  await build();
  await runTests();
}

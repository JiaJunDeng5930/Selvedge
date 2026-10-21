import { readdir } from 'node:fs/promises';
import { build, root } from './build.mjs';
import { runTestProcess, terminateTestProcessGroup } from './test-process.mjs';
import { buildModel } from '../plugins/selvedge-chatgpt/scripts/build-model.mjs';
await build();
await buildModel();
const files = (await readdir(new URL('../tests/', import.meta.url))).filter(name => name.endsWith('.test.mjs')).sort();
const selected = process.argv.slice(2);
const tests = selected.length ? files.filter(name => selected.includes(name) || selected.includes(`tests/${name}`)) : files;
if (!tests.length) throw new Error('No end-to-end tests selected');
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
  const result = await runTestProcess('Selvedge end-to-end tests', [process.execPath, 'test', '--timeout', '30000', ...tests.map(name => `tests/${name}`)], { cwd: root, active });
  const output = `${result.out}\n${result.err}`;
  const passes = [...output.matchAll(/^\s*(\d+) pass\s*$/gm)];
  const failures = [...output.matchAll(/^\s*(\d+) fail\s*$/gm)];
  const runs = [...output.matchAll(/^Ran (\d+) tests? across (\d+) files?\./gm)];
  const complete = passes.length === 1 && failures.length === 1 && runs.length === 1
    && Number(passes[0][1]) === Number(runs[0][1]) && Number(failures[0][1]) === 0
    && Number(runs[0][1]) > 0 && Number(runs[0][2]) > 0;
  // DEFENSE: A test module can exit zero before running tests; require Bun's complete successful footer.
  if (interrupted || result.exitCode !== 0 || result.signal || !complete) {
    throw new Error(`End-to-end suite failed: exit=${result.exitCode}, signal=${result.signal ?? 'none'}, completeFooter=${complete}`);
  }
} finally {
  for (const [signal, handler] of handlers) process.off(signal, handler);
  for (const child of active) terminateTestProcessGroup(child);
}

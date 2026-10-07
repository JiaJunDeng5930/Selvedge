import { readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
if (process.argv.slice(2).some(arg => arg !== '--ci') || process.argv.length > 3) {
  console.error('Usage: bun scripts/test.mjs [--ci]');
  process.exit(1);
}
const ci = process.argv[2] === '--ci';
// NOTE: Repeated whole-program compiler mutations and extension builds belong to full validation.
const fullValidationOnly = new Set([
  'board-proof.test.mjs',
  'chatgpt-plugin-proof.test.mjs',
  'locality.test.mjs',
  'proof-gate.test.mjs',
  'reasoning-proof.test.mjs',
  'whole-program-proof.test.mjs',
]);
const files = (await readdir(new URL('../tests-bend/', import.meta.url)))
  .filter(name => name.endsWith('.test.mjs') && (!ci || !fullValidationOnly.has(name)))
  .sort().map(name => `tests-bend/${name}`);
console.log(`${ci ? 'CI integration' : 'Full validation'} suite: ${files.length} files; 2 isolated Bun processes${ci ? `; ${fullValidationOnly.size} full-validation files deferred` : ''}.`);

const active = new Set();
const records = [];
let next = 0;
let interrupted = null;

function terminate(proc) {
  try {
    process.kill(-proc.pid, 'SIGKILL');
  } catch (error) {
    if (error.code !== 'ESRCH') {
      console.error(`Could not kill process group ${proc.pid}: ${error.message}`);
    }
    if (proc.exitCode === null) proc.kill('SIGKILL');
  }
}
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    interrupted = signal;
    process.exitCode = 1;
    for (const proc of active) terminate(proc);
  });
}

async function runFile(file) {
  console.log(`Running ${file}`);
  let proc;
  let timer;
  let timedOut = false;
  try {
    proc = Bun.spawn([process.execPath, 'test', '--max-concurrency', '1', file], {
      cwd: root, env: process.env, stdout: 'pipe', stderr: 'pipe', detached: true,
    });
    active.add(proc);
    // NOTE: Drain both pipes immediately so a full pipe cannot block test completion.
    const stdout = new Response(proc.stdout).text();
    const stderr = new Response(proc.stderr).text();
    timer = setTimeout(() => {
      timedOut = true;
      terminate(proc);
    }, 900_000);
    const [exitCode, out, err] = await Promise.all([proc.exited, stdout, stderr]);
    if (out) process.stdout.write(out);
    if (err) process.stderr.write(err);
    const raw = `${out}\n${err}`;
    const pass = [...raw.matchAll(/^\s*(\d+) pass\s*$/gm)];
    const fail = [...raw.matchAll(/^\s*(\d+) fail\s*$/gm)];
    const ran = [...raw.matchAll(/^Ran (\d+) tests? across (\d+) files?\./gm)];
    const footer = pass.length === 1 && fail.length === 1 && ran.length === 1;
    const passed = footer ? Number(pass[0][1]) : 0;
    const failed = footer ? Number(fail[0][1]) : 0;
    const count = footer ? Number(ran[0][1]) : 0;
    const fileCount = footer ? Number(ran[0][2]) : 0;
    const signal = proc.signalCode;
    const success = exitCode === 0 && !signal && !timedOut && footer && failed === 0
      && fileCount === 1 && passed + failed === count;
    if (!success) console.error(`Failed ${file}: exit=${exitCode}, signal=${signal ?? 'none'}, timeout=${timedOut}, normalFooter=${footer}, pass=${passed}, fail=${failed}, tests=${count}, files=${fileCount}`);
    records.push({ file, success, passed, failed, count, fileCount });
  } catch (error) {
    if (proc) terminate(proc);
    console.error(`Failed ${file}: ${error.stack ?? error}`);
    records.push({ file, success: false, passed: 0, failed: 0, count: 0, fileCount: 0 });
  } finally {
    clearTimeout(timer);
    if (proc) active.delete(proc);
  }
}
async function worker() {
  while (!interrupted && next < files.length) {
    const file = files[next++];
    await runFile(file);
  }
}
await Promise.all([worker(), worker()]);
const sum = key => records.reduce((total, record) => total + record[key], 0);
const unsuccessful = records.filter(record => !record.success).length;
const incomplete = files.length - records.length;
console.log(`Total ${sum('passed')} pass, ${sum('failed')} fail; ${sum('count')} tests across ${sum('fileCount')} files; ${unsuccessful} unsuccessful files, ${incomplete} not completed${interrupted ? `; interrupted by ${interrupted}` : ''}.`);
if (unsuccessful || incomplete || interrupted) process.exitCode = 1;

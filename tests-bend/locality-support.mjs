import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';
import { bendSources } from '../scripts/check-components.mjs';
import { compiler } from '../scripts/toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const binary = compiler();
const environment = { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' };

export async function specimen(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-locality-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const originals = new Map();
  for (const filename of [...await bendSources(root), 'components.json', 'host/transport.c']) {
    const source = await readFile(path.join(root, filename));
    originals.set(filename, source);
    await mkdir(path.dirname(path.join(directory, filename)), { recursive: true });
    await cp(path.join(root, filename), path.join(directory, filename));
  }
  return { directory, originals };
}

export async function unchanged({ directory, originals }, allowed = []) {
  const exceptions = new Set(allowed);
  for (const [filename, source] of originals) {
    if (!exceptions.has(filename)) {
      assert.deepEqual(await readFile(path.join(directory, filename)), source, `Existing source must remain byte-identical: ${filename}`);
    }
  }
}

export function check(directory, entry = 'PROOF.bend') {
  return spawnSync(binary, [entry, '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 60_000,
    maxBuffer: 8 * 1024 * 1024, env: environment });
}

export function checked(result) {
  assert.equal(result.error, undefined, 'A timeout or execution error is not proof evidence');
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(result.stdout.trim(), 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.');
  assert.equal(result.stderr, '');
}

export function rejected(result, obligation) {
  assert.equal(result.error, undefined, 'A timeout or execution error is not semantic rejection');
  assert.notEqual(result.status, 0, 'The proof accepted the defect');
  assert.match(result.stdout + result.stderr, obligation);
}

export function replaceOnce(source, before, after) {
  assert.equal(source.split(before).length, 2, `Mutation or extension must identify exactly one source location: ${before}`);
  return source.replace(before, after);
}

export async function modify(directory, filename, operation) {
  const target = path.join(directory, filename);
  const source = await readFile(target, 'utf8');
  const changed = operation(source);
  assert.notEqual(changed, source, `Expected a real change to ${filename}`);
  await writeFile(target, changed);
}

export function replaceDefinition(source, name, definition) {
  const start = source.indexOf(`def ${name}(`);
  assert.notEqual(start, -1, `Missing definition ${name}`);
  const tail = source.slice(start + 1).search(/\n(?:def|type|law) /);
  const end = tail < 0 ? source.length : start + 1 + tail + 1;
  return source.slice(0, start) + definition.trimEnd() + '\n\n' + source.slice(end);
}

// Compilation includes the actual native backend, not just the Bend checker.
// Terminate the compiler's own process group on cancellation so a timed-out
// fixture cannot leave clang running after its temporary sources are removed.
export async function nativeBuild(directory, entry = 'MAIN.bend', { signal, timeout = 300_000 } = {}) {
  signal?.throwIfAborted();
  const executable = path.join(directory, 'locality-native');
  await new Promise((resolve, reject) => {
    const grouped = process.platform !== 'win32';
    const child = spawn(binary, [entry, '-o', executable], {
      cwd: directory, env: environment, detached: grouped, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let output = '', stderr = '', failure;
    const started = Date.now();
    const diagnostics = process.env.SELVEDGE_NATIVE_BUILD_DIAGNOSTICS === '1'
      ? setInterval(() => {
        // Report command names, not arguments: compiler diagnostics must not expose credentials.
        const sample = spawnSync('ps', ['-axo', 'pid,pgid,%cpu,rss,comm'], { encoding: 'utf8', timeout: 1000 });
        const rows = sample.stdout?.split('\n').filter(line => Number(line.trim().split(/\s+/)[1]) === child.pid);
        console.log(`Native compiler process group after ${Date.now() - started}ms:\n${rows?.join('\n') ?? ''}`);
      }, 30_000) : undefined;
    const stop = error => {
      failure ??= error;
      try {
        if (grouped && child.pid) process.kill(-child.pid, 'SIGKILL');
        else child.kill('SIGKILL');
      } catch (error) { if (error.code !== 'ESRCH') failure = error; }
    };
    const append = (chunk, isError = false) => {
      output += chunk;
      if (isError) stderr += chunk;
      if (output.length > 8 * 1024 * 1024) stop(new Error('Native compiler exceeded its diagnostic bound'));
    };
    child.stdout.on('data', chunk => append(chunk));
    child.stderr.on('data', chunk => append(chunk, true));
    child.once('error', error => { failure ??= error; });
    const timer = setTimeout(() => stop(new Error(`Native compilation timed out after ${timeout}ms; this is not proof evidence`)), timeout);
    const abort = () => stop(signal.reason ?? new Error('Native compilation cancelled'));
    signal?.addEventListener('abort', abort, { once: true });
    child.once('close', (code, exitSignal) => {
      clearTimeout(timer);
      clearInterval(diagnostics);
      signal?.removeEventListener('abort', abort);
      if (failure) reject(failure);
      else if (code !== 0 || stderr.trim() !== '') {
        reject(new Error(`Native compilation failed (${exitSignal ?? code}):\n${output}`));
      }
      else resolve();
    });
    if (signal?.aborted) abort();
  });
  return executable;
}

export async function nativeProbe(directory, source, expected = '1', options = {}) {
  await writeFile(path.join(directory, 'LOCALITY_NATIVE.bend'), source);
  checked(check(directory, 'LOCALITY_NATIVE.bend'));
  const executable = await nativeBuild(directory, 'LOCALITY_NATIVE.bend', options);
  const result = spawnSync(executable, [], { cwd: directory, encoding: 'utf8', timeout: 15_000, env: environment });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout.trim(), expected);
}

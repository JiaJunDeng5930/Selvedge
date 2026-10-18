import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
export const sourceVersion = '2.0.34';
export const sourceHash = 'bb673065b291b16ce814a808eeb7e4b9b173c02a02820b9f928f99f4d664e213';
const nodeVersion = '26.10.0';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
let preparation;

export async function prepareCompilerSource(runtime = 'node') {
  const provider = await (preparation ??= prepare());
  if (runtime === 'node') return provider;
  if (runtime !== 'bun') throw new Error('Unknown compiler runtime');
  return { directory: provider.directory, extension: 'ts', node: null, identity: provider.bunIdentity };
}

async function prepare() {
  if (!process.versions.bun) throw new Error('Compiler preparation requires Bun');
  if (readFileSync(path.join(root, 'bend-version'), 'utf8').trim() !== sourceVersion) {
    throw new Error('Compiler source version must match bend-version');
  }
  const archivePath = path.join(root, '.build/javascript-compiler.tar.gz');
  let archive;
  try { archive = await readFile(archivePath); } catch {}
  if (!archive || hash(archive) !== sourceHash) {
    const response = await fetch(`https://codeload.github.com/bendlang/bend/tar.gz/refs/tags/v${sourceVersion}`, { signal: AbortSignal.timeout(120_000) });
    if (!response.ok) throw new Error(`Compiler source download failed: HTTP ${response.status}`);
    archive = Buffer.from(await response.arrayBuffer());
    if (hash(archive) !== sourceHash) throw new Error('Compiler source checksum mismatch');
    await mkdir(path.dirname(archivePath), { recursive: true });
    const temporary = `${archivePath}.${randomUUID()}.tmp`;
    try { await writeFile(temporary, archive); await rename(temporary, archivePath); }
    finally { await rm(temporary, { force: true }); }
  }
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-bend-compiler-'));
  try {
    const result = spawnSync('tar', ['-xzf', '-', '-C', directory, '--strip-components=1'], { input: archive, encoding: 'utf8' });
    if (result.error || result.status !== 0) throw new Error(`Compiler extraction failed: ${result.error?.message ?? result.stderr}`);
    const node = findNode();
    if (!node) throw new Error(`Node ${nodeVersion} compiler runtime is required; run bun install --frozen-lockfile`);
    const extension = node ? 'mjs' : 'ts';
    const compilerDirectory = path.join(directory, 'bend2');
    const transpiler = new Bun.Transpiler({ loader: 'ts', target: 'node' });
    const adapter = createHash('sha256');
    const bunAdapter = createHash('sha256');
    for (const name of (await readdir(compilerDirectory)).sort()) {
      if (!name.endsWith('.ts')) continue;
      const source = await readFile(path.join(compilerDirectory, name), 'utf8');
      bunAdapter.update(name).update('\0').update(source).update('\0');
      if (name === 'main.ts') {
        const entry = source.lastIndexOf('if (import.meta.main)');
        if (entry < 0) throw new Error('Unrecognized pinned compiler CLI entry');
        const api = source.slice(0, entry) + '\nexport { book_promises, cli_verdict };\n';
        await writeFile(path.join(compilerDirectory, 'api.ts'), api);
        bunAdapter.update('api\0').update(api);
      }
      let code = node ? transpiler.transformSync(source)
        .replace(/from (["'])(\.\/[^"']+)\.ts\1/g, 'from $1$2.mjs$1') : source;
      if (name === 'main.ts') {
        const entry = node ? 'if (require.main == require.module)' : 'if (import.meta.main)';
        const index = code.lastIndexOf(entry);
        if (index < 0) throw new Error('Unrecognized pinned compiler CLI entry');
        const api = code.slice(0, index) + '\nexport { book_promises, cli_verdict };\n';
        await writeFile(path.join(compilerDirectory, `api.${extension}`), api);
        adapter.update('api\0').update(api);
        if (node) {
          code = code.replace(entry, 'if (import.meta.main)');
          const begin = code.indexOf('  if (typeof Bun === "undefined") {', index);
          const end = code.indexOf('  ua_fetch();', begin);
          if (begin < 0 || end < 0) throw new Error('Unrecognized pinned CLI runtime guard');
          code = code.slice(0, begin) + code.slice(end);
        }
      }
      if (node) await writeFile(path.join(compilerDirectory, name.replace(/\.ts$/, '.mjs')), code);
      adapter.update(name).update('\0').update(code).update('\0');
    }
    const runtimePath = await realpath(node ?? process.execPath);
    const identity = {
      version: sourceVersion, sourceSha256: sourceHash, adapterSha256: adapter.digest('hex'),
      runtime: { name: node ? 'node' : 'bun', version: node ? nodeVersion : process.versions.bun, sha256: hash(await readFile(runtimePath)) },
      transpiler: { name: 'bun', version: process.versions.bun, sha256: hash(await readFile(process.execPath)) },
    };
    const bunIdentity = { ...identity, adapterSha256: bunAdapter.digest('hex'), runtime: identity.transpiler };
    // Each controller owns its extraction. Parallel controllers cannot replace
    // a compiler or its standard library while another process is using it.
    process.once('exit', () => rmSync(directory, { recursive: true, force: true }));
    return { directory: compilerDirectory, extension, node: node ? runtimePath : null, identity, bunIdentity };
  } catch (error) {
    await rm(directory, { recursive: true, force: true });
    throw error;
  }
}

function findNode() {
  const candidates = [path.join(root, 'node_modules/node/bin/node'), Bun.which('node')];
  for (const candidate of new Set(candidates.filter(Boolean))) {
    if (!existsSync(candidate)) continue;
    const version = spawnSync(candidate, ['-p', 'process.versions.node'], { encoding: 'utf8', env: { ...process.env, NODE_OPTIONS: '' } });
    if (!version.error && version.status === 0 && version.stdout.trim() === nodeVersion) return candidate;
  }
  return null;
}

export function compilerWorkerCommand(provider, entry) {
  if (!provider.node) return [process.execPath, entry];
  const heap = Number(process.env.SELVEDGE_COMPILER_HEAP_MB ?? 6144);
  if (!Number.isInteger(heap) || heap < 256) throw new Error('Invalid compiler heap budget');
  return [provider.node, '--stack-size=4096', `--max-old-space-size=${heap}`, entry];
}

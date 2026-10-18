import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
export const sourceVersion = '2.0.34';
export const sourceHash = 'bb673065b291b16ce814a808eeb7e4b9b173c02a02820b9f928f99f4d664e213';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
let preparation;

export function prepareCompilerSource() {
  return preparation ??= prepare();
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
    const response = await fetch(`https://codeload.github.com/bendlang/bend/tar.gz/refs/tags/v${sourceVersion}`);
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
    const result = spawnSync('tar', ['-xzf', '-', '-C', directory, '--strip-components=1'], { input: archive, encoding: 'utf8', maxBuffer: Infinity });
    if (result.error || result.status !== 0) throw new Error(`Compiler extraction failed: ${result.error?.message ?? result.stderr}`);
    const compilerDirectory = path.join(directory, 'bend2');
    const adapter = createHash('sha256');
    for (const name of (await readdir(compilerDirectory)).sort()) {
      if (!name.endsWith('.ts')) continue;
      const source = await readFile(path.join(compilerDirectory, name), 'utf8');
      adapter.update(name).update('\0').update(source).update('\0');
      if (name === 'main.ts') {
        const entry = source.lastIndexOf('if (import.meta.main)');
        if (entry < 0) throw new Error('Unrecognized pinned compiler CLI entry');
        const api = source.slice(0, entry) + '\nexport { book_promises, cli_verdict };\n';
        await writeFile(path.join(compilerDirectory, 'api.ts'), api);
        adapter.update('api\0').update(api);
      }
    }
    const runtimePath = await realpath(process.execPath);
    const identity = {
      version: sourceVersion, sourceSha256: sourceHash, adapterSha256: adapter.digest('hex'),
      runtime: { name: 'bun', version: process.versions.bun, sha256: hash(await readFile(runtimePath)) },
    };
    // Each controller owns its extraction. Parallel controllers cannot replace
    // a compiler or its standard library while another process is using it.
    process.once('exit', () => rmSync(directory, { recursive: true, force: true }));
    return { directory: compilerDirectory, extension: 'ts', identity };
  } catch (error) {
    await rm(directory, { recursive: true, force: true });
    throw error;
  }
}

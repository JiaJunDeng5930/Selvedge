import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, writeFile, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { expectedVersion } from './toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const sourceVersion = '2.0.27';
const sourceHash = '0c763567dc08bd297906a0100df149fb211d936df627882f806fa88a98feff68';
const compilerDirectory = path.join(root, '.build/javascript-compiler');
const driver = fileURLToPath(import.meta.url);
let compilerPreparation;
const hash = value => createHash('sha256').update(value).digest('hex');

async function prepareCompiler() {
  if (expectedVersion !== sourceVersion) throw new Error('JavaScript compiler version must match bend-version');
  if (!process.versions.bun) throw new Error('JavaScript compilation requires Bun');
  let archive;
  try { archive = await readFile(`${compilerDirectory}.tar.gz`); } catch {}
  if (!archive || hash(archive) !== sourceHash) {
    const response = await fetch(`https://codeload.github.com/bendlang/bend/tar.gz/refs/tags/v${sourceVersion}`, { signal: AbortSignal.timeout(120000) });
    if (!response.ok) throw new Error(`JavaScript compiler download failed: HTTP ${response.status}`);
    archive = Buffer.from(await response.arrayBuffer());
    if (hash(archive) !== sourceHash) throw new Error('JavaScript compiler source checksum mismatch');
    await mkdir(path.dirname(compilerDirectory), { recursive: true });
    await writeFile(`${compilerDirectory}.tar.gz`, archive);
  }
  // Extract the verified archive each time so modified cache files cannot compile production code.
  const temporary = await mkdtemp(`${compilerDirectory}.new-`);
  try {
    const extraction = spawnSync('tar', ['-xzf', `${compilerDirectory}.tar.gz`, '-C', temporary, '--strip-components=1'], { encoding: 'utf8' });
    if (extraction.error || extraction.status !== 0) throw new Error(`JavaScript compiler extraction failed: ${extraction.error?.message ?? extraction.stderr}`);
    await rm(compilerDirectory, { recursive: true, force: true });
    await rename(temporary, compilerDirectory);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

// Separate compiler processes isolate upstream mutable compilation state and its stack budget.
export async function compileJavaScript({ entry, exports: publicExports, output }) {
  if (typeof entry !== 'string' || typeof output !== 'string' || !publicExports || Array.isArray(publicExports)) {
    throw new Error('JavaScript compilation requires entry, exports, and output');
  }
  const entries = Object.entries(publicExports).sort(([a], [b]) => a.localeCompare(b));
  if (entries.length === 0) throw new Error('JavaScript compilation requires at least one export');
  for (const [name, definition] of entries) {
    if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name) || name === 'default' || typeof definition !== 'string' || !definition) {
      throw new Error(`Invalid JavaScript compiler export: ${name}`);
    }
  }
  await (compilerPreparation ??= prepareCompiler());
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'selvedge-javascript-'));
  try {
    const request = path.join(temporary, 'request.json');
    const response = path.join(temporary, 'response.json');
    await writeFile(request, JSON.stringify({ entry: path.resolve(root, entry), exports: Object.fromEntries(entries), output: path.resolve(root, output), response }));
    const result = spawnSync(process.execPath, [driver, '--emit', request], {
      cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, env: { ...process.env, BEND_NO_TELEMETRY: '1' },
    });
    if (result.error || result.status !== 0) throw new Error(`JavaScript compilation failed: ${result.error?.message ?? result.stderr.trim() ?? result.status}`);
    return JSON.parse(await readFile(response, 'utf8'));
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

async function emit(requestPath) {
  if (!process.versions.bun) throw new Error('JavaScript compilation requires Bun');
  const request = JSON.parse(await readFile(requestPath, 'utf8'));
  const Bend = await import(pathToFileURL(path.join(compilerDirectory, 'bend2/bend.ts')).href);
  const Comp = await import(pathToFileURL(path.join(compilerDirectory, 'bend2/comp.ts')).href);
  try {
    const book = Bend.book_nil();
    const seen = new Map();
    await Bend.book_load(book, request.entry, '', seen);
    Bend.book_valid(book, 0);
    if (book.hols + book.open !== 0) throw new Error('JavaScript compilation refuses incomplete Bend definitions');
    const exports = Object.entries(request.exports);
    const roots = [...new Set(exports.map(([, definition]) => definition))];
    for (const definition of roots) {
      const value = book.tlds[definition];
      if (value?.$ !== 'Def' || value.v === null || value.i !== undefined || value.x !== 0 || Comp.io_base(book, value.T) !== null) {
        throw new Error(`JavaScript compilation requires a pure implemented definition: ${definition}`);
      }
    }
    const sources = await Promise.all([...seen.keys()].sort().map(async file => ({ path: path.relative(root, file), sha256: hash(await readFile(file)) })));
    const compiler = { version: sourceVersion, sourceSha256: sourceHash, driverSha256: hash(await readFile(driver)), runtime: { name: 'bun', version: process.versions.bun } };
    const fingerprint = hash(JSON.stringify({ entry: path.relative(root, request.entry), exports: request.exports, compiler, sources }));
    let previous;
    try { previous = JSON.parse(await readFile(`${request.output}.json`, 'utf8')); } catch {}
    if (previous?.fingerprint === fingerprint) {
      try {
        if (hash(await readFile(request.output)) === previous.outputSha256) {
          await writeFile(request.response, JSON.stringify({ output: request.output, fingerprint, cached: true }));
          return;
        }
      } catch {}
    }
    const library = Comp.js_lib(book, roots, roots);
    // v2.0.27 emits this table only when its reachable closure contains foreign effects.
    if (library.includes('const $0eff = {')) throw new Error('JavaScript compilation refuses reachable foreign effects');
    const marker = 'export default {\n';
    const index = library.lastIndexOf(marker);
    if (index < 0) throw new Error('JavaScript compiler did not produce an export object');
    const facade = exports.map(([name, definition], i) => `const $0public${i} = $0exports[${JSON.stringify(definition)}];\nexport { $0public${i} as ${name} };`).join('\n');
    const defaultExport = exports.map(([name], i) => `${JSON.stringify(name)}: $0public${i}`).join(', ');
    const result = `// Bend ${sourceVersion}; compiler source SHA256 ${sourceHash}\n// Source and compiler fingerprint: ${fingerprint}\n`
      + library.slice(0, index) + library.slice(index).replace(marker, 'const $0exports = {\n')
      + `\n${facade}\nexport default { ${defaultExport} };\n`;
    if (sources.some(source => path.resolve(root, source.path) === request.output)) throw new Error('JavaScript output cannot overwrite a compiler input');
    await mkdir(path.dirname(request.output), { recursive: true });
    const temporary = `${request.output}.${process.pid}.tmp`;
    try {
      await writeFile(temporary, result);
      await rename(temporary, request.output);
    } finally {
      await rm(temporary, { force: true });
    }
    await writeFile(`${request.output}.json`, JSON.stringify({ fingerprint, compiler, sources, exports: request.exports, outputSha256: hash(result) }, null, 2) + '\n');
    await writeFile(request.response, JSON.stringify({ output: request.output, fingerprint, cached: false }));
  } catch (error) {
    throw new Error(error?.$ === 'Err' ? Bend.err_show(error) : String(error));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv[2] !== '--emit' || !process.argv[3]) throw new Error('Use compileJavaScript({ entry, exports, output }) from this module');
    await emit(process.argv[3]);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

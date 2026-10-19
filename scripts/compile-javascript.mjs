import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, writeFile, rename, rm, realpath } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { prepareCompilerSource, sourceVersion, sourceHash } from './compiler-source.mjs';
import { optimizeJavaScript } from './optimize-javascript.mjs';
import { compilerEnvironment, compilerInvocation } from './toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const driver = fileURLToPath(import.meta.url);
const optimizer = fileURLToPath(new URL('./optimize-javascript.mjs', import.meta.url));
const parser = fileURLToPath(new URL(import.meta.resolve('acorn'), import.meta.url));
let compilerIdentity;
const hash = value => createHash('sha256').update(value).digest('hex');
let compilationQueue = Promise.resolve();

// Follow the pinned book_load's header imports, independently of the old manifest.
// Hub imports and unfamiliar syntax fall back to the compiler; never guess a closure.
async function currentSources(entry) {
  const files = new Map();
  const active = new Set();
  async function visit(filename) {
    const file = await realpath(filename);
    // DEFENSE: A source import cycle cannot supply a reusable cache closure; the compiler reports it.
    if (active.has(file)) return false;
    if (files.has(file)) return true;
    active.add(file);
    const bytes = await readFile(file);
    files.set(file, hash(bytes));
    for (const line of bytes.toString('utf8').split('\n')) {
      const text = line.trim();
      if (!text || text.startsWith('#')) continue;
      if (!/^import(\s|$)/.test(text)) break;
      const match = /^import\s+(\S+)(?:\s+as\s+([A-Za-z_]\w*))?\s*(?:#.*)?$/.exec(text);
      // DEFENSE: Compiler-supported import syntax outside this scanner must be compiled afresh.
      if (!match) return false;
      if (match[1] === 'Base' && !match[2]) {
        // Base belongs to the checksum-verified compiler archive, bound by compiler identity.
      } else if (match[2] && /^(?:\.\/|(?:\.\.\/)*)(?:[A-Za-z_][\w-]*\/)*[A-Za-z_][\w-]*\.bend$/.test(match[1])) {
        if (!await visit(path.resolve(path.dirname(file), match[1]))) return false;
      } else {
        // DEFENSE: Hub imports are resolved by the compiler rather than guessed by the cache scanner.
        return false;
      }
    }
    active.delete(file);
    return true;
  }
  try {
    for (const filename of Array.isArray(entry) ? entry : [entry]) if (!await visit(filename)) return null;
    return [...files].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
      .map(([file, sha256]) => ({ path: path.relative(root, file), sha256 }));
  } catch (error) {
    // DEFENSE: An imported file deleted between builds invalidates the cache; permission and I/O errors propagate.
    if (error.code !== 'ENOENT') throw error;
    return null;
  }
}

export function javascriptCompilerIdentity() {
  return compilerIdentity ??= (async () => ({
    ...(await prepareCompilerSource()).identity,
    driverSha256: hash(await readFile(driver)),
    optimizerSha256: hash(await readFile(optimizer)), parserSha256: hash(await readFile(parser)),
  }))();
}

async function compilationIdentity(request, sources) {
  const compiler = request.compilerIdentity ?? await javascriptCompilerIdentity();
  const fingerprint = hash(JSON.stringify({ entry: path.relative(root, request.entry), sourceRoot: request.sourceRoot, exports: request.exports, compiler, sources }));
  return { fingerprint, sourceRoot: request.sourceRoot, compiler, sources, exports: request.exports };
}

async function cachedCompilation(request, expectedPrefix) {
  let previous;
  try {
    previous = JSON.parse(await readFile(`${request.output}.json`, 'utf8'));
  } catch (error) {
    // DEFENSE: Initial builds and interrupted manifest writes have no reusable cache; other read errors propagate.
    if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) throw error;
    return null;
  }
  // DEFENSE: Cache files are editable disk inputs; a scalar JSON value cannot describe a compilation.
  if (!previous || typeof previous !== 'object' || Array.isArray(previous)) return null;
  // DEFENSE: A cached artifact checked under another prefix cannot establish this batch's checked identity.
  if (expectedPrefix !== undefined && previous.checkedPrefix !== expectedPrefix) return null;
  const inputs = compilationInputs(request, previous);
  // DEFENSE: Invalid cached prefix or joint-entry paths cannot establish this artifact's input closure.
  if (!inputs) return null;
  const sources = await currentSources(inputs);
  // DEFENSE: Deleted or scanner-unsupported source imports require compilation instead of cache reuse.
  if (!sources) return null;
  const identity = await compilationIdentity({ ...request, compilerIdentity: await javascriptCompilerIdentity() }, sources);
  // DEFENSE: Changed source, compiler, export or manifest identity must force fresh emission instead of reusing stale code.
  if (previous.reusable === true && previous.fingerprint === identity.fingerprint
      && ['sourceRoot', 'compiler', 'sources', 'exports'].every(key => JSON.stringify(previous[key]) === JSON.stringify(identity[key]))) {
    let output;
    // DEFENSE: Cache cleanup may remove an output independently of its manifest.
    try { output = await readFile(request.output); }
    catch (error) { if (error.code !== 'ENOENT') throw error; return null; }
    // DEFENSE: A truncated or edited generated module must be rebuilt even when its manifest still matches.
    if (hash(output) === previous.outputSha256) return { output: request.output, fingerprint: identity.fingerprint, cached: true };
  }
  return null;
}

function compilationInputs(request, { checkedPrefix, jointEntries } = {}) {
  const inputs = [request.entry];
  if (checkedPrefix !== undefined) {
    const prefix = prefixPath(request.sourceRoot, checkedPrefix);
    // DEFENSE: A cached checked prefix outside the source root cannot authorize reuse.
    if (!prefix) return null;
    inputs.push(prefix);
  }
  if (jointEntries !== undefined) {
    // DEFENSE: Editable cache metadata must describe a nonempty distinct batch checked under its prefix.
    if (checkedPrefix === undefined || !Array.isArray(jointEntries) || !jointEntries.length
        || new Set(jointEntries).size !== jointEntries.length) return null;
    const entries = jointEntries.map(entry => prefixPath(request.sourceRoot, entry));
    // DEFENSE: Damaged joint metadata must neither escape the source root nor omit the artifact's own input.
    if (entries.includes(null) || !entries.includes(request.entry)) return null;
    inputs.push(...entries);
  }
  return inputs;
}

function prefixPath(sourceRoot, relative) {
  // DEFENSE: Editable cache paths must stay within the declared source root and name Bend files.
  if (typeof relative !== 'string' || !relative.endsWith('.bend') || path.isAbsolute(relative)
      || relative.split(/[\\/]/).includes('..') || relative.includes('\0')) {
    return null;
  }
  return path.resolve(sourceRoot, relative);
}

// Separate compiler processes isolate upstream mutable compilation state.
export function compileJavaScript(request) {
  // Compiler jobs share the verified extraction and can exceed the machine's RAM.
  const result = compilationQueue.then(() => compileIsolated(request));
  // DEFENSE: A failed compile rejects its caller without poisoning later independent fixture compilations.
  compilationQueue = result.catch(() => {});
  return result;
}

// A prefix is checked afresh within this batch. Only that in-memory book is
// seeded into its entries; changed source roots still compile independently.
export function compileJavaScriptBatch({ prefix, requests, verify = false }) {
  const result = compilationQueue.then(() => compileBatch(prefix, requests, verify));
  // DEFENSE: A failed batch rejects its caller without poisoning later independent compilations.
  compilationQueue = result.catch(() => {});
  return result;
}

async function normalizedRequest({ entry, exports: publicExports, output, sourceRoot = root }) {
  const entries = Object.entries(publicExports).sort(([a], [b]) => a.localeCompare(b));
  const [canonicalEntry, canonicalSourceRoot] = await Promise.all([
    realpath(path.resolve(root, entry)), realpath(path.resolve(root, sourceRoot)),
  ]);
  return { entry: canonicalEntry, sourceRoot: canonicalSourceRoot, exports: Object.fromEntries(entries), output: path.resolve(root, output) };
}

async function compileBatch(prefix, requests, verify) {
  const provider = await prepareCompilerSource();
  const configurations = await Promise.all(requests.map(normalizedRequest));
  const sourceRoot = configurations[0].sourceRoot;
  const canonicalPrefix = await realpath(path.resolve(root, prefix));
  const relativePrefix = path.relative(sourceRoot, canonicalPrefix);
  const inputs = await currentSources([canonicalPrefix, ...configurations.map(request => request.entry)]);
  // DEFENSE: Source imports outside the local scanner subset cannot establish a checked shared-prefix cache identity.
  if (!inputs) throw new Error('A compilation batch requires discoverable local sources');
  const results = await Promise.all(configurations.map(request => cachedCompilation(request, relativePrefix)));
  const pending = configurations.filter((_, index) => !results[index]);
  if (!pending.length && !verify) return results;
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'selvedge-javascript-batch-'));
  try {
    const requestFile = path.join(temporary, 'request.json');
    const response = path.join(temporary, 'response.json');
    await writeFile(requestFile, JSON.stringify({ prefix: canonicalPrefix, sourceRoot, requests: pending, response, verify, provider, compilerIdentity: await javascriptCompilerIdentity() }));
    await runBatchProcess(requestFile, verify);
    const emitted = JSON.parse(await readFile(response, 'utf8'));
    // DEFENSE: Source files can change while the compiler or proof gate is running; never publish an artifact under the earlier source identity.
    if (JSON.stringify(await currentSources([canonicalPrefix, ...configurations.map(request => request.entry)])) !== JSON.stringify(inputs)) {
      throw new Error('Compilation batch inputs changed; retry with stable sources');
    }
    let index = 0;
    return results.map(result => result ?? emitted[index++]);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

async function runBatchProcess(requestFile, verify) {
  await new Promise((resolve, reject) => {
    const invocation = compilerInvocation(process.execPath, ['--smol', driver, '--emit-batch', requestFile]);
    const child = spawn(invocation.command, invocation.args, {
      cwd: root, stdio: ['ignore', 'pipe', 'pipe'], env: { ...compilerEnvironment(), BUN_JSC_miniVMHeapGrowthFactor: '1.1', BEND_NO_TELEMETRY: '1' },
    });
    let diagnostic = '', failure;
    const stop = error => { failure ??= error; child.kill('SIGKILL'); };
    let proofReport = '';
    let prefixChecked = !verify;
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', text => {
      process.stdout.write(text);
      if (!prefixChecked) {
        proofReport += text;
        if (proofReport.includes('Compilation prefix checked (')) {
          // DEFENSE: The compiler can emit an unsafe or failed proof verdict before its completion marker.
          if (proofReport.slice(0, proofReport.indexOf('Compilation prefix checked (')) !== 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.\n') {
            stop(new Error('Pure proof gate emitted an unexpected verdict'));
          } else { prefixChecked = true; }
        }
      }
    });
    child.stderr.on('data', text => {
      diagnostic += text;
    });
    child.on('error', error => { failure ??= error; });
    child.on('close', (status, signal) => {
      // DEFENSE: Spawn errors, failed or signalled compiles, missing proof verdicts and compiler diagnostics must fail this batch.
      if (failure) reject(failure);
      else if (status !== 0 || !prefixChecked || diagnostic.trim()) reject(new Error(`JavaScript batch compilation failed (status: ${status}, signal: ${signal}): ${diagnostic.trim()}`));
      else resolve();
    });
  });
}

async function compileIsolated(options) {
  const provider = await prepareCompilerSource();
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'selvedge-javascript-'));
  try {
    const request = path.join(temporary, 'request.json');
    const response = path.join(temporary, 'response.json');
    const configuration = { ...await normalizedRequest(options), response, provider, compilerIdentity: await javascriptCompilerIdentity() };
    const cached = await cachedCompilation(configuration);
    if (cached) return cached;
    await writeFile(request, JSON.stringify(configuration));
    const invocation = compilerInvocation(process.execPath, ['--smol', driver, '--emit', request]);
    const result = spawnSync(invocation.command, invocation.args, {
      cwd: root, encoding: 'utf8', maxBuffer: Infinity,
      env: { ...compilerEnvironment(), BUN_JSC_miniVMHeapGrowthFactor: '1.1', BEND_NO_TELEMETRY: '1' },
    });
    // DEFENSE: The compiler subprocess can fail to start, exit unsuccessfully or be terminated before returning an artifact.
    if (result.error || result.status !== 0) {
      const diagnostic = result.error?.message || result.stderr.trim() || result.stdout.trim() || 'No compiler diagnostic was emitted';
      throw new Error(`JavaScript compilation failed (status: ${result.status ?? 'none'}, signal: ${result.signal ?? 'none'}): ${diagnostic}`);
    }
    return JSON.parse(await readFile(response, 'utf8'));
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

async function emit(requestPath) {
  const request = JSON.parse(await readFile(requestPath, 'utf8'));
  const Bend = await import(pathToFileURL(path.join(request.provider.directory, `bend.${request.provider.extension}`)).href);
  const Comp = await import(pathToFileURL(path.join(request.provider.directory, `comp.${request.provider.extension}`)).href);
  try {
    const before = await currentSources(request.entry);
    const book = Bend.book_nil();
    const seen = new Map();
    // Shared constructors need the same source namespace across independently compiled entries.
    await Bend.book_load(book, request.entry, '', seen, undefined, request.sourceRoot);
    await checkPureRuntimeBook(book, 0, Bend, request.provider);
    const result = await emitBook(request, book, seen, before, Bend, Comp);
    await writeFile(request.response, JSON.stringify(result));
  } catch (error) {
    // DEFENSE: The upstream compiler throws tagged Bend errors rather than JavaScript Error objects.
    if (error?.$ === 'Err') throw new Error(Bend.err_show(error));
    throw error;
  }
}

async function checkPureRuntimeBook(book, offset, Bend, provider) {
  Bend.book_valid(book, offset);
  // DEFENSE: An edited runtime entry can introduce an unfilled law or TODO outside the verified prefix; incomplete books cannot authorize emission.
  if (book.hols !== 0) throw new Error('JavaScript compilation refuses incomplete Bend definitions');
  // Use the compiler's dependency graph, including types and constructor fields.
  const { book_promises } = await import(pathToFileURL(path.join(provider.directory, `api.${provider.extension}`)).href);
  const promises = book_promises(book);
  // DEFENSE: A reproduced runtime-entry dependency marked @unsafe passed book_valid outside the checked prefix; reject its transitive promise before emission.
  if (promises.length) {
    throw new Error(`JavaScript compilation refuses unchecked or foreign definitions: ${promises.join(', ')}`);
  }
}

async function emitBook(request, book, seen, before, Bend, Comp, checkedPrefix, generated) {
  const jointEntries = generated?.jointEntries;
  const inputs = compilationInputs(request, { checkedPrefix, jointEntries });
  const exports = Object.entries(request.exports);
  const roots = [...new Set(generated ? Object.values(generated.definitions) : exports.map(([, definition]) => definition))];
  for (const definition of roots) {
    const value = book.tlds[definition];
    // DEFENSE: A requested export read from Bend source can be absent, a promise, unsafe or effectful instead of a pure implementation.
    if (value?.$ !== 'Def' || value.v === null || value.i !== undefined || value.b === true || value.x !== 0 || Comp.io_base(book, value.T) !== null) {
      throw new Error(`JavaScript compilation requires a pure implemented definition: ${definition}`);
    }
  }
  const sources = await Promise.all([...seen.keys()].filter(file => file !== Bend.BASE_BEND).sort().map(async file => ({ path: path.relative(root, file), sha256: hash(await readFile(file)) })));
  const identity = await compilationIdentity(request, sources);
  const { fingerprint } = identity;
  const reusable = before !== null && JSON.stringify(before) === JSON.stringify(sources);
  // DEFENSE: Source files can change while the compiler or proof gate is running; never publish an artifact under the earlier source identity.
  if (before !== null && !reusable) {
    throw new Error('JavaScript compiler input closure changed during compilation; retry with stable sources');
  }
  const library = Comp.js_lib({ ...book, order: roots }, true);
  // The pinned emitter adds this registration check only for reachable foreign effects.
  // DEFENSE: A reachable generated function can retain a foreign effect despite the pure export contract.
  if (library.includes('throw new Error("bend: no effect registers "')) throw new Error('JavaScript compilation refuses reachable foreign effects');
  const { source: optimized, intrinsics } = optimizeJavaScript(library, {
    sourceHashes: new Map([...sources.map(source => [path.resolve(root, source.path), source.sha256]),
      [Bend.BASE_BEND, hash(await readFile(Bend.BASE_BEND))]]),
    sourceRoot: request.sourceRoot, basePath: Bend.BASE_BEND,
  });
  const marker = 'export default {\n';
  const index = optimized.lastIndexOf(marker);
  // DEFENSE: Compiler output without the pinned export object cannot be given the requested JavaScript facade.
  if (index < 0) throw new Error('JavaScript compiler did not produce an export object');
  const facade = exports.map(([name, definition], i) => `const $0public${i} = $0exports[${JSON.stringify(generated?.definitions[definition] ?? definition)}];\nexport { $0public${i} as ${name} };`).join('\n');
  const defaultExport = exports.map(([name], i) => `${JSON.stringify(name)}: $0public${i}`).join(', ');
  const result = `// Bend ${sourceVersion}; compiler source SHA256 ${sourceHash}\n// Source and compiler fingerprint: ${fingerprint}\n`
    + optimized.slice(0, index) + optimized.slice(index).replace(marker, 'const $0exports = {\n')
    + `\n${facade}\nexport default { ${defaultExport} };\n`;
  // DEFENSE: Source files can change while the compiler or proof gate is running; never publish an artifact under the earlier source identity.
  if (reusable && JSON.stringify(await currentSources(inputs)) !== JSON.stringify(before)) {
    throw new Error('JavaScript compiler inputs changed during compilation; retry with stable sources');
  }
  await mkdir(path.dirname(request.output), { recursive: true });
  const temporary = `${request.output}.${process.pid}.tmp`;
  try {
    await writeFile(temporary, result);
    await rename(temporary, request.output);
  } finally {
    await rm(temporary, { force: true });
  }
  await writeFile(`${request.output}.json`, JSON.stringify({ ...identity, reusable, ...(checkedPrefix === undefined ? {} : { checkedPrefix }), ...(jointEntries === undefined ? {} : { jointEntries }), intrinsics, outputSha256: hash(result) }, null, 2) + '\n');
  return { output: request.output, fingerprint, cached: false };
}

function seedBook(Bend, original) {
  const book = Bend.book_nil();
  for (const [name, value] of Object.entries(original.tlds)) book.tlds[name] = { ...value };
  Object.assign(book.ctrs, original.ctrs);
  for (const [name, instances] of Object.entries(original.tmps)) book.tmps[name] = { ...instances };
  book.order.push(...original.order);
  return book;
}

async function jointBook(batch, seed, seen, Bend) {
  if (batch.requests.length < 2) return null;
  const book = seedBook(Bend, seed), ownSeen = new Map(seen);
  const entries = [];
  for (const request of batch.requests) {
    const namespace = ownSeen.get(request.entry)
      ?? path.relative(batch.sourceRoot, request.entry).slice(0, -5).split(path.sep).join('/');
    const previous = new Set(book.order);
    const done = book.order.length;
    await Bend.book_load(book, request.entry, namespace, ownSeen, undefined, batch.sourceRoot);
    // DEFENSE: Entry-local constructors and colliding definitions require independent emission; qualifying their tags would change public values consumed across modules.
    if (book.order.slice(done).some(name => previous.has(name))
        || Object.entries(book.tlds).some(([name, value]) => name.startsWith(`${namespace}.`) && value.$ === 'ADT')) return null;
    const definitions = Object.fromEntries(Object.values(request.exports).map(name =>
      [name, namespace && book.tlds[`${namespace}.${name}`] ? `${namespace}.${name}` : name]));
    entries.push({ request: { ...request, compilerIdentity: batch.compilerIdentity }, definitions });
  }
  await checkPureRuntimeBook(book, seed.order.length, Bend, batch.provider);
  return { book, seen: ownSeen, entries };
}

async function emitBatch(requestPath) {
  const batch = JSON.parse(await readFile(requestPath, 'utf8'));
  const Bend = await import(pathToFileURL(path.join(batch.provider.directory, `bend.${batch.provider.extension}`)).href);
  const Comp = await import(pathToFileURL(path.join(batch.provider.directory, `comp.${batch.provider.extension}`)).href);
  try {
    const beforePrefix = await currentSources(batch.prefix);
    // DEFENSE: Source imports outside the local scanner subset cannot establish a checked shared-prefix cache identity.
    if (!beforePrefix) throw new Error('A compilation prefix requires discoverable local sources');
    const prefixHashes = new Map(beforePrefix.map(source => [source.path, source.sha256]));
    const seed = Bend.book_nil(), seen = new Map();
    const started = performance.now();
    const namespace = path.relative(batch.sourceRoot, batch.prefix).slice(0, -5).split(path.sep).join('/');
    await Bend.book_load(seed, batch.prefix, namespace, seen, undefined, batch.sourceRoot);
    Bend.book_valid(seed, 0);
    // DEFENSE: Edited Bend inputs can contain holes; the generated runtime must not treat incomplete definitions as checked code.
    if (seed.hols !== 0) throw new Error('JavaScript compilation refuses an incomplete prefix');
    if (batch.verify) {
      const { cli_verdict } = await import(pathToFileURL(path.join(batch.provider.directory, `api.${batch.provider.extension}`)).href);
      // DEFENSE: The compiler can report unsafe assumptions, holes or failed proofs; only the complete pure verdict authorizes production emission.
      if (cli_verdict(seed, false) !== 0) throw new Error('Pure proof gate rejected the compilation prefix');
    }
    // DEFENSE: Source files can change while the compiler or proof gate is running; never publish an artifact under the earlier source identity.
    if (JSON.stringify(await currentSources(batch.prefix)) !== JSON.stringify(beforePrefix)) {
      throw new Error('Proof prefix changed during checking; retry with stable sources');
    }
    console.log(`Compilation prefix checked (${((performance.now() - started) / 1000).toFixed(2)}s).`);
    const checkedPrefix = path.relative(batch.sourceRoot, batch.prefix);
    const jointStarted = performance.now();
    const beforeJoint = await currentSources([batch.prefix, ...batch.requests.map(request => request.entry)]);
    const joint = await jointBook(batch, seed, seen, Bend);
    if (joint) {
      const jointEntries = [...new Set(batch.requests.map(request => path.relative(batch.sourceRoot, request.entry)))];
      const before = beforeJoint;
      // DEFENSE: Source files can change while the compiler or proof gate is running; never publish an artifact under the earlier source identity.
      if (!before || before.some(source => prefixHashes.has(source.path) && prefixHashes.get(source.path) !== source.sha256)
          || beforePrefix.some(source => !before.some(current => current.path === source.path && current.sha256 === source.sha256))) {
        throw new Error('Compilation prefix changed after checking; retry with stable sources');
      }
      console.log(`Joint JavaScript entry checking (${((performance.now() - jointStarted) / 1000).toFixed(2)}s).`);
      const results = [];
      for (const { request, definitions } of joint.entries) {
        const started = performance.now();
        // The official backend constructs one closed module from its own roots.
        // Emitting the union retained too much compiler IR at once and hit OOM.
        results.push(await emitBook(request, joint.book, joint.seen, before, Bend, Comp, checkedPrefix,
          { definitions, jointEntries }));
        console.log(`Shared-book JavaScript emission: ${path.relative(root, request.output)} (${((performance.now() - started) / 1000).toFixed(2)}s).`);
      }
      await writeFile(batch.response, JSON.stringify(results));
      return;
    }
    const results = [];
    for (const configuration of batch.requests) {
      const request = { ...configuration, compilerIdentity: batch.compilerIdentity };
      const started = performance.now();
      const before = await currentSources([batch.prefix, request.entry]);
      // DEFENSE: Source files can change while the compiler or proof gate is running; never publish an artifact under the earlier source identity.
      if (!before || before.some(source => prefixHashes.has(source.path) && prefixHashes.get(source.path) !== source.sha256)
          || beforePrefix.some(source => !before.some(current => current.path === source.path && current.sha256 === source.sha256))) {
        throw new Error('Compilation prefix changed after checking; retry with stable sources');
      }
      const book = seedBook(Bend, seed), ownSeen = new Map(seen);
      await Bend.book_load(book, request.entry, '', ownSeen, undefined, request.sourceRoot);
      await checkPureRuntimeBook(book, seed.order.length, Bend, batch.provider);
      results.push(await emitBook(request, book, ownSeen, before, Bend, Comp, checkedPrefix));
      console.log(`Shared-prefix JavaScript compilation: ${path.relative(root, request.output)} (${((performance.now() - started) / 1000).toFixed(2)}s).`);
    }
    await writeFile(batch.response, JSON.stringify(results));
  } catch (error) {
    // DEFENSE: The upstream compiler throws tagged Bend errors rather than JavaScript Error objects.
    if (error?.$ === 'Err') throw new Error(Bend.err_show(error));
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    // DEFENSE: A command-line caller can pass unsupported arguments; reject the invocation before running the build operation.
    if (!['--emit', '--emit-batch'].includes(process.argv[2]) || !process.argv[3]) throw new Error('Use compileJavaScript({ entry, exports, output }) from this module');
    if (process.argv[2] === '--emit-batch') await emitBatch(process.argv[3]);
    else await emit(process.argv[3]);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

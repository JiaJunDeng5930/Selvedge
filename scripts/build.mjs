import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile, readdir, stat, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { root, run, targets, jsonEntries } from './build-tools.mjs';
import { auditAssumptions } from './assumptions.mjs';
import { generateModelSchema } from './generate-model-schema.mjs';
import { productionFlags as flags, compilationFlags, dependencyFlags, moduleFile, sourceFiles } from './rocq-sources.mjs';
export { root, run, targets, jsonEntries } from './build-tools.mjs';

const buildDirectory = path.join(root, '.build');
const digest = value => createHash('sha256').update(value).digest('hex');
const stateFile = path.join(buildDirectory, 'build-state.json');
const productionTargets = ['schema', 'kernel', 'host', 'browser', 'interaction'];
export async function compilerVersions() {
  return Promise.all([
    run('rocq', ['--version']), run('ocamlc', ['-version']), run('js_of_ocaml', ['--version']),
    run('opam', ['var', 'rocq-metarocq-template:version']),
    run('ocamlfind', ['query', '-format', '%v', 'zarith']), run('bun', ['--version'])
  ]);
}
const exists = filename => stat(path.join(root, filename)).then(() => true, error => {
  // DEFENSE: A missing build artifact requires compilation; other filesystem errors are real failures.
  if (error.code === 'ENOENT') return false;
  throw error;
});
async function fingerprint(filename) {
  return await exists(filename) ? digest(await readFile(path.join(root, filename))) : null;
}
let nextTemporary = 0;
async function writeChanged(filename, value) {
  const previous = await exists(filename) ? await readFile(path.join(root, filename), 'utf8') : null;
  if (previous !== value) {
    await mkdir(path.dirname(path.join(root, filename)), { recursive: true });
    const temporary = `${path.join(root, filename)}.${process.pid}.${nextTemporary++}.tmp`;
    try {
      await writeFile(temporary, value);
      await rename(temporary, path.join(root, filename));
    } finally {
      await rm(temporary, { force: true });
    }
  }
}
async function dependencies(files, recursive, readInput) {
  const graph = new Map();
  let pending = files;
  while (pending.length) {
    await Promise.all(pending.map(readInput));
    const output = await run('coqdep', [...dependencyFlags, ...pending]);
    for (const line of output.split('\n')) {
      const [left, right] = line.split(':');
      if (!left?.includes('.vo ') && !left?.endsWith('.vo')) continue;
      const target = left.split(/\s+/).find(value => value.endsWith('.vo'));
      if (!target) continue;
      const filename = target.slice(0, -1);
      graph.set(filename, (right ?? '').trim().split(/\s+/).filter(value => value.endsWith('.vo')).map(value => value.slice(0, -1)));
    }
    pending = recursive ? [...new Set([...graph.values()].flat().filter(file => !graph.has(file)))] : [];
  }
  return graph;
}

// Module checks and extraction have separate limits because their memory profiles differ.
function limitConcurrency(limit) {
  let active = 0;
  const queue = [];
  return async action => {
    if (active >= limit) await new Promise(resolve => queue.push(resolve));
    else active++;
    try { return await action(); }
    finally {
      const resume = queue.shift();
      if (resume) resume(); else active--;
    }
  };
}

async function settleIndependent(actions, description) {
  const results = await Promise.allSettled(actions);
  const errors = [...new Set(results.filter(result => result.status === 'rejected').map(result => result.reason))];
  // DEFENSE: Independent compiler jobs can fail together; finish them all before reporting their distinct failures.
  if (errors.length) throw new AggregateError(errors, `${description}: ${errors.length} independent failure(s)`);
}

export async function build(options = {}) {
  const { modules = [], check = false } = options;
  const selected = [...new Set(options.selected ?? (modules.length ? [] : productionTargets))];
  const allModules = !modules.length && (check || options.selected === undefined);
  const moduleFiles = modules.map(name => {
    if (!/^[A-Za-z_][A-Za-z_0-9']*(?:\.[A-Za-z_][A-Za-z_0-9']*)*$/.test(name)) throw new Error(`Invalid Rocq module: ${name}`);
    return moduleFile(name);
  });
  const roots = [...selected.map(name => {
    if (!targets[name]) throw new Error(`Unknown build target: ${name}`);
    return `theories/${targets[name].module.replaceAll('.', '/')}.v`;
  }), ...moduleFiles, ...(selected.length ? ['theories/Foundation/TextJson.v'] : [])];
  await mkdir(buildDirectory, { recursive: true });
  for (const filename of moduleFiles) if (!await exists(filename)) throw new Error(`Requested Rocq module is missing: ${filename}`);
  for (const name of selected) {
    if (!targets[name]) throw new Error(`Unknown build target: ${name}`);
    const filename = `theories/${targets[name].module.replaceAll('.', '/')}.v`;
    if (name !== 'commands' && !await exists(filename)) {
      throw new Error(`Production entry ${filename} is missing; the full migration build is incomplete`);
    }
  }
  const versions = await compilerVersions();
  const inputFingerprints = new Map();
  let inputsStable = true;
  let checkedSourceFiles = null;
  async function readInput(filename) {
    const bytes = await readFile(path.join(root, filename));
    const actual = digest(bytes);
    const previous = inputFingerprints.get(filename);
    if (previous !== undefined && previous !== actual) {
      inputsStable = false;
      throw new Error(`Build input changed during compilation: ${filename}`);
    }
    inputFingerprints.set(filename, actual);
    return bytes;
  }
  async function assertInputsUnchanged() {
    if (!inputsStable) return;
    const changed = (await Promise.all([...inputFingerprints].map(async ([filename, expected]) => {
      let actual;
      try {
        actual = digest(await readFile(path.join(root, filename)));
      } catch (error) {
        // DEFENSE: A source or runtime input can be removed while Rocq or extraction is using the captured build inputs.
        if (error.code === 'ENOENT') actual = null;
        else throw error;
      }
      return actual === expected ? null : filename;
    }))).find(Boolean);
    if (changed) {
      inputsStable = false;
      throw new Error(`Build input changed during Rocq checking or extraction: ${changed}; retry with stable sources`);
    }
    if (allModules && checkedSourceFiles) {
      const current = (await sourceFiles()).filter(file => !file.startsWith('theories/Derive/'));
      if (JSON.stringify(current) !== JSON.stringify(checkedSourceFiles)) {
        inputsStable = false;
        throw new Error('Rocq source file set changed during the full build; retry with stable sources');
      }
    }
  }
  const pins = JSON.parse((await readInput('toolchain.json')).toString('utf8'));
  // DEFENSE: The public build can be launched with Bun below its declared minimum.
  if (!Bun.semver.satisfies(versions[5].trim(), `>=${pins.bun}`)) {
    throw new Error(`Bun ${pins.bun} or later is required by toolchain.json`);
  }
  if (!versions[0].includes(`version ${pins.rocq}`) || versions[1].trim() !== pins.ocaml || versions[2].trim() !== pins.js_of_ocaml
      || versions[3].trim() !== pins['metarocq-template'] || versions[4].trim() !== pins.zarith) {
    throw new Error('Toolchain does not match toolchain.json; run scripts/bootstrap.sh');
  }
  const stubsDirectory = '.build/deps/zarith_stubs_js';
  for (const [name, expected] of Object.entries(pins.zarith_stubs_js_sha256)) {
    const filename = `${stubsDirectory}/${name}`;
    if (!await exists(filename)) throw new Error('Pinned Zarith JS runtime is missing; run scripts/bootstrap.sh');
    if (digest(await readInput(filename)) !== expected) throw new Error(`Zarith JS runtime checksum mismatch: ${filename}`);
  }
  const identity = digest(JSON.stringify([versions[0], flags]));
  const buildScript = await readInput(path.relative(root, fileURLToPath(import.meta.url)));
  const extraction = await readInput('runtime/Extraction.v');
  const buildTools = await readInput('scripts/build-tools.mjs');
  const sourceLayout = await readInput('scripts/rocq-sources.mjs');
  const assumptionAudit = await readInput('scripts/assumptions.mjs');
  if (selected.includes('schema')) await readInput('scripts/generate-model-schema.mjs');
  const extractionIdentity = digest(JSON.stringify([identity, versions.slice(1), pins, buildScript, buildTools, sourceLayout, assumptionAudit, extraction]));
  const state = await exists('.build/build-state.json') ? JSON.parse(await readFile(stateFile, 'utf8')) : {};
  const next = {};
  let compiled = 0;
  const pending = new Map();
  async function persistState() {
    const temporary = `${stateFile}.${process.pid}.tmp`;
    await writeFile(temporary, `${JSON.stringify({ ...state, ...next }, null, 2)}\n`);
    await rename(temporary, stateFile);
  }
  const publicationDirectory = selected.length ? await mkdtemp(path.join(buildDirectory, 'publication-')) : null;
  const publications = new Map();
  try {
    const graphInputs = async () => {
      if (allModules) {
        checkedSourceFiles = (await sourceFiles()).filter(file => !file.startsWith('theories/Derive/'));
        return checkedSourceFiles;
      }
      return (await Promise.all(roots.map(async file => await exists(file) ? file : null))).filter(Boolean);
    };
    let graph = await dependencies(await graphInputs(), !allModules, readInput);
    const withModuleSlot = limitConcurrency(4);
    async function compile(filename) {
      if (pending.has(filename)) return pending.get(filename);
      const promise = (async () => {
        const imported = graph.get(filename) ?? [];
        await Promise.all(imported.map(compile));
        const source = (await readInput(filename)).toString('utf8');
        // Rocq records imported object identities, including objects rebuilt outside this cache.
        const moduleIdentity = digest(JSON.stringify([versions[0], compilationFlags(filename)]));
        const key = digest(JSON.stringify([moduleIdentity, source, imported.map(file => [
          next[file], next[`artifact:${file.slice(0, -1)}vo`]
        ])]));
        const artifact = filename.slice(0, -1) + 'vo';
        const actual = await fingerprint(artifact);
        // DEFENSE: A direct rocq compilation followed by restoring the source can leave a different .vo behind the cached source key.
        if (state[filename] !== key || actual === null || state[`artifact:${artifact}`] !== actual) {
          await withModuleSlot(() => run('rocq', ['c', ...compilationFlags(filename), filename]));
          compiled++;
        }
        next[filename] = key;
        next[`artifact:${artifact}`] = await fingerprint(artifact);
      })();
      pending.set(filename, promise);
      return promise;
    }

    const reachable = new Set();
    const requested = [...roots];
    while (requested.length) {
      const filename = requested.pop();
      if (reachable.has(filename)) continue;
      reachable.add(filename);
      requested.push(...(graph.get(filename) ?? []));
    }
    if (allModules || reachable.has('theories/Generated/Commands.v')) {
      const generatorDependencies = ['theories/Kernel/CommandDeclarations.v', 'theories/Foundation/ArgumentProjection.v'];
      await settleIndependent(generatorDependencies.map(compile), 'Command generator dependencies failed');
      const generator = 'theories/Derive/Commands.v';
      const generatorSource = (await readInput(generator)).toString('utf8');
      const generatorKey = digest(JSON.stringify([identity, versions[3].trim(), generatorSource, generatorDependencies.map(filename => next[filename])]));
      const generatedPath = 'theories/Generated/Commands.v';
      const generatedCurrent = await fingerprint(generatedPath);
      if (check || state.generator !== generatorKey || generatedCurrent !== state.generatedSource) {
        const output = await run('rocq', ['c', ...flags, generator]);
        const match = /SELVDERIVE_BEGIN\r?\n([\s\S]*?)SELVDERIVE_END/.exec(output);
        if (!match) throw new Error('MetaRocq command generator did not produce its delimited source');
        const generated = `(* Generated by MetaRocq from Kernel.Commands.command_specs. Do not edit. *)\n${match[1].trimEnd()}\n`;
        if (check && generatedCurrent && generatedCurrent !== digest(generated)) throw new Error('Generated command source is stale; run bun run build');
        await writeChanged(generatedPath, generated);
        inputFingerprints.set(generatedPath, digest(generated));
      }
      next.generator = generatorKey;
      next.generatedSource = await fingerprint(generatedPath);
      graph = await dependencies(await graphInputs(), !allModules, readInput);
    }
    if (selected.length) await compile('theories/Foundation/TextJson.v');
    const requestedChecks = (allModules ? [...graph.keys()] : roots).map(compile);
    await settleIndependent([...requestedChecks, ...pending.values()], 'Rocq checking failed');

    if (selected.length || roots.some(filename => filename.startsWith('requirements/'))) {
      await auditAssumptions({ sources: [...graph.keys()], entries: [
        ...(allModules ? Object.values(targets) : selected.map(name => targets[name]))
          .flatMap(target => target.entry.map(entry => `${target.module}.${entry}`)),
        ...(selected.length ? Object.values(jsonEntries) : [])
      ] });
    }
    await assertInputsUnchanged();
    await persistState();

    const withTargetSlot = limitConcurrency(2);
    await settleIndependent(selected.map(name => withTargetSlot(async () => {
      const target = targets[name];
      const filename = `theories/${target.module.replaceAll('.', '/')}.v`;
      const runtime = name === 'commands' ? (await readInput('runtime/commands_runtime.ml')).toString('utf8')
        : name === 'kernel' ? (await readInput('runtime/kernel_runtime.ml')).toString('utf8')
        : (await readInput('runtime/call_runtime.ml.in')).toString('utf8').replaceAll('@MODEL@', target.model).replaceAll('@GLOBAL@', target.global).replaceAll('@ENTRY@', `selvedge_${name}_call`);
      const jsonIo = (await readInput('runtime/json_io.ml')).toString('utf8');
      const key = digest(JSON.stringify([extractionIdentity, next[filename], next['theories/Foundation/TextJson.v'], runtime, jsonIo]));
      const output = `.build/${name}-model.mjs`;
      const actual = [await fingerprint(output)];
      const expected = state[`target:${name}:artifacts`];
      // DEFENSE: Build-directory cleanup or external compilation can remove or replace a cached bundle.
      if (state[`target:${name}`] === key && actual.every(value => value !== null)
          && expected?.every((value, index) => value === actual[index])) {
        if (['host','browser','interaction'].includes(name)) {
          publications.set(`host/public/generated/${name}-model.mjs`, await readFile(path.join(root, output), 'utf8'));
        }
        next[`target:${name}`] = key;
        next[`target:${name}:artifacts`] = actual;
        return;
      }
      // This invocation owns every extracted unit it will compile and publish.
      // Reused output paths can receive restored artifacts from another build.
      const directory = path.relative(root, path.join(publicationDirectory, 'extracted', name));
      await mkdir(path.join(root, directory), { recursive: true });
      const aliases = target.entry.map(entry => `Definition selvedge_${name}_${entry} := Selvedge.${target.module}.${entry}.`).join('\n');
      const jsonAliases = Object.entries(jsonEntries).map(([alias, entry]) => `Definition ${alias} := Selvedge.${entry}.`).join('\n');
      // Separate extraction preserves module aliases used by typed domain surfaces.
      // Each target owns its OCaml units; ocamldep supplies their compilation order.
      const extraction = `From Selvedge.${target.module.split('.')[0]} Require Import ${target.module.split('.')[1]}.\nFrom Selvedge.Foundation Require Import TextJson.\nLoad "runtime/Extraction.v".\n${aliases}\n${jsonAliases}\nSet Extraction Output Directory "${directory}".\nSeparate Extraction ${target.entry.map(entry => `selvedge_${name}_${entry}`).join(' ')} ${Object.keys(jsonEntries).join(' ')}.\n`;
      const extractionFile = path.relative(root, path.join(publicationDirectory, `Extract${target.model}.v`));
      await writeChanged(extractionFile, extraction);
      await run('rocq', ['c', ...flags, extractionFile]);
      await writeChanged(`${directory}/${target.model}.ml`, `include Json\ninclude Extract${target.model}\n`);
      await writeChanged(`${directory}/json_io.ml`, jsonIo);
      await writeChanged(`${directory}/entry.ml`, runtime);
      // Extraction and its runtime wrappers share one dependency-ordered unit
      // list. A wrapper is compiled and linked exactly once, like every unit.
      const extracted = (await readdir(path.join(root, directory)))
        .filter(filename => filename.endsWith('.ml')).map(filename => `${directory}/${filename}`);
      const ordered = (await run('ocamlfind', ['ocamldep', '-package', 'zarith,js_of_ocaml', '-I', directory, '-sort', ...extracted])).trim().split(/\s+/);
      const ocaml = ['ocamlc', '-package', 'zarith,js_of_ocaml', '-I', directory];
      for (const source of ordered) {
        const signature = source.replace(/\.ml$/, '.mli');
        if (await exists(signature)) await run('ocamlfind', [...ocaml, '-c', signature]);
        await run('ocamlfind', [...ocaml, '-c', source]);
      }
      await run('ocamlfind', [...ocaml, '-linkpkg', '-o', `${directory}/runtime.bc`, ...ordered.map(source => source.replace(/\.ml$/, '.cmo'))]);
      const stagedRuntime = path.join(publicationDirectory, `${name}-runtime.js`);
      await run('js_of_ocaml', ['--target-env', 'browser', '-o', stagedRuntime, `${stubsDirectory}/biginteger.js`, `${stubsDirectory}/runtime.js`, `${directory}/runtime.bc`]);
      const exports = name === 'kernel'
        ? 'export const initial = runtime.initial;\nexport const packet = runtime.packet;\nexport const observe = runtime.observe;\nexport const assess = runtime.assess;\n'
        : `export const ${target.exported} = runtime.${name === 'commands' ? 'decode' : 'call'};\n${name === 'host' ? 'export const callStructured = runtime.callStructured;\n' : ''}`;
      // Keep each runtime and its exports in one atomically replaceable module.
      const bundle = `${await readFile(stagedRuntime, 'utf8')}\nconst runtime = globalThis.${target.global};\ndelete globalThis.${target.global};\n${exports}`;
      publications.set(output, bundle);
      if (['host','browser','interaction'].includes(name)) {
        publications.set(`host/public/generated/${name}-model.mjs`, bundle);
      }
      next[`target:${name}`] = key;
      next[`target:${name}:artifacts`] = [digest(bundle)];
      console.log(`extracted ${name}`);
    })), 'Executable extraction failed');
    // No executable asset is published until every selected target and captured input has passed.
    await assertInputsUnchanged();
    for (const [filename, bundle] of publications) await writeChanged(filename, bundle);
    if (selected.includes('schema')) await generateModelSchema(root);
    console.log(`Rocq: ${compiled} checked module${compiled === 1 ? '' : 's'}; ${selected.length} executable target${selected.length === 1 ? '' : 's'}`);
    const provenance = Object.fromEntries(selected.map(name => {
      const target = targets[name];
      const sources = new Set(['runtime/Extraction.v', 'theories/Foundation/TextJson.v',
        `theories/${target.module.replaceAll('.', '/')}.v`]);
      const pending = [...sources];
      while (pending.length) {
        for (const dependency of graph.get(pending.pop()) ?? []) {
          if (!sources.has(dependency)) { sources.add(dependency); pending.push(dependency); }
        }
      }
      if (sources.has('theories/Generated/Commands.v')) sources.add('theories/Derive/Commands.v');
      for (const filename of inputFingerprints.keys()) {
        if (!filename.endsWith('.v')) sources.add(filename);
      }
      return [name, Object.freeze({ sourceRoot: root, target: name, compiler: Object.freeze([...versions]),
        sources: Object.freeze([...sources].sort().map(filename => Object.freeze({
          path: filename, sha256: inputFingerprints.get(filename)
        }))), artifacts: Object.freeze([...next[`target:${name}:artifacts`]]) })];
    }));
    const result = Object.freeze({
      checked: check && allModules && productionTargets.every(name => selected.includes(name)),
      targets: Object.freeze([...selected]),
      provenance: Object.freeze(provenance),
    });
    return result;
  } finally {
    // DEFENSE: A failed dependency can reject its consumer while other scheduled checks are still running.
    await Promise.allSettled([...pending.values()]);
    if (publicationDirectory) await rm(publicationDirectory, { recursive: true, force: true });
    // Cache completed checks even when an independent module fails. Source and
    // object fingerprints invalidate these entries on the next build; executable
    // publication still requires every selected check and input guard to pass.
    await persistState();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const targetIndex = process.argv.indexOf('--target');
  const moduleIndex = process.argv.indexOf('--module');
  if (targetIndex >= 0 && moduleIndex >= 0) throw new Error('Choose --target or --module, not both');
  const selected = targetIndex < 0 ? undefined : process.argv[targetIndex + 1].split(',');
  const modules = moduleIndex < 0 ? [] : process.argv[moduleIndex + 1].split(',');
  await build({ selected, modules, check: process.argv.includes('--check') });
}

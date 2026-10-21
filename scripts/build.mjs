import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile, readdir, stat, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

export const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const buildDirectory = path.join(root, '.build');
const digest = value => createHash('sha256').update(value).digest('hex');
const stateFile = path.join(buildDirectory, 'build-state.json');
const flags = ['-w', '-register-all,-extraction-default-directory', '-Q', 'theories', 'Selvedge'];
const productionTargets = ['kernel', 'host', 'browser', 'interaction'];
export const targets = {
  commands: { module: 'Generated.Commands', model: 'CommandsModel', entry: ['decode','encode'], global: '__selvedgeCommands', exported: 'decode' },
  kernel: { module: 'Kernel.Packet', model: 'KernelModel', entry: ['initial', 'packet', 'world_json', 'assess'], global: '__selvedgeKernel' },
  host: { module: 'Adapters.Api', model: 'HostModel', entry: ['call'], global: '__selvedgeHost', exported: 'call' },
  browser: { module: 'Browser.Runtime', model: 'BrowserModel', entry: ['call'], global: '__selvedgeBrowser', exported: 'browserCall' },
  interaction: { module: 'Interaction.Application', model: 'InteractionModel', entry: ['call'], global: '__selvedgeInteraction', exported: 'interactionCall' }
};
export const jsonEntries = {
  selvedge_parse_json: 'Foundation.TextJson.parse_json',
  selvedge_render_json: 'Foundation.TextJson.render_json'
};

export async function run(command, args, options = {}) {
  const output = await new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, ...options, stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    child.stdout.on('data', chunk => chunks.push(chunk));
    child.stderr.on('data', chunk => chunks.push(chunk));
    child.on('error', reject);
    child.on('close', code => resolve({ code, text: Buffer.concat(chunks).toString() }));
  });
  if (output.code !== 0) {
    await mkdir(path.join(buildDirectory, 'logs'), { recursive: true });
    const filename = path.join(buildDirectory, 'logs', `${path.basename(command)}-${Date.now()}.log`);
    await writeFile(filename, output.text);
    throw new Error(`${command} failed (${output.code}); full output: ${filename}\n${output.text.slice(-5000)}`);
  }
  return output.text;
}
const exists = filename => stat(path.join(root, filename)).then(() => true, error => {
  // DEFENSE: A missing build artifact requires compilation; other filesystem errors are real failures.
  if (error.code === 'ENOENT') return false;
  throw error;
});
async function fingerprint(filename) {
  return await exists(filename) ? digest(await readFile(path.join(root, filename))) : null;
}
async function writeChanged(filename, value) {
  const previous = await exists(filename) ? await readFile(path.join(root, filename), 'utf8') : null;
  if (previous !== value) {
    await mkdir(path.dirname(path.join(root, filename)), { recursive: true });
    await writeFile(path.join(root, filename), value);
  }
}
async function sourceFiles(directory = 'theories') {
  const entries = await readdir(path.join(root, directory), { withFileTypes: true });
  return (await Promise.all(entries.map(entry => {
    const filename = `${directory}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(filename) : filename.endsWith('.v') ? [filename] : [];
  }))).flat().sort();
}
async function dependencies(files, recursive = false) {
  const graph = new Map();
  let pending = files;
  while (pending.length) {
    const output = await run('coqdep', ['-Q', 'theories', 'Selvedge', ...pending]);
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
    return `theories/${name.replaceAll('.', '/')}.v`;
  });
  const roots = [...selected.map(name => {
    if (!targets[name]) throw new Error(`Unknown build target: ${name}`);
    return `theories/${targets[name].module.replaceAll('.', '/')}.v`;
  }), ...moduleFiles];
  await mkdir(buildDirectory, { recursive: true });
  for (const filename of moduleFiles) if (!await exists(filename)) throw new Error(`Requested Rocq module is missing: ${filename}`);
  for (const name of selected) {
    if (!targets[name]) throw new Error(`Unknown build target: ${name}`);
    const filename = `theories/${targets[name].module.replaceAll('.', '/')}.v`;
    if (name !== 'commands' && !await exists(filename)) {
      throw new Error(`Production entry ${filename} is missing; the full migration build is incomplete`);
    }
  }
  const versions = await Promise.all([
    run('rocq', ['--version']), run('ocamlc', ['-version']), run('js_of_ocaml', ['--version']),
    run('opam', ['var', 'rocq-metarocq-template:version']),
    run('ocamlfind', ['query', '-format', '%v', 'zarith']), run('bun', ['--version'])
  ]);
  const pins = JSON.parse(await readFile(path.join(root, 'toolchain.json'), 'utf8'));
  if (!versions[0].includes(`version ${pins.rocq}`) || versions[1].trim() !== pins.ocaml || versions[2].trim() !== pins.js_of_ocaml
      || versions[3].trim() !== pins['metarocq-template'] || versions[4].trim() !== pins.zarith) {
    throw new Error('Toolchain does not match toolchain.json; run scripts/bootstrap.sh');
  }
  const stubsDirectory = '.build/deps/zarith_stubs_js';
  for (const [name, expected] of Object.entries(pins.zarith_stubs_js_sha256)) {
    const filename = `${stubsDirectory}/${name}`;
    if (!await exists(filename)) throw new Error('Pinned Zarith JS runtime is missing; run scripts/bootstrap.sh');
    if (digest(await readFile(path.join(root, filename))) !== expected) throw new Error(`Zarith JS runtime checksum mismatch: ${filename}`);
  }
  const identity = digest(JSON.stringify([versions[0], flags]));
  const extractionIdentity = digest(JSON.stringify([identity, versions.slice(1), pins, await readFile(fileURLToPath(import.meta.url), 'utf8'), await readFile(path.join(root, 'runtime/Extraction.v'), 'utf8')]));
  const state = await exists('.build/build-state.json') ? JSON.parse(await readFile(stateFile, 'utf8')) : {};
  const next = {};
  let compiled = 0;
  const pending = new Map();
  async function persistState() {
    const temporary = `${stateFile}.${process.pid}.tmp`;
    await writeFile(temporary, `${JSON.stringify({ ...state, ...next }, null, 2)}\n`);
    await rename(temporary, stateFile);
  }
  try {
    const graphInputs = async () => allModules
      ? (await sourceFiles()).filter(file => !file.startsWith('theories/Derive/'))
      : (await Promise.all(roots.map(async file => await exists(file) ? file : null))).filter(Boolean);
    let graph = await dependencies(await graphInputs(), !allModules);
    const withModuleSlot = limitConcurrency(4);
    async function compile(filename) {
      if (pending.has(filename)) return pending.get(filename);
      const promise = (async () => {
        const imported = graph.get(filename) ?? [];
        await Promise.all(imported.map(compile));
        const key = digest(JSON.stringify([identity, await readFile(path.join(root, filename), 'utf8'), imported.map(file => next[file])]));
        const artifact = filename.slice(0, -1) + 'vo';
        const actual = await fingerprint(artifact);
        // DEFENSE: A direct rocq compilation followed by restoring the source can leave a different .vo behind the cached source key.
        if (state[filename] !== key || actual === null || state[`artifact:${artifact}`] !== actual) {
          await withModuleSlot(() => run('rocq', ['c', ...flags, filename]));
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
      await compile('theories/Kernel/Commands.v');
      const generator = 'theories/Derive/Commands.v';
      const generatorKey = digest(JSON.stringify([identity, versions[3].trim(), await readFile(path.join(root, generator), 'utf8'), next['theories/Kernel/Commands.v']]));
      const generatedPath = 'theories/Generated/Commands.v';
      const generatedCurrent = await fingerprint(generatedPath);
      if (check || state.generator !== generatorKey || generatedCurrent !== state.generatedSource) {
        const output = await run('rocq', ['c', ...flags, generator]);
        const match = /SELVDERIVE_BEGIN\r?\n([\s\S]*?)SELVDERIVE_END/.exec(output);
        if (!match) throw new Error('MetaRocq command generator did not produce its delimited source');
        const generated = `(* Generated by MetaRocq from Kernel.Commands.command_specs. Do not edit. *)\n${match[1].trimEnd()}\n`;
        if (check && generatedCurrent && generatedCurrent !== digest(generated)) throw new Error('Generated command source is stale; run bun run build');
        await writeChanged(generatedPath, generated);
      }
      next.generator = generatorKey;
      next.generatedSource = await fingerprint(generatedPath);
      graph = await dependencies(await graphInputs(), !allModules);
    }
    if (selected.length) await compile('theories/Foundation/TextJson.v');
    const requestedChecks = (allModules ? [...graph.keys()] : roots).map(compile);
    await settleIndependent([...requestedChecks, ...pending.values()], 'Rocq checking failed');

    await persistState();

    const withTargetSlot = limitConcurrency(2);
    await settleIndependent(selected.map(name => withTargetSlot(async () => {
      const target = targets[name];
      const filename = `theories/${target.module.replaceAll('.', '/')}.v`;
      const runtime = name === 'commands' ? await readFile(path.join(root, 'runtime/commands_runtime.ml'), 'utf8')
        : name === 'kernel' ? await readFile(path.join(root, 'runtime/kernel_runtime.ml'), 'utf8')
        : (await readFile(path.join(root, 'runtime/call_runtime.ml.in'), 'utf8')).replaceAll('@MODEL@', target.model).replaceAll('@GLOBAL@', target.global).replaceAll('@ENTRY@', `selvedge_${name}_call`);
      const key = digest(JSON.stringify([extractionIdentity, next[filename], next['theories/Foundation/TextJson.v'], runtime, await readFile(path.join(root, 'runtime/json_io.ml'), 'utf8')]));
      const output = `.build/${name}-model.mjs`;
      const runtimeOutput = `.build/${name}-runtime.js`;
      const actual = await Promise.all([fingerprint(output), fingerprint(runtimeOutput)]);
      const expected = state[`target:${name}:artifacts`];
      // DEFENSE: A partial build-directory cleanup can retain the ES module while removing or replacing its imported runtime.
      if (state[`target:${name}`] === key && actual.every(value => value !== null)
          && expected?.every((value, index) => value === actual[index])) {
        if (['host','browser','interaction'].includes(name)) {
          await writeChanged(`host/public/generated/${name}-model.mjs`, await readFile(path.join(root, output), 'utf8'));
          await writeChanged(`host/public/generated/${name}-runtime.js`, await readFile(path.join(root, `.build/${name}-runtime.js`), 'utf8'));
        }
        next[`target:${name}`] = key;
        next[`target:${name}:artifacts`] = actual;
        return;
      }
      const directory = `.build/extracted/${name}`;
      await rm(path.join(root, directory), { recursive: true, force: true });
      await mkdir(path.join(root, directory), { recursive: true });
      const aliases = target.entry.map(entry => `Definition selvedge_${name}_${entry} := Selvedge.${target.module}.${entry}.`).join('\n');
      const jsonAliases = Object.entries(jsonEntries).map(([alias, entry]) => `Definition ${alias} := Selvedge.${entry}.`).join('\n');
      // Separate extraction preserves module aliases used by typed domain surfaces.
      // Each target owns its OCaml units; ocamldep supplies their compilation order.
      const extraction = `From Selvedge.${target.module.split('.')[0]} Require Import ${target.module.split('.')[1]}.\nFrom Selvedge.Foundation Require Import TextJson.\nLoad "runtime/Extraction.v".\n${aliases}\n${jsonAliases}\nSet Extraction Output Directory "${directory}".\nSeparate Extraction ${target.entry.map(entry => `selvedge_${name}_${entry}`).join(' ')} ${Object.keys(jsonEntries).join(' ')}.\n`;
      const extractionFile = `.build/Extract${target.model}.v`;
      await writeChanged(extractionFile, extraction);
      await run('rocq', ['c', ...flags, extractionFile]);
      await writeChanged(`${directory}/${target.model}.ml`, `include Json\ninclude Extract${target.model}\n`);
      const extracted = (await readdir(path.join(root, directory)))
        .filter(filename => filename.endsWith('.ml')).map(filename => `${directory}/${filename}`);
      const ordered = (await run('ocamlfind', ['ocamldep', '-package', 'zarith,js_of_ocaml', '-I', directory, '-sort', ...extracted])).trim().split(/\s+/);
      await writeChanged(`${directory}/json_io.ml`, await readFile(path.join(root, 'runtime/json_io.ml'), 'utf8'));
      await writeChanged(`${directory}/entry.ml`, runtime);
      const ocaml = ['ocamlc', '-package', 'zarith,js_of_ocaml', '-I', directory];
      for (const source of ordered) {
        const signature = source.replace(/\.ml$/, '.mli');
        if (await exists(signature)) await run('ocamlfind', [...ocaml, '-c', signature]);
        await run('ocamlfind', [...ocaml, '-c', source]);
      }
      await run('ocamlfind', [...ocaml, '-c', `${directory}/json_io.ml`]);
      await run('ocamlfind', [...ocaml, '-c', `${directory}/entry.ml`]);
      await run('ocamlfind', [...ocaml, '-linkpkg', '-o', `${directory}/runtime.bc`, ...ordered.map(source => source.replace(/\.ml$/, '.cmo')), `${directory}/json_io.cmo`, `${directory}/entry.cmo`]);
      await run('js_of_ocaml', ['--target-env', 'browser', '-o', `.build/${name}-runtime.js`, `${stubsDirectory}/biginteger.js`, `${stubsDirectory}/runtime.js`, `${directory}/runtime.bc`]);
      const exports = name === 'kernel'
        ? 'export const initial = runtime.initial;\nexport const packet = runtime.packet;\nexport const observe = runtime.observe;\nexport const assess = runtime.assess;\n'
        : `export const ${target.exported} = runtime.${name === 'commands' ? 'decode' : 'call'};\n${name === 'host' ? 'export const callStructured = runtime.callStructured;\n' : ''}`;
      await writeChanged(output, `import './${name}-runtime.js';\nconst runtime = globalThis.${target.global};\ndelete globalThis.${target.global};\n${exports}`);
      if (['host','browser','interaction'].includes(name)) {
        const publicDirectory = 'host/public/generated';
        await writeChanged(`${publicDirectory}/${name}-model.mjs`, await readFile(path.join(root, output), 'utf8'));
        await writeChanged(`${publicDirectory}/${name}-runtime.js`, await readFile(path.join(root, `.build/${name}-runtime.js`), 'utf8'));
      }
      next[`target:${name}`] = key;
      next[`target:${name}:artifacts`] = await Promise.all([fingerprint(output), fingerprint(runtimeOutput)]);
      console.log(`extracted ${name}`);
    })), 'Executable extraction failed');
    console.log(`Rocq: ${compiled} checked module${compiled === 1 ? '' : 's'}; ${selected.length} executable target${selected.length === 1 ? '' : 's'}`);
  } finally {
    // DEFENSE: A failed dependency can reject its consumer while other scheduled checks are still running.
    await Promise.allSettled([...pending.values()]);
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

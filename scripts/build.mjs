import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { compiler, expectedVersion } from './toolchain.mjs';
import { checkBundle } from './import-stdlib.mjs';
import { checkRelations } from './import-relations.mjs';
import { checkMaps } from './import-maps.mjs';
import { checkComponents, bendSources, entrySources } from './check-components.mjs';
import { compileJavaScriptBatch } from './compile-javascript.mjs';
import { prepareUiVerification } from './ui-verification.mjs';
import { buildModel } from '../plugins/selvedge-chatgpt/scripts/build-model.mjs';
import { compilerEnvironment } from './compiler-memory.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

async function timed(label, action) {
  const started = performance.now();
  const result = await action();
  console.log(`${label} (${((performance.now() - started) / 1000).toFixed(2)}s).`);
  return result;
}

async function entryRequest(entry, output, { publicSource = entry, namespacePrefix = '' } = {}) {
  // Root entry definitions are public wrappers; import aliases are not compiler names.
  const source = await readFile(path.join(root, publicSource), 'utf8');
  const names = [...source.matchAll(/^def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/gm)].map(match => match[1]);
  if (!names.length) throw new Error(`No public Bend wrappers in ${publicSource}`);
  return { entry, exports: Object.fromEntries(names.map(name => [name, `${namespacePrefix}${name}`])), output, sourceRoot: root };
}

async function nativeIdentity(bend, compileArguments) {
  const compilerPath = Bun.which(bend);
  if (!compilerPath) throw new Error(`Cannot resolve native Bend compiler: ${bend}`);
  const compilerBytes = await readFile(compilerPath);
  const hash = createHash('sha256');
  const digest = bytes => createHash('sha256').update(bytes).digest('hex');
  const configuration = { entry: compileArguments[0], arguments: compileArguments,
    platform: process.platform, architecture: process.arch, compilerVersion: expectedVersion };
  // Length-tagged records keep arbitrary source bytes distinct from cache metadata.
  function record(kind, name, bytes) {
    hash.update(JSON.stringify([kind, name, bytes.length])).update('\0').update(bytes).update('\0');
  }
  record('configuration', '', Buffer.from(JSON.stringify(configuration)));
  record('compiler', 'bend', compilerBytes);
  const sources = [];
  for (const filename of await entrySources(root, configuration.entry)) {
    const bytes = await readFile(path.join(root, filename));
    record('source', filename, bytes);
    sources.push({ path: filename, sha256: digest(bytes) });
  }
  return { fingerprint: hash.digest('hex'), ...configuration,
    compiler: { path: compilerPath, version: expectedVersion, sha256: digest(compilerBytes) }, sources };
}

export async function build({ native = false, force = false } = {}) {
  console.log(await checkComponents(root));
  const bend = compiler();
  await checkBundle();
  await checkRelations();
  await checkMaps();
  const verification = prepareUiVerification(root);

  const hostOutput = 'host/public/generated/host-model.mjs';
  const requests = [
    await entryRequest('KERNEL.bend', '.build/kernel-model.mjs'),
    await entryRequest(verification.runtimeEntry, 'host/public/generated/browser-model.mjs', {
      publicSource: 'BROWSER.bend', namespacePrefix: verification.browserPrefix,
    }),
    { entry: 'HOST.bend', exports: { run: 'run' }, output: hostOutput, sourceRoot: root },
    { entry: 'plugins/selvedge-chatgpt/MODEL.bend', exports: { run: 'run' }, output: 'plugins/selvedge-chatgpt/generated/model.mjs', sourceRoot: root },
  ];
  if (force) for (const request of requests) await rm(path.resolve(root, `${request.output}.json`), { force: true });
  const [kernel, browser, host] = await timed('Production JavaScript compilation', () => compileJavaScriptBatch({ prefix: verification.entry, requests, verify: true }));
  console.log(`Bend JavaScript kernel ${kernel.cached ? 'is current' : 'built'} (${kernel.fingerprint.slice(0, 12)}).`);
  console.log(`Bend JavaScript browser ${browser.cached ? 'is current' : 'built'} (${browser.fingerprint.slice(0, 12)}).`);
  console.log(`Bend JavaScript host ${host.cached ? 'is current' : 'built'} (${host.fingerprint.slice(0, 12)}).`);
  await timed('Plugin JavaScript compilation', () => buildModel());

  const inputs = await bendSources(root);
  const backend = 'bend-javascript';
  const kernelManifest = JSON.parse(await readFile(`${kernel.output}.json`, 'utf8'));
  const javascriptCompiler = kernelManifest.compiler;
  const hash = createHash('sha256').update(`Bend ${expectedVersion}\0${backend}\0`)
    .update(JSON.stringify(javascriptCompiler)).update('\0').update(kernel.fingerprint).update('\0').update(browser.fingerprint).update('\0').update(host.fingerprint).update('\0');
  for (const name of inputs) hash.update(name).update('\0').update(await readFile(path.join(root, name))).update('\0');
  const fingerprint = hash.digest('hex');
  const directory = path.join(root, '.build');
  await mkdir(directory, { recursive: true });
  // Publish build identity only after all production libraries have compiled successfully.
  await writeFile(path.join(directory, 'kernel.json'), JSON.stringify({
    compiler: expectedVersion, fingerprint, backend, javascriptCompiler,
    sources: inputs, models: { kernel: kernel.fingerprint, browser: browser.fingerprint, host: host.fingerprint },
  }, null, 2) + '\n');

  if (native) {
    const compileArguments = ['MAIN.bend', '-o', '.build/selvedge-kernel'];
    const identity = await nativeIdentity(bend, compileArguments);
    let previous;
    try { previous = JSON.parse(await readFile(path.join(directory, 'native.json'), 'utf8')); } catch {}
    const output = path.join(directory, 'selvedge-kernel');
    let outputSha256;
    try { outputSha256 = createHash('sha256').update(await readFile(output)).digest('hex'); } catch {}
    if (previous?.fingerprint !== identity.fingerprint || !outputSha256 || previous.outputSha256 !== outputSha256 || force) {
      const result = spawnSync(bend, compileArguments, { cwd: root, stdio: 'inherit', env: compilerEnvironment() });
      if (result.error) throw result.error;
      if (result.status !== 0) throw new Error(`Native Bend compilation failed (${result.status})`);
      await writeFile(path.join(directory, 'native.json'), JSON.stringify({ ...identity,
        outputSha256: createHash('sha256').update(await readFile(output)).digest('hex'),
      }, null, 2) + '\n');
      console.log(`Built optional native Bend kernel ${identity.fingerprint.slice(0, 12)}.`);
    } else console.log(`Optional native Bend kernel is current (${identity.fingerprint.slice(0, 12)}).`);
  }
  return { kernel, browser, host, fingerprint };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await build({ native: process.argv.includes('--native'), force: process.argv.includes('--force') });
}

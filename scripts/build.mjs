import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { compiler, compilerEnvironment, compilerInvocation, expectedVersion } from './toolchain.mjs';
import { checkBundle } from './import-stdlib.mjs';
import { checkRelations } from './import-relations.mjs';
import { checkMaps } from './import-maps.mjs';
import { checkComponents, bendSources, entrySources } from './check-components.mjs';
import { compileJavaScript, compileJavaScriptBatch } from './compile-javascript.mjs';
import { prepareUiVerification } from './ui-verification.mjs';
import { buildModel } from '../plugins/selvedge-chatgpt/scripts/build-model.mjs';

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
  // DEFENSE: An edited public entry can remove every wrapper and would otherwise produce an empty runtime interface.
  if (!names.length) throw new Error(`No public Bend wrappers in ${publicSource}`);
  return { entry, exports: Object.fromEntries(names.map(name => [name, `${namespacePrefix}${name}`])), output, sourceRoot: root };
}

async function productionInputs(verification) {
  const sources = await bendSources(root);
  const hash = createHash('sha256');
  // Generated verification/runtime entries are hidden from bendSources. Bind
  // their assembly and the ownership policy along with all production sources.
  for (const name of [...sources, verification.entry, verification.runtimeEntry, 'components.json'].sort()) {
    const bytes = await readFile(path.join(root, name));
    hash.update(JSON.stringify([name, bytes.length])).update('\0').update(bytes).update('\0');
  }
  return { sources, fingerprint: hash.digest('hex') };
}

async function nativeIdentity(bend, compileArguments) {
  const compilerPath = Bun.which(bend);
  // DEFENSE: The selected native compiler can disappear from PATH between its version check and executable hashing.
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
  const inputs = await productionInputs(verification);

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
  const [kernel, browser, host] = await timed('Production JavaScript compilation', async () => {
    const [kernel, browser] = await compileJavaScriptBatch({
      prefix: verification.entry, requests: requests.slice(0, 2), verify: true,
    });
    // The shared compiler exits before host/plugin emission, releasing the full
    // proof book and browser IR instead of retaining them across every backend.
    const host = await compileJavaScript(requests[2]);
    await compileJavaScript(requests[3]);
    return [kernel, browser, host];
  });
  console.log(`Bend JavaScript kernel ${kernel.cached ? 'is current' : 'built'} (${kernel.fingerprint.slice(0, 12)}).`);
  console.log(`Bend JavaScript browser ${browser.cached ? 'is current' : 'built'} (${browser.fingerprint.slice(0, 12)}).`);
  console.log(`Bend JavaScript host ${host.cached ? 'is current' : 'built'} (${host.fingerprint.slice(0, 12)}).`);
  await timed('Plugin JavaScript compilation', () => buildModel());

  // DEFENSE: Source or assembly edits between the checked batch and isolated host/plugin compilation must not publish one build identity for different inputs.
  if ((await productionInputs(verification)).fingerprint !== inputs.fingerprint) {
    throw new Error('Production sources changed between proof checking and JavaScript emission; retry with stable sources');
  }
  const backend = 'bend-javascript';
  const kernelManifest = JSON.parse(await readFile(`${kernel.output}.json`, 'utf8'));
  const javascriptCompiler = kernelManifest.compiler;
  const hash = createHash('sha256').update(`Bend ${expectedVersion}\0${backend}\0`)
    .update(JSON.stringify(javascriptCompiler)).update('\0').update(kernel.fingerprint).update('\0').update(browser.fingerprint).update('\0').update(host.fingerprint).update('\0');
  hash.update(inputs.fingerprint);
  const fingerprint = hash.digest('hex');
  const directory = path.join(root, '.build');
  await mkdir(directory, { recursive: true });
  // Publish build identity only after all production libraries have compiled successfully.
  await writeFile(path.join(directory, 'kernel.json'), JSON.stringify({
    compiler: expectedVersion, fingerprint, backend, javascriptCompiler,
    sources: inputs.sources, models: { kernel: kernel.fingerprint, browser: browser.fingerprint, host: host.fingerprint },
  }, null, 2) + '\n');

  if (native) {
    const compileArguments = ['MAIN.bend', '-o', '.build/selvedge-kernel'];
    const identity = await nativeIdentity(bend, compileArguments);
    let previous;
    // DEFENSE: A first build or interrupted manifest write leaves no usable native cache identity.
    try { previous = JSON.parse(await readFile(path.join(directory, 'native.json'), 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) throw error; }
    const output = path.join(directory, 'selvedge-kernel');
    let outputSha256;
    // DEFENSE: The optional executable can be absent before its first build or after cache cleanup.
    try { outputSha256 = createHash('sha256').update(await readFile(output)).digest('hex'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    // DEFENSE: Missing, edited or stale native cache artifacts must be rebuilt from the current compiler and source bytes.
    if (previous?.fingerprint !== identity.fingerprint || previous.outputSha256 !== outputSha256 || force) {
      const invocation = compilerInvocation(bend, compileArguments);
      const result = spawnSync(invocation.command, invocation.args, { cwd: root, stdio: 'inherit', env: { ...compilerEnvironment(), BEND_NO_TELEMETRY: '1' } });
      // DEFENSE: The native compiler launcher can fail to start because the OS refuses its process.
      if (result.error) throw result.error;
      // DEFENSE: The native compiler can exit unsuccessfully or be terminated before producing its executable.
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

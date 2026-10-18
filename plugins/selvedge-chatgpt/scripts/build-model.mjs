import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const plugin = fileURLToPath(new URL('../', import.meta.url));
const checkout = path.resolve(plugin, '../..');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const assets = ['model.mjs', 'model.mjs.json', 'json-tokens.mjs', 'model-boundary.mjs', 'opaque-credentials.mjs'];
export const packagedModelFiles = Object.freeze([...assets, 'sources.json']);

/** Compilation runs in the source checkout; installed runtime consumes only shipped assets. */
export async function buildModel() {
  const compiler = path.join(checkout, 'scripts/compile-javascript.mjs');
  try { await access(compiler); }
  catch { throw new Error('Build the Selvedge plugin model in its source checkout before packaging'); }
  const { compileJavaScript } = await import(pathToFileURL(compiler).href);
  const output = path.join(plugin, 'generated/model.mjs');
  const compiled = await compileJavaScript({ entry: path.join(plugin, 'MODEL.bend'),
    exports: { run: 'run' }, output, sourceRoot: checkout });
  const tokenSource = path.join(checkout, 'host/public/json-tokens.mjs');
  const boundarySource = path.join(checkout, 'host/public/model-boundary.mjs');
  const credentialsSource = path.join(checkout, 'host/opaque-credentials.mjs');
  const [tokens, facade, credentials] = await Promise.all([
    readFile(tokenSource), readFile(boundarySource, 'utf8'), readFile(credentialsSource),
  ]);
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(path.join(plugin, 'generated/json-tokens.mjs'), tokens);
  await writeFile(path.join(plugin, 'generated/opaque-credentials.mjs'), credentials);
  // Only the generated library import changes; token conversion and outer-envelope
  // handling use exactly the shared source implementation.
  const boundary = facade.replace("'./generated/host-model.mjs'", "'./model.mjs'");
  if (boundary === facade) throw new Error('Shared host model facade import no longer matches the plugin packaging contract');
  await writeFile(path.join(plugin, 'generated/model-boundary.mjs'), boundary);
  const packagedAssets = Object.fromEntries(await Promise.all(assets.map(async name =>
    [name, hash(await readFile(path.join(plugin, 'generated', name)))])));
  await writeFile(path.join(plugin, 'generated/sources.json'), JSON.stringify({
    assets: packagedAssets,
    modelFingerprint: compiled.fingerprint,
    jsonTokens: { source: 'host/public/json-tokens.mjs', sha256: hash(tokens) },
    opaqueCredentials: { source: 'host/opaque-credentials.mjs', sha256: hash(credentials) },
    boundary: { source: 'host/public/model-boundary.mjs', sha256: hash(facade), packagedSha256: hash(boundary) },
  }, null, 2) + '\n');
}

export async function requirePackagedModel() {
  const generated = path.join(plugin, 'generated');
  let provenance;
  let model;
  try {
    provenance = JSON.parse(await readFile(path.join(generated, 'sources.json'), 'utf8'));
    for (const name of assets) {
      if (hash(await readFile(path.join(generated, name))) !== provenance.assets?.[name]) {
        throw new Error(`Packaged plugin asset does not match its manifest: ${name}`);
      }
    }
    model = JSON.parse(await readFile(path.join(generated, 'model.mjs.json'), 'utf8'));
    if (model.fingerprint !== provenance.modelFingerprint || model.outputSha256 !== provenance.assets['model.mjs']) {
      throw new Error('Packaged plugin model identity does not match its asset manifest');
    }
  } catch (error) {
    throw new Error(`Invalid packaged plugin model; run npm run build:model in the source checkout before packaging: ${error.message}`);
  }

  // An installed package has no source checkout. A checkout must also establish
  // that its shipped bytes still correspond to the current compiler and sources.
  try { await access(path.join(plugin, 'MODEL.bend')); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  const compiler = path.join(checkout, 'scripts/compile-javascript.mjs');
  let currentCompiler;
  if (process.versions.bun) {
    const { javascriptCompilerIdentity } = await import(pathToFileURL(compiler).href);
    currentCompiler = await javascriptCompilerIdentity();
  } else {
    // Checkout verification needs the build toolchain; installed packages above
    // validate only their shipped assets and never invoke a compiler preparer.
    const code = `const { javascriptCompilerIdentity } = await import(${JSON.stringify(pathToFileURL(compiler).href)}); console.log(JSON.stringify(await javascriptCompilerIdentity()));`;
    const result = spawnSync('bun', ['--eval', code], {
      cwd: checkout, encoding: 'utf8', timeout: 10_000, maxBuffer: 1024 * 1024,
      env: { ...process.env, NODE_OPTIONS: '' },
    });
    if (result.error || result.status !== 0 || result.stderr.trim()) {
      throw new Error(`Cannot verify the checkout compiler identity: ${result.error?.message ?? result.stderr.trim()}`);
    }
    currentCompiler = JSON.parse(result.stdout);
  }
  if (JSON.stringify(model.compiler) !== JSON.stringify(currentCompiler)
      || model.sourceRoot !== checkout || model.exports?.run !== 'run' || Object.keys(model.exports).length !== 1
      || !Array.isArray(model.sources) || model.sources.length === 0) {
    throw new Error('Packaged plugin compiler identity is stale; run npm run build:model before packaging');
  }
  for (const source of model.sources) {
    if (hash(await readFile(path.resolve(checkout, source.path))) !== source.sha256) {
      throw new Error(`Packaged plugin model source is stale: ${source.path}`);
    }
  }
  const fingerprint = hash(JSON.stringify({ entry: path.relative(checkout, path.join(plugin, 'MODEL.bend')),
    sourceRoot: checkout, exports: model.exports, compiler: model.compiler, sources: model.sources }));
  if (fingerprint !== model.fingerprint) throw new Error('Packaged plugin model fingerprint does not match its inputs');
  for (const shared of [provenance.jsonTokens, provenance.boundary, provenance.opaqueCredentials]) {
    if (hash(await readFile(path.join(checkout, shared.source))) !== shared.sha256) {
      throw new Error(`Packaged plugin shared source is stale: ${shared.source}`);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await buildModel();

import { readFile, writeFile, mkdir, access, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const plugin = fileURLToPath(new URL('../', import.meta.url));
const checkout = path.resolve(plugin, '../..');
const hash = value => createHash('sha256').update(value).digest('hex');
const assets = ['host-model.mjs', 'json-tokens.mjs', 'model-boundary.mjs', 'opaque-credentials.mjs'];
export const packagedModelFiles = Object.freeze([...assets, 'sources.json']);

/** Runtime packages contain the actual extracted definitions and no compiler dependency. */
export async function buildModel({ buildResult } = {}) {
  const compiler = path.join(checkout, 'scripts/build.mjs');
  try { await access(compiler); }
  // DEFENSE: Installed packages omit the Rocq source checkout and cannot compile it.
  catch (error) {
    if (error.code === 'ENOENT') throw new Error('Build the Selvedge plugin model in its source checkout before packaging');
    throw error;
  }
  if (buildResult) {
    if (!buildResult.targets?.includes('host')) throw new Error('Plugin model packaging requires the host build target');
  } else {
    const { build } = await import(pathToFileURL(compiler).href);
    buildResult = await build({ selected: ['host'] });
  }
  const model = buildResult.provenance?.host;
  // DEFENSE: Packaging needs the source snapshot of the host extraction, not an unrelated completed build.
  if (!model || model.sourceRoot !== checkout || model.target !== 'host') {
    throw new Error('Plugin model packaging requires host extraction provenance from the current checkout');
  }
  const generated = path.join(plugin, 'generated');
  await mkdir(generated, { recursive: true });
  const sources = {
    'host-model.mjs': '.build/host-model.mjs',
    'json-tokens.mjs': 'host/public/json-tokens.mjs',
    'model-boundary.mjs': 'host/public/model-boundary.mjs',
    'opaque-credentials.mjs': 'host/opaque-credentials.mjs',
  };
  const provenance = {};
  for (const [name, source] of Object.entries(sources)) {
    const original = await readFile(path.join(checkout, source));
    // DEFENSE: Another build can replace an extraction artifact after the supplied build result was captured.
    if (name === 'host-model.mjs' && hash(original) !== model.artifacts[0]) {
      throw new Error(`Host extraction changed before plugin packaging: ${source}`);
    }
    const packaged = name === 'model-boundary.mjs'
      ? Buffer.from(original.toString().replace("'./generated/host-model.mjs'", "'./host-model.mjs'")) : original;
    await writeFile(path.join(generated, name), packaged);
    provenance[name] = { source, sourceSha256: hash(original), sha256: hash(packaged) };
  }
  // DEFENSE: Rebuilding a package can leave the retired split runtime in its shipped directory.
  await rm(path.join(generated, 'host-runtime.js'), { force: true });
  await writeFile(path.join(generated, 'sources.json'), `${JSON.stringify({ format: 'selvedge-rocq-plugin-1',
    model, modelFingerprint: hash(JSON.stringify(model)), assets: provenance }, null, 2)}\n`);
  return requirePackagedModel();
}

export async function requirePackagedModel() {
  const generated = path.join(plugin, 'generated');
  let manifest;
  try {
    manifest = JSON.parse(await readFile(path.join(generated, 'sources.json'), 'utf8'));
    if (manifest.format !== 'selvedge-rocq-plugin-1') throw new Error('Unknown extracted model manifest format');
    // DEFENSE: An interrupted or edited manifest must still bind the extraction inputs to the shipped bundle.
    if (manifest.modelFingerprint !== hash(JSON.stringify(manifest.model))
        || manifest.model?.artifacts?.length !== 1
        || manifest.model.artifacts[0] !== manifest.assets?.['host-model.mjs']?.sha256) {
      throw new Error('Packaged plugin extraction identity does not match its assets');
    }
    for (const name of assets) {
      // DEFENSE: Partial or modified package copies must fail before loading executable assets.
      if (hash(await readFile(path.join(generated, name))) !== manifest.assets?.[name]?.sha256) {
        throw new Error(`Packaged plugin asset does not match its manifest: ${name}`);
      }
    }
  // DEFENSE: Deployment can omit generated assets; fail with the required source-build command.
  } catch (error) {
    throw new Error(`Invalid packaged plugin model; run npm run build:model in the source checkout before packaging: ${error.message}`);
  }
  const compiler = path.join(checkout, 'scripts/build.mjs');
  try { await access(compiler); }
  // DEFENSE: Installed packages omit the source checkout and validate only their shipped assets.
  catch (error) { if (error.code === 'ENOENT') return manifest; throw error; }
  const { compilerVersions } = await import(pathToFileURL(compiler).href);
  const model = manifest.model;
  // DEFENSE: A source checkout can retain generated assets after its source tree or compiler has changed.
  if (model.sourceRoot !== checkout || model.target !== 'host'
      || !Array.isArray(model.sources) || model.sources.length === 0
      || JSON.stringify(model.compiler) !== JSON.stringify(await compilerVersions())) {
    throw new Error('Packaged plugin compiler identity is stale; run npm run build:model before packaging');
  }
  for (const source of model.sources) {
    // DEFENSE: Editing a source used by extraction invalidates the checkout's shipped model.
    if (hash(await readFile(path.join(checkout, source.path))) !== source.sha256) {
      throw new Error(`Packaged plugin model source is stale: ${source.path}`);
    }
  }
  for (const asset of Object.values(manifest.assets)) {
    // DEFENSE: Shared transport and credential code can change independently of the Rocq extraction.
    if (hash(await readFile(path.join(checkout, asset.source))) !== asset.sourceSha256) {
      throw new Error(`Packaged plugin shared source is stale: ${asset.source}`);
    }
  }
  return manifest;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await buildModel();

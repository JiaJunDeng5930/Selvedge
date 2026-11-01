import { readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const plugin = fileURLToPath(new URL('../', import.meta.url));
const checkout = path.resolve(plugin, '../..');
const sources = {
  'host-model.mjs': '.build/host-model.mjs',
  'json-tokens.mjs': 'host/public/json-tokens.mjs',
  'model-boundary.mjs': 'host/public/model-boundary.mjs',
  'opaque-credentials.mjs': 'host/opaque-credentials.mjs',
  'file-io.mjs': 'host/file-io.mjs',
};
export const packagedModelFiles = Object.freeze(Object.keys(sources));

/** Runtime packages contain the actual extracted definitions and no compiler dependency. */
export async function buildModel({ buildResult } = {}) {
  if (!buildResult) {
    const { build } = await import(pathToFileURL(path.join(checkout, 'scripts/build.mjs')).href);
    await build({ selected: ['host'] });
  }
  const generated = path.join(plugin, 'generated');
  await rm(generated, { recursive: true, force: true });
  await mkdir(generated, { recursive: true });
  for (const [name, source] of Object.entries(sources)) {
    const original = await readFile(path.join(checkout, source));
    const packaged = name === 'model-boundary.mjs'
      ? Buffer.from(original.toString().replace("'./generated/host-model.mjs'", "'./host-model.mjs'")) : original;
    await writeFile(path.join(generated, name), packaged);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await buildModel();

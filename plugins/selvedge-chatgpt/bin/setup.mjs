#!/usr/bin/env node
import { mkdir, open, readFile, writeFile, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { settings } from '../src/client.mjs';
import { requirePackagedModel, packagedModelFiles } from '../scripts/build-model.mjs';

const root = path.resolve(fileURLToPath(new URL('../', import.meta.url)));

// Deployment packages contain only these shipped files. Local connection data
// and arbitrary source-directory contents cannot become publication inputs.
const deploymentFiles = [
  'README.md', 'package.json', 'package-lock.json', 'plugin.json',
  'bin/server.mjs', 'bin/setup.mjs', 'bin/tunnel.mjs',
  'src/client.mjs', 'src/server.mjs', 'scripts/build-model.mjs',
  ...packagedModelFiles.map(filename => `generated/${filename}`),
  'skills/local-projects/SKILL.md',
];

export async function saveConnection(directory, env = process.env) {
  if (!path.isAbsolute(directory)) throw new Error('Use an absolute plugin data directory');
  const config = settings(env);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const filename = path.join(directory, 'connection.json');
  const file = await open(filename, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try {
    await file.writeFile(JSON.stringify({ SELVEDGE_URL: config.endpoint, SELVEDGE_CONNECTION_ID: config.connection,
      SELVEDGE_CONNECTION_TOKEN: config.token }) + '\n');
    await file.sync();
  } finally { await file.close(); }
  return filename;
}

/** Registered app IDs are deployment data; build a separate package without a second local tool route. */
export async function packageConnection(id, directory) {
  if (!/^plugin_asdk_app_[A-Za-z0-9_-]+$/.test(id)) throw new Error('Use the registered plugin_asdk_app ID from ChatGPT');
  if (path.isAbsolute(directory)) directory = path.resolve(directory);
  if (!path.isAbsolute(directory) || directory === root || directory.startsWith(root + path.sep)) {
    throw new Error('Use an absolute output directory outside the source plugin');
  }
  directory = path.join(await realpath(path.dirname(directory)), path.basename(directory));
  const source = await realpath(root);
  if (directory === source || directory.startsWith(source + path.sep)) throw new Error('The output must stay outside the source plugin');
  await requirePackagedModel();
  await mkdir(directory, { mode: 0o700 });
  for (const relative of deploymentFiles) {
    const filename = path.join(root, relative);
    if (!(await realpath(filename)).startsWith(source + path.sep)) {
      throw new Error(`Invalid deployment file: ${relative}`);
    }
    const target = path.join(directory, relative);
    await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
    const file = await open(filename, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const observed = await file.stat();
      if (!observed.isFile()) throw new Error(`Invalid deployment file: ${relative}`);
      await writeFile(target, await file.readFile(), { flag: 'wx', mode: observed.mode & 0o777 });
    } finally { await file.close(); }
  }
  const filename = path.join(directory, 'plugin.json');
  const manifest = JSON.parse(await readFile(filename, 'utf8'));
  manifest.extensions['com.openai'].apps = './.app.json';
  await writeFile(filename, JSON.stringify(manifest, null, 2) + '\n');
  await writeFile(path.join(directory, '.app.json'), JSON.stringify({ apps: { selvedge: { id, required: true } } }, null, 2) + '\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [action, first, second, ...extra] = process.argv.slice(2);
  try {
    if (extra.length || !first || (action === 'connection' && second)) throw new Error('Invalid setup arguments');
    if (action === 'connection') console.log(`Saved private connection settings: ${await saveConnection(first)}`);
    else if (action === 'package' && second) { await packageConnection(first, second); console.log(`Packaged registered connection: ${second}`); }
    else throw new Error('Usage: setup.mjs connection ABSOLUTE_DATA_DIR | package PLUGIN_ASDK_APP_ID ABSOLUTE_OUTPUT_DIR');
  } catch (error) { console.error(`Selvedge setup: ${error.message}`); process.exitCode = 1; }
}

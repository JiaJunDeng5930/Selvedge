#!/usr/bin/env node
import { mkdir, open, cp, readFile, writeFile, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { settings } from '../src/client.mjs';

const root = path.resolve(fileURLToPath(new URL('../', import.meta.url)));

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
  await mkdir(directory, { mode: 0o700 });
  await cp(root, directory, { recursive: true, filter: source => !['node_modules', 'mcp.json'].includes(path.basename(source)) });
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

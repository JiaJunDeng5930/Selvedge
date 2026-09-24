import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readdir, readFile, mkdir, writeFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { compiler, expectedVersion } from './toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bend = compiler();

async function sources(directory, relative = '') {
  const result = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (item.name.startsWith('.') || ['node_modules', 'crates', 'target'].includes(item.name)) continue;
    const name = path.join(relative, item.name);
    if (item.isDirectory()) result.push(...await sources(path.join(directory, item.name), name));
    else if (name.endsWith('.bend') || name === 'host/transport.c') result.push(name);
  }
  return result.sort();
}

const inputs = await sources(root);
const hash = createHash('sha256').update(`Bend ${expectedVersion}\0`);
for (const name of inputs) hash.update(name).update('\0').update(await readFile(path.join(root, name))).update('\0');
const fingerprint = hash.digest('hex');
const build = path.join(root, '.build');
await mkdir(build, { recursive: true });
let previous;
try { previous = JSON.parse(await readFile(path.join(build, 'kernel.json'), 'utf8')); } catch {}
let binaryExists = false;
try { binaryExists = (await stat(path.join(build, 'selvedge-kernel'))).isFile(); } catch {}
if (previous?.fingerprint === fingerprint && binaryExists && !process.argv.includes('--force')) {
  console.log(`Bend kernel is current (${fingerprint.slice(0, 12)}).`);
} else {
  for (const args of [['PROOF.bend', '--check-only'], ['MAIN.bend', '-o', '.build/selvedge-kernel']]) {
    const result = spawnSync(bend, args, { cwd: root, stdio: 'inherit', env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
    if (result.error) throw result.error;
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
  await writeFile(path.join(build, 'kernel.json'), JSON.stringify({ format: 'selvedge-bend-journal-1', compiler: expectedVersion, fingerprint, sources: inputs }, null, 2) + '\n');
  console.log(`Built Bend kernel ${fingerprint.slice(0, 12)}.`);
}

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const expectedVersion = readFileSync(new URL('../bend-version', import.meta.url), 'utf8').trim();
const local = fileURLToPath(new URL('../.build/bend/bin/bend', import.meta.url));

export function compiler() {
  if (Number(process.versions.node.split('.')[0]) < 26) throw new Error('Selvedge requires Node.js 26 or later');
  const binary = existsSync(local) ? local : 'bend';
  const version = spawnSync(binary, ['version'], { encoding: 'utf8', env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
  if (version.error || version.status !== 0 || version.stdout.trim() !== `bend ${expectedVersion}`) {
    throw new Error(`Bend ${expectedVersion} is required. Run bash scripts/install-bend.sh to install the pinned workspace compiler.`);
  }
  return binary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(`Using ${compiler()} (${expectedVersion})`);
}

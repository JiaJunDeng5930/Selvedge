import { spawnSync } from 'node:child_process';
import { readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { compiler } from './toolchain.mjs';
import { verifyProof } from './verify-proof.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

async function checkDirectory(directory) {
  for (const entry of await readdir(path.join(root, directory), { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) await checkDirectory(filename);
    else if (entry.name.endsWith('.mjs')) run(process.execPath, ['--check', filename]);
  }
}

for (const directory of ['host', 'scripts', 'tests-bend']) await checkDirectory(directory);
run(process.execPath, ['scripts/import-stdlib.mjs', '--check']);
// Check the obligations even when a compiled kernel is already cached.
console.log(verifyProof({ cwd: root }));
run(compiler(), ['MAIN.bend', '--check-only']);
for (const filename of ['bootstrap.sh', 'setup-worktree.sh', 'install-bend.sh']) run('bash', ['-n', `scripts/${filename}`]);
console.log('Host syntax and Bend proof obligations check.');

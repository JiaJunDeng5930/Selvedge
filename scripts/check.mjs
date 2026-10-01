import { spawnSync } from 'node:child_process';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { compiler } from './toolchain.mjs';
import { build } from './build.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const syntax = new Bun.Transpiler({ loader: 'js' });

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

async function checkDirectory(directory) {
  for (const entry of await readdir(path.join(root, directory), { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) await checkDirectory(filename);
    else if (entry.name.endsWith('.mjs')) {
      const source = await readFile(path.join(root, filename), 'utf8');
      try {
        syntax.transformSync(source);
      } catch (error) {
        throw new Error(`JavaScript syntax check failed: ${filename}`, { cause: error });
      }
    }
  }
}

for (const directory of ['host', 'scripts', 'tests-bend', 'examples']) await checkDirectory(directory);
run(process.execPath, ['scripts/check-web-vendor.mjs']);
run(process.execPath, ['scripts/theory-index.mjs', 'check']);
// Build checks proof obligations and links both production Bend libraries, including cached builds.
await build();
run(compiler(), ['MAIN.bend', '--check-only']);
for (const filename of ['bootstrap.sh', 'setup-worktree.sh', 'install-bend.sh']) run('bash', ['-n', `scripts/${filename}`]);
console.log('Host syntax, Bend proof obligations, and production JavaScript libraries check.');

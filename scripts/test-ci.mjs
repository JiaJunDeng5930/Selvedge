import { readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
// NOTE: Repeated whole-program compiler mutations and extension builds belong to full validation.
const fullValidationOnly = new Set([
  'board-proof.test.mjs',
  'chatgpt-plugin-proof.test.mjs',
  'locality.test.mjs',
  'proof-gate.test.mjs',
  'reasoning-proof.test.mjs',
  'whole-program-proof.test.mjs',
]);
const files = (await readdir(new URL('../tests-bend/', import.meta.url)))
  .filter(name => name.endsWith('.test.mjs') && !fullValidationOnly.has(name))
  .sort().map(name => `tests-bend/${name}`);
console.log(`CI integration suite: ${files.length} files; ${fullValidationOnly.size} full-validation files deferred.`);
const result = spawnSync(process.execPath, ['--test', '--test-concurrency=1', ...files], {
  cwd: root, stdio: 'inherit',
});
if (result.error) throw result.error;
process.exit(result.status ?? 1);

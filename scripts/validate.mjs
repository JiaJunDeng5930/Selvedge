import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { check } from './check.mjs';
import { runTests } from './test.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
if (process.argv.length !== 2) throw new Error('Usage: bun scripts/validate.mjs');

// One invocation owns the checked build and consumes those same production assets.
await check();
await runTests();
const index = spawnSync(process.execPath, ['scripts/agents-index.mjs', 'check'], { cwd: root, stdio: 'inherit' });
if (index.error) throw index.error;
if (index.status !== 0) process.exitCode = index.status ?? 1;

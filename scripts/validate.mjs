import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { check } from './check.mjs';
import { runTests } from './test.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
// DEFENSE: A command-line caller can pass unsupported arguments; reject the invocation before running the build operation.
if (process.argv.length !== 2) throw new Error('Usage: bun scripts/validate.mjs');

// One invocation owns the checked build and consumes those same production assets.
await check();
await runTests();
const index = spawnSync(process.execPath, ['scripts/agents-index.mjs', 'check'], { cwd: root, stdio: 'inherit' });
// DEFENSE: The index checker can fail to start because the OS refuses its process.
if (index.error) throw index.error;
// DEFENSE: A failed or signalled index checker must fail the complete validation command.
if (index.status !== 0) process.exitCode = index.status ?? 1;

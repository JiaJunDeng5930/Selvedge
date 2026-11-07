import assert from 'node:assert/strict';
import { appendFileSync } from 'node:fs';

// This runs in the real approved subprocess, not in the service's test driver.
const [marker, workspace] = process.argv.slice(2);
assert.equal(process.cwd(), workspace);
appendFileSync(marker, 'ran\n');
process.stdout.write(JSON.stringify({ cwd: process.cwd() }));

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { home } from './support.mjs';

const execute = promisify(execFile);
const root = fileURLToPath(new URL('../', import.meta.url));

test('a browser startup failure stops the test command after a single launch', async t => {
  const directory = await home(t);
  const launcher = path.join(directory, 'chromium');
  const attempts = path.join(directory, 'launches');
  await writeFile(launcher, `#!/bin/sh
printf 'launch\n' >> "$SELVEDGE_TEST_LAUNCHES"
printf 'fixture browser startup failure\n' >&2
exit 19
`, { mode: 0o755 });

  await assert.rejects(execute(process.execPath, ['run', 'test',
    'ui-migration-boundaries.test.mjs', 'ui-settings-collections.test.mjs'], {
    cwd: root, timeout: 10000,
    env: { ...process.env, SELVEDGE_CHROMIUM_EXECUTABLE_PATH: launcher, SELVEDGE_TEST_LAUNCHES: attempts },
  }), error => {
    assert.equal(typeof error.code, 'number');
    assert.match(error.stderr, /Browser test setup failed before running the selected suite/);
    assert.match(error.stderr, /fixture browser startup failure/);
    assert.doesNotMatch(error.stdout, /Running Selvedge end-to-end tests/);
    return true;
  });
  assert.equal(await readFile(attempts, 'utf8'), 'launch\n');
});

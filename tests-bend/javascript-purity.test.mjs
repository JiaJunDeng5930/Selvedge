import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { compileJavaScriptBatch } from '../scripts/compile-javascript.mjs';

test('a checked prefix cannot admit an unchecked dependency introduced by a runtime entry', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-javascript-purity-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const prefix = path.join(directory, 'prefix.bend');
  const helper = path.join(directory, 'helper.bend');
  const entry = path.join(directory, 'entry.bend');
  const output = path.join(directory, 'output.mjs');
  await writeFile(prefix, 'import Base\n');
  await writeFile(helper, 'import Base\ndef value() -> Nat:\n  7n\n');
  await writeFile(entry, 'import Base\nimport ./helper.bend as Helper\ndef run() -> Nat:\n  Helper.value()\n');
  const compile = () => compileJavaScriptBatch({ prefix, verify: true,
    requests: [{ entry, output, sourceRoot: directory, exports: { run: 'run' } }] });
  await compile();
  const library = await import(pathToFileURL(output).href);
  assert.equal(library.run(), 7n);

  // The mutation still type-checks; only the compiler's promise verdict rejects
  // its unchecked recursion. Neither dependency belongs to the verified prefix.
  await writeFile(helper, 'import Base\n@unsafe def value() -> Nat:\n  value()\n');
  await assert.rejects(compile(), /JavaScript compilation refuses unchecked or foreign definitions:/);
});

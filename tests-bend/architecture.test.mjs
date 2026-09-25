import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

async function imports(filename, seen = new Set()) {
  if (seen.has(filename)) return seen;
  seen.add(filename);
  const source = await readFile(filename, 'utf8');
  for (const match of source.matchAll(/^import (\.[^\s]+\.bend)(?: as \w+)?$/gm)) {
    await imports(path.resolve(path.dirname(filename), match[1]), seen);
  }
  return seen;
}

test('the complete command, interaction and finite execution specifications do not depend on their implementation', async () => {
  const seen = new Set();
  for (const filename of ['COMMANDS.bend', 'bendlib/protocol.bend', 'bendlib/commit.bend', 'bendlib/execution.bend']) {
    await imports(path.join(root, filename), seen);
  }
  for (const filename of ['PROGRAM.bend', 'PROOF.bend', 'CONCEPTS.bend', 'MAIN.bend']) {
    assert.equal(seen.has(path.join(root, filename)), false, `Specification depends on ${filename}`);
  }
  const concepts = await readFile(path.join(root, 'CONCEPTS.bend'), 'utf8');
  assert.match(concepts, /Commit\.command\(~Execution\.scheduled,/);
  assert.match(concepts, /Commit\.input\(~Execution\.scheduled,/);
  assert.doesNotMatch(concepts, /Commit\.(command|input)\(~P\./);
});

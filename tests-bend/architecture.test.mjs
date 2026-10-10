import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bendSources, isProofSource } from '../scripts/check-components.mjs';

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
  for (const filename of ['harness/COMMANDS.bend', 'harness/protocol/PROGRAM.bend', 'harness/protocol/COMMIT.bend', 'harness/execution/PROGRAM.bend', 'harness/transport/MODEL.bend', 'harness/conversation/MODEL.bend',
    'features/board/SPEC.bend', 'features/board/scheduling-spec.bend', 'harness/conversation/CONTRACT.bend']) {
    await imports(path.join(root, filename), seen);
  }
  for (const filename of ['harness/PROGRAM.bend', 'PROOF.bend', 'CONCEPTS.bend', 'MAIN.bend', 'harness/transport/PROGRAM.bend', 'harness/CONTRACT.bend', 'harness/history/PROGRAM.bend',
    'features/board/PROGRAM.bend', 'features/board/scheduling.bend']) {
    assert.equal(seen.has(path.join(root, filename)), false, `Specification depends on ${filename}`);
  }
  const concepts = await readFile(path.join(root, 'harness/CONTRACT.bend'), 'utf8');
  assert.match(concepts, /Commit\.command\(~Execution\.scheduled,/);
  assert.match(concepts, /Commit\.input\(~Execution\.scheduled,/);
  assert.doesNotMatch(concepts, /Commit\.(command|input)\(~P\./);
  // Commit specifies UI decoration by its existing public projection. The
  // conversation content specification, unlike that commit interface, must be
  // independently defined without importing the renderer it constrains.
  const conversation = await imports(path.join(root, 'harness/conversation/CONTRACT.bend'));
  assert.equal(conversation.has(path.join(root, 'interaction/MODEL.bend')), false);
});

test('the native entry contains only IO and all pure runtime imports belong to the proof closure', async () => {
  const checked = await imports(path.join(root, 'PROOF.bend'));
  const runtime = await imports(path.join(root, 'MAIN.bend'));
  runtime.delete(path.join(root, 'MAIN.bend'));
  for (const filename of runtime) {
    assert.equal(checked.has(filename), true, `Runtime definition outside the proof closure: ${filename}`);
  }
  const source = await readFile(path.join(root, 'MAIN.bend'), 'utf8');
  const definitions = [...source.matchAll(/^(?:@unsafe )?def ([^\n]+):$/gm)];
  assert.ok(definitions.length > 0);
  for (const [, signature] of definitions) assert.match(signature, / -> IO\(/);
  assert.match(source, /Frontend\.packet\(tokens, world\)/);
});

test('the conceptual entry declares proof-carrying concepts rather than implementation functions', async () => {
  const source = await readFile(path.join(root, 'CONCEPTS.bend'), 'utf8');
  assert.doesNotMatch(source, /^(?:@unsafe )?def /m);
  assert.doesNotMatch(source, /M\.(World|Task)|J\.(Json|Field)|P\./);
  for (const name of ['Meaning', 'Composition', 'Recovery', 'Observation', 'Concurrency', 'Harness']) {
    assert.match(source, new RegExp(`type ${name} is Type:`));
  }
  assert.match(source, /law harness:\s+Harness/);
});

test('proof modules form an explicit acyclic dependency graph', async () => {
  const graph = new Map();
  for (const filename of (await bendSources(root)).filter(isProofSource)) {
    const source = await readFile(path.join(root, filename), 'utf8');
    const dependencies = [];
    for (const [, relative] of source.matchAll(/^import (\.[^\s]+\.bend) as (\w+)$/gm)) {
      const target = path.posix.normalize(path.posix.join(path.posix.dirname(filename), relative));
      if (isProofSource(target)) dependencies.push(target);
    }
    graph.set(filename, dependencies);
  }
  function visit(filename, active = new Set(), complete = new Set()) {
    assert.equal(active.has(filename), false, `Cyclic proof module dependency: ${filename}`);
    if (complete.has(filename)) return;
    assert.ok(graph.has(filename), `Missing proof provider: ${filename}`);
    active.add(filename);
    for (const next of graph.get(filename)) visit(next, active, complete);
    active.delete(filename);
    complete.add(filename);
  }
  for (const filename of graph.keys()) visit(filename);
});

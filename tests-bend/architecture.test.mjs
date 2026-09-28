import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
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
  for (const filename of ['COMMANDS.bend', 'bendlib/protocol.bend', 'bendlib/commit.bend', 'bendlib/execution.bend', 'bendlib/interface.bend', 'bendlib/transcript.bend',
    'bendlib/board-spec.bend', 'bendlib/board-scheduling-spec.bend']) {
    await imports(path.join(root, filename), seen);
  }
  for (const filename of ['PROGRAM.bend', 'PROOF.bend', 'CONCEPTS.bend', 'MAIN.bend', 'bendlib/frontend.bend', 'bendlib/architecture.bend', 'bendlib/traces.bend',
    'bendlib/board.bend', 'bendlib/board-scheduling.bend']) {
    assert.equal(seen.has(path.join(root, filename)), false, `Specification depends on ${filename}`);
  }
  const concepts = await readFile(path.join(root, 'bendlib/architecture.bend'), 'utf8');
  assert.match(concepts, /Commit\.command\(~Execution\.scheduled,/);
  assert.match(concepts, /Commit\.input\(~Execution\.scheduled,/);
  assert.doesNotMatch(concepts, /Commit\.(command|input)\(~P\./);
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

test('proof modules form an explicit acyclic graph and consume public laws rather than sibling helpers', async () => {
  const directory = path.join(root, 'bendlib/proofs');
  const graph = new Map();
  for (const filename of await readdir(directory)) {
    if (!filename.endsWith('.bend')) continue;
    const source = await readFile(path.join(directory, filename), 'utf8');
    const dependencies = [];
    for (const [, relative, alias] of source.matchAll(/^import (\.\/[^\s]+\.bend) as (\w+)$/gm)) {
      dependencies.push(path.basename(relative));
      assert.doesNotMatch(source, new RegExp(`\\b${alias}\\.`), 'Sibling evidence must be consumed through declared laws');
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

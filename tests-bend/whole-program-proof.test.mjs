import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

test('whole-program proofs reject type-correct loss of input, durability and trace receipts', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-whole-program-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const filename of await readdir(root)) {
    if (filename.endsWith('.bend')) await cp(path.join(root, filename), path.join(directory, filename));
  }
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const check = filename => spawnSync(compiler(), [filename, '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
  const baseline = check('PROOF.bend');
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  for (const [filename, before, after, law] of [
    ['bendlib/frontend.bend', 'P.reject(world, "invalid_json", reason), False{}', 'P.reject(world, "invalid_json", reason), True{}', /frontend_json/],
    ['bendlib/frontend.bend', 'json(J.decode(tokens), world)', 'json(J.decode(Nil{}), world)', /frontend_packet/],
    ['bendlib/traces.bend', 'Spec.record(P.transition(input, world), pending, receipts)', 'Spec.record(P.transition(input, world), pending, Nil{})', /trace_step/],
    ['bendlib/traces.bend', 'Std.iter(~Spec.Tape, ~implementation, count, tape)', 'Std.iter(~Spec.Tape, ~implementation, 0n, tape)', /trace_refinement|trace_partition|trace_interpretation/],
    ['PROGRAM.bend', 'Theory.replay(~M.World, ~M.Input, ~next, events, world)', 'Theory.replay(~M.World, ~M.Input, ~next, Nil{}, world)', /trace_interpretation|trace_cons/],
  ]) {
    const target = path.join(directory, filename);
    const original = await readFile(target, 'utf8');
    assert.equal(original.split(before).length, 2);
    try {
      await writeFile(target, original.replace(before, after));
      // Use the production root for relative-module identity. Checking a nested
      // module as a different project root is not a type-correctness comparison.
      await writeFile(path.join(directory, 'TYPECHECK.bend'), `import ./${filename} as Subject\n`);
      const wellTyped = check('TYPECHECK.bend');
      assert.equal(wellTyped.error, undefined);
      assert.equal(wellTyped.status, 0, wellTyped.stdout + wellTyped.stderr);
      const rejected = check('PROOF.bend');
      assert.equal(rejected.error, undefined);
      assert.notEqual(rejected.status, 0, `The proof accepted ${after}`);
      assert.match(rejected.stdout + rejected.stderr, law);
    } finally { await writeFile(target, original); }
  }
});

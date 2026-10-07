import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { translateRelations } from '../scripts/import-relations.mjs';
import { compiler } from '../scripts/toolchain.mjs';

const bundle = JSON.parse(await readFile(new URL('../theory/relation-certificates.json', import.meta.url), 'utf8'));

test('relation theory reproduces original dependencies and explicit applications without Rocq at build time', async () => {
  assert.equal(bundle.stdlib, '9.2.0');
  assert.equal(bundle.metarocq, '1.5.1+9.2');
  for (const source of ['Corelib.Relations.Relation_Definitions', 'Stdlib.Relations.Relation_Operators', 'Stdlib.Relations.Operators_Properties']) {
    assert.match(bundle.sources[source], /^[a-f0-9]{64}$/);
  }
});

test('relation translation rejects unknown proof syntax, arbitrary inductives and changed eliminator recursion', () => {
  for (const term of [
    ['const', 'Untrusted.axiom'], ['ind', 'Untrusted.Closure', 0],
    ['ctor', 'Stdlib.Relations.Relation_Operators.clos_refl_trans', 0, 3],
    ['ctor', 'Stdlib.Relations.Relation_Operators.clos_refl_trans', 0, -1],
    ['unsupported', 'a missing proof'], ['rel', 999], ['sort', 'SProp'],
  ]) {
    const entities = structuredClone(bundle.entities);
    entities[5][2] = term;
    assert.throws(() => translateRelations(entities), /Unmapped|Unsupported|Unbound/);
  }
  const entities = structuredClone(bundle.entities);
  let changed = false;
  function visit(node) {
    if (!Array.isArray(node)) return;
    if (node[0] === 'fix') { node[2][0][3] = 0; changed = true; }
    else node.forEach(visit);
  }
  visit(entities[2][2]);
  assert.equal(changed, true);
  assert.throws(() => translateRelations(entities), /structural recursion on a path/);
});

test('Bend checks the actual imported closure branches and rejects invented reachability evidence', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-relations-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const source = translateRelations(bundle.entities);
  const baseline = path.join(directory, 'relations.bend');
  await writeFile(baseline, source);
  const checked = spawnSync(compiler(), [baseline, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  assert.equal(checked.stdout.trim(), 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.');
  const mutants = [
    ['wrong-reflexive-endpoint', source.replace('same: {x == y : A}', 'same: {x == x : A}')],
    ['wrong-transitive-middle', source.replace('left: Closure<A, R, x, middle>', 'left: Closure<A, R, x, x>')],
    ['unrelated-step', source.replace('edge: R(x, y)', 'edge: R(x, x)')],
  ];
  for (const name of ['clos_rt_idempotent', 'closure_map', 'closure_invariant']) {
    const start = source.indexOf(`def ${name}(`);
    const body = source.indexOf(':\n', start) + 2;
    const next = source.indexOf('\n# ', body);
    assert.ok(start >= 0 && body > start);
    mutants.push([name, source.slice(0, body) + '  {==}\n' + (next < 0 ? '' : source.slice(next))]);
  }
  for (const [name, mutant] of mutants) {
    assert.notEqual(mutant, source);
    const filename = path.join(directory, `${name}.bend`);
    await writeFile(filename, mutant);
    const rejected = spawnSync(compiler(), [filename, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
    assert.equal(rejected.error, undefined);
    assert.notEqual(rejected.status, 0, `${name} must not certify the production protocol`);
  }
});


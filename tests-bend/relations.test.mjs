import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { translateRelations } from '../scripts/import-relations.mjs';

const bundle = JSON.parse(await readFile(new URL('../theory/relation-certificates.json', import.meta.url), 'utf8'));

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

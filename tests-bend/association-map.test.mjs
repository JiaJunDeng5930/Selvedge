import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { translateMaps } from '../scripts/import-maps.mjs';

const bundle = JSON.parse(await readFile(new URL('../theory/rocq-maps.json', import.meta.url), 'utf8'));

test('the bridge rejects unquoted axioms, altered reflection premises and changed source statements', () => {
  for (const index of [0, 1, 2, 3, 4, 5, 6, 7]) {
    const entities = structuredClone(bundle.entities);
    entities[index][2] = ['const', 'Untrusted.claim'];
    assert.throws(() => translateMaps(entities), /Unmapped/);
  }
  for (const [index, field, replacement] of [
    [3, 1, ['sort', 'Prop']], [4, 1, ['sort', 'Prop']],
    [5, 2, ['ctor', 'Corelib.Init.Datatypes.bool', 0, 0]],
    [6, 2, ['ctor', 'Corelib.Init.Datatypes.bool', 0, 0]],
    [7, 2, ['ctor', 'Corelib.Init.Datatypes.bool', 0, 0]],
  ]) {
    const entities = structuredClone(bundle.entities);
    entities[index][field] = replacement;
    assert.throws(() => translateMaps(entities), /Association-map certificate/);
  }
});

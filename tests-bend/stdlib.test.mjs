import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { translate } from '../scripts/import-stdlib.mjs';

const bundle = JSON.parse(await readFile(new URL('../theory/stdlib-certificates.json', import.meta.url), 'utf8'));

test('certificate translation fails closed on unmapped constants, inductives, and syntax', () => {
  for (const term of [
    ['const', 'Untrusted.axiom'], ['ind', 'Untrusted.Type', 0],
    ['unsupported', 'a missing proof'], ['sort', 'SProp'], ['rel', 500],
  ]) {
    const entities = structuredClone(bundle.entities);
    entities[1][2] = term;
    assert.throws(() => translate(entities), /Unmapped|Unsupported|Unbound/);
  }
});

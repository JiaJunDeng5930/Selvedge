import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { checkMaps, mapNames, translateMaps } from '../scripts/import-maps.mjs';
import { compiler } from '../scripts/toolchain.mjs';

const bundle = JSON.parse(await readFile(new URL('../theory/rocq-maps.json', import.meta.url), 'utf8'));

test('the association-map bridge reproduces pinned original definitions and proof without the source prover', async () => {
  await checkMaps();
  assert.deepEqual(bundle.entities.map(([name]) => name), mapNames);
  assert.equal(bundle.extlib, '0.13.1');
  assert.equal(bundle.stdlib, '9.2.0');
  for (const name of ['ExtLib/Data/Map/FMapAList', 'ExtLib/Core/RelDec', 'ExtLib/Tactics/Consider', 'Stdlib/Lists/List']) {
    assert.match(bundle.sources[name], /^[a-f0-9]{64}$/);
  }
});

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

test('the target checker rejects a corrupted imported deletion proof rather than trusting the source label', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-association-certificate-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const check = async (name, source) => {
    const filename = path.join(directory, name + '.bend');
    await writeFile(filename, source);
    const result = spawnSync(compiler(), [filename, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
    assert.equal(result.error, undefined);
    return result;
  };
  const source = translateMaps(bundle.entities);
  const valid = await check('valid', source);
  assert.equal(valid.status, 0, valid.stdout + valid.stderr);
  assert.equal(valid.stdout.trim(), 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.');
  for (const [name, before, after] of [
    ['forged-proof', 'case True{}: induction', 'case True{}: {==}'],
    ['incorrect-removal', 'case False{}: tail\n\ndef remove', 'case False{}: (key, value) <> tail\n\ndef remove'],
  ]) {
    assert.equal(source.split(before).length, 2, name);
    const rejected = await check(name, source.replace(before, after));
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stdout + rejected.stderr, /Location: absence_case/);
  }
});

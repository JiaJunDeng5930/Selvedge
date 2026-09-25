import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { checkBundle, translate } from '../scripts/import-stdlib.mjs';
import { compiler } from '../scripts/toolchain.mjs';

const bundle = JSON.parse(await readFile(new URL('../theory/stdlib-certificates.json', import.meta.url), 'utf8'));

test('standard algebra certificates reproduce the saved Bend proof terms without invoking Rocq', async () => {
  await checkBundle();
  assert.equal(translate(bundle.entities), await readFile(new URL('../bendlib/stdlib.bend', import.meta.url), 'utf8'));
  assert.equal(bundle.stdlib, '9.2.0');
  assert.equal(bundle.metarocq, '1.5.1+9.2');
  assert.match(bundle.sources['Corelib.Init.Datatypes'], /^[a-f0-9]{64}$/);
  assert.match(bundle.sources['Stdlib.Lists.List'], /^[a-f0-9]{64}$/);
  assert.match(bundle.sources['Corelib.Init.Nat'], /^[a-f0-9]{64}$/);
  assert.match(bundle.sources['Stdlib.Arith.PeanoNat'], /^[a-f0-9]{64}$/);
  for (const name of ['iter_swap_gen', 'iter_add', 'iter_ind']) {
    assert.ok(bundle.entities.some(([entity]) => entity === `Stdlib.Arith.PeanoNat.Nat.${name}`));
  }
});

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

test('Bend rejects a well-formed foreign certificate that replaces an existing proof with reflexivity', async t => {
  const entities = structuredClone(bundle.entities);
  const list = ['ind', 'Corelib.Init.Datatypes.list', 0];
  entities[1][2] = ['lam', 'A', ['sort', 'Type'],
    ['lam', 'l', ['app', list, [['rel', 0]]],
      ['app', ['ctor', 'Corelib.Init.Logic.eq', 0, 0], [
        ['app', list, [['rel', 1]]], ['rel', 0],
      ]]]];
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-foreign-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filename = path.join(directory, 'corrupt.bend');
  await writeFile(filename, translate(entities));
  const rejected = spawnSync(compiler(), [filename, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
  assert.equal(rejected.error, undefined);
  assert.notEqual(rejected.status, 0, 'A source manifest is not a trusted proof oracle');
  assert.match(rejected.stdout + rejected.stderr, /app_nil_r/);
});

test('the original map certificates reject a correspondence that silently drops all elements', async t => {
  const source = translate(bundle.entities);
  const corrupted = source.replace('f(item) <> tail', 'tail');
  assert.notEqual(corrupted, source);
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-map-correspondence-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filename = path.join(directory, 'corrupt-map.bend');
  await writeFile(filename, corrupted);
  const rejected = spawnSync(compiler(), [filename, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
  assert.equal(rejected.error, undefined);
  assert.notEqual(rejected.status, 0, 'An append-preserving empty map is not the required standard map');
  assert.match(rejected.stdout + rejected.stderr, /Location: map_(app|map|id)/);
});

test('the imported natural-number eliminator cannot replace every successor proof with its zero proof', async t => {
  const source = translate(bundle.entities);
  const corrupted = source.replace(/(case 1n\+\w+: )S_\d+\([^\n]*/, '$1O_2');
  assert.notEqual(corrupted, source);
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-nat-certificate-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const filename = path.join(directory, 'corrupt-nat.bend');
  await writeFile(filename, corrupted);
  const rejected = spawnSync(compiler(), [filename, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
  assert.equal(rejected.error, undefined);
  assert.notEqual(rejected.status, 0, 'Finite-run composition must use the actual imported induction step');
  assert.match(rejected.stdout + rejected.stderr, /Location: nat_ind/);
});

test('original finite-run certificates reject dropped steps and fabricated theorem proofs', async t => {
  const source = translate(bundle.entities);
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-iteration-certificates-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const mutants = [['a stationary iterator', source.replace('f(iter(~A, ~f, rest, seed))', 'iter(~A, ~f, rest, seed)')]];
  for (const name of ['iter_swap_gen', 'iter_add', 'iter_ind']) {
    const start = source.indexOf(`def ${name}(`);
    assert.notEqual(start, -1);
    const body = source.indexOf(':\n', start) + 2;
    const next = source.indexOf('\n# Imported proof term:', body);
    mutants.push([name, source.slice(0, body) + '  {==}\n' + (next < 0 ? '' : source.slice(next))]);
  }
  for (const [name, corrupted] of mutants) {
    assert.notEqual(corrupted, source);
    const filename = path.join(directory, `${name.replaceAll(' ', '-')}.bend`);
    await writeFile(filename, corrupted);
    const rejected = spawnSync(compiler(), [filename, '--check-only'], { encoding: 'utf8', timeout: 10_000 });
    assert.equal(rejected.error, undefined);
    assert.notEqual(rejected.status, 0, `${name} must not certify the production trace`);
    assert.match(rejected.stdout + rejected.stderr, /Location: iter_(swap_gen|add|ind)/);
  }
});

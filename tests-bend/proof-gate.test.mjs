import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, readdir, cp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compiler } from '../scripts/toolchain.mjs';

const bend = compiler();

test('the installed proof gate rejects both missing and false proofs', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-proof-gate-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'LAWS.bend'), 'import Base\nlaw impossible:\n  {True{} == False{} : Bool}\n');
  for (const [proof, diagnostic] of [
    ['import ./LAWS.bend as Laws\n', /TODO found[\s\S]*not a valid proof/],
    ['import Base\nimport ./LAWS.bend as Laws\ndef Laws.impossible():\n  {==}\n', /True[\s\S]*False|False[\s\S]*True/],
  ]) {
    await writeFile(path.join(directory, 'PROOF.bend'), proof);
    const result = spawnSync(bend, ['PROOF.bend', '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0, 'An unproved or false requirement must fail the build gate');
    assert.match(result.stdout + result.stderr, diagnostic);
  }
});

test('bypassing production admission invalidates the transition theorem', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-proof-mutation-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const filename of await readdir(root)) {
    if (filename.endsWith('.bend')) await cp(path.join(root, filename), path.join(directory, filename));
  }
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const check = () => spawnSync(bend, ['PROOF.bend', '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
  const baseline = check();
  assert.equal(baseline.error, undefined);
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  const filename = path.join(directory, 'PROGRAM.bend');
  const source = await readFile(filename, 'utf8');
  const changed = source.replace(/(def admitted\([^\n]*\) -> M\.Decision:\n)[\s\S]*?(?=\ndef check_live)/, '$1  decision\n');
  assert.notEqual(changed, source, 'The mutation must remove the production admission check');
  await writeFile(filename, changed);
  const rejected = check();
  assert.equal(rejected.error, undefined);
  assert.notEqual(rejected.status, 0, 'The same proof must reject an implementation that bypasses admission');
  assert.match(rejected.stdout + rejected.stderr, /admitted_certificate/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

test('the installed proof gate rejects both missing and false proofs', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-proof-gate-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'LAWS.bend'), 'import Base\nlaw impossible:\n  {True{} == False{} : Bool}\n');
  for (const [proof, diagnostic] of [
    ['import ./LAWS.bend as Laws\n', /TODO found[\s\S]*not a valid proof/],
    ['import Base\nimport ./LAWS.bend as Laws\ndef Laws.impossible():\n  {==}\n', /True[\s\S]*False|False[\s\S]*True/],
  ]) {
    await writeFile(path.join(directory, 'PROOF.bend'), proof);
    const result = spawnSync('bend', ['PROOF.bend', '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0, 'An unproved or false requirement must fail the build gate');
    assert.match(result.stdout + result.stderr, diagnostic);
  }
});

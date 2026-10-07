import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm, readdir, cp, readFile } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { verifyProof, verifyNativeEntry } from '../scripts/verify-proof.mjs';

test('the shared proof gate accepts pure evidence and rejects unsafe or circular evidence', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-pure-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'LAWS.bend'), 'import Base\nlaw fact:\n  {True{} == True{} : Bool}\n');
  const filename = path.join(directory, 'PROOF.bend');
  await writeFile(filename, 'import Base\nimport ./LAWS.bend as L\ndef L.fact():\n  {==}\n');
  assert.equal(verifyProof({ cwd: directory, entry: 'PROOF.bend' }), 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.');
  for (const body of [
    'import Base\nimport ./LAWS.bend as L\n@unsafe def unchecked() -> {True{} == True{} : Bool}:\n  unchecked()\ndef L.fact():\n  unchecked()\n',
    'import Base\nimport ./LAWS.bend as L\ndef L.fact():\n  L.fact()\n',
  ]) {
    await writeFile(filename, body);
    assert.throws(() => verifyProof({ cwd: directory, entry: 'PROOF.bend', timeout: 10_000 }), error =>
      error.message.startsWith('Pure proof gate rejected') && error.cause === undefined);
  }
});

test('the native entry gate accepts only the production IO assumptions and rejects extra promises or type errors', { timeout: 180_000 }, async t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-native-entry-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const name of await readdir(root)) if (name.endsWith('.bend')) await cp(path.join(root, name), path.join(directory, name));
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  for (const name of ['core', 'webui']) await cp(path.join(root, name), path.join(directory, name), { recursive: true });
  await cp(path.join(root, 'host'), path.join(directory, 'host'), { recursive: true, filter: source => !source.includes(`${path.sep}public`) });
  assert.equal(verifyNativeEntry({ cwd: directory }), 'Native entry types check with the declared IO assumptions.');
  const filename = path.join(directory, 'MAIN.bend');
  const original = await readFile(filename, 'utf8');
  for (const addition of [
    '\n@unsafe def undeclared_assumption() -> Bool:\n  True{}\n',
    '\ndef invalid_type() -> Bool:\n  0u\n',
  ]) {
    await writeFile(filename, original + addition);
    assert.throws(() => verifyNativeEntry({ cwd: directory }), error =>
      error.message.startsWith('Native entry gate rejected') && error.cause === undefined);
  }
});

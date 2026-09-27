import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { verifyProof } from '../scripts/verify-proof.mjs';

test('the shared proof gate accepts pure evidence and rejects unsafe or circular evidence', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-pure-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'LAWS.bend'), 'import Base\nlaw fact:\n  {True{} == True{} : Bool}\n');
  const filename = path.join(directory, 'PROOF.bend');
  await writeFile(filename, 'import Base\nimport ./LAWS.bend as L\ndef L.fact():\n  {==}\n');
  assert.equal(verifyProof({ cwd: directory }), 'All terms check.');
  for (const body of [
    'import Base\nimport ./LAWS.bend as L\n@unsafe def unchecked() -> {True{} == True{} : Bool}:\n  unchecked()\ndef L.fact():\n  unchecked()\n',
    'import Base\nimport ./LAWS.bend as L\ndef L.fact():\n  L.fact()\n',
  ]) {
    await writeFile(filename, body);
    assert.throws(() => verifyProof({ cwd: directory, timeout: 10_000 }), error =>
      error.message.startsWith('Pure proof gate rejected') && error.cause === undefined);
  }
});

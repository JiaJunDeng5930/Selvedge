import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { prepareUiVerification } from '../scripts/ui-verification.mjs';

test('the source gate imports a referenced UI law provider before its consumer', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'selvedge-ui-verification-'));
  const write = (filename, source) => {
    const target = path.join(root, filename);
    mkdirSync(path.dirname(target), { recursive: true });
    writeFileSync(target, source);
  };
  try {
    write('PROOF.bend', 'import Base\n');
    write('BROWSER.bend', 'import Base\n');
    write('browser/sample/CONTRACT.bend', 'import Base\nlaw alpha:\n  {True{} == True{} : Bool}\nlaw beta:\n  {True{} == True{} : Bool}\n');
    write('browser/sample/z-provider-proof.bend', 'import Base\nimport ./CONTRACT.bend as Rule\ndef Rule.alpha():\n  {==}\n');
    write('browser/sample/a-consumer-proof.bend', 'import Base\nimport ./CONTRACT.bend as Rule\ndef Rule.beta():\n  Rule.alpha()\n');
    const { entry } = prepareUiVerification(root);
    const imports = readFileSync(path.join(root, entry), 'utf8').split('\n');
    const provider = imports.findIndex(line => line.startsWith('import ../browser/sample/z-provider-proof.bend as '));
    const consumer = imports.findIndex(line => line.startsWith('import ../browser/sample/a-consumer-proof.bend as '));
    assert.ok(provider >= 0 && consumer > provider, imports.join('\n'));
  } finally { rmSync(root, { recursive: true, force: true }); }
});

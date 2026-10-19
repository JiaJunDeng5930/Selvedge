import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { checkUiLawProviders, prepareUiVerification } from '../scripts/ui-verification.mjs';

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
    symlinkSync('BROWSER.bend', path.join(root, 'browser-entry.txt'));
    // Construction evidence is executable code and needs no extra facade law.
    write('browser/sample/MODEL.bend', `import Base
import ./a-consumer-proof.bend as Consumer
type Requirements is Type:
  Requirements{reflexive: {True{} == True{} : Bool}}
def constructed() -> Requirements:
  Requirements{{==}}
def reflexive() -> {True{} == True{} : Bool}:
  {==}
law inline:
  {True{} == True{} : Bool}
def inline():
  Consumer.dependent()
`);
    write('browser/sample/CONTRACT.bend', 'import Base\nlaw alpha:\n  {True{} == True{} : Bool}\nlaw beta:\n  {True{} == True{} : Bool}\n');
    write('browser/sample/z-provider-proof.bend', 'import Base\nimport ./CONTRACT.bend as Rule\ndef Rule.alpha():\n  {==}\n');
    write('browser/sample/a-consumer-proof.bend', 'import Base\nimport ./CONTRACT.bend as Rule\ndef Rule.beta():\n  Rule.alpha()\ndef dependent() -> {True{} == True{} : Bool}:\n  Rule.beta()\n');
    const { entry } = prepareUiVerification(root);
    const imports = readFileSync(path.join(root, entry), 'utf8').split('\n');
    const provider = imports.findIndex(line => line.startsWith('import ../browser/sample/z-provider-proof.bend as '));
    const consumer = imports.findIndex(line => line.startsWith('import ../browser/sample/a-consumer-proof.bend as '));
    const inline = imports.findIndex(line => line.startsWith('import ../browser/sample/MODEL.bend as '));
    assert.ok(provider >= 0 && consumer > provider && inline > consumer, imports.join('\n'));
    write('browser/sample/z-provider-proof.bend', 'import Base\nimport ./CONTRACT.bend as Rule\n');
    assert.throws(() => checkUiLawProviders(root), /UI proof does not fill its rule law: browser\/sample\/CONTRACT.bend:alpha/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { checkUiSeparation, prepareUiVerification } from '../scripts/ui-verification.mjs';

const firstRule = 'browser/sample/first-laws.bend';
const secondRule = 'browser/sample/second-rules.bend';
const ownerImports = 'import Base\nimport ./first-laws.bend as First\nimport ./second-rules.bend as Second\n';
const laws = ['First.alpha', 'First.beta', 'Second.gamma', 'Second.delta'];

function binding(law, body = '{==}') {
  return `def ${law}():\n  ${body}\n`;
}

function fixture(run) {
  const root = mkdtempSync(path.join(tmpdir(), 'selvedge-ui-verification-'));
  function write(filename, source) {
    const target = path.join(root, filename);
    mkdirSync(path.dirname(target), { recursive: true });
    writeFileSync(target, source);
  }
  try {
    write('PROOF.bend', 'import Base\n');
    write('BROWSER.bend', 'import Base\n');
    write(firstRule, 'import Base\nlaw alpha:\n  {True{} == True{} : Bool}\nlaw beta:\n  {True{} == True{} : Bool}\n');
    write(secondRule, 'import Base\nlaw gamma:\n  {True{} == True{} : Bool}\nlaw delta:\n  {True{} == True{} : Bool}\n');
    run({ root, write });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function rejectsSeparation(root, reason) {
  assert.throws(() => checkUiSeparation(root), error => {
    assert.ok(error.message.startsWith('UI verification separation failed:\n'));
    assert.ok(error.message.split('\n').some(line => line.startsWith(reason)), error.message);
    return true;
  });
}

test('UI laws can be split across providers or merged in the concept proof', () => {
  fixture(({ root, write }) => {
    const providers = ['browser/sample/one-proof.bend', 'browser/sample/two-proof.bend'];
    write(providers[0], ownerImports + binding(laws[0]) + binding(laws[2]));
    write(providers[1], ownerImports + binding(laws[1]) + binding(laws[3]));
    const discovered = checkUiSeparation(root);
    assert.ok(Array.isArray(discovered));
    assert.deepEqual(discovered, [firstRule, secondRule, ...providers].sort());
  });
  fixture(({ root, write }) => {
    write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join(''));
    assert.deepEqual(checkUiSeparation(root), ['browser/sample/PROOF.bend', firstRule, secondRule].sort());
  });
});

test('UI laws require exactly one binding, including within a single provider', () => {
  for (const missing of laws) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.filter(law => law !== missing).map(law => binding(law)).join(''));
      const [alias, name] = missing.split('.');
      rejectsSeparation(root, `UI proof does not fill its rule law: ${alias === 'First' ? firstRule : secondRule}:${name}`);
    });
  }
  for (const sameFile of [false, true]) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join('') + (sameFile ? binding(laws[0]) : ''));
      if (!sameFile) write('browser/sample/extra-proof.bend', ownerImports + binding(laws[0]));
      rejectsSeparation(root, `UI rule law has multiple proof providers: ${firstRule}:alpha:`);
    });
  }
});

test('UI verification imports the actual referenced law provider before its consumer', () => {
  fixture(({ root, write }) => {
    const provider = 'browser/sample/z-provider-proof.bend';
    const consumer = 'browser/sample/a-consumer-proof.bend';
    write(provider, ownerImports + binding(laws[0]) + binding(laws[2]));
    write(consumer, ownerImports + binding(laws[1], 'First.alpha()') + binding(laws[3], 'Second.gamma()'));
    const prepared = prepareUiVerification(root);
    const imports = readFileSync(path.join(root, prepared.entry), 'utf8').split('\n');
    const providerIndex = imports.findIndex(line => line.startsWith(`import ../${provider} as `));
    const consumerIndex = imports.findIndex(line => line.startsWith(`import ../${consumer} as `));
    assert.ok(providerIndex >= 0);
    assert.ok(consumerIndex > providerIndex);
  });
});

test('UI models and rules cannot import proofs transitively or implement evidence', () => {
  for (const source of ['model', 'rule']) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join(''));
      write('shared/bridge.bend', 'import Base\nimport ../browser/sample/PROOF.bend as Evidence\n');
      const filename = source === 'model' ? 'browser/sample/MODEL.bend' : firstRule;
      const declarations = source === 'rule' ? 'law alpha:\n  {True{} == True{} : Bool}\nlaw beta:\n  {True{} == True{} : Bool}\n' : '';
      write(filename, 'import Base\nimport ../../shared/bridge.bend as Bridge\n' + declarations);
      rejectsSeparation(root, `UI model/rule imports a proof provider: ${filename} -> browser/sample/PROOF.bend`);
    });
  }
  for (const [source, reason] of [
    [ownerImports + binding(laws[0]), 'UI law implementation outside proofs:'],
    ['import Base\ndef evidence() -> {True{} == True{} : Bool}:\n  {==}\n', 'UI equality witness outside proofs:'],
  ]) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join(''));
      write('browser/sample/MODEL.bend', source);
      rejectsSeparation(root, reason);
    });
  }
});

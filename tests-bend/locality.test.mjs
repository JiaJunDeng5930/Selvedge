import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { auditComponents } from '../scripts/check-components.mjs';

test('source ownership scanning distinguishes multiline patterns from comments and strings', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-source-ownership-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const write = (name, source) => writeFile(path.join(directory, name), source);
  const imports = 'import Base\nimport ./core.bend as Core\nimport ./alphabet.bend as Feature\n';
  await Promise.all([
    write('core.bend', 'import Base\ntype State is Data:\n  State{value: Nat}\n'),
    write('alphabet.bend', 'import Base\ntype Command is Data:\n  Add{value: Nat}\n'),
    write('PROOF.bend', 'import Base\nimport ./client.bend as Client\n'),
    write('client.bend', imports + `
# Core.State{value} and case Feature.Add{value}: are inert here.
def text() -> String:
  "Core.State{value} case Feature.Add{value}:"
`),
    write('components.json', JSON.stringify({
      version: 2,
      core_roots: ['core.bend'],
      core_forbidden_dependencies: ['alphabet.bend'],
      feature_alphabet: 'alphabet.bend',
      feature_alphabet_types: ['Command'],
      feature_match_owners: ['alphabet.bend'],
      model_representations: [{ module: 'core.bend', constructors: ['State'], owners: ['core.bend'] }],
      proof_root: 'PROOF.bend',
      runtime_roots: ['client.bend'],
      foreign_sources: {},
    })),
  ]);
  await symlink('core.bend', path.join(directory, 'source-link.txt'));
  assert.equal((await auditComponents(directory)).ok, true);

  await write('client.bend', imports + `
def private_state(state: Core.State) -> Nat:
  Core.State{
    value} = state
  value

def feature_value(command: Feature.Command) -> Nat:
  match command:
    case Feature.Add{
      value}: value
`);
  const { errors } = await auditComponents(directory);
  assert.equal(errors.length, 2);
  assert.ok(errors.some(error => error.includes('Model representation outside its owner boundary: client.bend:')));
  assert.ok(errors.some(error => error.includes('Feature pattern outside its component/assembly boundary: client.bend:')));

  // Adding an independent helper needs no copy of the current import graph.
  await write('helper.bend', 'import Base\n');
  await write('core.bend', 'import Base\nimport ./helper.bend as Helper\ntype State is Data:\n  State{value: Nat}\n');
  await write('client.bend', imports);
  assert.equal((await auditComponents(directory)).ok, true);
  // The same helper must not smuggle a feature dependency into the core.
  await write('helper.bend', 'import Base\nimport ./alphabet.bend as Feature\n');
  assert.ok((await auditComponents(directory)).errors.some(error =>
    error.includes('Core depends on application assembly or feature ownership: core.bend -> alphabet.bend')));
  await write('helper.bend', 'import Base\n');
  await write('PROOF.bend', 'import Base\n');
  assert.ok((await auditComponents(directory)).errors.includes('Pure production module outside proof closure: helper.bend'));
});

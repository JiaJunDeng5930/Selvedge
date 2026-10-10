import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bend = path.join(root, '.build/bend/bin/bend');

const vocabulary = `import Base
import ../../bendlib/categories.bend as Categories

def positive(value: Nat) -> Bool:
  match value:
    case 0n: False{}
    case 1n+rest: True{}

def bounded(value: Nat) -> Bool:
  match value:
    case 0n: True{}
    case 1n+rest:
      match rest:
        case 0n: True{}
        case 1n+more: False{}

def apply(-A: Nat -> Type, -B: Nat -> Type, inclusion: Categories.Inclusion<Nat, A, B>, -value: Nat, evidence: A(value)) -> B(value):
  Categories.Inclusion{derive} = inclusion
  derive(value, evidence)

def positive_consumer(-value: Nat, -evidence: Categories.holds(Nat, positive, value)) -> Bool:
  True{}

def bounded_consumer(-value: Nat, -evidence: Categories.holds(Nat, bounded, value)) -> Bool:
  True{}
`;
const intersection = '(value => Categories.intersection(Nat, Categories.holds(Nat, positive), Categories.holds(Nat, bounded), value))';
const member = `Categories.Membership<Nat, ${intersection}>`;
const admission = `Maybe<&1, ${member}>`;

const client = `${vocabulary}
def consume(member: ${member}) -> Bool:
  Categories.Membership{value, Categories.Intersection{first, second}} = member
  a = positive_consumer(value, apply(Categories.holds(Nat, positive), Categories.holds(Nat, positive), Categories.inclusion_identity(Nat, Categories.holds(Nat, positive)), value, first))
  b = bounded_consumer(value, second)
  Bool.and(a, b)

def consume_projected(member: ${member}) -> Bool:
  Categories.Membership{value, evidence} = member
  bounded_consumer(value, apply(${intersection}, Categories.holds(Nat, bounded), Categories.intersection_second(Nat, Categories.holds(Nat, positive), Categories.holds(Nat, bounded)), value, evidence))

def admitted(result: ${admission}) -> Bool:
  match result:
    case Some{member}: consume(member)
    case None{}: False{}

def projected(result: ${admission}) -> Bool:
  match result:
    case Some{member}: consume_projected(member)
    case None{}: False{}

def extracted(result: ${admission}) -> Bool:
  match result:
    case Some{member}: positive(Categories.value(Nat, ${intersection}, member))
    case None{}: False{}

def rejected(result: ${admission}) -> Bool:
  match result:
    case Some{member}: False{}
    case None{}: True{}

def main() -> Bool:
  Bool.and(admitted(Categories.admit_intersection(Nat, positive, bounded, 1n)),
    Bool.and(projected(Categories.admit_intersection(Nat, positive, bounded, 1n)),
      Bool.and(extracted(Categories.admit_intersection(Nat, positive, bounded, 1n)),
        Bool.and(rejected(Categories.admit_intersection(Nat, positive, bounded, 0n)),
          rejected(Categories.admit_intersection(Nat, positive, bounded, 2n))))))
`;

async function fixture(t, source) {
  await mkdir(path.join(root, '.build'), { recursive: true });
  const directory = await mkdtemp(path.join(root, '.build/categories-boundary-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'client.bend'), source);
  return checkOnly => spawnSync(bend, ['client.bend', ...(checkOnly ? ['--check-only'] : [])], {
    cwd: directory, encoding: 'utf8', timeout: 20_000, maxBuffer: 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
}

function accepted(result, proofCheck = true) {
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  if (proofCheck) assert.match(result.stdout, /ALL PROOFS CHECK/);
}

function proofRejected(result, location, equations = false) {
  const diagnostic = result.stdout + result.stderr;
  assert.equal(result.error, undefined, 'A timeout or process error is not proof rejection');
  assert.equal(result.signal, null, 'A compiler crash is not proof rejection');
  assert.equal(result.status, 1, diagnostic);
  assert.match(diagnostic, /SOME PROOFS FAIL/);
  assert.match(diagnostic, new RegExp(`Location: ${location}\\b`));
  if (equations) {
    assert.match(diagnostic, /expected\s*:\s*\{False\{\} == True\{\} : Bool\}/);
    assert.match(diagnostic, /observed\s*:\s*\{True\{\} == True\{\} : Bool\}/);
  } else {
    assert.match(diagnostic, /expected\s*:\s*False\{\}/);
    assert.match(diagnostic, /observed\s*:\s*True\{\}/);
  }
  assert.doesNotMatch(diagnostic, /TYPE ERROR|TYPE MISMATCH|undefined (?:reference|name)|unresolved import|syntax error|stack overflow|segmentation fault|panic|TODOs found/i);
}

test('public category admission executes intersections and consumes their evidence', async t => {
  assert.equal(compiler(), bend, 'Use the pinned workspace compiler');
  const compile = await fixture(t, client);
  accepted(compile(true));
  const executed = compile(false);
  accepted(executed, false);
  assert.match(executed.stdout, /\bTrue\{\}/);
});

test('the checker rejects forged membership evidence after accepting the same valid client', async t => {
  const membership = value => `${vocabulary}
def witness() -> Categories.Membership<Nat, Categories.holds(Nat, positive)>:
  Categories.Membership{${value}n, {==}}

def consume(member: Categories.Membership<Nat, Categories.holds(Nat, positive)>) -> Bool:
  Categories.Membership{value, evidence} = member
  positive_consumer(value, evidence)

def main() -> Bool:
  consume(witness())
`;
  const valid = await fixture(t, membership(1));
  accepted(valid(true));
  const invalid = await fixture(t, membership(0));
  proofRejected(invalid(true), 'witness');
});

test('positive evidence at an out-of-bounds value cannot authorize a bounded consumer', async t => {
  const source = consumer => `${vocabulary}
def witness() -> Categories.holds(Nat, positive, 2n):
  {==}

def consume(-evidence: Categories.holds(Nat, positive, 2n)) -> Bool:
  ${consumer}(2n, evidence)

def main() -> Bool:
  consume(witness())
`;
  const valid = await fixture(t, source('positive_consumer'));
  accepted(valid(true));
  const invalid = await fixture(t, source('bounded_consumer'));
  proofRejected(invalid(true), 'consume', true);
});

test('an inclusion must supply a valid implication for every value', async t => {
  const valid = await fixture(t, `${vocabulary}
def inclusion() -> Categories.Inclusion<Nat, Categories.holds(Nat, positive), Categories.holds(Nat, positive)>:
  Categories.inclusion_identity(Nat, Categories.holds(Nat, positive))

def main() -> Bool:
  positive_consumer(2n, apply(Categories.holds(Nat, positive), Categories.holds(Nat, positive), inclusion(), 2n, {==}))
`);
  accepted(valid(true));
  const invalid = await fixture(t, `${vocabulary}
def false_implication(value: Nat, -evidence: Categories.holds(Nat, positive, value)) -> Categories.holds(Nat, bounded, value):
  match value:
    case 0n: {==}
    case 1n+rest:
      match rest:
        case 0n: {==}
        case 1n+more: {==}

def false_inclusion() -> Categories.Inclusion<Nat, Categories.holds(Nat, positive), Categories.holds(Nat, bounded)>:
  Categories.Inclusion{value => evidence => false_implication(value, evidence)}

def main() -> Bool:
  bounded_consumer(2n, apply(Categories.holds(Nat, positive), Categories.holds(Nat, bounded), false_inclusion(), 2n, {==}))
`);
  proofRejected(invalid(true), 'false_implication');
});

test('a detached true result cannot stand in for the predicate observation at admission', async t => {
  const source = value => `${vocabulary}
def detached() -> Bool:
  True{}

def scoped_admission() -> Maybe<&1, Categories.Membership<Nat, Categories.holds(Nat, positive)>>:
  Categories.admit_checked(Nat, positive, ${value}n, detached(), {==})
`;
  const valid = await fixture(t, source(1));
  accepted(valid(true));
  const invalid = await fixture(t, source(0));
  proofRejected(invalid(true), 'scoped_admission');
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler, compilerEnvironment, compilerInvocation } from '../scripts/toolchain.mjs';

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
  const invocation = compilerInvocation(bend, ['client.bend']);
  return () => spawnSync(invocation.command, invocation.args, {
    cwd: directory, encoding: 'utf8', timeout: 20_000, maxBuffer: 1024 * 1024,
    env: { ...compilerEnvironment(), BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
}

function accepted(result) {
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

test('public category admission executes intersections and consumes their evidence', async t => {
  assert.equal(compiler(), bend, 'Use the pinned workspace compiler');
  const compile = await fixture(t, client);
  const executed = compile();
  accepted(executed);
  assert.match(executed.stdout, /\bTrue\{\}/);
});

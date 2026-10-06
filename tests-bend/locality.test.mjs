import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { auditComponents } from '../scripts/check-components.mjs';
import { specimen, unchanged, check, checked, rejected, modify, replaceOnce, replaceDefinition, nativeProbe, nativeBuild } from './locality-support.mjs';
import { extendCounter, assemblyChanges, counterProbe } from './fixtures/locality-extension.mjs';

async function extendRemainders(directory, large = false) {
  await modify(directory, 'FEATURES.bend', source => {
    let result = replaceDefinition(source, 'Rest', `def Rest() -> Data:\n  ${large ? 'C.Frame<Nat, +List<Nat>>' : 'Nat'}`);
    result = replaceDefinition(result, 'initial_rest', `def initial_rest() -> Rest():\n  ${large ? 'C.Frame{17n, [3n, 5n, 8n]}' : '17n'}`);
    result = replaceDefinition(result, 'CursorRest', `def CursorRest() -> Data:\n  ${large ? '+List<Nat>' : 'Nat'}`);
    return replaceDefinition(result, 'initial_cursor_rest', `def initial_cursor_rest() -> CursorRest():\n  ${large ? '[23n, 29n]' : '23n'}`);
  });
}

test('state and cursor extensions reuse the complete existing source and proof tree', { timeout: 300_000 }, async t => {
  for (const large of [false, true]) await t.test(large ? 'nested state representation' : 'independent state and cursor', async t => {
    const copy = await specimen(t);
    await extendRemainders(copy.directory, large);
    checked(check(copy.directory));
    assert.equal((await auditComponents(copy.directory)).ok, true);
    await unchanged(copy, ['FEATURES.bend']);
    if (!large) await nativeProbe(copy.directory, `import Base
import ./PROOF.bend as Proof
import ./MODEL.bend as M
import ./FEATURES.bend as F
import ./BOARD.bend as B
import ./UI.bend as UI
import ./bendlib/component.bend as C
import ./bendlib/domain.bend as D
import ./bendlib/json.bend as J
import ./bendlib/board-state.bend as BoardState
import ./bendlib/feature-ui.bend as FeatureUI

def result(valid: Bool) -> U32:
  match valid:
    case True{}: 1
    case False{}: 0

def main() -> U32:
  world = BoardState.store(B.initial(), M.initial())
  cursor = UI.navigate(M.FeatureEvent{F.BoardEvent{B.Search{"probe"}}}, UI.initial(), J.Null{})
  result(Nat.is_eq(F.rest(C.rest(D.State, F.State(), world)), 17n) && Nat.is_eq(FeatureUI.remainder(cursor), 23n))
`);
    await unchanged(copy, ['FEATURES.bend']);
  });
});

test('source boundaries reject behavior-preserving representation coupling', { timeout: 180_000 }, async t => {
  const copy = await specimen(t);
  const target = 'bendlib/reasoning.bend';
  await modify(copy.directory, target, source => source.replace('import Base\n', 'import Base\nimport ../MODEL.bend as Application\n'));
  checked(check(copy.directory));
  const result = await auditComponents(copy.directory);
  assert.equal(result.ok, false);
  assert.ok(result.errors.some(message => message.includes(`${target} -> MODEL.bend`)));
  await unchanged(copy, [target]);
});

test('source boundaries reject feature case analysis outside its owner', { timeout: 180_000 }, async t => {
  const copy = await specimen(t);
  await modify(copy.directory, 'bendlib/commit.bend', source => source.replace('import Base\n',
    'import Base\nimport ../FEATURES.bend as FeatureAlphabet\n') + `
def unwanted_case(command: FeatureAlphabet.Command) -> Unit:
  match command:
    case FeatureAlphabet.BoardCommand{command}: Unit{}
`);
  checked(check(copy.directory));
  const result = await auditComponents(copy.directory);
  assert.equal(result.ok, false);
  assert.ok(result.errors.some(message => message.includes('Feature pattern outside') && message.includes('bendlib/commit.bend')));
});

test('source boundaries also reject multiline constructor bindings and keep feature imports out of universal adapters', { timeout: 120_000 }, async t => {
  const copy = await specimen(t);
  await modify(copy.directory, 'bendlib/commit.bend', source => source.replace('import Base\n',
    'import Base\nimport ../FEATURES.bend as Private\n') + `
def unwanted_binding(value: Private.Command) -> Unit:
  Private.BoardCommand{
    command} = value
  Unit{}
`);
  checked(check(copy.directory));
  let audit = await auditComponents(copy.directory);
  assert.ok(audit.errors.some(message => message.includes('Feature pattern outside') && message.includes('commit.bend')));
  await writeFile(path.join(copy.directory, 'bendlib/commit.bend'), copy.originals.get('bendlib/commit.bend'));
  await modify(copy.directory, 'UI.bend', source => source + '\n# case Private.BoardCommand{command}: is only a comment\n');
  assert.equal((await auditComponents(copy.directory)).ok, true);
  await modify(copy.directory, 'UI.bend', source => source.replace('import Base\n', 'import Base\nimport ./BOARD.bend as PrivateBoard\n'));
  audit = await auditComponents(copy.directory);
  assert.ok(audit.errors.some(message => message.includes('UI.bend -> BOARD.bend')));
});

test('locality proofs reject type-correct forgotten updates and damaged remainders', { timeout: 300_000 }, async t => {
  const copy = await specimen(t);
  await extendRemainders(copy.directory);
  checked(check(copy.directory));
  const target = path.join(copy.directory, 'FEATURES.bend');
  const baseline = await readFile(target, 'utf8');
  for (const [label, name, definition, obligation] of [
    ['discard the written board', 'with_board', 'def with_board(value: Board.State, state: State()) -> State():\n  state', /board_written|change_meaning|archive_saved/],
    ['reset unrelated persistent state', 'with_board', 'def with_board(value: Board.State, state: State()) -> State():\n  C.Frame{value, initial_rest()}', /board_frame|change_meaning|archive_saved/],
    ['discard the written cursor', 'with_board_cursor', 'def with_board_cursor(value: Board.Cursor, cursor: Cursor()) -> Cursor():\n  cursor', /cursor_written/],
    ['reset unrelated view state', 'with_board_cursor', 'def with_board_cursor(value: Board.Cursor, cursor: Cursor()) -> Cursor():\n  C.Frame{value, initial_cursor_rest()}', /cursor_frame|navigation_frame/],
  ]) await t.test(label, async () => {
    try {
      await writeFile(target, replaceDefinition(baseline, name, definition));
      checked(check(copy.directory, 'PROGRAM.bend'));
      rejected(check(copy.directory), obligation);
    } finally { await writeFile(target, baseline); }
  });
  await unchanged(copy, ['FEATURES.bend']);
});

test('component audit fails closed for missing imports and incomplete configuration', async t => {
  const copy = await specimen(t);
  await modify(copy.directory, 'bendlib/reasoning.bend', source => `${source}\nimport ./missing-module.bend as Missing\n`);
  await assert.rejects(auditComponents(copy.directory), /Missing or out-of-root source/);
  await writeFile(path.join(copy.directory, 'bendlib/reasoning.bend'), copy.originals.get('bendlib/reasoning.bend'));
  await modify(copy.directory, 'components.json', source => {
    const config = JSON.parse(source);
    delete config.core_modules;
    return JSON.stringify(config);
  });
  await assert.rejects(auditComponents(copy.directory), /Unsupported or incomplete/);
});

test('a matching native build cache cannot bypass the actual-source boundary gate', async t => {
  const copy = await specimen(t);
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const filename of ['scripts', 'theory', 'bend-version']) {
    await cp(path.join(root, filename), path.join(copy.directory, filename), { recursive: true });
  }
  await modify(copy.directory, 'bendlib/reasoning.bend', source => source.replace('import Base\n',
    'import Base\nimport ../MODEL.bend as Application\n'));
  const compiler = (await readFile(path.join(root, 'bend-version'), 'utf8')).trim();
  const format = 'selvedge-bend-journal-2';
  const hash = createHash('sha256').update(`Bend ${compiler}\0${format}\0`);
  for (const filename of [...copy.originals.keys()].filter(name => name.endsWith('.bend') || name === 'host/transport.c').sort()) {
    hash.update(filename).update('\0').update(await readFile(path.join(copy.directory, filename))).update('\0');
  }
  await mkdir(path.join(copy.directory, '.build'));
  // Cache selection checks the fingerprint and file presence. The file is never
  // executed: the structural gate must reject this source before cache selection.
  await writeFile(path.join(copy.directory, '.build/selvedge-kernel'), 'cache fixture');
  await writeFile(path.join(copy.directory, '.build/kernel.json'), JSON.stringify({ format, compiler, fingerprint: hash.digest('hex') }));
  const result = spawnSync(process.execPath, ['scripts/build.mjs'], { cwd: copy.directory,
    encoding: 'utf8', timeout: 30_000, env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
  assert.equal(result.error, undefined);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /Component boundary check failed:[\s\S]*reasoning.bend -> MODEL.bend/);
  assert.doesNotMatch(result.stdout, /Bend kernel is current|Built Bend kernel/);
});

test('contract-preserving replacement changes only the implementation and its local proof', { timeout: 120_000 }, async t => {
  const copy = await specimen(t);
  const implementation = 'bendlib/tasks.bend';
  const provider = 'bendlib/proofs/task-storage.bend';
  // Appending the empty list is extensionally identical, but the checker cannot
  // erase it on an unknown list. This deliberately challenges clients that rely
  // on unfolding storage rather than its operation boundary; it is not an
  // optimization intended for production.
  await modify(copy.directory, implementation, source => replaceOnce(source,
    'D.State{replace(tasks, task), next_task, next_ticket, environment, limits, projects}',
    'D.State{List.append(&2, D.Task, replace(tasks, task), Nil{}), next_task, next_ticket, environment, limits, projects}'));
  checked(check(copy.directory, 'PROGRAM.bend'));
  rejected(check(copy.directory), /task-storage.update_meaning/);
  await modify(copy.directory, provider, source => replaceDefinition(
    source.replace('import Base\n', 'import Base\nimport ../stdlib.bend as Std\n'), 'update_meaning',
    `def update_meaning(-R: Data, +task: D.Task, +state: D.State, +rest: R) ->
  {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{Spec.required_update(task, state), rest} : C.Frame<D.State, R>}:
  match state:
    case D.State{+tasks, next_task, next_ticket, environment, limits, projects}:
      Equal.cong(+List<D.Task>, C.Frame<D.State, R>,
        values => C.Frame{D.State{values, next_task, next_ticket, environment, limits, projects}, rest},
        List.append(&2, D.Task, Tasks.replace(tasks, task), Nil{}), Tasks.replace(tasks, task),
        Std.app_nil_r(D.Task, Tasks.replace(tasks, task)))`));
  checked(check(copy.directory));
  const audit = await auditComponents(copy.directory);
  assert.equal(audit.ok, true, audit.errors.join('\n'));
  await unchanged(copy, [implementation, provider]);
});

test('a complete feature extends all alphabets without editing existing application code or proofs', { timeout: 420_000 }, async t => {
  const copy = await specimen(t);
  await extendCounter(copy.directory);
  checked(check(copy.directory));
  const audit = await auditComponents(copy.directory);
  assert.equal(audit.ok, true, audit.errors.join('\n'));
  await unchanged(copy, assemblyChanges);
  const binary = await nativeBuild(copy.directory, 'MAIN.bend', { signal: t.signal });
  await counterProbe(binary);
  await unchanged(copy, assemblyChanges);
});

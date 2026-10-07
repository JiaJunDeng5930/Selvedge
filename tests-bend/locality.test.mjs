import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { auditComponents, checkComponents } from '../scripts/check-components.mjs';
import { specimen, unchanged, check, checked, rejected, modify, replaceOnce, replaceDefinition, nativeProbe } from './locality-support.mjs';
import { extendCounter, assemblyChanges, counterProbe } from './fixtures/locality-extension.mjs';

async function extendRemainders(directory, large = false) {
  await modify(directory, 'FEATURES.bend', source => {
    let result = replaceDefinition(source, 'Rest', `def Rest() -> Data:\n  ${large ? 'C.Frame<Nat, +List<Nat>>' : 'Nat'}`);
    result = replaceDefinition(result, 'initial_rest', `def initial_rest() -> Rest():\n  ${large ? 'C.Frame{17n, [3n, 5n, 8n]}' : '17n'}`);
    return result;
  });
}

test('persistent state extensions reuse the complete existing source and proof tree', { timeout: 300_000 }, async t => {
  for (const large of [false, true]) await t.test(large ? 'nested state representation' : 'independent persistent state', async t => {
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
import ./bendlib/component.bend as C
import ./bendlib/domain.bend as D
import ./bendlib/board-state.bend as BoardState

def result(valid: Bool) -> U32:
  match valid:
    case True{}: 1
    case False{}: 0

def main() -> U32:
  world = BoardState.store(B.initial(), M.initial())
  result(Nat.is_eq(F.rest(C.rest(D.State, F.State(), world)), 17n))
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
    case _: Unit{}
`);
  checked(check(copy.directory));
  const result = await auditComponents(copy.directory);
  assert.equal(result.ok, false);
  assert.ok(result.errors.some(message => message.includes('Feature pattern outside') && message.includes('bendlib/commit.bend')));
});

test('source boundaries also reject multiline constructor bindings and keep private feature imports out of the universal wire adapter', { timeout: 120_000 }, async t => {
  const copy = await specimen(t);
  await modify(copy.directory, 'bendlib/commit.bend', source => source.replace('import Base\n',
    'import Base\nimport ../FEATURES.bend as Private\n') + `
def unwanted_binding(value: Private.Command) -> Unit:
  match value:
    case Private.BoardCommand{
      command}: Unit{}
    case _: Unit{}
`);
  checked(check(copy.directory));
  let audit = await auditComponents(copy.directory);
  assert.ok(audit.errors.some(message => message.includes('Feature pattern outside') && message.includes('commit.bend')));
  await writeFile(path.join(copy.directory, 'bendlib/commit.bend'), copy.originals.get('bendlib/commit.bend'));
  await modify(copy.directory, 'UI.bend', source => source + '\n# case Private.BoardCommand{command}: is only a comment\n');
  assert.equal((await auditComponents(copy.directory)).ok, true);
  await modify(copy.directory, 'bendlib/wire.bend', source => source.replace('import Base\n', 'import Base\nimport ../BOARD.bend as PrivateBoard\n'));
  checked(check(copy.directory));
  audit = await auditComponents(copy.directory);
  assert.ok(audit.errors.some(message => message.includes('bendlib/wire.bend -> BOARD.bend')));
});

test('locality proofs reject type-correct forgotten updates and damaged remainders', { timeout: 300_000 }, async t => {
  const copy = await specimen(t);
  await extendRemainders(copy.directory);
  checked(check(copy.directory));
  const target = path.join(copy.directory, 'FEATURES.bend');
  const baseline = await readFile(target, 'utf8');
  for (const [label, name, definition, obligation] of [
    ['discard the written board', 'with_board', 'def with_board(value: Board.State, state: State()) -> State():\n  state', /board_written|change_meaning|archive_saved/],
    ['reset unrelated persistent state', 'with_board', 'def with_board(value: Board.State, state: State()) -> State():\n  C.Frame{value, C.Frame{ChatGPT.initial(), initial_rest()}}', /board_frame|board_preserves|change_meaning|archive_saved/],
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

test('private model construction and destructuring fail the actual source boundary gate', { timeout: 180_000 }, async t => {
  const copy = await specimen(t);
  const target = 'model-boundary-probe.bend';
  const prelude = 'import Base\nimport ./bendlib/domain.bend as Private\n';
  const fields = 'tasks, next_task, next_ticket, environment, limits, projects';
  const probes = [
    ['constructor introduction', `def probe(+state: Private.State) -> Private.State:\n  Private.State{Private.state_tasks(state), Private.state_next_task(state), Private.state_next_ticket(state), Private.state_environment(state), Private.state_limits(state), Private.state_projects(state)}\n`],
    ['assignment destructuring', `def probe(state: Private.State) -> Nat:\n  Private.State{${fields}} = state\n  next_task\n`],
    ['multiline case destructuring', `def probe(state: Private.State) -> Nat:\n  match state:\n    case Private.State{tasks, next_task, next_ticket,\n      environment, limits, projects}: next_task\n`],
  ];
  for (const [label, source] of probes) await t.test(label, async () => {
    await writeFile(path.join(copy.directory, target), prelude + source);
    // These are legal Bend programs. Rejection must come from the source policy,
    // separately from the production semantic proof mutation tests below.
    checked(check(copy.directory, target));
    await assert.rejects(checkComponents(copy.directory), error => {
      assert.match(error.message, /Component boundary check failed/);
      assert.match(error.message, /Model representation outside its owner boundary/);
      assert.match(error.message, /model-boundary-probe\.bend:\d+: Private\.State/);
      return true;
    });
  });
  await unchanged(copy);
});

test('model ownership permits public command data, explicit owners and inert constructor text', async t => {
  const copy = await specimen(t);
  await writeFile(path.join(copy.directory, 'model-boundary-probe-laws.bend'), `import Base
import ./bendlib/domain.bend as Private

law state_identity:
  for +state: Private.State
  {state == state : Private.State}
`);
  await writeFile(path.join(copy.directory, 'model-boundary-probe.bend'), `import Base
import ./BOARD.bend as Board
import ./bendlib/domain.bend as Private
import ./model-boundary-probe-laws.bend as Law

def profile(value: Board.AgentProfile) -> Board.AgentProfile:
  Board.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = value
  Board.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}

def draft(value: Board.Draft) -> Board.Draft:
  Board.Draft{title, description, stage, priority, owner, project, labels, attachments} = value
  Board.Draft{title, description, stage, priority, owner, project, labels, attachments}

def Law.state_identity(state):
  {==}

# Private.State{tasks, next_task, next_ticket, environment, limits, projects} is inert.
def text() -> String:
  "case Private.State{fields}: Private.State{fields}"
`);
  checked(check(copy.directory, 'model-boundary-probe.bend'));
  const policy = JSON.parse(copy.originals.get('components.json')).model_representations.find(entry => entry.module === 'bendlib/domain.bend');
  assert.ok(policy.owners.includes('bendlib/domain.bend'));
  assert.ok(policy.owners.includes('bendlib/proofs/task-storage.bend'));
  await modify(copy.directory, 'bendlib/domain.bend', source => `${source}\ndef model_boundary_owner_probe(state: State) -> Nat:\n  State{tasks, next_task, next_ticket, environment, limits, projects} = state\n  next_task\n`);
  await modify(copy.directory, 'bendlib/proofs/task-storage.bend', source => `${source}\ndef model_boundary_owner_probe(state: D.State) -> Nat:\n  D.State{tasks, next_task, next_ticket, environment, limits, projects} = state\n  next_task\n`);
  assert.match(await checkComponents(copy.directory), /Component boundaries check/);
  await unchanged(copy, ['bendlib/domain.bend', 'bendlib/proofs/task-storage.bend']);
});

test('model representation policy rejects malformed, unknown and duplicate ownership declarations', async t => {
  const copy = await specimen(t);
  const original = JSON.parse(copy.originals.get('components.json'));
  const mutations = [
    ['missing policy', config => { delete config.model_representations; }, /Unsupported or incomplete/],
    ['empty policy', config => { config.model_representations = []; }, /Invalid model representation boundaries/],
    ['extra policy field', config => { config.model_representations[0].wildcard = true; }, /Invalid model representation policy shape/],
    ['unknown module', config => { config.model_representations[0].module = 'missing-model.bend'; }, /Missing model representation module/],
    ['unknown constructor', config => { config.model_representations[0].constructors = ['MissingState']; }, /Missing model representation constructor/],
    ['duplicate module', config => { config.model_representations.push(structuredClone(config.model_representations[0])); }, /Duplicate model representation ownership/],
    ['duplicate constructor', config => { config.model_representations[0].constructors.push(config.model_representations[0].constructors[0]); }, /Invalid model representation constructors/],
    ['unknown owner', config => { config.model_representations[0].owners.push('missing-owner.bend'); }, /Invalid model representation owners/],
    ['wildcard owner', config => { config.model_representations[0].owners.push('bendlib/proofs/*'); }, /Invalid model representation owners/],
    ['duplicate owner', config => { config.model_representations[0].owners.push(config.model_representations[0].owners[0]); }, /Invalid model representation owners/],
    ['missing declaring owner', config => { config.model_representations[0].owners = config.model_representations[0].owners.filter(owner => owner !== config.model_representations[0].module); }, /Invalid model representation owners/],
  ];
  for (const [label, mutate, diagnostic] of mutations) await t.test(label, async () => {
    const config = structuredClone(original);
    mutate(config);
    await writeFile(path.join(copy.directory, 'components.json'), JSON.stringify(config));
    await assert.rejects(checkComponents(copy.directory), diagnostic);
  });
  await unchanged(copy, ['components.json']);
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

test('contract-preserving replacement preserves clients and declares its local proof dependency', { timeout: 120_000 }, async t => {
  const copy = await specimen(t);
  const implementation = 'bendlib/tasks.bend';
  const provider = 'bendlib/proofs/task-storage.bend';
  // Appending the empty list is extensionally identical, but the checker cannot
  // erase it on an unknown list. This deliberately challenges clients that rely
  // on unfolding storage rather than its operation boundary; it is not an
  // optimization intended for production.
  await modify(copy.directory, implementation, source => replaceOnce(source,
    'write(replace(read(state), task), state)',
    'write(List.append(&2, D.Task, replace(read(state), task), Nil{}), state)'));
  checked(check(copy.directory, 'PROGRAM.bend'));
  rejected(check(copy.directory), /Location: update_meaning\b/);
  await modify(copy.directory, provider, source => replaceDefinition(
    source.replace('import Base\n', 'import Base\nimport ../stdlib.bend as Std\n'), 'update_meaning',
    `def update_meaning(-R: Data, +task: D.Task, +state: D.State, +rest: R) ->
  {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{Spec.required_update(task, state), rest} : C.Frame<D.State, R>}:
  Equal.cong(+List<D.Task>, C.Frame<D.State, R>,
    values => C.Frame{D.with_state_tasks(values, state), rest},
    List.append(&2, D.Task, Tasks.replace(D.state_tasks(state), task), Nil{}), Tasks.replace(D.state_tasks(state), task),
    Std.app_nil_r(D.Task, Tasks.replace(D.state_tasks(state), task)))`));
  await modify(copy.directory, 'components.json', source => {
    const config = JSON.parse(source);
    config.application_dependencies[provider] = [
      ...config.application_dependencies[provider], 'bendlib/stdlib.bend',
    ];
    return JSON.stringify(config, null, 2) + '\n';
  });
  const originalManifest = JSON.parse(copy.originals.get('components.json'));
  const expectedManifest = structuredClone(originalManifest);
  expectedManifest.application_dependencies[provider] = [
    ...originalManifest.application_dependencies[provider], 'bendlib/stdlib.bend',
  ];
  assert.deepEqual(JSON.parse(await readFile(path.join(copy.directory, 'components.json'), 'utf8')), expectedManifest);
  checked(check(copy.directory));
  const audit = await auditComponents(copy.directory);
  assert.equal(audit.ok, true, audit.errors.join('\n'));
  await unchanged(copy, [implementation, provider, 'components.json']);
});

test('a kernel feature extends all kernel alphabets with existing clients and proofs frozen', { timeout: 420_000 }, async t => {
  const copy = await specimen(t);
  await extendCounter(copy.directory);
  const expectedManifest = JSON.parse(copy.originals.get('components.json').toString());
  for (const [owner, dependencies] of Object.entries({
    'bendlib/feature-codec.bend': ['COUNTER.bend'],
    'bendlib/feature-execution.bend': ['bendlib/counter-execution.bend', 'bendlib/counter-assembly.bend', 'COUNTER.bend'],
    'bendlib/feature-laws.bend': ['bendlib/counter-laws.bend'],
    'bendlib/feature-spec.bend': ['bendlib/counter-assembly.bend', 'COUNTER.bend'],
    'bendlib/feature-state.bend': ['bendlib/counter-assembly.bend', 'COUNTER.bend'],
  })) expectedManifest.application_dependencies[owner].push(...dependencies);
  assert.deepEqual(JSON.parse(await readFile(path.join(copy.directory, 'components.json'), 'utf8')), expectedManifest);
  checked(check(copy.directory));
  const audit = await auditComponents(copy.directory);
  assert.equal(audit.ok, true, audit.errors.join('\n'));
  await unchanged(copy, assemblyChanges);
  const output = path.join(copy.directory, 'locality-kernel.mjs');
  await compileJavaScript({ entry: path.join(copy.directory, 'KERNEL.bend'), output, sourceRoot: copy.directory,
    exports: { initial: 'initial', packet: 'packet', envelope: 'envelope', show: 'show', state: 'state' } });
  await counterProbe(output);
  await unchanged(copy, assemblyChanges);
});

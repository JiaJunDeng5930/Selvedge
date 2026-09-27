import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, readdir, cp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compiler } from '../scripts/toolchain.mjs';

const bend = compiler();

test('the installed proof gate rejects both missing and false proofs', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-proof-gate-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'LAWS.bend'), 'import Base\nlaw impossible:\n  {True{} == False{} : Bool}\n');
  for (const [proof, diagnostic] of [
    ['import ./LAWS.bend as Laws\n', /TODO found[\s\S]*not a valid proof/],
    ['import Base\nimport ./LAWS.bend as Laws\ndef Laws.impossible():\n  {==}\n', /True[\s\S]*False|False[\s\S]*True/],
  ]) {
    await writeFile(path.join(directory, 'PROOF.bend'), proof);
    const result = spawnSync(bend, ['PROOF.bend', '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0, 'An unproved or false requirement must fail the build gate');
    assert.match(result.stdout + result.stderr, diagnostic);
  }
});

test('bypassing production admission invalidates the transition theorem', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-proof-mutation-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const filename of await readdir(root)) {
    if (filename.endsWith('.bend')) await cp(path.join(root, filename), path.join(directory, filename));
  }
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const check = () => spawnSync(bend, ['PROOF.bend', '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
  const baseline = check();
  assert.equal(baseline.error, undefined);
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  const filename = path.join(directory, 'PROGRAM.bend');
  const source = await readFile(filename, 'utf8');
  const changed = source.replace(/(def admitted\([^\n]*\) -> M\.Decision:\n)[\s\S]*?(?=\ndef check_live)/, '$1  decision\n');
  assert.notEqual(changed, source, 'The mutation must remove the production admission check');
  await writeFile(filename, changed);
  const rejected = check();
  assert.equal(rejected.error, undefined);
  assert.notEqual(rejected.status, 0, 'The same proof must reject an implementation that bypasses admission');
  assert.match(rejected.stdout + rejected.stderr, /admitted_certificate|guard_semantics/);
});

function replaceOnce(source, before, after) {
  assert.equal(source.split(before).length, 2, `Mutation must identify one occurrence: ${before}`);
  return source.replace(before, after);
}

function alterDefinition(source, name, alter) {
  const start = source.indexOf(`def ${name}(`);
  assert.notEqual(start, -1, `Missing definition ${name}`);
  const next = source.indexOf('\ndef ', start + 1);
  const end = next < 0 ? source.length : next;
  const block = source.slice(start, end);
  const changed = alter(block);
  assert.notEqual(changed, block, `Mutation must change ${name}`);
  return source.slice(0, start) + changed + source.slice(end);
}

function replaceBody(source, name, body) {
  return alterDefinition(source, name, block => {
    const marker = ' -> M.Decision:\n';
    const index = block.indexOf(marker);
    assert.notEqual(index, -1, `Missing decision result type in ${name}`);
    return block.slice(0, index + marker.length) + `  ${body}\n`;
  });
}

test('functional proof gates reject type-correct no-ops, wrong replies, missing work, and arbitrary rejection', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-functional-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const filename of await readdir(root)) {
    if (filename.endsWith('.bend')) await cp(path.join(root, filename), path.join(directory, filename));
  }
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const filename = path.join(directory, 'PROGRAM.bend');
  const original = await readFile(filename, 'utf8');
  const tasksFilename = path.join(directory, 'bendlib/tasks.bend');
  const originalTasks = await readFile(tasksFilename, 'utf8');
  const compile = file => spawnSync(bend, [file, '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 10_000 });
  const baseline = compile('PROOF.bend');
  assert.equal(baseline.error, undefined);
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  const mutations = [
    ['refuse every valid create', source => replaceOnce(source,
      'case Commands.Start{profile, reasoning, message, selection}: execute_start(profile, reasoning, message, selection, world)',
      'case Commands.Start{profile, reasoning, message, selection}: reject(world, "refused", "safe but not useful")')],
    ['acknowledge send without delivering it', source => replaceOnce(source,
      'case Commands.Deliver{task, message}: execute_delivery(message, task, world)',
      'case Commands.Deliver{task, message}: respond(world, id_result(M.task_id(task)))')],
    ['return the wrong created identity', source => alterDefinition(source, 'execute_start', block =>
      replaceOnce(block, 'id_result(next_task))', 'id_result(1n+next_task))'))],
    ['omit interruption cancellation', source => alterDefinition(source, 'change_requested', block =>
      replaceOnce(block, '[M.CancelTask{M.task_id(task)}]', 'Nil{}'))],
    ['record a model pending phase but omit its request', source => alterDefinition(source, 'model_request_direct', block =>
      block.replace(/\[M\.RequestModel\{[\s\S]*?\}\]/, 'Nil{}'))],
    ['record a tool pending phase but omit its request', source => alterDefinition(source, 'external_tool', block =>
      block.replace(/\[M\.ExecuteTool\{[\s\S]*?\}\]/, 'Nil{}'))],
    ['never run the scheduler', source => replaceBody(source, 'scheduled', 'decision')],
    ['drop the continuation at fuel exhaustion', source => replaceBody(source, 'defer', 'decision')],
    ['ignore the complete resolved execution alphabet', source => replaceBody(source, 'realize_action', 'respond(world, J.Null{})')],
    ['turn every selected task into a safe no-op', source => replaceBody(source, 'work', 'respond(world, J.Null{})')],
    ['discard earlier effects when combining scheduler steps', source => alterDefinition(source, 'combine', block =>
      replaceOnce(block, 'List.append(&2, M.Effect, effects, added)', 'added'))],
    ['reject even admitted decisions', source => replaceBody(source, 'admitted',
      'reject(previous, "invariant_violation", "The candidate violates a world invariant, task retention, or effect authority")')],
    ['publish oversized decisions', source => replaceBody(source, 'output_admitted', 'decision')],
    ['claim successful tool settlement without appending it', source => alterDefinition(source, 'tool_matched', block =>
      replaceOnce(block, 'Results.begin(operation, value, error, task, world)',
        'respond(world, accepted(True{}))'))],
    ['silently discard every resolved input', source => replaceBody(source, 'realize_event', 'respond(world, J.Null{})')],
    ['claim acceptance of an ignored completion', source => replaceOnce(source,
      'case Protocol.Ignore{}: respond(world, accepted(False{}))',
      'case Protocol.Ignore{}: respond(world, accepted(True{}))')],
    ['skip recovery while retaining a safe world', source => alterDefinition(source, 'recover_tasks', block =>
      replaceOnce(block, 'Protocol.recovery(tasks)', 'tasks'))],
    ['execute an internal command without settling its caller', source => alterDefinition(source, 'realize_invocation', block =>
      replaceOnce(block, 'finish_internal(M.task_id(task), call, remaining, realize(operation, world))', 'realize(operation, world)'))],
    ['lose accepted calls after an internal fork', source => alterDefinition(source, 'commit_invoked_fork', block =>
      replaceOnce(block, 'Results.internal(call, remaining,', 'Results.internal(call, Nil{},'))],
    ['strand new FIFO input after summary failure', source => alterDefinition(source, 'summary_failure', block =>
      replaceOnce(block, 'promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{message}, task)))',
        'M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{message}, task))')), 'bendlib/tasks.bend'],
  ];
  for (const [name, mutate, target = 'PROGRAM.bend'] of mutations) {
    await t.test(name, async () => {
      await writeFile(filename, original);
      await writeFile(tasksFilename, originalTasks);
      await writeFile(path.join(directory, target), mutate(target === 'PROGRAM.bend' ? original : originalTasks));
      const wellTyped = compile('PROGRAM.bend');
      assert.equal(wellTyped.error, undefined);
      assert.equal(wellTyped.status, 0, `The mutant must be well-typed:\n${wellTyped.stdout}${wellTyped.stderr}`);
      const rejected = compile('PROOF.bend');
      assert.equal(rejected.error, undefined, `${name} must fail a proof, not time out`);
      assert.notEqual(rejected.status, 0, `${name} was not rejected by the functional specification`);
      assert.match(rejected.stdout + rejected.stderr, /semantics|scheduling_|model_dispatch|tool_dispatch|settlement|summary_failure_promotes_fifo|summary_rejects_invocations/);
    });
  }
});

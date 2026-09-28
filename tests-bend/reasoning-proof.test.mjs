import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

test('the assembled reasoning boundary rejects type-correct evaluator, lease, prefix and privacy faults', { timeout: 180_000 }, async t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-reasoning-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const name of await readdir(root)) if (name.endsWith('.bend')) await cp(path.join(root, name), path.join(directory, name));
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const check = filename => spawnSync(compiler(), [filename, '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 15_000 });
  const baseline = check('PROOF.bend');
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  assert.match(baseline.stdout, /All terms check/);
  const mutations = [
    ['ordinary profiles request an evaluator', 'bendlib/reasoning.bend',
      'case R.Fixed{}: R.FixedPlan{}', 'case R.Fixed{}: R.Evaluate{}', /route_meaning|reasoning_boundary/],
    ['extend a consumed lease', 'bendlib/reasoning.bend',
      'request(Context.generation(effort, remaining, task), world)', 'request(Context.generation(effort, 1n+remaining, task), world)', /execution_meaning/],
    ['omit the evaluator effect but record it as pending', 'bendlib/reasoning.bend',
      '[M.RequestReasoning{M.task_id(task), ticket, T.task_model(M.task_contract(task)), M.task_history(task)}]', 'Nil{}', /evaluator_meaning/],
    ['apply a stale recommendation', 'bendlib/reasoning.bend',
      'case False{}: T.promote(M.with_phase(M.Ready{Nil{}}, task))', 'case False{}: observed(outcome, task)', /fresh_meaning|reasoning_boundary/],
    ['permit an unconfigured duration', 'REASONING.bend',
      'Nat.is_eq(steps, 10n)', 'Nat.is_eq(steps, 3n)', /reasoning_boundary/],
    ['change the supposedly pinned request prefix', 'REASONING.bend',
      'case Adaptive{evaluator, efforts, baseline, ConfigurationUpdates{}, maximum}: baseline',
      'case Adaptive{evaluator, efforts, baseline, ConfigurationUpdates{}, maximum}: effective', /reasoning_boundary/],
    ['inherit a different task lease', 'bendlib/reasoning-context.bend',
      'recorded(Nat.is_eq(owner, other), effort, remaining)', 'recorded(True{}, effort, remaining)', /reasoning_boundary/],
    ['reuse a lease after a new user message', 'bendlib/reasoning-context.bend',
      'case M.HistoryNode{previous, M.UserMessage{text}}: R.NoLease{}',
      'case M.HistoryNode{previous, M.UserMessage{text}}: lease(previous, owner)', /reasoning_boundary/],
    ['retain the old effective update across a checkpoint', 'bendlib/reasoning-context.bend',
      'case M.HistoryNode{previous, M.ContextCheckpoint{summary}}: None{}',
      'case M.HistoryNode{previous, M.ContextCheckpoint{summary}}: last_update(previous)', /reasoning_boundary/],
    ['forget one generation when recording a sample', 'bendlib/reasoning-context.bend',
      'M.ReasoningRecord{owner, effort, remaining, True{}}', 'M.ReasoningRecord{owner, effort, 1n+remaining, True{}}', /reasoning_boundary/],
    ['expose encrypted continuation in nested tool JSON', 'bendlib/reasoning-context.bend',
      'J.Field{"encrypted_content", J.Text{"[Private provider continuation omitted]"}}', 'J.Field{"encrypted_content", value}', /reasoning_boundary/],
    ['bypass the public tool-output projection', 'bendlib/reasoning-context.bend',
      'case M.FunctionOutput{id, value, error}:\n      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{id}},\n        J.Field{"content", public_value(512n, value)}, J.Field{"is_error", J.Boolean{error}}]} <> rest',
      'case M.FunctionOutput{id, value, error}:\n      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{id}},\n        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]} <> rest', /reasoning_boundary/],
    ['accept a completion with another ticket', 'bendlib/protocol.bend',
      'matching(Nat.is_eq(ticket, expected), ReasoningResult{task, revision, outcome})',
      'matching(True{}, ReasoningResult{task, revision, outcome})', /reasoning_boundary/],
  ];
  for (const [label, file, before, after, expected] of mutations) {
    await t.test(label, async () => {
      const filename = path.join(directory, file);
      const original = await readFile(filename, 'utf8');
      assert.equal(original.split(before).length, 2, `${label}: mutation must target exactly one production expression`);
      try {
        await writeFile(filename, original.replace(before, after));
        const operational = check('PROGRAM.bend');
        assert.equal(operational.error, undefined, `${label}: compiler must not time out`);
        assert.equal(operational.status, 0, operational.stdout + operational.stderr);
        assert.match(operational.stdout, /All terms check/, `${label}: the runtime mutant must still type-check`);
        const proof = check('PROOF.bend');
        assert.equal(proof.error, undefined, `${label}: proof failure must not be a timeout`);
        assert.notEqual(proof.status, 0, `${label}: proof accepted the fault`);
        assert.match(proof.stdout + proof.stderr, expected);
      } finally { await writeFile(filename, original); }
    });
  }
});

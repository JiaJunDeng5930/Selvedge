import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

test('whole-program proofs reject type-correct loss of input, durability, receipts and independent operation ownership', { timeout: 900_000 }, async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-whole-program-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const filename of await readdir(root)) {
    if (filename.endsWith('.bend')) await cp(path.join(root, filename), path.join(directory, filename));
  }
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  await cp(path.join(root, 'core'), path.join(directory, 'core'), { recursive: true });
  await cp(path.join(root, 'webui'), path.join(directory, 'webui'), { recursive: true });
  const check = filename => spawnSync(compiler(), [filename, '--check-only'], { cwd: directory, encoding: 'utf8', timeout: 60_000, env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' } });
  const baseline = check('PROOF.bend');
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  for (const [filename, before, after, law] of [
    ['bendlib/reachability.bend', 'record(P.transition(input, world), receipts)',
      'record(P.transition(input, world), Nil{})', /Location: exact\b|receipts_prepend/],
    ['bendlib/reachability.bend', 'decision <> receipts}',
      '[decision]}', /receipts_prepend/],
    ['bendlib/reachability.bend', 'List.foldl(~&2, ~M.Input, ~State, ~advance, events, state)',
      'List.foldl(~&2, ~M.Input, ~State, ~advance, Nil{}, state)', /Location: prepend\b|replay_prepend|receipts_prepend/],
    ['bendlib/execution.bend',
      'authorization(D.may_execute(D.recovery(D.tool_source(tool)), attempt), tool, attempt, remaining, task, world)',
      'authorization(True{}, tool, D.CheckedAttempt{D.attempt_call(attempt), Nil{}}, remaining, task, world)', /hook_gateway/],
    ['HOOKS.bend', 'record_matching(Nat.is_eq(task_id, owner) && String.eq(call_id, id), state, reference, outcome)',
      'record_matching(String.eq(call_id, id), state, reference, outcome)', /hook_foreign_owner/],
    ['HOOKS.bend', 'case D.DenyTool{reason}: Refused{}',
      'case D.DenyTool{reason}: Awaiting{call, pending}', /hook_deny/],
    ['HOOKS.bend', 'checked(D.plugin_same(reference, expected), outcome, call, pending)',
      'checked(True{}, outcome, call, pending)', /hook_record_order/],
    ['bendlib/domain.bend', 'Call{id, name, arguments}\n\ntype HookOutcome',
      'Call{id, "bash", arguments}\n\ntype HookOutcome', /hook_rewrite_identity/],
    ['bendlib/notifications.bend', 'C.Decision{world, reply, List.append(&2, M.Effect(), effects, [Effects.NotifyPlugins{first <> rest}])}',
      'C.Decision{world, J.Null{}, List.append(&2, M.Effect(), effects, [Effects.NotifyPlugins{first <> rest}])}', /appended|plugin_observation_extension/],
    ['bendlib/notifications.bend', 'case Fail{reason}: plain',
      'case Fail{reason}: enriched', /fitted|plugin_observation_budget_failure/],
    ['APPROVALS.bend', 'case ModelDecision{} D.ModelReviewer{profile}: True{}\n    case _ _: False{}',
      'case ModelDecision{} D.ModelReviewer{profile}: True{}\n    case _ _: True{}', /approval_boundary/],
    ['APPROVALS.bend', 'case D.ApprovalPending{+reviewer}: matched(origin_matches(origin, reviewer), origin, operation, task, reviewer, outcome)',
      'case D.ApprovalPending{+reviewer}: matched(origin_matches(origin, reviewer), origin, operation, task, reviewer, outcome)\n    case D.ApprovalGranted{+reviewer}: matched(origin_matches(origin, reviewer), origin, operation, task, reviewer, outcome)', /approval_boundary/],
    ['PROGRAM.bend', 'Approvals.review_effects(F.Effect, reviewer, pending, ticket, call)', 'Nil{}', /approval_boundary|execution_semantics/],
    ['PROGRAM.bend', 'tool, Ops.call(operation), D.task_context(task), D.Unrestricted{}',
      'tool, D.Call{"different", "bash", J.Object{Nil{}}}, D.task_context(task), D.Unrestricted{}', /execution_semantics/],
    ['bendlib/frontend.bend', 'P.reject(world, "invalid_json", reason), False{}', 'P.reject(world, "invalid_json", reason), True{}', /frontend_json/],
    ['bendlib/frontend.bend', 'json(J.decode(tokens), world)', 'json(J.decode(Nil{}), world)', /frontend_packet/],
    ['bendlib/traces.bend', 'Spec.record(P.transition(input, world), pending, receipts)', 'Spec.record(P.transition(input, world), pending, Nil{})', /trace_step/],
    ['bendlib/traces.bend', 'Std.iter(~Spec.Tape, ~implementation, count, tape)', 'Std.iter(~Spec.Tape, ~implementation, 0n, tape)', /trace_partition|trace_interpretation/],
    ['PROGRAM.bend', 'Theory.replay(~M.World(), ~M.Input, ~next, events, world)', 'Theory.replay(~M.World(), ~M.Input, ~next, Nil{}, world)', /trace_interpretation|trace_cons/],
    ['bendlib/operations.bend', 'Finite.remove(~D.OperationBody, operations, id)', 'Nil{}', /operation_rights/],
    ['bendlib/operations.bend', 'binding(Finite.find(~D.OperationBody, operations, id), id)', 'None{}', /operation_rights/],
    ['bendlib/domain.bend', 'with_notified(Bool.or(task_notified(task), True{}), with_phase(wake_phase(task_phase(task)), task))',
      'with_notified(False{}, with_phase(wake_phase(task_phase(task)), task))', /notification_join|notification_sticky/],
    ['bendlib/operations.bend', '(ticket, D.OperationBody{call, True{}, stage})', '(0n, D.OperationBody{call, True{}, stage})', /announce_ticket/],
    ['bendlib/operations.bend', 'with_notified(False{}, D.with_operations(Std.map(', 'with_notified(True{}, D.with_operations(Std.map(', /notification_consumed/],
    ['bendlib/operations.bend', 'case True{}: D.OperationResult{ticket, id, name, value, error}',
      'case True{}: D.FunctionOutput{id, value, error}', /later_output/],
    ['bendlib/tasks.bend', 'promote(Ops.completed(operation, value, error, task))',
      'promote(D.with_phase(D.Idle{}, Ops.completed(operation, value, error, task)))', /pending_model/],
    ['bendlib/results.bend', 'received(StateRest, EffectRest, Hooks.after(Hooks.plugins(D.task_contract(task))), operation, value, error, task, world)',
      'finished(StateRest, EffectRest, operation, value, error, task, world)', /result_boundary/],
    ['bendlib/results.bend', 'internal_chain(StateRest, EffectRest, Hooks.after(Hooks.plugins(D.task_contract(task))), call, remaining, value, error, task, world)',
      'internal_chain(StateRest, EffectRest, Nil{}, call, remaining, value, error, task, world)', /result_boundary/],
    ['bendlib/results.bend', 'T.complete_operation(operation, value, error, task)', 'task', /result_boundary/],
    ['bendlib/results.bend', 'complete_action(StateRest, EffectRest, Hooks.result_action(outcome, value, error), pending, operation,',
      'complete_action(StateRest, EffectRest, Hooks.result_action(outcome, value, False{}), pending, operation,', /result_boundary/],
    ['HOOKS.bend', 'case D.RewriteResult{rewritten}: ResultValue{rewritten, error}',
      'case D.RewriteResult{rewritten}: ResultValue{rewritten, False{}}', /result_boundary/],
    ['bendlib/domain.bend', 'case ToolReceipt{owner, operation, call, value, error}: previous',
      'case ToolReceipt{owner, operation, call, value, error}: HistoryNode{previous, ToolReceipt{owner, operation, call, value, error}}', /result_boundary|project_node_idempotent/],
    ['bendlib/protocol.bend', 'matching(Ops.executing(Ops.stage(operation)), ToolResult{task, operation, value, error})',
      'ToolResult{task, operation, value, error}', /result_boundary/],
  ]) {
    const target = path.join(directory, filename);
    const original = await readFile(target, 'utf8');
    assert.equal(original.split(before).length, 2, `${filename}: missing or ambiguous mutation anchor ${before}`);
    try {
      await writeFile(target, original.replace(before, after));
      // Use the production root for relative-module identity. Checking a nested
      // module as a different project root is not a type-correctness comparison.
      await writeFile(path.join(directory, 'TYPECHECK.bend'), `import ./${filename} as Subject\n`);
      const wellTyped = check('TYPECHECK.bend');
      assert.equal(wellTyped.error, undefined);
      assert.equal(wellTyped.status, 0, wellTyped.stdout + wellTyped.stderr);
      const rejected = check('PROOF.bend');
      assert.equal(rejected.error, undefined);
      assert.notEqual(rejected.status, 0, `The proof accepted ${after}`);
      assert.match(rejected.stdout + rejected.stderr, law);
    } finally { await writeFile(target, original); }
  }
});

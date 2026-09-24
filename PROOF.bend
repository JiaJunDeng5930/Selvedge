import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./LAWS.bend as Laws
import ./bendlib/tasks.bend as T
import ./bendlib/theory.bend as Theory
import ./bendlib/json.bend as J
import ./bendlib/presentation.bend as View

def Laws.archived_terminal(request):
  match request:
    case M.Freeze{}: {==}
    case M.Unfreeze{}: {==}
    case M.Stop{}: {==}
    case M.Archive{}: {==}

def Laws.archived_input_unchanged(id, lineage, contract, history, queue, phase, text):
  {==}

def Laws.frozen_no_dispatch(phase):
  {==}

def Laws.stopped_no_model(phase):
  match phase:
    case M.Idle{}: {==}
    case M.Ready{Nil{}}: {==}
    case M.Ready{Con{call, rest}}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.ToolPending{ticket, call, remaining}: {==}

def Laws.stopped_input_reactivates():
  {==}

def Laws.status_preserves_contract(status, task):
  match task:
    case M.Task{id, lineage, contract, old, history, queued, phase}: {==}

def Laws.phase_preserves_contract(phase, task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, old}: {==}

def Laws.queue_order(first, second, task):
  match task:
    case M.Task{id, lineage, contract, status, history, +queued, phase}:
      Theory.append_associative(String, queued, [first], [second])

def Laws.child_contract(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_history_prefix(id, parent, call, branch, remaining):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_lineage(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_queue_empty(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.unknown_effect_not_repeated(call):
  {==}

def Laws.internal_effect_retry_safe(attempt):
  {==}

def Laws.recover_phase_idempotent(phase):
  match phase:
    case M.Idle{}: {==}
    case M.Ready{calls}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.ToolPending{ticket, call, remaining}: {==}

def Laws.unmatched_model_result_unchanged(outcome, allowed, task, world):
  {==}

def Laws.unmatched_tool_result_unchanged(call, remaining, value, error, task, world):
  {==}

def Laws.history_append_composition(first, second, history):
  match first:
    case Nil{}: {==}
    case Con{+message, +rest}:
      Laws.history_append_composition(rest, second, M.HistoryNode{history, message})

def Laws.replay_composition(first, second, world):
  Theory.replay_composition(~M.World, ~M.Input, ~P.next, first, second, world)

def Laws.replay_empty(world):
  {==}

def read_checked_world(valid: Bool, task: M.Task, after: Nat, limit: Nat, +world: M.World) ->
  {P.decision_world(P.read_checked(valid, task, after, limit, world)) == world : M.World}:
  match valid:
    case False{}: {==}
    case True{}: {==}

def read_found_world(found: Maybe<&2, M.Task>, +after: Nat, +limit: Nat, +world: M.World) ->
  {P.decision_world(P.read_found(found, after, limit, world)) == world : M.World}:
  match found:
    case None{}: {==}
    case Some{+task}:
      read_checked_world(Nat.is_le(1n, limit) && Nat.is_le(limit, 100n) && Nat.is_le(after, M.history_length(M.task_history(task))),
        task, after, limit, world)

def output_admitted_world(fits: Bool, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_world(decision) == previous : M.World}) ->
  {P.decision_world(P.output_admitted(fits, decision, previous)) == previous : M.World}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_world(rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_world(decision) == previous : M.World}) ->
  {P.decision_world(P.admission(rendered, decision, previous)) == previous : M.World}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_world(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def deliver_world(+durable: Bool, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_world(decision) == previous : M.World}) ->
  {P.decision_world(P.deliver(durable, decision, previous)) == previous : M.World}:
  admission_world(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous, evidence)

def Laws.read_preserves_world(id, after, limit, world):
  deliver_world(False{}, P.read(id, after, limit, world), world,
    read_found_world(T.find(P.tasks(world), id), after, limit, world))

def list_world(+world: M.World) -> {P.decision_world(P.list(world)) == world : M.World}:
  match world:
    case M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants}, limits}:
      {==}

def Laws.list_preserves_world(world):
  deliver_world(False{}, P.list(world), world, list_world(world))

def Laws.rejected_delivery_unchanged(decision, world):
  {==}

def Laws.rejected_delivery_no_effects(decision, world):
  {==}

def Laws.context_has_no_call_authority(value):
  {==}

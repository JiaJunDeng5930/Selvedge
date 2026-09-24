import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./LAWS.bend as Laws
import ./bendlib/tasks.bend as T
import ./bendlib/theory.bend as Theory
import ./bendlib/json.bend as J
import ./bendlib/presentation.bend as View
import ./INVARIANTS.bend as I

def Laws.initial_world_valid():
  {==}

def admitted_certificate(+state_valid: Bool, +change_valid: Bool, +decision: M.Decision, +previous: M.World,
  state_checked: {P.valid_world(decision) == state_valid : Bool},
  change_checked: {I.decision(previous, decision) == change_valid : Bool}) ->
  Laws.Admitted(previous, P.admitted(state_valid, change_valid, decision, previous)):
  match state_valid change_valid:
    case True{} True{}: Done{(state_checked, change_checked)}
    case True{} False{}: Fail{({==}, {==})}
    case False{} _: Fail{({==}, {==})}

def live_certificate(+decision: M.Decision, +previous: M.World) ->
  Laws.Admitted(previous, P.check_live(decision, previous)):
  admitted_certificate(P.valid_world(decision), I.decision(previous, decision), decision, previous, {==}, {==})

def checked_certificate(decision: M.Decision, +previous: M.World) ->
  Laws.Admitted(previous, P.checked(decision, previous)):
  live_certificate(P.live_decision(decision), previous)

def output_certificate(fits: Bool, +decision: M.Decision, +previous: M.World,
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.output_admitted(fits, decision, previous)):
  match fits:
    case True{}: certificate
    case False{}: Fail{({==}, {==})}

def admission_certificate(rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World,
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.admission(rendered, decision, previous)):
  match rendered:
    case Fail{error}: Fail{({==}, {==})}
    case Done{text}:
      output_certificate(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, certificate)

def deliver_certificate(+durable: Bool, +decision: M.Decision, +previous: M.World,
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.deliver(durable, decision, previous)):
  admission_certificate(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}),
    decision, previous, certificate)

def update_certificate(+input: M.Input, +world: M.World) -> Laws.Admitted(world, P.update(input, world)):
  +candidate = P.scheduled(M.schedules(input), P.apply(input, world))
  deliver_certificate(M.durable(input), P.checked(candidate, world), world, checked_certificate(candidate, world))

def observe_certificate(query: M.Query, +world: M.World) ->
  Laws.Admitted(world, P.deliver(False{}, P.observe(query, world), world)):
  deliver_certificate(False{}, P.observe(query, world), world, Fail{({==}, {==})})

def Laws.transition_admitted(world, input):
  match input:
    case M.UserCommand{M.Observe{query}}: observe_certificate(query, world)
    case M.UserCommand{M.Create{profile, reasoning, message}}:
      update_certificate(M.UserCommand{M.Create{profile, reasoning, message}}, world)
    case M.UserCommand{M.Send{id, message}}:
      update_certificate(M.UserCommand{M.Send{id, message}}, world)
    case M.UserCommand{M.ChangeStatus{id, control}}:
      update_certificate(M.UserCommand{M.ChangeStatus{id, control}}, world)
    case M.UserCommand{M.Fork{id, count, messages}}:
      update_certificate(M.UserCommand{M.Fork{id, count, messages}}, world)
    case M.ModelCompleted{id, ticket, outcome}:
      update_certificate(M.ModelCompleted{id, ticket, outcome}, world)
    case M.ToolCompleted{id, ticket, value, error}:
      update_certificate(M.ToolCompleted{id, ticket, value, error}, world)
    case M.Configure{settings}: update_certificate(M.Configure{settings}, world)
    case M.Recover{}: update_certificate(M.Recover{}, world)
    case M.Continue{}: update_certificate(M.Continue{}, world)

def certificate_world(+previous: M.World, +decision: M.Decision,
  evidence: {I.world(previous) == True{} : Bool}, certificate: Laws.Admitted(previous, decision)) ->
  {P.valid_world(decision) == True{} : Bool}:
  match certificate:
    case Fail{(unchanged, no_effects)}:
      Equal.trans(Bool, P.valid_world(decision), I.world(previous), True{},
        Equal.cong(M.World, Bool, I.world, P.decision_world(decision), previous, unchanged), evidence)
    case Done{(valid, retained)}: valid

def transition_preserves(+world: M.World, +input: M.Input,
  evidence: {I.world(world) == True{} : Bool}) -> {I.world(P.next(world, input)) == True{} : Bool}:
  certificate_world(world, P.transition(input, world), evidence, Laws.transition_admitted(world, input))

def Laws.transition_preserves_world(world, input, evidence):
  transition_preserves(world, input, evidence)

def Laws.replay_preserves_world(events, world, evidence):
  Theory.replay_invariant(~M.World, ~M.Input, ~P.next, ~I.world,
    ~Laws.transition_preserves_world, events, world, evidence)

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

def Laws.observation_preserves_world(query, world):
  deliver_world(False{}, P.observe(query, world), world, {==})

def output_admitted_no_effects(fits: Bool, +decision: M.Decision, previous: M.World,
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect>}) ->
  {P.decision_effects(P.output_admitted(fits, decision, previous)) == Nil{} : +List<M.Effect>}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_no_effects(rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World,
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect>}) ->
  {P.decision_effects(P.admission(rendered, decision, previous)) == Nil{} : +List<M.Effect>}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_no_effects(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def Laws.observation_has_no_effects(query, world):
  admission_no_effects(J.render(P.rendering_budget(world), J.One{View.envelope(False{}, P.observe(query, world))}),
    P.observe(query, world), world, {==})

def Laws.observation_not_durable(query):
  {==}

def Laws.observation_replay(query, first, second, world):
  Theory.replay_insert_identity(~M.World, ~M.Input, ~P.next, first, second,
    M.UserCommand{M.Observe{query}}, world, Laws.observation_preserves_world(query, P.replay(first, world)))

def Laws.rejected_delivery_unchanged(decision, world):
  {==}

def Laws.rejected_delivery_no_effects(decision, world):
  {==}

def Laws.context_has_no_call_authority(value):
  {==}

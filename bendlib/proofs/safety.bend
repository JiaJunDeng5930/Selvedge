import Base
import ../../FEATURES.bend as Features
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../json.bend as J
import ../presentation.bend as View
import ../../INVARIANTS.bend as I
import ../commit.bend as Commit
import ../notifications.bend as Notifications

# Local proof obligations for the safety boundary. No runtime policy lives here.

def Laws.initial_world_valid():
  {==}

def admitted_certificate(+state_valid: Bool, +change_valid: Bool, +decision: M.Decision(), +previous: M.World(),
  state_checked: {P.valid_world(decision) == state_valid : Bool},
  change_checked: {I.decision(previous, decision) == change_valid : Bool}) ->
  Laws.Admitted(previous, P.admitted(state_valid, change_valid, decision, previous)):
  match state_valid change_valid:
    case True{} True{}: Done{(state_checked, change_checked)}
    case True{} False{}: Fail{({==}, {==})}
    case False{} _: Fail{({==}, {==})}

def live_certificate(+decision: M.Decision(), +previous: M.World()) ->
  Laws.Admitted(previous, P.check_live(decision, previous)):
  admitted_certificate(P.valid_world(decision), I.decision(previous, decision), decision, previous, {==}, {==})

def checked_certificate(decision: M.Decision(), +previous: M.World()) ->
  Laws.Admitted(previous, P.checked(decision, previous)):
  live_certificate(P.live_decision(decision), previous)

def output_certificate(fits: Bool, +decision: M.Decision(), +previous: M.World(),
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.output_admitted(fits, decision, previous)):
  match fits:
    case True{}: certificate
    case False{}: Fail{({==}, {==})}

def admission_certificate(rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.admission(rendered, decision, previous)):
  match rendered:
    case Fail{error}: Fail{({==}, {==})}
    case Done{text}:
      output_certificate(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, certificate)

def deliver_certificate(+durable: Bool, +decision: M.Decision(), +previous: M.World(),
  certificate: Laws.Admitted(previous, decision)) ->
  Laws.Admitted(previous, P.deliver(durable, decision, previous)):
  admission_certificate(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}),
    decision, previous, certificate)

def update_certificate(+input: M.Input, +world: M.World()) -> Laws.Admitted(world, P.update(input, world)):
  +raw = P.apply(input, world)
  +candidate = Notifications.decorate(input, world, P.scheduled(Commit.schedules(input, raw), raw))
  deliver_certificate(M.durable(input), P.checked(candidate, world), world, checked_certificate(candidate, world))

def observe_certificate(query: M.Query, +world: M.World()) ->
  Laws.Admitted(world, P.deliver(False{}, P.observe(query, world), world)):
  deliver_certificate(False{}, P.observe(query, world), world, Fail{({==}, {==})})

def Laws.transition_admitted(world, input):
  match input:
    case M.UserCommand{M.Observe{query}}: observe_certificate(query, world)
    case M.UserCommand{M.FeatureCommand{command}}:
      update_certificate(M.UserCommand{M.FeatureCommand{command}}, world)
    case M.UserCommand{M.Create{profile, reasoning, message, options}}:
      update_certificate(M.UserCommand{M.Create{profile, reasoning, message, options}}, world)
    case M.UserCommand{M.Send{id, message}}:
      update_certificate(M.UserCommand{M.Send{id, message}}, world)
    case M.UserCommand{M.Steer{id, message}}:
      update_certificate(M.UserCommand{M.Steer{id, message}}, world)
    case M.UserCommand{M.Cancel{id, ticket}}:
      update_certificate(M.UserCommand{M.Cancel{id, ticket}}, world)
    case M.UserCommand{M.ChangeStatus{id, control}}:
      update_certificate(M.UserCommand{M.ChangeStatus{id, control}}, world)
    case M.UserCommand{M.Fork{id, count, messages, options}}:
      update_certificate(M.UserCommand{M.Fork{id, count, messages, options}}, world)
    case M.UserCommand{M.Compact{id, summary}}:
      update_certificate(M.UserCommand{M.Compact{id, summary}}, world)
    case M.UserCommand{M.CreateProject{name, workspace, guidance}}:
      update_certificate(M.UserCommand{M.CreateProject{name, workspace, guidance}}, world)
    case M.UserCommand{M.UpdateProject{id, name, workspace, guidance}}:
      update_certificate(M.UserCommand{M.UpdateProject{id, name, workspace, guidance}}, world)
    case M.UserCommand{M.DeleteProject{id}}:
      update_certificate(M.UserCommand{M.DeleteProject{id}}, world)
    case M.UserCommand{M.ReviewApproval{id, operation, outcome}}:
      update_certificate(M.UserCommand{M.ReviewApproval{id, operation, outcome}}, world)
    case M.ModelCompleted{id, ticket, outcome}:
      update_certificate(M.ModelCompleted{id, ticket, outcome}, world)
    case M.ReasoningCompleted{id, ticket, outcome}:
      update_certificate(M.ReasoningCompleted{id, ticket, outcome}, world)
    case M.FeatureCompleted{completion}:
      update_certificate(M.FeatureCompleted{completion}, world)
    case M.ToolCompleted{id, ticket, value, error}:
      update_certificate(M.ToolCompleted{id, ticket, value, error}, world)
    case M.HookCompleted{id, ticket, outcome}: update_certificate(M.HookCompleted{id, ticket, outcome}, world)
    case M.AfterCompleted{id, operation, ticket, outcome}: update_certificate(M.AfterCompleted{id, operation, ticket, outcome}, world)
    case M.ApprovalCompleted{id, ticket, outcome}: update_certificate(M.ApprovalCompleted{id, ticket, outcome}, world)
    case M.Configure{settings}: update_certificate(M.Configure{settings}, world)
    case M.Recover{}: update_certificate(M.Recover{}, world)
    case M.Continue{}: update_certificate(M.Continue{}, world)

def certificate_world(+previous: M.World(), +decision: M.Decision(),
  evidence: {I.world(previous) == True{} : Bool}, certificate: Laws.Admitted(previous, decision)) ->
  {P.valid_world(decision) == True{} : Bool}:
  match certificate:
    case Fail{(unchanged, no_effects)}:
      Equal.trans(Bool, P.valid_world(decision), I.world(previous), True{},
        Equal.cong(M.World(), Bool, world => I.world(world), P.decision_world(decision), previous, unchanged), evidence)
    case Done{(valid, retained)}: valid

def transition_preserves(+world: M.World(), +input: M.Input,
  evidence: {I.world(world) == True{} : Bool}) -> {I.world(P.next(world, input)) == True{} : Bool}:
  certificate_world(world, P.transition(input, world), evidence, Laws.transition_admitted(world, input))

def Laws.transition_preserves_world(world, input, evidence):
  transition_preserves(world, input, evidence)

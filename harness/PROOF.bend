import Base
import ./tasks/PROOF.bend as TaskProof
import ./features/PROOF.bend as FrameProof
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ./reasoning/PROOF.bend as ReasoningProof
import ./features/MODEL.bend as F
import ../features/board/MODEL.bend as Board
import ./MODEL.bend as M
import ../features/board/STATE.bend as BoardState
import ./LOCALITY.bend as Rule
import ./PROGRAM.bend as P
import ./LAWS.bend as Laws
import ../bendlib/json.bend as J
import ./transport/presentation.bend as View
import ./INVARIANTS.bend as I
import ./protocol/COMMIT.bend as Commit
import ./execution/notifications.bend as Notifications

def board_frame(value: Board.State, world: M.World()) ->
  {F.rest(C.rest(D.State, F.State(), BoardState.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()}:
  match world:
    case C.Frame{core, state}: FrameProof.board_frame(value, state)

def board_core_frame(value: Board.State, world: M.World()) ->
  {C.local(D.State, F.State(), BoardState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, state}: {==}

def locality() -> Rule.Locality:
  Rule.Locality{
    Rule.TaskStorage{
      R => +task => +state => +rest => TaskProof.update_meaning(R, task, state, rest),
      R => task => world => TaskProof.update_frame(R, task, world),
      task => world => {==}},
    Rule.ReasoningComponent{
      R => X => +task => +world => ReasoningProof.start_meaning(R, X, task, world),
      R => X => task => world => ReasoningProof.start_frame(R, X, task, world),
      task => world => ReasoningProof.start_frame(F.State(), F.Effect, task, world)},
    Rule.BoardStorage{
      +value => state => FrameProof.board_written(value, state),
      value => world => board_frame(value, world),
      value => world => board_core_frame(value, world)}}

# Local proof obligations for the observations boundary. No runtime policy lives here.

def output_admitted_world(fits: Bool, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(P.output_admitted(fits, decision, previous)) == previous : M.World()}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_world(rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(P.admission(rendered, decision, previous)) == previous : M.World()}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_world(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def deliver_world(+durable: Bool, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(P.deliver(durable, decision, previous)) == previous : M.World()}:
  admission_world(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous, evidence)

def Laws.observation_preserves_world(query, world):
  deliver_world(False{}, P.observe(query, world), world, {==})

def output_admitted_no_effects(fits: Bool, +decision: M.Decision(), previous: M.World(),
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}) ->
  {P.decision_effects(P.output_admitted(fits, decision, previous)) == Nil{} : +List<M.Effect()>}:
  match fits:
    case True{}: evidence
    case False{}: {==}

def admission_no_effects(rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}) ->
  {P.decision_effects(P.admission(rendered, decision, previous)) == Nil{} : +List<M.Effect()>}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      output_admitted_no_effects(Nat.is_le(J.utf8_length(text), U32.to_nat(P.frame_limit(previous))), decision, previous, evidence)

def Laws.observation_has_no_effects(query, world):
  admission_no_effects(J.render(P.rendering_budget(world), J.One{View.envelope(False{}, P.observe(query, world))}),
    P.observe(query, world), world, {==})

def Laws.observation_not_durable(query):
  {==}

def Laws.delivery_observation_world(durable, decision, previous, unchanged):
  deliver_world(durable, decision, previous, unchanged)

def Laws.delivery_observation_effects(durable, decision, previous, silent):
  admission_no_effects(J.render(P.rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous, silent)

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

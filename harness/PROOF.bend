import ./search/PROOF.bend as SearchProof
import ./conversation/speech-proof.bend as SpeechProof
import Base
import ./tasks/PROOF.bend as TaskProof
import ./features/PROOF.bend as FrameProof
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ./reasoning/PROOF.bend as ReasoningProof
import ./reasoning/PROGRAM.bend as Reasoning
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
import ../features/compaction/SPEC.bend as CompactionSpec
import ./protocol/COMMIT.bend as Commit
import ./protocol/commit-proof.bend as CommitProof
import ../bendlib/categories.bend as Categories
import ./execution/notifications.bend as Notifications

def board_frame(value: Board.State, world: M.World()) ->
  {F.modules(C.rest(D.State, F.State(), BoardState.store(value, world))) == F.modules(C.rest(D.State, F.State(), world)) : F.Modules()}:
  match world:
    case C.Frame{core, state}: FrameProof.board_frame(value, state)

def board_core_frame(value: Board.State, world: M.World()) ->
  {C.local(D.State, F.State(), BoardState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, state}: {==}

# Target encoding changes effects only; the reasoning component still preserves
# the assembled feature state for every input world.
def attached_remaining(+decision: M.Decision()) ->
  {C.remaining(D.State, F.State(), M.Effect(), CompactionSpec.attach(decision)) ==
    C.remaining(D.State, F.State(), M.Effect(), decision) : F.State()}:
  match decision:
    case C.Decision{C.Frame{core, features}, reply, effects}: {==}

def production_reasoning_frame(+task: D.Task, +world: M.World()) ->
  {C.remaining(D.State, F.State(), M.Effect(), P.model_request_direct(task, world)) == C.rest(D.State, F.State(), world) : F.State()}:
  Equal.trans(F.State(),
    C.remaining(D.State, F.State(), M.Effect(), P.model_request_direct(task, world)),
    C.remaining(D.State, F.State(), M.Effect(), Reasoning.start(F.State(), F.Effect, task, world)),
    C.rest(D.State, F.State(), world),
    attached_remaining(Reasoning.start(F.State(), F.Effect, task, world)),
    ReasoningProof.start_frame(F.State(), F.Effect, task, world))

def locality() -> Rule.Locality:
  Rule.Locality{
    Rule.TaskStorage{
      R => +task => +state => +rest => TaskProof.update_meaning(R, task, state, rest),
      R => task => world => TaskProof.update_frame(R, task, world),
      task => world => {==}},
    Rule.ReasoningComponent{
      R => X => +task => +world => ReasoningProof.start_meaning(R, X, task, world),
      R => X => task => world => ReasoningProof.start_frame(R, X, task, world),
      task => world => production_reasoning_frame(task, world)},
    Rule.BoardStorage{
      +value => state => FrameProof.board_written(value, state),
      value => world => board_frame(value, world),
      value => world => board_core_frame(value, world)}}

# Local proof obligations for the observations boundary. No runtime policy lives here.

def sized_world(+previous: M.World(), admitted: Maybe<&1, Categories.Membership<String, Commit.bounded_envelope(previous)>>,
  +decision: M.Decision(), evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(Commit.sized_admitted(previous, admitted, decision)) == previous : M.World()}:
  match admitted:
    case Some{Categories.Membership{member_text, bounded_evidence}}: evidence
    case None{}: {==}

def rendered_world(+rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(Commit.rendered(rendered, decision, previous)) == previous : M.World()}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      sized_world(previous, Categories.admit(String, value => Commit.envelope_fits(previous, value), text), decision, evidence)

def deliver_world(+durable: Bool, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_world(decision) == previous : M.World()}) ->
  {P.decision_world(Commit.deliver(durable, decision, previous)) == previous : M.World()}:
  rendered_world(J.render(D.state_render_budget(C.local(D.State, F.State(), previous)), J.One{View.envelope(durable, decision)}), decision, previous, evidence)

def Laws.observation_preserves_world(query, world):
  Equal.trans(M.World(), P.decision_world(P.transition(M.UserCommand{M.Observe{query}}, world)),
    P.decision_world(Commit.deliver(False{}, P.observe(query, world), world)), world,
    Equal.cong(M.Decision(), M.World(), P.decision_world, P.transition(M.UserCommand{M.Observe{query}}, world),
      Commit.deliver(False{}, P.observe(query, world), world), CommitProof.observation_projection(query, world)),
    deliver_world(False{}, P.observe(query, world), world, {==}))

def sized_no_effects(+previous: M.World(), admitted: Maybe<&1, Categories.Membership<String, Commit.bounded_envelope(previous)>>,
  +decision: M.Decision(), evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}) ->
  {P.decision_effects(Commit.sized_admitted(previous, admitted, decision)) == Nil{} : +List<M.Effect()>}:
  match admitted:
    case Some{Categories.Membership{member_text, bounded_evidence}}: evidence
    case None{}: {==}

def rendered_no_effects(+rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World(),
  evidence: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}) ->
  {P.decision_effects(Commit.rendered(rendered, decision, previous)) == Nil{} : +List<M.Effect()>}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      sized_no_effects(previous, Categories.admit(String, value => Commit.envelope_fits(previous, value), text), decision, evidence)

def Laws.observation_has_no_effects(query, world):
  Equal.trans(+List<M.Effect()>, P.decision_effects(P.transition(M.UserCommand{M.Observe{query}}, world)),
    P.decision_effects(Commit.deliver(False{}, P.observe(query, world), world)), Nil{},
    Equal.cong(M.Decision(), +List<M.Effect()>, P.decision_effects, P.transition(M.UserCommand{M.Observe{query}}, world),
      Commit.deliver(False{}, P.observe(query, world), world), CommitProof.observation_projection(query, world)),
    rendered_no_effects(J.render(D.state_render_budget(C.local(D.State, F.State(), world)), J.One{View.envelope(False{}, P.observe(query, world))}),
      P.observe(query, world), world, {==}))

def Laws.observation_not_durable(query):
  {==}

def Laws.delivery_observation_world(durable, decision, previous, unchanged):
  deliver_world(durable, decision, previous, unchanged)

def Laws.delivery_observation_effects(durable, decision, previous, silent):
  rendered_no_effects(J.render(D.state_render_budget(C.local(D.State, F.State(), previous)), J.One{View.envelope(durable, decision)}), decision, previous, silent)

# Local proof obligations for the safety boundary. No runtime policy lives here.

def Laws.initial_world_valid():
  {==}

def Laws.transition_admitted(world, input):
  Commit.evidence(world, P.construct_transition(input, world))

def certificate_candidate(+previous: M.World(), +world: M.World(), reply: J.Json, effects: +List<M.Effect()>,
  evidence: {I.world(previous) == True{} : Bool}, certificate: Laws.Admitted(previous, C.Decision{world, reply, effects})) ->
  {I.world(world) == True{} : Bool}:
  match certificate:
    case Fail{(unchanged, no_effects)}:
      Equal.trans(Bool, I.world(world), I.world(previous), True{},
        Equal.cong(M.World(), Bool, state => I.world(state), world, previous, unchanged), evidence)
    case Done{(valid, retained)}: valid

def certificate_world(+previous: M.World(), +decision: M.Decision(),
  evidence: {I.world(previous) == True{} : Bool}, certificate: Laws.Admitted(previous, decision)) ->
  {I.world(P.decision_world(decision)) == True{} : Bool}:
  match decision:
    case C.Decision{world, reply, effects}: certificate_candidate(previous, world, reply, effects, evidence, certificate)

def transition_preserves(+world: M.World(), +input: M.Input,
  evidence: {I.world(world) == True{} : Bool}) -> {I.world(P.next(world, input)) == True{} : Bool}:
  certificate_world(world, P.transition(input, world), evidence, Laws.transition_admitted(world, input))

def Laws.transition_preserves_world(world, input, evidence):
  transition_preserves(world, input, evidence)

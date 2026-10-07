import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../INVARIANTS.bend as I
import ../LAWS.bend as Laws
import ./MODEL.bend as Reach
import ../CONTRACT.bend as A
import ../../bendlib/relations.bend as R
import ../../bendlib/stdlib.bend as Std
import ../protocol/COMMIT.bend as Commit
import ../execution/PROGRAM.bend as Execution
import ./PROGRAM.bend as Traces
import ../conversation/MODEL.bend as Transcript
import ../protocol/commit-proof.bend as CommitProof
import ../PROOF.bend as SafetyProof
import ../DOMAIN.bend as D
import ../../bendlib/theory.bend as Theory

# Only this one-step square depends on Selvedge's operation semantics.
def exact(+input: M.Input, +state: Reach.State) ->
  {Reach.actual(input, state) == Reach.specified(input, state) : Reach.State}:
  Reach.State{world, receipts} = state
  Equal.cong(M.Decision(), Reach.State, (decision => Reach.record(decision, receipts)),
    P.transition(input, world), Commit.input(~Execution.scheduled, input, world),
    Laws.interaction_transition(input, world))

def simulation(-start: Reach.State, -end: Reach.State, edge: Reach.actual_edge(start, end)) ->
  Reach.specification_path(start, end):
  Reach.ResolvedEvent{+input, +source, before, after} = edge
  R.Step{Reach.ResolvedEvent{input, source, before,
    Equal.trans(Reach.State, end, Reach.actual(input, source), Reach.specified(input, source),
      after, exact(input, source))}}

def validity(-start: Reach.State, -end: Reach.State, same: {start == end : Reach.State}, evidence: Reach.valid(start)) -> Reach.valid(end):
  %same : Reach.valid(_)
  evidence

def input_safe(input: M.Input, +state: Reach.State, evidence: Reach.valid(state)) -> Reach.valid(Reach.actual(input, state)):
  Reach.State{world, receipts} = state
  Laws.transition_preserves_world(world, input, evidence)

def preserves(-start: Reach.State, -end: Reach.State, evidence: Reach.valid(start), edge: Reach.actual_edge(start, end)) -> Reach.valid(end):
  Reach.ResolvedEvent{+input, +source, before, after} = edge
  validity(Reach.actual(input, source), end,
    Equal.sym(Reach.State, end, Reach.actual(input, source), after),
    input_safe(input, source, validity(start, source, before, evidence)))

def meaning(-start: Reach.State, -end: Reach.State, proof: Reach.path(start, end)) -> Reach.specification_path(start, end):
  R.closure_map(~Reach.State, ~Reach.State, ~Reach.actual_edge, ~Reach.specified_edge,
    ~(state => state), ~simulation, start, end, proof)

def safety(-start: Reach.State, -end: Reach.State, proof: Reach.path(start, end), evidence: Reach.valid(start)) -> Reach.valid(end):
  R.closure_invariant(~Reach.State, ~Reach.actual_edge, ~Reach.valid, ~preserves, start, end, proof, evidence)

# This induction establishes only the representation correspondence from the
# concrete journal fold to input-labelled edges. Reachability algebra, arbitrary
# batching, simulation and safety are not re-proved over project traces.
def Journal(events: +List<M.Input>) -> Type:
  @+state:Reach.State -> Reach.path(state, Reach.run(events, state))

def empty(+state: Reach.State) -> Reach.path(state, Reach.run(Nil{}, state)):
  R.rt_refl(Reach.State, Reach.actual_edge, state)

def prepend(+input: M.Input, +rest: +List<M.Input>, induction: Journal(rest), +state: Reach.State) ->
  Reach.path(state, Reach.run(input <> rest, state)):
  R.rt_trans(Reach.State, Reach.actual_edge, state, Reach.actual(input, state), Reach.run(input <> rest, state),
    Reach.one(input, state), induction(Reach.actual(input, state)))

def journal(events: +List<M.Input>, state: Reach.State) -> Reach.path(state, Reach.run(events, state)):
  Std.list_ind(~M.Input, ~Journal, ~empty,
    ~(input => rest => induction => state => prepend(input, rest, induction, state)), events)(state)

def Replay(events: +List<M.Input>) -> Type:
  @+state:Reach.State -> {Reach.world(Reach.run(events, state)) == P.replay(events, Reach.world(state)) : M.World()}

def replay_empty(+state: Reach.State) ->
  {Reach.world(Reach.run(Nil{}, state)) == P.replay(Nil{}, Reach.world(state)) : M.World()}:
  {==}

def replay_prepend(+input: M.Input, +rest: +List<M.Input>, induction: Replay(rest), +state: Reach.State) ->
  {Reach.world(Reach.run(input <> rest, state)) == P.replay(input <> rest, Reach.world(state)) : M.World()}:
  Reach.State{world, receipts} = state
  induction(Reach.actual(input, Reach.State{world, receipts}))

def replay(events: +List<M.Input>, state: Reach.State) ->
  {Reach.world(Reach.run(events, state)) == P.replay(events, Reach.world(state)) : M.World()}:
  Std.list_ind(~M.Input, ~Replay, ~replay_empty,
    ~(input => rest => induction => state => replay_prepend(input, rest, induction, state)), events)(state)

def ReceiptCorrespondence(events: +List<M.Input>) -> Type:
  @+state:Reach.State -> {Reach.run(events, state) == Reach.execute(events, state) : Reach.State}

def receipts_empty(+state: Reach.State) -> {Reach.run(Nil{}, state) == Reach.execute(Nil{}, state) : Reach.State}:
  Reach.State{world, receipts} = state
  {==}

def receipts_prepend(+input: M.Input, +rest: +List<M.Input>, induction: ReceiptCorrespondence(rest), +state: Reach.State) ->
  {Reach.run(input <> rest, state) == Reach.execute(input <> rest, state) : Reach.State}:
  Reach.State{+world, +receipts} = state
  +tape : Transcript.Tape = Transcript.Tape{world, input <> rest, receipts}
  +count = List.length(&2, M.Input, rest)
  Equal.trans(Reach.State,
    Reach.run(input <> rest, Reach.State{world, receipts}),
    Reach.execute(rest, Reach.actual(input, Reach.State{world, receipts})),
    Reach.execute(input <> rest, Reach.State{world, receipts}),
    induction(Reach.actual(input, Reach.State{world, receipts})),
    Equal.cong(Transcript.Tape, Reach.State, Reach.project,
      Traces.actual(count, Traces.implementation(tape)), Traces.actual(1n+count, tape),
      Equal.sym(Transcript.Tape, Traces.actual(1n+count, tape), Traces.actual(count, Traces.implementation(tape)),
        Std.iter_swap_gen(~Transcript.Tape, ~Transcript.Tape, ~Traces.implementation, ~Traces.implementation, ~Traces.implementation, ~(tape => {==}), count, tape))))

def receipts(events: +List<M.Input>, state: Reach.State) ->
  {Reach.run(events, state) == Reach.execute(events, state) : Reach.State}:
  Std.list_ind(~M.Input, ~ReceiptCorrespondence, ~receipts_empty,
    ~(input => rest => induction => state => receipts_prepend(input, rest, induction, state)), events)(state)

def A.protocol_reachability():
  Reach.Protocol{Reach.one, Reach.preorder(), Reach.batches, meaning, safety, journal, receipts, replay}

# Local proof obligations for the traces boundary. No runtime policy lives here.

def Laws.trace_step(tape):
  match tape:
    case Transcript.Tape{world, Nil{}, receipts}: {==}
    case Transcript.Tape{world, Con{input, pending}, receipts}:
      Equal.cong(M.Decision(), Transcript.Tape, (decision => Transcript.record(decision, pending, receipts)),
        P.transition(input, world), Commit.input(~Execution.scheduled, input, world),
        Laws.interaction_transition(input, world))

def Laws.trace_partition(first, second, tape):
  Std.iter_add(~Transcript.Tape, ~Traces.implementation, first, second, tape)

def TraceInterpretation(events: +List<M.Input>) -> Type:
  @+world:M.World() -> @+receipts:+List<M.Decision()> ->
    {Transcript.state(Traces.actual(List.length(&2, M.Input, events), Transcript.Tape{world, events, receipts})) == P.replay(events, world) : M.World()}

def trace_empty(+world: M.World(), +receipts: +List<M.Decision()>) ->
  {Transcript.state(Traces.actual(0n, Transcript.Tape{world, Nil{}, receipts})) == P.replay(Nil{}, world) : M.World()}:
  {==}

def trace_cons(+input: M.Input, +rest: +List<M.Input>, induction: TraceInterpretation(rest),
  +world: M.World(), +receipts: +List<M.Decision()>) ->
  {Transcript.state(Traces.actual(List.length(&2, M.Input, input <> rest), Transcript.Tape{world, input <> rest, receipts})) == P.replay(input <> rest, world) : M.World()}:
  +count = List.length(&2, M.Input, rest)
  +tape : Transcript.Tape = Transcript.Tape{world, input <> rest, receipts}
  Equal.trans(M.World(), Transcript.state(Traces.actual(1n+count, tape)),
    Transcript.state(Traces.actual(count, Traces.implementation(tape))), P.replay(input <> rest, world),
    Equal.cong(Transcript.Tape, M.World(), Transcript.state,
      Traces.actual(1n+count, tape), Traces.actual(count, Traces.implementation(tape)),
      Std.iter_swap_gen(~Transcript.Tape, ~Transcript.Tape, ~Traces.implementation, ~Traces.implementation, ~Traces.implementation, ~(tape => {==}), count, tape)),
    induction(P.next(world, input), P.transition(input, world) <> receipts))

def Laws.trace_interpretation(events, world):
  Std.list_ind(~M.Input, ~TraceInterpretation, ~trace_empty,
    ~(input => rest => induction => +world => +receipts => trace_cons(input, rest, induction, world, receipts)), events)(world, Nil{})

def trace_preserves(+tape: Transcript.Tape, evidence: {Transcript.valid(tape) == True{} : Bool}) ->
  {Transcript.valid(Traces.implementation(tape)) == True{} : Bool}:
  match tape:
    case Transcript.Tape{world, Nil{}, receipts}: evidence
    case Transcript.Tape{world, Con{input, pending}, receipts}:
      Laws.transition_preserves_world(world, input, evidence)

def Laws.replay_preserves_world(events, world, evidence):
  +count = List.length(&2, M.Input, events)
  +tape : Transcript.Tape = Transcript.Tape{world, events, Nil{}}
  Equal.trans(Bool, I.world(P.replay(events, world)), I.world(Traces.replay(events, world)), True{},
    Equal.cong(M.World(), Bool, world => I.world(world), P.replay(events, world), Traces.replay(events, world),
      Equal.sym(M.World(), Traces.replay(events, world), P.replay(events, world), Laws.trace_interpretation(events, world))),
    Std.iter_ind(~Transcript.Tape, ~Traces.implementation, ~(count => tape => {Transcript.valid(tape) == True{} : Bool}),
      ~(count => tape => evidence => trace_preserves(tape, evidence)), tape, evidence, count))

def Laws.history_append_composition(first, second, history):
  Std.fold_left_app(~D.History, ~D.Message, ~D.history_step, first, second, history)

def Laws.replay_composition(first, second, world):
  Std.fold_left_app(~M.World(), ~M.Input, ~P.next, first, second, world)

def Laws.replay_empty(world):
  {==}

def Laws.observation_replay(query, first, second, world):
  Theory.replay_insert_identity(~M.World(), ~M.Input, ~P.next, first, second,
    M.UserCommand{M.Observe{query}}, world, Laws.observation_preserves_world(query, P.replay(first, world)))

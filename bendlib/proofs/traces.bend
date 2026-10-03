import Base
import ../domain.bend as D
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../theory.bend as Theory
import ../stdlib.bend as Std
import ../../INVARIANTS.bend as I
import ../commit.bend as Commit
import ../architecture.bend as Concepts
import ../execution.bend as Execution
import ../traces.bend as Traces
import ../transcript.bend as Transcript
import ./commit.bend as CommitProof
import ./observations.bend as ObservationsProof
import ./safety.bend as SafetyProof

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
    Equal.cong(M.World(), Bool, I.world, P.replay(events, world), Traces.replay(events, world),
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

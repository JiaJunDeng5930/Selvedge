import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../INVARIANTS.bend as I
import ../protocol/COMMIT.bend as Commit
import ../execution/PROGRAM.bend as Execution
import ../../bendlib/relations.bend as R
import ./PROGRAM.bend as Traces
import ../conversation/MODEL.bend as Transcript

# The carrier retains the complete committed decisions, not just the world.
# An edge chooses one real external input; its witnesses bind both endpoints
# to the production interpreter. This admits every ordering of independent
# completions, without assuming their external effects commute or terminate.
type State is Data:
  State{world: M.World(), receipts: +List<M.Decision()>}

def world(state: State) -> M.World():
  State{world, receipts} = state
  world

def record(+decision: M.Decision(), receipts: +List<M.Decision()>) -> State:
  State{P.decision_world(decision), decision <> receipts}

def project(tape: Transcript.Tape) -> State:
  Transcript.Tape{world, pending, receipts} = tape
  State{world, receipts}

def execute(+events: +List<M.Input>, state: State) -> State:
  State{world, receipts} = state
  project(Traces.actual(List.length(&2, M.Input, events), Transcript.Tape{world, events, receipts}))

def actual(input: M.Input, state: State) -> State:
  State{world, receipts} = state
  record(P.transition(input, world), receipts)

def specified(input: M.Input, state: State) -> State:
  State{world, receipts} = state
  record(Commit.input(~Execution.scheduled, input, world), receipts)

type Edge<-step: M.Input -> State -> State, -start: State, -end: State> is Type:
  ResolvedEvent{input: M.Input, source: State,
    before: {start == source : State}, after: {end == step(input, source) : State}}

def actual_edge(-start: State, -end: State) -> Type:
  Edge<actual, start, end>

def specified_edge(-start: State, -end: State) -> Type:
  Edge<specified, start, end>

def path(-start: State, -end: State) -> Type:
  R.Closure<State, actual_edge, start, end>

def specification_path(-start: State, -end: State) -> Type:
  R.Closure<State, specified_edge, start, end>

def valid(-state: State) -> Type:
  {I.world(world(state)) == True{} : Bool}

def one(input: M.Input, state: State) -> path(state, actual(input, state)):
  R.Step{ResolvedEvent{input, state, {==}, {==}}}

def advance(state: State, input: M.Input) -> State:
  actual(input, state)

def run(events: +List<M.Input>, state: State) -> State:
  List.foldl(~&2, ~M.Input, ~State, ~advance, events, state)

# These results come from the original relation library, not project recursion.

def bind_preorder(evidence: R.Preorder<State, (first => last => R.Closure<State, actual_edge, first, last>)>) -> R.Preorder<State, path>:
  R.Preorder{reflexive, transitive} = evidence
  R.Preorder{(state => reflexive(state)),
    (first => middle => last => left => right => transitive(first, middle, last, left, right))}

def preorder() -> R.Preorder<State, path>:
  bind_preorder(R.clos_rt_is_preorder(~State, ~actual_edge))

def batches(-start: State, -end: State, proof: R.Closure<State, path, start, end>) -> path(start, end):
  R.clos_rt_idempotent(~State, ~actual_edge, start, end, proof)

# A relational protocol is the standard closure of its actual input-labelled
# edges. The project owes only single-step meaning/safety and the journal/fold
# correspondence. The imported theorems supply arbitrary-path lifting.

type Protocol is Type:
  Protocol{
    input: @input:M.Input -> @state:State -> path(state, actual(input, state)),
    composition: R.Preorder<State, path>,
    batching: @-start:State -> @-end:State -> R.Closure<State, path, start, end> -> path(start, end),
    meaning: @-start:State -> @-end:State -> path(start, end) -> specification_path(start, end),
    safety: @-start:State -> @-end:State -> path(start, end) -> valid(start) -> valid(end),
    journal: @events:+List<M.Input> -> @state:State -> path(state, run(events, state)),
    receipts: @events:+List<M.Input> -> @state:State -> {run(events, state) == execute(events, state) : State},
    replay: @events:+List<M.Input> -> @state:State ->
      {world(run(events, state)) == P.replay(events, world(state)) : M.World()}}

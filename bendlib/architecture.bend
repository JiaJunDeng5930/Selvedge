import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../INVARIANTS.bend as I
import ./tasks.bend as T
import ./commit.bend as Commit
import ./structures.bend as S
import ./protocol.bend as Protocol
import ./execution.bend as Execution
import ./json.bend as J
import ../COMMANDS.bend as Commands
import ./traces.bend as Traces
import ./transcript.bend as Transcript
import ./interface.bend as Interface
import ./frontend.bend as Frontend

# Concrete bindings for the conceptual entry in ../CONCEPTS.bend. These indices
# name the actual production operations. PROOF supplies the correspondences;
# standard results are instantiated from imported, checked proof terms.

def specification(command: M.Command, world: M.World) -> M.Decision:
  Commit.command(~Execution.scheduled, command, world)

def implementation(command: M.Command, world: M.World) -> M.Decision:
  P.transition(M.UserCommand{command}, world)

def CommandMeaning() -> Type:
  S.Refinement<M.World, M.Command, M.Decision, specification, implementation>

law commands:
  CommandMeaning()

def interaction_specification(input: M.Input, world: M.World) -> M.Decision:
  Commit.input(~Execution.scheduled, input, world)

def interaction_implementation(input: M.Input, world: M.World) -> M.Decision:
  P.transition(input, world)

def observation(query: M.Query, world: M.World) -> M.Decision:
  P.transition(M.UserCommand{M.Observe{query}}, world)

def InputMeaning() -> Type:
  S.Refinement<M.World, M.Input, M.Decision, interaction_specification, interaction_implementation>

law interactions:
  InputMeaning()

def StateMachine() -> Type:
  S.InvariantSystem<M.World, M.Input, M.initial(), P.next, I.world>

law task_machine:
  StateMachine()

# Inputs, messages, queued user text, and effect intents use the same free-monoid
# theory. Replay and history extension are its right actions, not special cases.
def inputs() -> S.Monoid<+List<M.Input>, Nil{}, S.append(M.Input)>:
  S.list_monoid(M.Input)

def inbox() -> S.Monoid<+List<String>, Nil{}, S.append(String)>:
  S.list_monoid(String)

def effects() -> S.Monoid<+List<M.Effect>, Nil{}, S.append(M.Effect)>:
  S.list_monoid(M.Effect)

def JournalAction() -> Type:
  S.RightAction<M.World, +List<M.Input>, Nil{}, S.append(M.Input), S.act(~M.World, ~M.Input, ~P.next)>

def journal() -> JournalAction():
  S.list_action(~M.World, ~M.Input, ~P.next)

def HistoryAction() -> Type:
  S.RightAction<M.History, +List<M.Message>, Nil{}, S.append(M.Message), S.act(~M.History, ~M.Message, ~M.history_step)>

def history() -> HistoryAction():
  S.list_action(~M.History, ~M.Message, ~M.history_step)

law journal_interpretation:
  for +world: M.World
  for +inputs: +List<M.Input>
  {P.replay(inputs, world) == S.act(~M.World, ~M.Input, ~P.next, world, inputs) : M.World}

law history_interpretation:
  for +history: M.History
  for +messages: +List<M.Message>
  {M.history_append(messages, history) == S.act(~M.History, ~M.Message, ~M.history_step, history, messages) : M.History}

# Decisions have associative composition, but no global identity: the first
# reply and the last world have different ownership. Only effects form a monoid.
def DecisionComposition() -> Type:
  S.Semigroup<M.Decision, P.combine>

law decisions:
  DecisionComposition()

# A context cut, recovery normalization, and interruption are three different
# idempotent projections. Idempotence does not assert summary fidelity or undo.
def ContextProjection() -> Type:
  S.Projection<M.History, M.context_history>

law context:
  ContextProjection()

def RecoveryProjection() -> Type:
  S.Projection<M.Phase, T.recover_phase>

law recovery:
  RecoveryProjection()

def InterruptionProjection() -> Type:
  S.Projection<M.Task, T.interrupt>

law interruption:
  InterruptionProjection()

def Observations() -> Type:
  S.ReadOnly<M.World, M.Query, M.Decision, M.Effect, observation, P.decision_world, P.decision_effects>

law observations:
  Observations()

# Batch recovery and public views are monoid homomorphisms. Their partition and
# composition laws are imported map theorems, not special recovery/API proofs.
def RecoveryBatches() -> Type:
  S.Homomorphism<+List<M.Task>, +List<M.Task>, Nil{}, S.append(M.Task), Nil{}, S.append(M.Task), Protocol.recovery>

law recovery_batches:
  RecoveryBatches()

def TaskViews() -> Type:
  S.Homomorphism<+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json), T.summaries>

law task_views:
  TaskViews()

def BranchResults() -> Type:
  S.Homomorphism<+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json), Commands.identities>

law branch_results:
  BranchResults()

def ActionMeaning() -> Type:
  S.Refinement<M.World, Execution.Action, M.Decision, Execution.meaning, P.realize_action>

law actions:
  ActionMeaning()

def scheduling_specification(enabled: Bool, decision: M.Decision) -> M.Decision:
  Execution.scheduled(enabled, decision)

def scheduling_implementation(enabled: Bool, decision: M.Decision) -> M.Decision:
  P.scheduled(enabled, decision)

def SchedulingMeaning() -> Type:
  S.Refinement<M.Decision, Bool, M.Decision, scheduling_specification, scheduling_implementation>

law scheduling:
  SchedulingMeaning()

def TraceSimulation() -> Type:
  S.Simulation<Transcript.Tape, Transcript.Tape, Traces.implementation, Transcript.step,
    Transcript.identity, Traces.actual, Transcript.run>

law traces:
  TraceSimulation()

def NativeInterface() -> Type:
  S.Refinement<M.World, +List<String>, Interface.Output, Interface.packet, Frontend.packet>

law native_interface:
  NativeInterface()

# Interpretation is part of the journal object, rather than a nearby theorem
# that could describe some other fold with the same carrier.
type Journal is Type:
  Journal{action: JournalAction(),
    interpretation: @world:M.World -> @inputs:+List<M.Input> ->
      {P.replay(inputs, world) == S.act(~M.World, ~M.Input, ~P.next, world, inputs) : M.World},
    safe: @inputs:+List<M.Input> -> @world:M.World -> {I.world(world) == True{} : Bool} ->
      {I.world(P.replay(inputs, world)) == True{} : Bool}}

law persistence:
  Journal

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
import ./operations.bend as Ops
import ./stdlib.bend as Std
import ../UI.bend as UI

def user_surface(state: M.ViewState, world: M.World) -> M.Decision:
  P.transition(M.UserInterface{state, M.RefreshView{}}, world)

type UserSurface is Type:
  UserSurface{
    observation: S.ReadOnly<M.World, M.ViewState, M.Decision, M.Effect, user_surface, P.decision_world, P.decision_effects>,
    submission: @state:M.ViewState -> @command:M.Command -> @world:M.World ->
      {P.apply(M.UserInterface{state, M.Submit{command}}, world) == P.apply_command(command, world) : M.Decision},
    action: @key:String -> @label:String -> @command:M.Command -> @world:M.World ->
      {UI.action(key, label, command, world) == UI.Action{key, label, M.Submit{command}, UI.selected(Commands.resolve(command, world)), False{}} : UI.Node},
    form: @key:String -> @title:String -> @label:String -> @command:M.Command -> @fields:+List<UI.Field> -> @world:M.World ->
      {UI.form(key, title, label, command, fields, world) == UI.Form{key, title, label, command, fields, UI.selected(Commands.resolve(command, world))} : UI.Node},
    state: @input:M.Input -> @decision:M.Decision -> {P.decision_world(UI.decorate(input, decision)) == P.decision_world(decision) : M.World},
    effects: @input:M.Input -> @decision:M.Decision -> {P.decision_effects(UI.decorate(input, decision)) == P.decision_effects(decision) : +List<M.Effect>}}

law surface:
  UserSurface

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

def OperationRights() -> Type:
  S.AssociationMap<M.Operation, Ops.ticket, Ops.find, Ops.remove>

law operation_rights:
  OperationRights()

type Announcement is Type:
  Announcement{projection: S.Projection<M.Operation, Ops.announce>,
    ticket: @operation:M.Operation -> {Ops.ticket(Ops.announce(operation)) == Ops.ticket(operation) : Nat},
    call: @operation:M.Operation -> {Ops.call(Ops.announce(operation)) == Ops.call(operation) : M.Call},
    status: @operation:M.Operation -> {Ops.announced(Ops.announce(operation)) == True{} : Bool}}

law announcement:
  Announcement

type Notifications is Type:
  Notifications{algebra: S.JoinSemilattice<Bool, False{}, Bool.or>,
    raise: @task:M.Task -> {M.task_notified(M.notify(task)) == Bool.or(M.task_notified(task), True{}) : Bool},
    sticky: @task:M.Task -> {M.task_notified(M.notify(task)) == True{} : Bool},
    consume: @task:M.Task -> {M.task_notified(Ops.publish(task)) == False{} : Bool}}

law notifications:
  Notifications

# Noninterference of the actual state coordinates, not of arbitrary external
# effects. Work settlement owns its right and notification, not a model ticket.
type Coordination is Type:
  Coordination{
    settlement_phase: @operation:M.Operation -> @value:J.Json -> @error:Bool -> @task:M.Task ->
      {M.task_phase(Ops.completed(operation, value, error, task)) == M.wake_phase(M.task_phase(task)) : M.Phase},
    settlement_rights: @operation:M.Operation -> @value:J.Json -> @error:Bool -> @task:M.Task ->
      {M.task_operations(Ops.completed(operation, value, error, task)) == Ops.remove(M.task_operations(task), Ops.ticket(operation)) : +List<M.Operation>},
    settlement_notifies: @operation:M.Operation -> @value:J.Json -> @error:Bool -> @task:M.Task ->
      {M.task_notified(Ops.completed(operation, value, error, task)) == True{} : Bool},
    steering_rights: @message:String -> @task:M.Task ->
      {M.task_operations(T.steer(message, task)) == M.task_operations(task) : +List<M.Operation>},
    steering_queue: @message:String -> @task:M.Task ->
      {M.task_queue(T.steer(message, task)) == M.task_queue(task) : +List<String>},
    abandonment: @task:M.Task -> {M.task_operations(Ops.abandoned(task)) == Nil{} : +List<M.Operation>},
    publication: @task:M.Task ->
      {M.task_operations(Ops.publish(task)) == Std.map(~M.Operation, ~M.Operation, ~Ops.announce, M.task_operations(task)) : +List<M.Operation>},
    final_output: @ticket:Nat -> @call:M.Call -> @value:J.Json -> @error:Bool ->
      {Ops.result(M.Operation{ticket, call, False{}}, value, error) == M.FunctionOutput{T.call_id(call), value, error} : M.Message},
    later_output: @operation:M.Operation -> @value:J.Json -> @error:Bool ->
      {Ops.result(Ops.announce(operation), value, error) ==
        M.OperationResult{Ops.ticket(operation), T.call_id(Ops.call(operation)), T.call_name(Ops.call(operation)), value, error} : M.Message},
    pending_model: @id:Nat -> @lineage:+List<Nat> -> @contract:M.Contract -> @status:M.Status ->
      @history:M.History -> @queued:+List<String> -> @ticket:Nat -> @allowed:+List<String> ->
      @operations:+List<M.Operation> -> @notified:Bool -> @operation:M.Operation -> @value:J.Json -> @error:Bool ->
      {M.task_phase(T.complete_operation(operation, value, error,
        M.Task{id, lineage, contract, status, history, queued, M.ModelPending{ticket, allowed}, operations, notified})) ==
        M.ModelPending{ticket, allowed} : M.Phase}}

law coordination:
  Coordination

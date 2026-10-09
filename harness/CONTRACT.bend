import Base
import ../interaction/CONTRACT.bend as ProductContract
import ../bendlib/effects.bend as Effects
import ./features/MODEL.bend as F
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./INVARIANTS.bend as I
import ./tasks/PROGRAM.bend as T
import ./protocol/COMMIT.bend as Commit
import ../bendlib/association-map.bend as Finite
import ./protocol/PROGRAM.bend as Protocol
import ./execution/PROGRAM.bend as Execution
import ../bendlib/json.bend as J
import ./COMMANDS.bend as Commands
import ./history/PROGRAM.bend as Traces
import ./conversation/MODEL.bend as Transcript
import ./transport/MODEL.bend as Interface
import ./transport/PROGRAM.bend as Frontend
import ./execution/OPERATIONS.bend as Ops
import ./protocol/RESULTS.bend as Results
import ../bendlib/stdlib.bend as Std
import ./approval/HOOKS.bend as Hooks
import ./LAWS.bend as Laws
import ./execution/notifications.bend as Notifications
import ./history/MODEL.bend as Reach

law protocol_reachability:
  Reach.Protocol

type PluginBoundary is Type:
  PluginBoundary{
    entry: @tool:D.Tool -> @attempt:D.Attempt -> @remaining:+List<D.Attempt> -> @task:D.Task -> @world:M.World() ->
      {Execution.found(Some{tool}, attempt, remaining, task, world) ==
        Execution.authorization(D.may_execute(D.recovery(D.tool_source(tool)), attempt), tool, attempt, remaining, task, world) : Execution.Action},
    before_route: @plugin:D.PluginRef -> @pending:+List<D.PluginRef> -> @tool:D.Tool -> @call:D.Call -> @remaining:+List<D.Attempt> -> @task:D.Task -> @world:M.World() ->
      {Execution.chain(plugin <> pending, tool, call, remaining, task, world) ==
        Execution.hook_available(Hooks.available(Hooks.live(F.State(), world), plugin), plugin, pending, tool, call, remaining, task) : Execution.Action},
    identity: @call:D.Call -> @arguments:J.Json ->
      {D.call_id(D.rewritten(call, arguments)) == D.call_id(call) : String} & {T.call_name(D.rewritten(call, arguments)) == T.call_name(call) : String},
    deny: @reason:String -> @call:D.Call -> @pending:+List<D.PluginRef> ->
      {Hooks.advance(D.DenyTool{reason}, call, pending) == Hooks.Refused{} : Hooks.Progress},
    fail: @reason:String -> @call:D.Call -> @pending:+List<D.PluginRef> ->
      {Hooks.advance(D.HookFailure{reason}, call, pending) == Hooks.Refused{} : Hooks.Progress},
    absorbing: @plugin:D.PluginRef -> @outcome:D.HookOutcome -> {Hooks.record(Hooks.Refused{}, plugin, outcome) == Hooks.Refused{} : Hooks.Progress},
    isolation: @owner:Nat -> @other:Nat -> @id:String -> @plugin:D.PluginRef -> @outcome:D.HookOutcome -> @pending:+List<D.PluginRef> -> @state:Hooks.Progress ->
      {Nat.is_eq(other, owner) == False{} : Bool} ->
      {Hooks.history_step(D.HookRecord{other, id, plugin, outcome}, owner, id, pending, state) == state : Hooks.Progress},
    observations: @source:M.Input -> @before:M.World() -> @decision:M.Decision() ->
      Laws.ObservationExtension<decision, Notifications.decorate(source, before, decision)>}

law plugin_boundary:
  PluginBoundary

# The after protocol transfers an execution receipt to a sequence of one-use
# callback rights. Its result edits preserve call identity and execution error;
# its audit records are deliberately outside the default model projection.

type ResultBoundary is Type:
  ResultBoundary{
    receipt: @+plugin: D.PluginRef -> @+pending: +List<D.PluginRef> -> @+operation: D.Operation() ->
      @+value: J.Json -> @+error: Bool -> @+task: D.Task -> @+world: M.World() ->
      {Results.received(F.State(), F.Effect, plugin <> pending, operation, value, error, task, world) ==
        Results.advance(F.State(), F.Effect, plugin <> pending, operation, value, error,
          D.append_message(D.ToolReceipt{D.task_id(task), Ops.ticket(operation), Ops.call(operation), value, error}, task), world) : M.Decision()},
    dispatch: @+plugin: D.PluginRef -> @+pending: +List<D.PluginRef> -> @+operation: D.Operation() ->
      @+value: J.Json -> @+error: Bool -> @+task: D.Task -> @+state: D.State -> @+board: F.State() ->
      {Results.waiting(F.State(), F.Effect, True{}, plugin, pending, operation, value, error, task,
        C.Frame{state, board}) ==
        C.Decision{C.Frame{D.with_state_next_ticket(1n+D.state_next_ticket(state),
          D.with_state_tasks(T.replace(D.state_tasks(state), D.with_operations(Ops.replace(D.task_operations(task),
            Ops.with_stage(D.ResultPending{D.state_next_ticket(state), plugin, pending, value, error}, operation)), task)), state)), board},
          D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}),
          [Effects.CheckResult{D.task_id(task), D.state_next_ticket(state), Ops.ticket(operation), plugin, Ops.call(operation), value, error}]} : M.Decision()},
    rewrite: @+call: D.Call -> @current: J.Json -> @+replacement: J.Json -> @+error: Bool -> @+pending: +List<D.PluginRef> ->
      {Hooks.result_advance(D.RewriteResult{replacement}, call, current, error, pending) ==
        Hooks.AwaitingResult{call, replacement, error, pending} : Hooks.ResultProgress},
    deny: @+reason: String -> @+call: D.Call -> @+value: J.Json -> @+error: Bool -> @+pending: +List<D.PluginRef> ->
      ({Hooks.result_advance(D.DenyResult{reason}, call, value, error, pending) == Hooks.RefusedResult{} : Hooks.ResultProgress} &
       {Hooks.result_advance(D.AfterFailure{reason}, call, value, error, pending) == Hooks.RefusedResult{} : Hooks.ResultProgress}),
    terminal: @plugin: D.PluginRef -> @outcome: D.AfterOutcome ->
      {Hooks.result_record(Hooks.RefusedResult{}, plugin, outcome) == Hooks.RefusedResult{} : Hooks.ResultProgress},
    stale: @+expected: Nat -> @+ticket: Nat -> @plugin: D.PluginRef -> @pending: +List<D.PluginRef> ->
      @value: J.Json -> @error: Bool -> @task: D.Task -> @operation: D.Operation() -> @outcome: D.AfterOutcome ->
      @different: {Nat.is_eq(ticket, expected) == False{} : Bool} ->
      {Protocol.after_stage(D.ResultPending{expected, plugin, pending, value, error}, task, operation, ticket, outcome) == Protocol.Ignore{} : Protocol.ResolvedEvent},
    execution_retired: @id: Nat -> @call: D.Call -> @announced: Bool -> @ticket: Nat -> @plugin: D.PluginRef ->
      @pending: +List<D.PluginRef> -> @value: J.Json -> @error: Bool -> @task: D.Task -> @duplicate: J.Json -> @duplicate_error: Bool ->
      {Protocol.tool_operation(Some{(id, D.OperationBody{call, announced, D.ResultPending{ticket, plugin, pending, value, error}})},
        task, duplicate, duplicate_error) == Protocol.Ignore{} : Protocol.ResolvedEvent},
    audit: @+history: D.History -> @+owner: Nat -> @+operation: Nat -> @call: D.Call -> @value: J.Json -> @error: Bool ->
      @plugin: D.PluginRef -> @outcome: D.AfterOutcome ->
      ({D.context_node(history, D.ToolReceipt{owner, operation, call, value, error}) == history : D.History} &
       {D.context_node(history, D.AfterRecord{owner, operation, plugin, outcome}) == history : D.History}),
    control_frame: @+task: D.Task -> @operation: D.Operation() ->
      {D.task_phase(D.with_operations(Ops.replace(D.task_operations(task), operation), task)) == D.task_phase(task) : D.Phase},
    completion_record: @+outcome: D.AfterOutcome -> @+plugin: D.PluginRef -> @+pending: +List<D.PluginRef> ->
      @+operation: D.Operation() -> @+value: J.Json -> @+error: Bool -> @+task: D.Task -> @+world: M.World() ->
      {Results.completed(F.State(), F.Effect, outcome, plugin, pending, operation, value, error, task, world) ==
        Results.complete_action(F.State(), F.Effect, Hooks.result_action(outcome, value, error), pending, operation,
          D.append_message(D.AfterRecord{D.task_id(task), Ops.ticket(operation), plugin, outcome}, task), world) : M.Decision()},
    value_action: @+value: J.Json -> @+error: Bool -> @+pending: +List<D.PluginRef> -> @+operation: D.Operation() -> @+task: D.Task -> @+world: M.World() ->
      {Results.complete_action(F.State(), F.Effect, Hooks.ResultValue{value, error}, pending, operation, task, world) == Results.advance(F.State(), F.Effect, pending, operation, value, error, task, world) : M.Decision()},
    error_action: @+code: String -> @+reason: String -> @pending: +List<D.PluginRef> -> @+operation: D.Operation() -> @+task: D.Task -> @+world: M.World() ->
      {Results.complete_action(F.State(), F.Effect, Hooks.ResultError{code, reason}, pending, operation, task, world) == Results.finished(F.State(), F.Effect, operation, D.failure(code, reason), True{}, task, world) : M.Decision()},
    finalization: @+operation: D.Operation() -> @+value: J.Json -> @+error: Bool -> @+task: D.Task -> @+world: M.World() ->
      {Results.finished(F.State(), F.Effect, operation, value, error, task, world) ==
        C.Decision{Commands.replace(Results.finish_status(D.task_status(task), T.complete_operation(operation, value, error, task)), world),
          D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision()},
    entry: @+operation:D.Operation() -> @+value:J.Json -> @+error:Bool -> @+task:D.Task -> @+world:M.World() ->
      {Results.begin(F.State(), F.Effect, operation, value, error, task, world) ==
        Results.received(F.State(), F.Effect, Hooks.after(Hooks.plugins(D.task_contract(task))), operation, value, error, task, world) : M.Decision()},
    empty: @+operation:D.Operation() -> @+value:J.Json -> @+error:Bool -> @+task:D.Task -> @+world:M.World() ->
      ({Results.received(F.State(), F.Effect, Nil{}, operation, value, error, task, world) == Results.finished(F.State(), F.Effect, operation, value, error, task, world) : M.Decision()} &
       {Results.advance(F.State(), F.Effect, Nil{}, operation, value, error, task, world) == Results.finished(F.State(), F.Effect, operation, value, error, task, world) : M.Decision()}),
    next: @+plugin:D.PluginRef -> @+pending:+List<D.PluginRef> -> @+operation:D.Operation() ->
      @+value:J.Json -> @+error:Bool -> @+task:D.Task -> @+world:M.World() ->
      {Results.advance(F.State(), F.Effect, plugin <> pending, operation, value, error, task, world) ==
        Results.waiting(F.State(), F.Effect, Hooks.after_available(Hooks.live(F.State(), world), plugin), plugin, pending, operation, value, error, task, world) : M.Decision()},
    callback: @ticket:Nat -> @+plugin:D.PluginRef -> @+pending:+List<D.PluginRef> -> @+value:J.Json -> @+error:Bool ->
      @+outcome:D.AfterOutcome -> @+operation:D.Operation() -> @+task:D.Task -> @+world:M.World() ->
      {Results.complete(F.State(), F.Effect, D.ResultPending{ticket, plugin, pending, value, error}, outcome, operation, task, world) ==
        Results.completed(F.State(), F.Effect, outcome, plugin, pending, operation, value, error, task, world) : M.Decision()},
    internal_entry: @+call:D.Call -> @+remaining:+List<D.Attempt> -> @+value:J.Json -> @+error:Bool -> @+task:D.Task -> @+world:M.World() ->
      {Results.internal(F.State(), F.Effect, call, remaining, value, error, task, world) ==
        Results.internal_chain(F.State(), F.Effect, Hooks.after(Hooks.plugins(D.task_contract(task))), call, remaining, value, error, task, world) : M.Decision()},
    internal_receipt: @+plugin:D.PluginRef -> @+pending:+List<D.PluginRef> -> @+call:D.Call -> @+remaining:+List<D.Attempt> ->
      @+value:J.Json -> @+error:Bool -> @+task:D.Task -> @+state:D.State -> @+board: F.State() ->
      {Results.internal_chain(F.State(), F.Effect, plugin <> pending, call, remaining, value, error, task, C.Frame{state, board}) ==
        Results.received(F.State(), F.Effect, plugin <> pending, (D.state_next_ticket(state), D.OperationBody{call, False{}, D.Executing{}}), value, error,
          Results.finish_status(D.task_status(task), Ops.started(D.state_next_ticket(state), call, remaining, task)),
          C.Frame{D.with_state_next_ticket(1n+D.state_next_ticket(state), state), board}) : M.Decision()}
  }

law result_boundary:
  ResultBoundary

def UserSurface() -> Type:
  ProductContract.Requirements

law surface:
  UserSurface()

# Concrete bindings for the conceptual entry in ../CONCEPTS.bend. These indices
# name the actual production operations. PROOF supplies the correspondences;
# standard results are instantiated from imported, checked proof terms.

def specification(command: M.Command, world: M.World()) -> M.Decision():
  Commit.command(~Execution.scheduled, command, world)

def implementation(command: M.Command, world: M.World()) -> M.Decision():
  P.transition(M.UserCommand{command}, world)

def CommandMeaning() -> Type:
  @+command:M.Command -> @+world:M.World() -> {implementation(command, world) == specification(command, world) : M.Decision()}

law commands:
  CommandMeaning()

def interaction_specification(input: M.Input, world: M.World()) -> M.Decision():
  Commit.input(~Execution.scheduled, input, world)

def interaction_implementation(input: M.Input, world: M.World()) -> M.Decision():
  P.transition(input, world)

def observation(query: M.Query, world: M.World()) -> M.Decision():
  P.transition(M.UserCommand{M.Observe{query}}, world)

def InputMeaning() -> Type:
  @+input:M.Input -> @+world:M.World() -> {interaction_implementation(input, world) == interaction_specification(input, world) : M.Decision()}

law interactions:
  InputMeaning()

def StateMachine() -> Type:
  {I.world(M.initial()) == True{} : Bool} &
    (@+state:M.World() -> @input:M.Input -> {I.world(state) == True{} : Bool} -> {I.world(P.next(state, input)) == True{} : Bool})

law task_machine:
  StateMachine()

# Lists are the existing free-word representation, and fold-left is its action.
# Store only the domain/representation correspondence. Consumers instantiate
# Std.fold_left_app or Std.app_assoc directly; no local monoid/action hierarchy.

def HistoryAction() -> Type:
  @+history:D.History -> @+messages:+List<D.Message> ->
    {D.history_append(messages, history) == List.foldl(~&2, ~D.Message, ~D.History, ~D.history_step, messages, history) : D.History}

def history() -> HistoryAction():
  (history => messages => {==})

law journal_interpretation:
  for +world: M.World()
  for +inputs: +List<M.Input>
  {P.replay(inputs, world) == List.foldl(~&2, ~M.Input, ~M.World(), ~P.next, inputs, world) : M.World()}

# Decisions have associative composition, but no global identity: the first
# reply and the last world have different ownership. Only effects form a monoid.

def DecisionComposition() -> Type:
  @+first:M.Decision() -> @+second:M.Decision() -> @+third:M.Decision() ->
    {P.combine(P.combine(first, second), third) == P.combine(first, P.combine(second, third)) : M.Decision()}

law decisions:
  DecisionComposition()

# A context cut, recovery normalization, and interruption are three different
# idempotent projections. Idempotence does not assert summary fidelity or undo.

def ContextProjection() -> Type:
  @+history:D.History -> {D.context_history(D.context_history(history)) == D.context_history(history) : D.History}

law context:
  ContextProjection()

def RecoveryProjection() -> Type:
  @+phase:D.Phase -> {T.recover_phase(T.recover_phase(phase)) == T.recover_phase(phase) : D.Phase}

law recovery:
  RecoveryProjection()

def InterruptionProjection() -> Type:
  @+task:D.Task -> {T.interrupt(T.interrupt(task)) == T.interrupt(task) : D.Task}

law interruption:
  InterruptionProjection()

def Observations() -> Type:
  @+query:M.Query -> @+world:M.World() ->
    ({P.decision_world(observation(query, world)) == world : M.World()} &
     {P.decision_effects(observation(query, world)) == Nil{} : +List<M.Effect()>})

law observations:
  Observations()

# Batch recovery and public views are monoid homomorphisms. Their partition and
# composition laws are imported map theorems, not special recovery/API proofs.

def RecoveryBatches() -> Type:
  @+tasks:+List<D.Task> -> {Protocol.recovery(tasks) == Std.map(~D.Task, ~D.Task, ~Protocol.recover, tasks) : +List<D.Task>}

law recovery_batches:
  RecoveryBatches()

def TaskViews() -> Type:
  @+tasks:+List<D.Task> -> {T.summaries(tasks) == Std.map(~D.Task, ~J.Json, ~T.summary, tasks) : +List<J.Json>}

law task_views:
  TaskViews()

def BranchResults() -> Type:
  @+tasks:+List<D.Task> -> {Commands.identities(tasks) == Std.map(~D.Task, ~J.Json, ~Commands.identity, tasks) : +List<J.Json>}

law branch_results:
  BranchResults()

def ActionMeaning() -> Type:
  @+action:Execution.Action -> @+world:M.World() -> {P.realize_action(action, world) == Execution.meaning(action, world) : M.Decision()}

law actions:
  ActionMeaning()

def scheduling_specification(enabled: Bool, decision: M.Decision()) -> M.Decision():
  Execution.scheduled(enabled, decision)

def scheduling_implementation(enabled: Bool, decision: M.Decision()) -> M.Decision():
  P.scheduled(enabled, decision)

def SchedulingMeaning() -> Type:
  @+enabled:Bool -> @+decision:M.Decision() ->
    {scheduling_implementation(enabled, decision) == scheduling_specification(enabled, decision) : M.Decision()}

law scheduling:
  SchedulingMeaning()

def TraceSimulation() -> Type:
  @+count:Nat -> @+tape:Transcript.Tape -> {Traces.actual(count, tape) == Transcript.run(count, tape) : Transcript.Tape}

law traces:
  TraceSimulation()

def NativeInterface() -> Type:
  @+tokens:+List<String> -> @+world:M.World() -> {Frontend.packet(tokens, world) == Interface.packet(tokens, world) : Interface.Output}

law native_interface:
  NativeInterface()

# Interpretation is part of the journal object, rather than a nearby theorem
# that could describe some other fold with the same carrier.

type Journal is Type:
  Journal{interpretation: @+world:M.World() -> @+inputs:+List<M.Input> ->
      {P.replay(inputs, world) == List.foldl(~&2, ~M.Input, ~M.World(), ~P.next, inputs, world) : M.World()},
    safe: @inputs:+List<M.Input> -> @world:M.World() -> {I.world(world) == True{} : Bool} ->
      {I.world(P.replay(inputs, world)) == True{} : Bool}}

law persistence:
  Journal

type OperationRights is Type:
  OperationRights{
    lookup: @+operations:+List<D.Operation()> -> @+id:Nat ->
      {Ops.find(operations, id) == Ops.binding(Finite.find(~D.OperationBody, operations, id), id) : Maybe<&2, D.Operation()>},
    retirement: @+operations:+List<D.Operation()> -> @+id:Nat ->
      {Ops.remove(operations, id) == Finite.remove(~D.OperationBody, operations, id) : +List<D.Operation()>},
    consumed: @+operations:+List<D.Operation()> -> @+id:Nat ->
      {Ops.find(Ops.remove(operations, id), id) == None{} : Maybe<&2, D.Operation()>}}

law operation_rights:
  OperationRights

type Announcement is Type:
  Announcement{projection: @+operation:D.Operation() -> {Ops.announce(Ops.announce(operation)) == Ops.announce(operation) : D.Operation()},
    ticket: @operation:D.Operation() -> {Ops.ticket(Ops.announce(operation)) == Ops.ticket(operation) : Nat},
    call: @operation:D.Operation() -> {Ops.call(Ops.announce(operation)) == Ops.call(operation) : D.Call},
    status: @operation:D.Operation() -> {Ops.announced(Ops.announce(operation)) == True{} : Bool}}

law announcement:
  Announcement

type Notifications is Type:
  Notifications{raise: @task:D.Task -> {D.task_notified(D.notify(task)) == Bool.or(D.task_notified(task), True{}) : Bool},
    sticky: @task:D.Task -> {D.task_notified(D.notify(task)) == True{} : Bool},
    consume: @task:D.Task -> {D.task_notified(Ops.publish(task)) == False{} : Bool}}

law notifications:
  Notifications

# Noninterference of the actual state coordinates, not of arbitrary external
# effects. Work settlement owns its right and notification, not a model ticket.

type Coordination is Type:
  Coordination{
    settlement_phase: @operation:D.Operation() -> @value:J.Json -> @error:Bool -> @task:D.Task ->
      {D.task_phase(Ops.completed(operation, value, error, task)) == D.wake_phase(D.task_phase(task)) : D.Phase},
    settlement_rights: @operation:D.Operation() -> @value:J.Json -> @error:Bool -> @task:D.Task ->
      {D.task_operations(Ops.completed(operation, value, error, task)) == Ops.remove(D.task_operations(task), Ops.ticket(operation)) : +List<D.Operation()>},
    settlement_notifies: @operation:D.Operation() -> @value:J.Json -> @error:Bool -> @task:D.Task ->
      {D.task_notified(Ops.completed(operation, value, error, task)) == True{} : Bool},
    steering_rights: @message:String -> @task:D.Task ->
      {D.task_operations(T.steer(message, task)) == D.task_operations(task) : +List<D.Operation()>},
    steering_queue: @message:String -> @task:D.Task ->
      {D.task_queue(T.steer(message, task)) == D.task_queue(task) : +List<String>},
    abandonment: @task:D.Task -> {D.task_operations(Ops.abandoned(task)) == Nil{} : +List<D.Operation()>},
    publication: @task:D.Task ->
      {D.task_operations(Ops.publish(task)) == Std.map(~D.Operation(), ~D.Operation(), ~Ops.announce, D.task_operations(task)) : +List<D.Operation()>},
    final_output: @ticket:Nat -> @call:D.Call -> @value:J.Json -> @error:Bool ->
      {Ops.result((ticket, D.OperationBody{call, False{}, D.Executing{}}), value, error) == D.FunctionOutput{T.call_id(call), value, error} : D.Message},
    later_output: @operation:D.Operation() -> @value:J.Json -> @error:Bool ->
      {Ops.result(Ops.announce(operation), value, error) ==
        D.OperationResult{Ops.ticket(operation), T.call_id(Ops.call(operation)), T.call_name(Ops.call(operation)), value, error} : D.Message},
    pending_model: @id:Nat -> @lineage:+List<Nat> -> @contract:D.Contract -> @status:D.Status ->
      @history:D.History -> @queued:+List<String> -> @ticket:Nat -> @allowed:+List<String> ->
      @operations:+List<D.Operation()> -> @notified:Bool -> @operation:D.Operation() -> @value:J.Json -> @error:Bool ->
      {D.task_phase(T.complete_operation(operation, value, error,
        D.Task{id, lineage, contract, status, history, queued, D.ModelPending{ticket, allowed}, operations, notified})) ==
        D.ModelPending{ticket, allowed} : D.Phase}}

law coordination:
  Coordination

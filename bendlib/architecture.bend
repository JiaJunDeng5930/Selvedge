import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../INVARIANTS.bend as I
import ./tasks.bend as T
import ./commit.bend as Commit
import ./association-map.bend as Finite
import ./protocol.bend as Protocol
import ./execution.bend as Execution
import ./json.bend as J
import ../COMMANDS.bend as Commands
import ./traces.bend as Traces
import ./transcript.bend as Transcript
import ./interface.bend as Interface
import ./frontend.bend as Frontend
import ./operations.bend as Ops
import ./results.bend as Results
import ./stdlib.bend as Std
import ../UI.bend as UI
import ../HOOKS.bend as Hooks
import ../LAWS.bend as Laws
import ./notifications.bend as Notifications
import ./reachability.bend as Reach

law protocol_reachability:
  Reach.Protocol

type PluginBoundary is Type:
  PluginBoundary{
    entry: @tool:M.Tool -> @attempt:M.Attempt -> @remaining:+List<M.Attempt> -> @task:M.Task -> @world:M.World ->
      {Execution.found(Some{tool}, attempt, remaining, task, world) ==
        Execution.authorization(M.may_execute(M.recovery(M.tool_source(tool)), attempt), tool, attempt, remaining, task, world) : Execution.Action},
    before_route: @plugin:M.PluginRef -> @pending:+List<M.PluginRef> -> @tool:M.Tool -> @call:M.Call -> @remaining:+List<M.Attempt> -> @task:M.Task -> @world:M.World ->
      {Execution.chain(plugin <> pending, tool, call, remaining, task, world) ==
        Execution.hook_available(Hooks.available(Hooks.live(world), plugin), plugin, pending, tool, call, remaining, task) : Execution.Action},
    identity: @call:M.Call -> @arguments:J.Json ->
      {M.call_id(M.rewritten(call, arguments)) == M.call_id(call) : String} & {T.call_name(M.rewritten(call, arguments)) == T.call_name(call) : String},
    deny: @reason:String -> @call:M.Call -> @pending:+List<M.PluginRef> ->
      {Hooks.advance(M.DenyTool{reason}, call, pending) == Hooks.Refused{} : Hooks.Progress},
    fail: @reason:String -> @call:M.Call -> @pending:+List<M.PluginRef> ->
      {Hooks.advance(M.HookFailure{reason}, call, pending) == Hooks.Refused{} : Hooks.Progress},
    absorbing: @plugin:M.PluginRef -> @outcome:M.HookOutcome -> {Hooks.record(Hooks.Refused{}, plugin, outcome) == Hooks.Refused{} : Hooks.Progress},
    isolation: @owner:Nat -> @other:Nat -> @id:String -> @plugin:M.PluginRef -> @outcome:M.HookOutcome -> @pending:+List<M.PluginRef> -> @state:Hooks.Progress ->
      {Nat.is_eq(other, owner) == False{} : Bool} ->
      {Hooks.history_step(M.HookRecord{other, id, plugin, outcome}, owner, id, pending, state) == state : Hooks.Progress},
    observations: @source:M.Input -> @before:M.World -> @decision:M.Decision ->
      Laws.ObservationExtension<decision, Notifications.decorate(source, before, decision)>}

law plugin_boundary:
  PluginBoundary

# The after protocol transfers an execution receipt to a sequence of one-use
# callback rights. Its result edits preserve call identity and execution error;
# its audit records are deliberately outside the default model projection.
type ResultBoundary is Type:
  ResultBoundary{
    receipt: @+plugin: M.PluginRef -> @+pending: +List<M.PluginRef> -> @+operation: M.Operation() ->
      @+value: J.Json -> @+error: Bool -> @+task: M.Task -> @+world: M.World ->
      {Results.received(plugin <> pending, operation, value, error, task, world) ==
        Results.advance(plugin <> pending, operation, value, error,
          M.append_message(M.ToolReceipt{M.task_id(task), Ops.ticket(operation), Ops.call(operation), value, error}, task), world) : M.Decision},
    dispatch: @+plugin: M.PluginRef -> @+pending: +List<M.PluginRef> -> @+operation: M.Operation() ->
      @+value: J.Json -> @+error: Bool -> @+task: M.Task -> @+tasks: +List<M.Task> -> @+next_task: Nat ->
      @+ticket: Nat -> @+environment: M.Environment -> @+limits: M.ExecutionLimits -> @+projects: M.Projects ->
      {Results.waiting(True{}, plugin, pending, operation, value, error, task,
        M.World{tasks, next_task, ticket, environment, limits, projects}) ==
        M.Decision{M.World{T.replace(tasks, M.with_operations(Ops.replace(M.task_operations(task),
          Ops.with_stage(M.ResultPending{ticket, plugin, pending, value, error}, operation)), task)),
          next_task, 1n+ticket, environment, limits, projects}, M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}),
          [M.CheckResult{M.task_id(task), ticket, Ops.ticket(operation), plugin, Ops.call(operation), value, error}]} : M.Decision},
    rewrite: @+call: M.Call -> @current: J.Json -> @+replacement: J.Json -> @+error: Bool -> @+pending: +List<M.PluginRef> ->
      {Hooks.result_advance(M.RewriteResult{replacement}, call, current, error, pending) ==
        Hooks.AwaitingResult{call, replacement, error, pending} : Hooks.ResultProgress},
    deny: @+reason: String -> @+call: M.Call -> @+value: J.Json -> @+error: Bool -> @+pending: +List<M.PluginRef> ->
      ({Hooks.result_advance(M.DenyResult{reason}, call, value, error, pending) == Hooks.RefusedResult{} : Hooks.ResultProgress} &
       {Hooks.result_advance(M.AfterFailure{reason}, call, value, error, pending) == Hooks.RefusedResult{} : Hooks.ResultProgress}),
    terminal: @plugin: M.PluginRef -> @outcome: M.AfterOutcome ->
      {Hooks.result_record(Hooks.RefusedResult{}, plugin, outcome) == Hooks.RefusedResult{} : Hooks.ResultProgress},
    stale: @+expected: Nat -> @+ticket: Nat -> @plugin: M.PluginRef -> @pending: +List<M.PluginRef> ->
      @value: J.Json -> @error: Bool -> @task: M.Task -> @operation: M.Operation() -> @outcome: M.AfterOutcome ->
      @different: {Nat.is_eq(ticket, expected) == False{} : Bool} ->
      {Protocol.after_stage(M.ResultPending{expected, plugin, pending, value, error}, task, operation, ticket, outcome) == Protocol.Ignore{} : Protocol.Event},
    execution_retired: @id: Nat -> @call: M.Call -> @announced: Bool -> @ticket: Nat -> @plugin: M.PluginRef ->
      @pending: +List<M.PluginRef> -> @value: J.Json -> @error: Bool -> @task: M.Task -> @duplicate: J.Json -> @duplicate_error: Bool ->
      {Protocol.tool_operation(Some{(id, M.OperationBody{call, announced, M.ResultPending{ticket, plugin, pending, value, error}})},
        task, duplicate, duplicate_error) == Protocol.Ignore{} : Protocol.Event},
    audit: @+history: M.History -> @+owner: Nat -> @+operation: Nat -> @call: M.Call -> @value: J.Json -> @error: Bool ->
      @plugin: M.PluginRef -> @outcome: M.AfterOutcome ->
      ({M.context_node(history, M.ToolReceipt{owner, operation, call, value, error}) == history : M.History} &
       {M.context_node(history, M.AfterRecord{owner, operation, plugin, outcome}) == history : M.History}),
    control_frame: @+task: M.Task -> @operation: M.Operation() ->
      {M.task_phase(M.with_operations(Ops.replace(M.task_operations(task), operation), task)) == M.task_phase(task) : M.Phase},
    completion_record: @+outcome: M.AfterOutcome -> @+plugin: M.PluginRef -> @+pending: +List<M.PluginRef> ->
      @+operation: M.Operation() -> @+value: J.Json -> @+error: Bool -> @+task: M.Task -> @+world: M.World ->
      {Results.completed(outcome, plugin, pending, operation, value, error, task, world) ==
        Results.complete_action(Hooks.result_action(outcome, value, error), pending, operation,
          M.append_message(M.AfterRecord{M.task_id(task), Ops.ticket(operation), plugin, outcome}, task), world) : M.Decision},
    value_action: @+value: J.Json -> @+error: Bool -> @+pending: +List<M.PluginRef> -> @+operation: M.Operation() -> @+task: M.Task -> @+world: M.World ->
      {Results.complete_action(Hooks.ResultValue{value, error}, pending, operation, task, world) == Results.advance(pending, operation, value, error, task, world) : M.Decision},
    error_action: @+code: String -> @+reason: String -> @pending: +List<M.PluginRef> -> @+operation: M.Operation() -> @+task: M.Task -> @+world: M.World ->
      {Results.complete_action(Hooks.ResultError{code, reason}, pending, operation, task, world) == Results.finished(operation, M.failure(code, reason), True{}, task, world) : M.Decision},
    finalization: @+operation: M.Operation() -> @+value: J.Json -> @+error: Bool -> @+task: M.Task -> @+world: M.World ->
      {Results.finished(operation, value, error, task, world) ==
        M.Decision{Commands.replace(Results.finish_status(M.task_status(task), T.complete_operation(operation, value, error, task)), world),
          M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision},
    entry: @+operation:M.Operation() -> @+value:J.Json -> @+error:Bool -> @+task:M.Task -> @+world:M.World ->
      {Results.begin(operation, value, error, task, world) ==
        Results.received(Hooks.after(Hooks.plugins(M.task_contract(task))), operation, value, error, task, world) : M.Decision},
    empty: @+operation:M.Operation() -> @+value:J.Json -> @+error:Bool -> @+task:M.Task -> @+world:M.World ->
      ({Results.received(Nil{}, operation, value, error, task, world) == Results.finished(operation, value, error, task, world) : M.Decision} &
       {Results.advance(Nil{}, operation, value, error, task, world) == Results.finished(operation, value, error, task, world) : M.Decision}),
    next: @+plugin:M.PluginRef -> @+pending:+List<M.PluginRef> -> @+operation:M.Operation() ->
      @+value:J.Json -> @+error:Bool -> @+task:M.Task -> @+world:M.World ->
      {Results.advance(plugin <> pending, operation, value, error, task, world) ==
        Results.waiting(Hooks.after_available(Hooks.live(world), plugin), plugin, pending, operation, value, error, task, world) : M.Decision},
    callback: @ticket:Nat -> @+plugin:M.PluginRef -> @+pending:+List<M.PluginRef> -> @+value:J.Json -> @+error:Bool ->
      @+outcome:M.AfterOutcome -> @+operation:M.Operation() -> @+task:M.Task -> @+world:M.World ->
      {Results.complete(M.ResultPending{ticket, plugin, pending, value, error}, outcome, operation, task, world) ==
        Results.completed(outcome, plugin, pending, operation, value, error, task, world) : M.Decision},
    internal_entry: @+call:M.Call -> @+remaining:+List<M.Attempt> -> @+value:J.Json -> @+error:Bool -> @+task:M.Task -> @+world:M.World ->
      {Results.internal(call, remaining, value, error, task, world) ==
        Results.internal_chain(Hooks.after(Hooks.plugins(M.task_contract(task))), call, remaining, value, error, task, world) : M.Decision},
    internal_receipt: @+plugin:M.PluginRef -> @+pending:+List<M.PluginRef> -> @+call:M.Call -> @+remaining:+List<M.Attempt> ->
      @+value:J.Json -> @+error:Bool -> @+task:M.Task -> @+tasks:+List<M.Task> -> @+next_task:Nat -> @+ticket:Nat ->
      @+environment:M.Environment -> @+limits:M.ExecutionLimits -> @+projects:M.Projects ->
      {Results.internal_chain(plugin <> pending, call, remaining, value, error, task, M.World{tasks, next_task, ticket, environment, limits, projects}) ==
        Results.received(plugin <> pending, (ticket, M.OperationBody{call, False{}, M.Executing{}}), value, error,
          Results.finish_status(M.task_status(task), Ops.started(ticket, call, remaining, task)),
          M.World{tasks, next_task, 1n+ticket, environment, limits, projects}) : M.Decision}
  }

law result_boundary:
  ResultBoundary

def user_surface(state: M.ViewState, world: M.World) -> M.Decision:
  P.transition(M.UserInterface{state, M.RefreshView{}}, world)

type UserSurface is Type:
  UserSurface{
    observation: @+state:M.ViewState -> @+world:M.World ->
      ({P.decision_world(user_surface(state, world)) == world : M.World} &
       {P.decision_effects(user_surface(state, world)) == Nil{} : +List<M.Effect>}),
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
  @+command:M.Command -> @+world:M.World -> {implementation(command, world) == specification(command, world) : M.Decision}

law commands:
  CommandMeaning()

def interaction_specification(input: M.Input, world: M.World) -> M.Decision:
  Commit.input(~Execution.scheduled, input, world)

def interaction_implementation(input: M.Input, world: M.World) -> M.Decision:
  P.transition(input, world)

def observation(query: M.Query, world: M.World) -> M.Decision:
  P.transition(M.UserCommand{M.Observe{query}}, world)

def InputMeaning() -> Type:
  @+input:M.Input -> @+world:M.World -> {interaction_implementation(input, world) == interaction_specification(input, world) : M.Decision}

law interactions:
  InputMeaning()

def StateMachine() -> Type:
  {I.world(M.initial()) == True{} : Bool} &
    (@+state:M.World -> @input:M.Input -> {I.world(state) == True{} : Bool} -> {I.world(P.next(state, input)) == True{} : Bool})

law task_machine:
  StateMachine()

# Lists are the existing free-word representation, and fold-left is its action.
# Store only the domain/representation correspondence. Consumers instantiate
# Std.fold_left_app or Std.app_assoc directly; no local monoid/action hierarchy.
def HistoryAction() -> Type:
  @+history:M.History -> @+messages:+List<M.Message> ->
    {M.history_append(messages, history) == List.foldl(~&2, ~M.Message, ~M.History, ~M.history_step, messages, history) : M.History}

def history() -> HistoryAction():
  (history => messages => {==})

law journal_interpretation:
  for +world: M.World
  for +inputs: +List<M.Input>
  {P.replay(inputs, world) == List.foldl(~&2, ~M.Input, ~M.World, ~P.next, inputs, world) : M.World}

# Decisions have associative composition, but no global identity: the first
# reply and the last world have different ownership. Only effects form a monoid.
def DecisionComposition() -> Type:
  @+first:M.Decision -> @+second:M.Decision -> @+third:M.Decision ->
    {P.combine(P.combine(first, second), third) == P.combine(first, P.combine(second, third)) : M.Decision}

law decisions:
  DecisionComposition()

# A context cut, recovery normalization, and interruption are three different
# idempotent projections. Idempotence does not assert summary fidelity or undo.
def ContextProjection() -> Type:
  @+history:M.History -> {M.context_history(M.context_history(history)) == M.context_history(history) : M.History}

law context:
  ContextProjection()

def RecoveryProjection() -> Type:
  @+phase:M.Phase -> {T.recover_phase(T.recover_phase(phase)) == T.recover_phase(phase) : M.Phase}

law recovery:
  RecoveryProjection()

def InterruptionProjection() -> Type:
  @+task:M.Task -> {T.interrupt(T.interrupt(task)) == T.interrupt(task) : M.Task}

law interruption:
  InterruptionProjection()

def Observations() -> Type:
  @+query:M.Query -> @+world:M.World ->
    ({P.decision_world(observation(query, world)) == world : M.World} &
     {P.decision_effects(observation(query, world)) == Nil{} : +List<M.Effect>})

law observations:
  Observations()

# Batch recovery and public views are monoid homomorphisms. Their partition and
# composition laws are imported map theorems, not special recovery/API proofs.
def RecoveryBatches() -> Type:
  @+tasks:+List<M.Task> -> {Protocol.recovery(tasks) == Std.map(~M.Task, ~M.Task, ~Protocol.recover, tasks) : +List<M.Task>}

law recovery_batches:
  RecoveryBatches()

def TaskViews() -> Type:
  @+tasks:+List<M.Task> -> {T.summaries(tasks) == Std.map(~M.Task, ~J.Json, ~T.summary, tasks) : +List<J.Json>}

law task_views:
  TaskViews()

def BranchResults() -> Type:
  @+tasks:+List<M.Task> -> {Commands.identities(tasks) == Std.map(~M.Task, ~J.Json, ~Commands.identity, tasks) : +List<J.Json>}

law branch_results:
  BranchResults()

def ActionMeaning() -> Type:
  @+action:Execution.Action -> @+world:M.World -> {P.realize_action(action, world) == Execution.meaning(action, world) : M.Decision}

law actions:
  ActionMeaning()

def scheduling_specification(enabled: Bool, decision: M.Decision) -> M.Decision:
  Execution.scheduled(enabled, decision)

def scheduling_implementation(enabled: Bool, decision: M.Decision) -> M.Decision:
  P.scheduled(enabled, decision)

def SchedulingMeaning() -> Type:
  @+enabled:Bool -> @+decision:M.Decision ->
    {scheduling_implementation(enabled, decision) == scheduling_specification(enabled, decision) : M.Decision}

law scheduling:
  SchedulingMeaning()

def TraceSimulation() -> Type:
  @+count:Nat -> @+tape:Transcript.Tape -> {Traces.actual(count, tape) == Transcript.run(count, tape) : Transcript.Tape}

law traces:
  TraceSimulation()

def NativeInterface() -> Type:
  @+tokens:+List<String> -> @+world:M.World -> {Frontend.packet(tokens, world) == Interface.packet(tokens, world) : Interface.Output}

law native_interface:
  NativeInterface()

# Interpretation is part of the journal object, rather than a nearby theorem
# that could describe some other fold with the same carrier.
type Journal is Type:
  Journal{interpretation: @+world:M.World -> @+inputs:+List<M.Input> ->
      {P.replay(inputs, world) == List.foldl(~&2, ~M.Input, ~M.World, ~P.next, inputs, world) : M.World},
    safe: @inputs:+List<M.Input> -> @world:M.World -> {I.world(world) == True{} : Bool} ->
      {I.world(P.replay(inputs, world)) == True{} : Bool}}

law persistence:
  Journal

type OperationRights is Type:
  OperationRights{
    lookup: @+operations:+List<M.Operation()> -> @+id:Nat ->
      {Ops.find(operations, id) == Ops.binding(Finite.find(~M.OperationBody, operations, id), id) : Maybe<&2, M.Operation()>},
    retirement: @+operations:+List<M.Operation()> -> @+id:Nat ->
      {Ops.remove(operations, id) == Finite.remove(~M.OperationBody, operations, id) : +List<M.Operation()>},
    consumed: @+operations:+List<M.Operation()> -> @+id:Nat ->
      {Ops.find(Ops.remove(operations, id), id) == None{} : Maybe<&2, M.Operation()>}}

law operation_rights:
  OperationRights

type Announcement is Type:
  Announcement{projection: @+operation:M.Operation() -> {Ops.announce(Ops.announce(operation)) == Ops.announce(operation) : M.Operation()},
    ticket: @operation:M.Operation() -> {Ops.ticket(Ops.announce(operation)) == Ops.ticket(operation) : Nat},
    call: @operation:M.Operation() -> {Ops.call(Ops.announce(operation)) == Ops.call(operation) : M.Call},
    status: @operation:M.Operation() -> {Ops.announced(Ops.announce(operation)) == True{} : Bool}}

law announcement:
  Announcement

type Notifications is Type:
  Notifications{raise: @task:M.Task -> {M.task_notified(M.notify(task)) == Bool.or(M.task_notified(task), True{}) : Bool},
    sticky: @task:M.Task -> {M.task_notified(M.notify(task)) == True{} : Bool},
    consume: @task:M.Task -> {M.task_notified(Ops.publish(task)) == False{} : Bool}}

law notifications:
  Notifications

# Noninterference of the actual state coordinates, not of arbitrary external
# effects. Work settlement owns its right and notification, not a model ticket.
type Coordination is Type:
  Coordination{
    settlement_phase: @operation:M.Operation() -> @value:J.Json -> @error:Bool -> @task:M.Task ->
      {M.task_phase(Ops.completed(operation, value, error, task)) == M.wake_phase(M.task_phase(task)) : M.Phase},
    settlement_rights: @operation:M.Operation() -> @value:J.Json -> @error:Bool -> @task:M.Task ->
      {M.task_operations(Ops.completed(operation, value, error, task)) == Ops.remove(M.task_operations(task), Ops.ticket(operation)) : +List<M.Operation()>},
    settlement_notifies: @operation:M.Operation() -> @value:J.Json -> @error:Bool -> @task:M.Task ->
      {M.task_notified(Ops.completed(operation, value, error, task)) == True{} : Bool},
    steering_rights: @message:String -> @task:M.Task ->
      {M.task_operations(T.steer(message, task)) == M.task_operations(task) : +List<M.Operation()>},
    steering_queue: @message:String -> @task:M.Task ->
      {M.task_queue(T.steer(message, task)) == M.task_queue(task) : +List<String>},
    abandonment: @task:M.Task -> {M.task_operations(Ops.abandoned(task)) == Nil{} : +List<M.Operation()>},
    publication: @task:M.Task ->
      {M.task_operations(Ops.publish(task)) == Std.map(~M.Operation(), ~M.Operation(), ~Ops.announce, M.task_operations(task)) : +List<M.Operation()>},
    final_output: @ticket:Nat -> @call:M.Call -> @value:J.Json -> @error:Bool ->
      {Ops.result((ticket, M.OperationBody{call, False{}, M.Executing{}}), value, error) == M.FunctionOutput{T.call_id(call), value, error} : M.Message},
    later_output: @operation:M.Operation() -> @value:J.Json -> @error:Bool ->
      {Ops.result(Ops.announce(operation), value, error) ==
        M.OperationResult{Ops.ticket(operation), T.call_id(Ops.call(operation)), T.call_name(Ops.call(operation)), value, error} : M.Message},
    pending_model: @id:Nat -> @lineage:+List<Nat> -> @contract:M.Contract -> @status:M.Status ->
      @history:M.History -> @queued:+List<String> -> @ticket:Nat -> @allowed:+List<String> ->
      @operations:+List<M.Operation()> -> @notified:Bool -> @operation:M.Operation() -> @value:J.Json -> @error:Bool ->
      {M.task_phase(T.complete_operation(operation, value, error,
        M.Task{id, lineage, contract, status, history, queued, M.ModelPending{ticket, allowed}, operations, notified})) ==
        M.ModelPending{ticket, allowed} : M.Phase}}

law coordination:
  Coordination

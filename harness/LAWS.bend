import Base
import ./tools/SYNTAX.bend as Native
import ../bendlib/effects.bend as Effects
import ./features/MODEL.bend as F
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ../bendlib/stdlib.bend as Std
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./tasks/PROGRAM.bend as T
import ./tasks/CONTRACT.bend as TaskRequirements
import ../bendlib/json.bend as J
import ./INVARIANTS.bend as I
import ./COMMANDS.bend as Commands
import ./protocol/COMMIT.bend as Commit
import ./protocol/PROGRAM.bend as Protocol
import ./execution/PROGRAM.bend as Execution
import ../features/board/scheduling-spec.bend as BoardScheduling
import ./history/PROGRAM.bend as Traces
import ./execution/OPERATIONS.bend as Ops
import ./protocol/RESULTS.bend as Results
import ./conversation/MODEL.bend as Transcript
import ./transport/MODEL.bend as Interface
import ./transport/PROGRAM.bend as Frontend
import ./approval/HOOKS.bend as Hooks
import ./execution/notifications.bend as Notifications
import ./workspace/WORKSPACE.bend as Workspace
import ./approval/MODEL.bend as Approvals
import ../bendlib/equality.bend as Same
import ./reasoning/PROGRAM.bend as ActualReasoning

law hook_gateway:
  for +tool: D.Tool
  for +attempt: D.Attempt
  for +remaining: +List<D.Attempt>
  for +task: D.Task
  for +world: M.World()
  {Execution.found(Some{tool}, attempt, remaining, task, world) ==
    Execution.authorization(tool, attempt, remaining, task, world) : Execution.Action}

law hook_before_route:
  for +plugin: D.PluginRef
  for +pending: +List<D.PluginRef>
  for +tool: D.Tool
  for +call: D.Call
  for +remaining: +List<D.Attempt>
  for +task: D.Task
  for +world: M.World()
  {Execution.chain(plugin <> pending, tool, call, remaining, task, world) ==
    Execution.hook_available(plugin, pending, tool, call, remaining, task, world) : Execution.Action}

law hook_rewrite_identity:
  for +call: D.Call
  for +arguments: J.Json
  {D.call_id(D.rewritten(call, arguments)) == D.call_id(call) : String} &
  {T.call_name(D.rewritten(call, arguments)) == T.call_name(call) : String}

law hook_rejected_is_absorbing:
  for plugin: D.PluginRef
  for outcome: D.HookOutcome
  {Hooks.record(Hooks.Refused{}, plugin, outcome) == Hooks.Refused{} : Hooks.Progress}

law hook_deny:
  for reason: String
  for call: D.Call
  for pending: +List<D.PluginRef>
  {Hooks.advance(D.DenyTool{reason}, call, pending) == Hooks.Refused{} : Hooks.Progress}

law hook_failure:
  for reason: String
  for call: D.Call
  for pending: +List<D.PluginRef>
  {Hooks.advance(D.HookFailure{reason}, call, pending) == Hooks.Refused{} : Hooks.Progress}

law hook_foreign_owner:
  for +owner: Nat
  for +other: Nat
  for +id: String
  for plugin: D.PluginRef
  for outcome: D.HookOutcome
  for pending: +List<D.PluginRef>
  for +state: Hooks.Progress
  for different: {Nat.is_eq(other, owner) == False{} : Bool}
  {Hooks.history_step(D.HookRecord{other, id, plugin, outcome}, owner, id, pending, state) == state : Hooks.Progress}

law hook_record_order:
  for +expected: D.PluginRef
  for +actual: D.PluginRef
  for +call: D.Call
  for +pending: +List<D.PluginRef>
  for +outcome: D.HookOutcome
  {Hooks.record(Hooks.Awaiting{call, expected <> pending}, actual, outcome) ==
    Hooks.checked_calculation(D.plugin_same(actual, expected), outcome, call, pending) : Hooks.Progress}

law event_kind_roundtrip:
  for +kind: D.EventKind
  {D.find_event(D.event_kinds(), D.event_name(kind)) == Some{kind} : Maybe<&2, D.EventKind>}

law child_return_serialization:
  for owner: Nat
  for +id: String
  for +branch: Nat
  {T.message_json(D.ForkResult{owner, id, branch}) == T.message_json(D.FunctionOutput{id, J.nat(branch), False{}}) : J.Json}

type ObservationExtension<-original: M.Decision(), -projected: M.Decision()> is Type:
  ObservationExtension{
    state: {P.decision_world(projected) == P.decision_world(original) : M.World()},
    reply: {P.decision_reply(projected) == P.decision_reply(original) : J.Json},
    effects: {Notifications.core(P.decision_effects(projected)) == Notifications.core(P.decision_effects(original)) : +List<M.Effect()>}}

law plugin_observation_extension:
  for +source: M.Input
  for before: M.World()
  for +decision: M.Decision()
  ObservationExtension<decision, Notifications.decorate(source, before, decision)>

law plugin_observation_budget_failure:
  for reason: String
  for bytes: U32
  for enriched: M.Decision()
  for +plain: M.Decision()
  {Notifications.fit(Fail{reason}, bytes, enriched, plain) == plain : M.Decision()}

# User-facing decisions are native entities too. The adapter cannot choose a
# different command resolver or manufacture state/effects while projecting it.

law delivery_observation_world:
  for +durable: Bool
  for +decision: M.Decision()
  for +previous: M.World()
  for unchanged: {P.decision_world(decision) == previous : M.World()}
  {P.decision_world(P.deliver(durable, decision, previous)) == previous : M.World()}

law delivery_observation_effects:
  for +durable: Bool
  for +decision: M.Decision()
  for +previous: M.World()
  for silent: {P.decision_effects(decision) == Nil{} : +List<M.Effect()>}
  {P.decision_effects(P.deliver(durable, decision, previous)) == Nil{} : +List<M.Effect()>}

# Unlike safety, these equalities prohibit both an always-rejecting command
# interpreter and a safe no-op. State, reply, and effects are all observable.

law review_semantics:
  for +resolution: Approvals.Resolution
  for +world: M.World()
  {P.review_result(resolution, world) == Approvals.meaning_calculation(F.State(), F.Effect, resolution, world) : M.Decision()}

law operation_semantics:
  for +operation: Commands.Operation
  for +world: M.World()
  {P.realize_calculation(operation, world) == Commands.meaning(operation, world) : M.Decision()}

law command_semantics:
  for +command: M.Command
  for +world: M.World()
  {P.apply_command(command, world) == Commands.command(command, world) : M.Decision()}

law event_semantics:
  for +event: Protocol.ResolvedEvent
  for +world: M.World()
  {P.realize_event_calculation(event, world) == Protocol.meaning(event, world) : M.Decision()}

law input_semantics:
  for +input: M.Input
  for +world: M.World()
  {P.apply(input, world) == Protocol.input(input, world) : M.Decision()}

law invocation_semantics:
  for +operation: Protocol.Invocation
  for +call: D.Call
  for +remaining: +List<D.Attempt>
  for +task: D.Task
  for +world: M.World()
  {P.realize_invocation(operation, call, remaining, task, world) == Protocol.invoked(operation, call, remaining, task, world) : M.Decision()}

law builtin_semantics:
  for +tool: Native.Body
  for +arguments: J.Json
  for +call: D.Call
  for +remaining: +List<D.Attempt>
  for +task: D.Task
  for +world: M.World()
  {P.builtin(tool, arguments, call, remaining, task, world) ==
    Protocol.invoked(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world) : M.Decision()}

law commit_semantics:
  for +decision: M.Decision()
  for +previous: M.World()
  {P.checked(decision, previous) == Commit.checked(decision, previous) : M.Decision()}

law output_semantics:
  for +durable: Bool
  for +decision: M.Decision()
  for +previous: M.World()
  {P.deliver(durable, decision, previous) == Commit.deliver(durable, decision, previous) : M.Decision()}

law command_transition:
  for +command: M.Command
  for +world: M.World()
  {P.transition(M.UserCommand{command}, world) == Commit.command(~Execution.scheduled, command, world) : M.Decision()}

law interaction_transition:
  for +input: M.Input
  for +world: M.World()
  {P.transition(input, world) == Commit.input(~Execution.scheduled, input, world) : M.Decision()}

law trace_step:
  for +tape: Transcript.Tape
  {Traces.implementation(tape) == Transcript.step(tape) : Transcript.Tape}

law trace_partition:
  for +first: Nat
  for +second: Nat
  for +tape: Transcript.Tape
  {Traces.actual(Nat.add(first, second), tape) == Traces.actual(first, Traces.actual(second, tape)) : Transcript.Tape}

law trace_interpretation:
  for +events: +List<M.Input>
  for +world: M.World()
  {Traces.replay(events, world) == P.replay(events, world) : M.World()}

law frontend_input:
  for +input: Result<&2, &2, String, M.Input>
  for +world: M.World()
  {Frontend.input(input, world) == Interface.input(input, world) : Interface.Output}

law frontend_json:
  for +json: Result<&2, &2, String, J.Json>
  for +world: M.World()
  {Frontend.json(json, world) == Interface.json(json, world) : Interface.Output}

law frontend_packet:
  for +tokens: +List<String>
  for +world: M.World()
  {Frontend.packet(tokens, world) == Interface.packet(tokens, world) : Interface.Output}

# These correspondences close the scheduling parameter in the complete command
# specification. They quantify over every resolved action and every finite run.

law execution_semantics:
  for +action: Execution.Action
  for +world: M.World()
  {P.realize_action_calculation(action, world) == Execution.meaning_calculation(action, world) : M.Decision()}

law work_semantics:
  for +work: D.Work
  for +task: D.Task
  for +world: M.World()
  {P.work_calculation(work, task, world) == Execution.work_calculation(work, task, world) : M.Decision()}

law schedule_semantics:
  for +fuel: Nat
  for +candidate: Maybe<&2, D.Task>
  for +decision: M.Decision()
  {P.schedule(fuel, candidate, decision) == Execution.schedule(fuel, candidate, decision) : M.Decision()}

law scheduling_semantics:
  for +enabled: Bool
  for +decision: M.Decision()
  {P.scheduled(enabled, decision) == Execution.scheduled(enabled, decision) : M.Decision()}

law recovery_partition:
  for +first: +List<D.Task>
  for +second: +List<D.Task>
  {P.recover_tasks(List.append(&2, D.Task, first, second)) == List.append(&2, D.Task, P.recover_tasks(first), P.recover_tasks(second)) : +List<D.Task>}

law task_view_partition:
  for +first: +List<D.Task>
  for +second: +List<D.Task>
  {T.summaries(List.append(&2, D.Task, first, second)) == List.append(&2, J.Json, T.summaries(first), T.summaries(second)) : +List<J.Json>}

law branch_result_partition:
  for +first: +List<D.Task>
  for +second: +List<D.Task>
  {Commands.identities(List.append(&2, D.Task, first, second)) == List.append(&2, J.Json, Commands.identities(first), Commands.identities(second)) : +List<J.Json>}

law recovery_view_composition:
  for +tasks: +List<D.Task>
  {T.summaries(P.recover_tasks(tasks)) == Std.map(~D.Task, ~J.Json, ~(task => T.summary(Protocol.recover(task))), tasks) : +List<J.Json>}

# These equations completely fix the bounded scheduler: zero fuel, quiescence,
# one successor step, and its dispatch gate. ContinueScheduling is observable.

law scheduling_disabled:
  for +decision: M.Decision()
  {P.scheduled(False{}, decision) == decision : M.Decision()}

law scheduling_enabled:
  for +decision: M.Decision()
  {P.scheduled(True{}, decision) ==
    Execution.scheduled_prepared(BoardScheduling.required_prepare(decision)) : M.Decision()}

law scheduling_idle:
  for fuel: Nat
  for +decision: M.Decision()
  {P.schedule(fuel, None{}, decision) == decision : M.Decision()}

law scheduling_exhausted:
  for task: D.Task
  for +world: M.World()
  for +reply: J.Json
  for +effects: +List<M.Effect()>
  {P.schedule(0n, Some{task}, C.Decision{world, reply, effects}) ==
    C.Decision{world, reply, List.append(&2, M.Effect(), effects, [Effects.ContinueScheduling{}])} : M.Decision()}

def scheduled_step(+task: D.Task, +decision: M.Decision()) -> M.Decision():
  P.combine(decision, P.work_calculation(D.task_work(task), task, P.decision_world(decision)))

law scheduling_progress:
  for +fuel: Nat
  for +task: D.Task
  for +decision: M.Decision()
  {P.schedule(1n+fuel, Some{task}, decision) ==
    P.schedule(fuel, T.runnable(P.tasks(P.decision_world(scheduled_step(task, decision)))), scheduled_step(task, decision)) : M.Decision()}

law scheduling_combines_outputs:
  for old: M.World()
  for +reply: J.Json
  for +effects: +List<M.Effect()>
  for +next: M.World()
  for ignored: J.Json
  for +added: +List<M.Effect()>
  {P.combine(C.Decision{old, reply, effects}, C.Decision{next, ignored, added}) ==
    C.Decision{next, reply, List.append(&2, M.Effect(), effects, added)} : M.Decision()}

# Dispatch and settlement are functional obligations too. A pending phase alone
# does not mean that its request was emitted, and a safe no-op cannot settle it.

law model_work:
  for +task: D.Task
  for +world: M.World()
  {P.work_calculation(D.RequestNextModel{}, task, world) == P.model_request(task, world) : M.Decision()}

law tool_work:
  for +task: D.Task
  for +world: M.World()
  {P.work_calculation(D.RunNextTool{}, task, world) == P.run_tool(D.task_phase(task), task, world) : M.Decision()}

law idle_work:
  for +task: D.Task
  for +world: M.World()
  {P.work_calculation(D.BecomeIdle{}, task, world) ==
    C.Decision{Commands.replace(D.with_phase(D.Idle{}, task), world), D.success(J.Null{}), Nil{}} : M.Decision()}

law no_work:
  for task: D.Task
  for +world: M.World()
  {P.work_calculation(D.NoWork{}, task, world) == C.Decision{world, D.success(J.Null{}), Nil{}} : M.Decision()}

law tool_dispatch:
  for +board: F.State()
  for +tool: D.Tool
  for +call: D.Call
  for +remaining: +List<D.Attempt>
  for +task: D.Task
  for +state: D.State
  {P.external_tool(tool, call, remaining, task, C.Frame{state, board}) ==
    C.Decision{C.Frame{D.with_state_next_ticket(1n+D.state_next_ticket(state),
      D.with_state_tasks(T.replace(D.state_tasks(state), T.promote(Ops.started(D.state_next_ticket(state), call, remaining, task))), state)), board},
      J.Null{}, [Effects.ExecuteTool{D.task_id(task), D.state_next_ticket(state), tool, call, D.task_context(task), Workspace.default_access(D.task_context(task))}]} : M.Decision()}

law full_history_dispatch:
  for +task: D.Task
  for +world: M.World()
  {P.model_request(task, world) == P.model_request_direct(task, world) : M.Decision()}

law model_has_no_context_preflight:
  for +task: D.Task
  for world: M.World()
  {Execution.model(task, world) == Execution.Model{task} : Execution.Action}

law summary_request_full_history:
  for +task: D.Task
  for +state: D.State
  for +board: F.State()
  {P.decision_effects(P.summary_request(task, False{}, C.Frame{state, board})) ==
    [Effects.RequestSummary{D.task_id(task), D.state_next_ticket(state), T.task_model(D.task_contract(task)),
      D.HistoryNode{D.task_history(task), D.UserMessage{D.summary_instructions()}}, D.task_context(task)}] : +List<M.Effect()>}

law accepted_model_settlement:
  for +outcome: D.Outcome
  for +allowed: +List<String>
  for +task: D.Task
  for +world: M.World()
  {P.model_matched(True{}, outcome, allowed, task, world) ==
    C.Decision{Commands.replace(T.model_outcome(outcome, allowed, task), world),
      D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision()}

law accepted_tool_settlement:
  for +operation: D.Operation()
  for +value: J.Json
  for +error: Bool
  for +task: D.Task
  for +world: M.World()
  {P.tool_matched(True{}, operation, value, error, task, world) ==
    Results.begin(F.State(), F.Effect, operation, value, error, task, world) : M.Decision()}

law accepted_summary_settlement:
  for +outcome: D.Outcome
  for +resume: Bool
  for +task: D.Task
  for +world: M.World()
  {P.summary_matched(True{}, outcome, resume, task, world) ==
    C.Decision{Commands.replace(T.summary_outcome(outcome, resume, task), world),
      D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision()}

# Recovery is a committed state-machine path, not an adapter-owned retry loop.

law context_limit_stops:
  for +task: D.Task
  {T.context_limit(True{}, task) ==
    T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Model context limit reached; full task history retained"}, task))) : D.Task}

law summary_recovery_idle:
  for ticket: Nat
  for resume: Bool
  {T.recover_phase(D.SummaryPending{ticket, resume}) == D.Idle{} : D.Phase}

law checkpoint_is_not_recompacted:
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: D.Contract
  for +status: D.Status
  for +history: D.History
  for +summary: String
  for +queued: +List<String>
  for +phase: D.Phase
  for +world: M.World()
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {P.model_request(D.Task{id, lineage, contract, status, D.HistoryNode{history, D.ContextCheckpoint{summary}}, queued, phase, operations, notified}, world) ==
    P.model_request_direct(D.Task{id, lineage, contract, status, D.HistoryNode{history, D.ContextCheckpoint{summary}}, queued, phase, operations, notified}, world) : M.Decision()}

law context_limit_after_checkpoint_stops:
  for allowed: +List<String>
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: D.Contract
  for +status: D.Status
  for +history: D.History
  for +summary: String
  for +phase: D.Phase
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {T.model_outcome(D.ContextLimit{}, allowed,
    D.Task{id, lineage, contract, status, D.HistoryNode{history, D.ContextCheckpoint{summary}}, Nil{}, phase, operations, notified}) ==
    D.Task{id, lineage, contract, status, D.HistoryNode{D.HistoryNode{history, D.ContextCheckpoint{summary}},
      D.FailureMessage{"Model context limit reached; full task history retained"}}, Nil{}, D.Idle{}, operations, notified} : D.Task}

law summary_context_limit_stops:
  for resume: Bool
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: D.Contract
  for +status: D.Status
  for +history: D.History
  for phase: D.Phase
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {T.summary_outcome(D.ContextLimit{}, resume, D.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}) ==
    D.Task{id, lineage, contract, status, D.HistoryNode{history,
      D.FailureMessage{"The summary request exceeded the model context limit; supply a bounded checkpoint with compact"}}, Nil{}, D.Idle{}, operations, notified} : D.Task}

law checkpoint_preserves_project_contract:
  for +task: D.Task
  for summary: String
  {D.task_contract(D.append_message(D.ContextCheckpoint{summary}, task)) == D.task_contract(task) : D.Contract}

# These are requirements about the definitions the server actually executes.
# They are deliberately separate from their proofs, so a changed requirement is
# visible in review. They do not claim that an OS, database, or model obeys us.

# A step either leaves the world unchanged with no effects, or preserves the
# declared world and transition predicates. This also covers rejected replies.

def Admitted(+previous: M.World(), +decision: M.Decision()) -> Type:
  Result<&1, &1,
    {P.decision_world(decision) == previous : M.World()} & {P.decision_effects(decision) == Nil{} : +List<M.Effect()>},
    {P.valid_world(decision) == True{} : Bool} & {I.decision(previous, decision) == True{} : Bool}>

law transition_admitted:
  for world: M.World()
  for input: M.Input
  Admitted(world, P.transition(input, world))

# The executable predicate includes canonical task identities, forest ancestry,
# inherited contracts, descendant quotas, and unique pending correlation tickets.
# Safety is closed under every admitted input and every finite execution trace.

law initial_world_valid:
  {I.world(M.initial()) == True{} : Bool}

law transition_preserves_world:
  for world: M.World()
  for input: M.Input
  for evidence: {I.world(world) == True{} : Bool}
  {I.world(P.next(world, input)) == True{} : Bool}

law replay_preserves_world:
  for +events: +List<M.Input>
  for +world: M.World()
  for evidence: {I.world(world) == True{} : Bool}
  {I.world(P.replay(events, world)) == True{} : Bool}

# Archived tasks are terminal. No later user input changes their history/queue.

law archived_terminal:
  for request: D.Control
  {D.control(D.Archived{}, request) == None{} : Maybe<&2, D.Status>}

law archived_input_unchanged:
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: D.Contract
  for +history: D.History
  for +queue: +List<String>
  for +phase: D.Phase
  for text: String
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {T.receive(text, D.Task{id, lineage, contract, D.Archived{}, history, queue, phase, operations, notified}) ==
    D.Task{id, lineage, contract, D.Archived{}, history, queue, phase, operations, notified} : D.Task}

# Freeze suspends dispatch; stop permits settlement but never requests a model.

law frozen_no_dispatch:
  for phase: D.Phase
  {D.work(D.Frozen{}, phase) == D.NoWork{} : D.Work}

law stopped_no_model:
  for phase: D.Phase
  {D.is_model_request(D.work(D.Stopped{}, phase)) == False{} : Bool}

law stopped_input_reactivates:
  {D.after_input(D.Stopped{}) == D.Active{} : D.Status}

law interrupt_preserves_contract:
  for +task: D.Task
  {D.task_contract(T.interrupt(task)) == D.task_contract(task) : D.Contract}

law interrupt_preserves_queue:
  for +task: D.Task
  {D.task_queue(T.interrupt(task)) == D.task_queue(task) : +List<String>}

law interrupt_settles_phase:
  for task: D.Task
  {D.task_phase(T.interrupt(task)) == D.Idle{} : D.Phase}

law interrupt_idempotent:
  for +task: D.Task
  {T.interrupt(T.interrupt(task)) == T.interrupt(task) : D.Task}

# The task contract does not change when its lifecycle or work phase changes.

law status_preserves_contract:
  for status: D.Status
  for +task: D.Task
  {D.task_contract(D.with_status(status, task)) == D.task_contract(task) : D.Contract}

law phase_preserves_contract:
  for phase: D.Phase
  for +task: D.Task
  {D.task_contract(D.with_phase(phase, task)) == D.task_contract(task) : D.Contract}

# FIFO is a list-monoid law instantiated by the actual input-queue operation.

law queue_order:
  for +first: String
  for +second: String
  for +task: D.Task
  {D.task_queue(D.queue_message(second, D.queue_message(first, task))) ==
    List.append(&2, String, D.task_queue(task), [first, second]) : +List<String>}

# A child shares the parent's history prefix and immutable contract, has a new
# task-parent edge, and receives no copy of the parent's waiting user messages.

law child_contract:
  for id: Nat
  for +parent: D.Task
  for call: String
  for branch: Nat
  for remaining: +List<D.Attempt>
  for message: Maybe<&2, String>
  {D.task_contract(P.child(id, parent, call, branch, remaining, message)) == D.task_contract(parent) : D.Contract}

law child_history_prefix:
  for +id: Nat
  for +parent: D.Task
  for +call: String
  for +branch: Nat
  for remaining: +List<D.Attempt>
  {D.task_history(P.child(id, parent, call, branch, remaining, None{})) ==
    D.child_history(Ops.inherited(parent), id, call, branch) : D.History}

law child_lineage:
  for id: Nat
  for +parent: D.Task
  for call: String
  for branch: Nat
  for remaining: +List<D.Attempt>
  for message: Maybe<&2, String>
  {D.task_lineage(P.child(id, parent, call, branch, remaining, message)) ==
    D.task_id(parent) <> D.task_lineage(parent) : +List<Nat>}

law child_queue_empty:
  for id: Nat
  for parent: D.Task
  for call: String
  for branch: Nat
  for remaining: +List<D.Attempt>
  for message: Maybe<&2, String>
  {D.task_queue(P.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<String>}

# Recovery and inheritance do not grant permission to repeat an external effect.

law unknown_effect_not_repeated:
  for call: D.Call
  {D.may_execute(D.OutcomeUnknown{}, D.RecoveryAttempt{call}) == False{} : Bool}

law internal_effect_retry_safe:
  for attempt: D.Attempt
  {D.may_execute(D.RetrySafe{}, attempt) == True{} : Bool}

# Shell and MCP effects must never be replayed merely because their result was
# lost. Their arguments do not establish that an arbitrary command is read-only.

law bash_recovery_blocked:
  for call: D.Call
  {D.may_execute(D.recovery(D.Harness{Native.Process{}}), D.RecoveryAttempt{call}) == False{} : Bool}

law mcp_recovery_blocked:
  for server: String
  for name: String
  for call: D.Call
  {D.may_execute(D.recovery(D.Mcp{server, name}), D.RecoveryAttempt{call}) == False{} : Bool}

law recover_phase_idempotent:
  for +phase: D.Phase
  {T.recover_phase(T.recover_phase(phase)) == T.recover_phase(phase) : D.Phase}

# Rejected correlation leaves state untouched before the scheduling stage.

law unmatched_model_result_unchanged:
  for outcome: D.Outcome
  for allowed: +List<String>
  for task: D.Task
  for +world: M.World()
  {P.decision_world(P.model_matched(False{}, outcome, allowed, task, world)) == world : M.World()}

law unmatched_tool_result_unchanged:
  for operation: D.Operation()
  for value: J.Json
  for error: Bool
  for task: D.Task
  for +world: M.World()
  {P.decision_world(P.tool_matched(False{}, operation, value, error, task, world)) == world : M.World()}

# History append and journal replay are actions of the list monoid: processing
# concatenated inputs equals processing the first part then the second part.
# Replay uses PROGRAM.next, not a specification-only simulator.

law history_append_composition:
  for +first: +List<D.Message>
  for +second: +List<D.Message>
  for +history: D.History
  {D.history_append(List.append(&2, D.Message, first, second), history) ==
    D.history_append(second, D.history_append(first, history)) : D.History}

law replay_composition:
  for +first: +List<M.Input>
  for +second: +List<M.Input>
  for +world: M.World()
  {P.replay(List.append(&2, M.Input, first, second), world) ==
    P.replay(second, P.replay(first, world)) : M.World()}

law replay_empty:
  for +world: M.World()
  {P.replay(Nil{}, world) == world : M.World()}

# All public queries, including invalid pages and failed output admission, leave
# the entire world unchanged and dispatch no effects. They need no journal entry.

law observation_preserves_world:
  for +query: M.Query
  for +world: M.World()
  {P.decision_world(P.transition(M.UserCommand{M.Observe{query}}, world)) == world : M.World()}

law observation_has_no_effects:
  for +query: M.Query
  for +world: M.World()
  {P.decision_effects(P.transition(M.UserCommand{M.Observe{query}}, world)) == Nil{} : +List<M.Effect()>}

law observation_not_durable:
  for query: M.Query
  {M.durable(M.UserCommand{M.Observe{query}}) == False{} : Bool}

# Inserting a query anywhere in an input trace preserves its final world.
# Query replies remain observable; this statement concerns task state, not replies.

law observation_replay:
  for +query: M.Query
  for +first: +List<M.Input>
  for +second: +List<M.Input>
  for +world: M.World()
  {P.replay(List.append(&2, M.Input, first, M.UserCommand{M.Observe{query}} <> second), world) ==
    P.replay(List.append(&2, M.Input, first, second), world) : M.World()}

law rejected_delivery_unchanged:
  for decision: M.Decision()
  for +world: M.World()
  {P.decision_world(P.output_admitted(False{}, decision, world)) == world : M.World()}

law rejected_delivery_no_effects:
  for decision: M.Decision()
  for world: M.World()
  {P.decision_effects(P.output_admitted(False{}, decision, world)) == Nil{} : +List<M.Effect()>}

law context_has_no_call_authority:
  for value: J.Json
  {T.item_calls([D.Context{value}]) == Nil{} : +List<D.Call>}

# This is an idempotent context projection, not a semantic-equivalence claim
# about model-generated text. The append-only history invariant is unchanged.

law full_history_source:
  for +history: D.History
  {D.context_history(history) == history : D.History}

law context_projection_idempotent:
  for +history: D.History
  {D.context_history(D.context_history(history)) == D.context_history(history) : D.History}

law provider_checkpoint_context:
  for +history: D.History
  for +value: J.Json
  for checked: {D.is_provider_checkpoint(value) == True{} : Bool}
  {D.context_history(D.HistoryNode{history, D.ModelContext{value}}) ==
    D.HistoryNode{history, D.ModelContext{value}} : D.History}

law provider_summary_preserves_record:
  for +value: J.Json
  for +resume: Bool
  for +task: D.Task
  for kind: {D.is_provider_checkpoint(value) == True{} : Bool}
  for valid: {D.valid_provider_checkpoint(value) == True{} : Bool}
  {T.summary_outcome(D.ModelReply{[D.Context{value}]}, resume, task) ==
    T.promote(D.with_phase(T.after_summary(resume), D.append_message(D.ModelContext{value}, task))) : D.Task}

law checkpoint_preserves_context:
  for history: D.History
  for +summary: String
  {D.context_history(D.HistoryNode{history, D.ContextCheckpoint{summary}}) ==
    D.HistoryNode{history, D.ContextCheckpoint{summary}} : D.History}

law summary_rejects_invocations:
  for call: D.Call
  for rest: +List<D.ModelItem>
  for resume: Bool
  for +task: D.Task
  {T.summary_outcome(D.ModelReply{D.Invoke{call} <> rest}, resume, task) ==
    T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Compaction failed: expected a nonempty bounded summary without tool calls; original history retained"}, task))) : D.Task}

law summary_failure_promotes_fifo:
  for +message: String
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: D.Contract
  for +history: D.History
  for +first: String
  for +rest: +List<String>
  for phase: D.Phase
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {T.summary_failure(message, D.Task{id, lineage, contract, D.Active{}, history, first <> rest, phase, operations, notified}) ==
    D.Task{id, lineage, contract, D.Active{}, D.history_append(T.user_messages(first <> rest), D.HistoryNode{history, D.FailureMessage{message}}),
      Nil{}, D.Ready{Nil{}}, operations, True{}} : D.Task}

law summary_failure_empty_stops:
  for +message: String
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: D.Contract
  for +status: D.Status
  for +history: D.History
  for phase: D.Phase
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {T.summary_failure(message, D.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}) ==
    D.Task{id, lineage, contract, status, D.HistoryNode{history, D.FailureMessage{message}}, Nil{}, D.Idle{}, operations, notified} : D.Task}


law command_consumer_correspondence:
  for member: Commands.ConstructedCommand()
  {P.realize(member) == P.command_consumer_correspondence_required(member) : M.Decision()}


law input_consumer_correspondence:
  for member: Protocol.ConstructedInput()
  {P.realize_event(member) == P.input_consumer_correspondence_required(member) : M.Decision()}


law initial_history_order:
  for +instructions: D.InitialInstructions
  for +project: D.ProjectContext
  for +message: String
  for +id: Nat
  for +lineage: +List<Nat>
  for +profile: D.Profile
  for +reasoning: String
  for +tools: +List<D.Tool>
  for +max_fork: Nat
  for +max_descendants: Nat
  for +plugins: +List<D.Plugin>
  for +context: D.TaskContext
  for +status: D.Status
  for +history: D.History
  for +queued: +List<String>
  for +phase: D.Phase
  for +operations: +List<D.Operation()>
  for +notified: Bool
  {D.task_history(D.initialize_history(instructions, project, message,
    D.Task{id, lineage, D.Contract{D.Model{profile, reasoning}, tools, max_fork, max_descendants, plugins, context}, status, history, queued, phase, operations, notified})) ==
    TaskRequirements.initial_history(instructions, project, context, profile, reasoning, message, history) : D.History}

law context_append_preserves_prefix:
  for +context: D.HistoryContext
  for +task: D.Task
  {D.task_history(D.append_context(context, task)) ==
    D.HistoryNode{D.task_history(task), D.ContextMessage{context}} : D.History}

law recorded_selection_history:
  for changed: Bool
  for +selection: Workspace.Selection
  for +parent: D.Task
  {D.task_history(Commands.record_selection(changed, selection, parent)) ==
    TaskRequirements.selected_history(changed, selection, parent) : D.History}


law selected_parent_history:
  for +context: D.TaskContext
  for +guidance: D.ProjectContext
  for +parent: D.Task
  {D.task_history(Commands.selected_parent(Workspace.Selection{context, guidance}, parent)) ==
    TaskRequirements.selected_history(Bool.not(Same.project(guidance, D.task_guidance(parent)) && Same.task_context(context, D.task_context(parent))),
      Workspace.Selection{context, guidance}, parent) : D.History}

law model_request_full_history:
  for +task: D.Task
  for +state: D.State
  for +board: F.State()
  for +catalog: +List<D.Tool>
  for profiles: +List<D.Profile>
  for forks: Nat
  for descendants: Nat
  for project: D.ProjectContext
  for plugins: +List<D.Plugin>
  for instructions: D.InitialInstructions
  {P.decision_effects(ActualReasoning.request_environment(F.State(), F.Effect, task, C.Frame{state, board},
    D.Environment{catalog, profiles, forks, descendants, project, plugins, instructions})) ==
    [Effects.RequestModel{D.task_id(task), D.state_next_ticket(state), T.task_model(D.task_contract(task)), D.task_history(task),
      T.task_tools(D.task_contract(task)), T.callable(T.task_tools(D.task_contract(task)), catalog), D.task_context(task)}] : +List<M.Effect()>}

law root_initial_history:
  for +profile: D.Profile
  for +reasoning: String
  for +message: String
  for +context: D.TaskContext
  for +instructions: D.InitialInstructions
  for +project: D.ProjectContext
  for +catalog: +List<D.Tool>
  for profiles: +List<D.Profile>
  for +forks: Nat
  for +descendants: Nat
  for +plugins: +List<D.Plugin>
  for +state: D.State
  for board: F.State()
  {D.state_tasks(C.local(D.State, F.State(), P.decision_world(P.execute_start_environment(profile, reasoning, message,
    Workspace.Selection{context, project}, C.Frame{state, board},
    D.Environment{catalog, profiles, forks, descendants, D.NoProject{}, plugins, instructions})))) ==
    List.append(&2, D.Task, D.state_tasks(state), [D.Task{D.state_next_task(state), Nil{}, D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context},
      D.Active{}, TaskRequirements.initial_history(instructions, project, context, profile, reasoning, message, D.EmptyHistory{}),
      Nil{}, D.Ready{Nil{}}, Nil{}, True{}}]) : +List<D.Task>}

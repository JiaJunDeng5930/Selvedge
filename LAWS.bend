import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./bendlib/tasks.bend as T
import ./bendlib/json.bend as J
import ./INVARIANTS.bend as I
import ./COMMANDS.bend as Commands
import ./bendlib/commit.bend as Commit
import ./bendlib/protocol.bend as Protocol
import ./bendlib/structures.bend as S
import ./bendlib/execution.bend as Execution
import ./bendlib/traces.bend as Traces
import ./bendlib/operations.bend as Ops
import ./bendlib/transcript.bend as Transcript
import ./bendlib/interface.bend as Interface
import ./bendlib/frontend.bend as Frontend

# Unlike safety, these equalities prohibit both an always-rejecting command
# interpreter and a safe no-op. State, reply, and effects are all observable.
law operation_semantics:
  for +operation: Commands.Operation
  for +world: M.World
  {P.realize(operation, world) == Commands.meaning(operation, world) : M.Decision}

law command_semantics:
  for +command: M.Command
  for +world: M.World
  {P.apply_command(command, world) == Commands.command(command, world) : M.Decision}

law event_semantics:
  for +event: Protocol.Event
  for +world: M.World
  {P.realize_event(event, world) == Protocol.meaning(event, world) : M.Decision}

law input_semantics:
  for +input: M.Input
  for +world: M.World
  {P.apply(input, world) == Protocol.input(input, world) : M.Decision}

law invocation_semantics:
  for +operation: Protocol.Invocation
  for +call: M.Call
  for +remaining: +List<M.Attempt>
  for +task: M.Task
  for +world: M.World
  {P.realize_invocation(operation, call, remaining, task, world) == Protocol.invoked(operation, call, remaining, task, world) : M.Decision}

law builtin_semantics:
  for +tool: M.Builtin
  for +arguments: J.Json
  for +call: M.Call
  for +remaining: +List<M.Attempt>
  for +task: M.Task
  for +world: M.World
  {P.builtin(tool, arguments, call, remaining, task, world) ==
    Protocol.invoked(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world) : M.Decision}

law commit_semantics:
  for +decision: M.Decision
  for +previous: M.World
  {P.checked(decision, previous) == Commit.checked(decision, previous) : M.Decision}

law output_semantics:
  for +durable: Bool
  for +decision: M.Decision
  for +previous: M.World
  {P.deliver(durable, decision, previous) == Commit.deliver(durable, decision, previous) : M.Decision}

law command_transition:
  for +command: M.Command
  for +world: M.World
  {P.transition(M.UserCommand{command}, world) == Commit.command(~Execution.scheduled, command, world) : M.Decision}

law interaction_transition:
  for +input: M.Input
  for +world: M.World
  {P.transition(input, world) == Commit.input(~Execution.scheduled, input, world) : M.Decision}

law trace_step:
  for +tape: Transcript.Tape
  {Traces.implementation(tape) == Transcript.step(tape) : Transcript.Tape}

law trace_refinement:
  for +count: Nat
  for +tape: Transcript.Tape
  {Traces.actual(count, tape) == Transcript.run(count, tape) : Transcript.Tape}

law trace_partition:
  for +first: Nat
  for +second: Nat
  for +tape: Transcript.Tape
  {Traces.actual(Nat.add(first, second), tape) == Traces.actual(first, Traces.actual(second, tape)) : Transcript.Tape}

law trace_interpretation:
  for +events: +List<M.Input>
  for +world: M.World
  {Traces.replay(events, world) == P.replay(events, world) : M.World}

law frontend_input:
  for +input: Result<&2, &2, String, M.Input>
  for +world: M.World
  {Frontend.input(input, world) == Interface.input(input, world) : Interface.Output}

law frontend_json:
  for +json: Result<&2, &2, String, J.Json>
  for +world: M.World
  {Frontend.json(json, world) == Interface.json(json, world) : Interface.Output}

law frontend_packet:
  for +tokens: +List<String>
  for +world: M.World
  {Frontend.packet(tokens, world) == Interface.packet(tokens, world) : Interface.Output}

# These correspondences close the scheduling parameter in the complete command
# specification. They quantify over every resolved action and every finite run.
law execution_semantics:
  for +action: Execution.Action
  for +world: M.World
  {P.realize_action(action, world) == Execution.meaning(action, world) : M.Decision}

law work_semantics:
  for +work: M.Work
  for +task: M.Task
  for +world: M.World
  {P.work(work, task, world) == Execution.work(work, task, world) : M.Decision}

law schedule_semantics:
  for +fuel: Nat
  for +candidate: Maybe<&2, M.Task>
  for +decision: M.Decision
  {P.schedule(fuel, candidate, decision) == Execution.schedule(fuel, candidate, decision) : M.Decision}

law scheduling_semantics:
  for +enabled: Bool
  for +decision: M.Decision
  {P.scheduled(enabled, decision) == Execution.scheduled(enabled, decision) : M.Decision}

law recovery_partition:
  for +first: +List<M.Task>
  for +second: +List<M.Task>
  {P.recover_tasks(S.append(M.Task, first, second)) == S.append(M.Task, P.recover_tasks(first), P.recover_tasks(second)) : +List<M.Task>}

law task_view_partition:
  for +first: +List<M.Task>
  for +second: +List<M.Task>
  {T.summaries(S.append(M.Task, first, second)) == S.append(J.Json, T.summaries(first), T.summaries(second)) : +List<J.Json>}

law branch_result_partition:
  for +first: +List<M.Task>
  for +second: +List<M.Task>
  {Commands.identities(S.append(M.Task, first, second)) == S.append(J.Json, Commands.identities(first), Commands.identities(second)) : +List<J.Json>}

law recovery_view_composition:
  for +tasks: +List<M.Task>
  {T.summaries(P.recover_tasks(tasks)) == S.mapped(~M.Task, ~J.Json, ~(task => T.summary(Protocol.recover(task))), tasks) : +List<J.Json>}

# These equations completely fix the bounded scheduler: zero fuel, quiescence,
# one successor step, and its dispatch gate. ContinueScheduling is observable.
law scheduling_disabled:
  for +decision: M.Decision
  {P.scheduled(False{}, decision) == decision : M.Decision}

law scheduling_enabled:
  for +decision: M.Decision
  {P.scheduled(True{}, decision) == P.schedule(P.scheduling_budget(P.decision_world(decision)),
    T.runnable(P.tasks(P.decision_world(decision))), decision) : M.Decision}

law scheduling_idle:
  for fuel: Nat
  for +decision: M.Decision
  {P.schedule(fuel, None{}, decision) == decision : M.Decision}

law scheduling_exhausted:
  for task: M.Task
  for +world: M.World
  for +reply: J.Json
  for +effects: +List<M.Effect>
  {P.schedule(0n, Some{task}, M.Decision{world, reply, effects}) ==
    M.Decision{world, reply, List.append(&2, M.Effect, effects, [M.ContinueScheduling{}])} : M.Decision}

def scheduled_step(+task: M.Task, +decision: M.Decision) -> M.Decision:
  P.combine(decision, P.work(M.task_work(task), task, P.decision_world(decision)))

law scheduling_progress:
  for +fuel: Nat
  for +task: M.Task
  for +decision: M.Decision
  {P.schedule(1n+fuel, Some{task}, decision) ==
    P.schedule(fuel, T.runnable(P.tasks(P.decision_world(scheduled_step(task, decision)))), scheduled_step(task, decision)) : M.Decision}

law scheduling_combines_outputs:
  for old: M.World
  for +reply: J.Json
  for +effects: +List<M.Effect>
  for +next: M.World
  for ignored: J.Json
  for +added: +List<M.Effect>
  {P.combine(M.Decision{old, reply, effects}, M.Decision{next, ignored, added}) ==
    M.Decision{next, reply, List.append(&2, M.Effect, effects, added)} : M.Decision}

# Dispatch and settlement are functional obligations too. A pending phase alone
# does not mean that its request was emitted, and a safe no-op cannot settle it.
law model_work:
  for +task: M.Task
  for +world: M.World
  {P.work(M.RequestNextModel{}, task, world) == P.model_request(task, world) : M.Decision}

law tool_work:
  for +task: M.Task
  for +world: M.World
  {P.work(M.RunNextTool{}, task, world) == P.run_tool(M.task_phase(task), task, world) : M.Decision}

law idle_work:
  for +task: M.Task
  for +world: M.World
  {P.work(M.BecomeIdle{}, task, world) ==
    M.Decision{Commands.replace(M.with_phase(M.Idle{}, task), world), M.success(J.Null{}), Nil{}} : M.Decision}

law no_work:
  for task: M.Task
  for +world: M.World
  {P.work(M.NoWork{}, task, world) == M.Decision{world, M.success(J.Null{}), Nil{}} : M.Decision}

law model_dispatch:
  for +task: M.Task
  for +tasks: +List<M.Task>
  for +next_task: Nat
  for +ticket: Nat
  for +catalog: +List<M.Tool>
  for +profiles: +List<M.Profile>
  for +max_fork: Nat
  for +max_descendants: Nat
  for +project: M.ProjectContext
  for +limits: M.ExecutionLimits
  {P.model_request_direct(task, M.World{tasks, next_task, ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project}, limits}) ==
    M.Decision{M.World{T.replace(tasks, M.with_phase(M.ModelPending{ticket, T.callable(T.task_tools(M.task_contract(task)), catalog)}, Ops.publish(task))),
      next_task, 1n+ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project}, limits}, J.Null{},
      [M.RequestModel{M.task_id(task), ticket, T.task_model(M.task_contract(task)), M.context_history(M.task_history(Ops.publish(task))),
        T.task_tools(M.task_contract(task)), T.callable(T.task_tools(M.task_contract(task)), catalog)}]} : M.Decision}

law tool_dispatch:
  for +tool: M.Tool
  for +call: M.Call
  for +remaining: +List<M.Attempt>
  for +task: M.Task
  for +tasks: +List<M.Task>
  for +next_task: Nat
  for +ticket: Nat
  for +environment: M.Environment
  for +limits: M.ExecutionLimits
  {P.external_tool(tool, call, remaining, task, M.World{tasks, next_task, ticket, environment, limits}) ==
    M.Decision{M.World{T.replace(tasks, T.promote(Ops.started(ticket, call, remaining, task))),
      next_task, 1n+ticket, environment, limits}, J.Null{}, [M.ExecuteTool{M.task_id(task), ticket, tool, call}]} : M.Decision}

law small_context_dispatch:
  for +task: M.Task
  for +world: M.World
  {P.realize_action(Execution.model_with_operations(False{}, False{}, task), world) == P.model_request_direct(task, world) : M.Decision}

law large_context_dispatch:
  for +task: M.Task
  for +world: M.World
  {P.realize_action(Execution.model_with_operations(True{}, False{}, task), world) == P.summary_request(task, True{}, world) : M.Decision}

law oversized_operation_barrier:
  for +task: M.Task
  {Execution.model_with_operations(True{}, True{}, task) == Execution.Idle{task} : Execution.Action}

law accepted_model_settlement:
  for +outcome: M.Outcome
  for +allowed: +List<String>
  for +task: M.Task
  for +world: M.World
  {P.model_matched(True{}, outcome, allowed, task, world) ==
    M.Decision{Commands.replace(T.model_outcome(outcome, allowed, task), world),
      M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision}

law accepted_tool_settlement:
  for +operation: M.Operation
  for +value: J.Json
  for +error: Bool
  for +task: M.Task
  for +world: M.World
  {P.tool_matched(True{}, operation, value, error, task, world) ==
    M.Decision{Commands.replace(T.complete_operation(operation, value, error, task), world),
      M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision}

law accepted_summary_settlement:
  for +outcome: M.Outcome
  for +resume: Bool
  for +task: M.Task
  for +world: M.World
  {P.summary_matched(True{}, outcome, resume, task, world) ==
    M.Decision{Commands.replace(T.summary_outcome(outcome, resume, task), world),
      M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}} : M.Decision}

# Recovery is a committed state-machine path, not an adapter-owned retry loop.
law context_recovery_work:
  for +task: M.Task
  for +world: M.World
  {P.work(M.RequestContextSummary{}, task, world) == P.summary_request(task, True{}, world) : M.Decision}

law context_recovery_ready:
  for task: M.Task
  {M.task_phase(T.context_limit(True{}, task)) == M.CompactionReady{} : M.Phase}

law recover_resumable_summary:
  for ticket: Nat
  {T.recover_phase(M.SummaryPending{ticket, True{}}) == M.CompactionReady{} : M.Phase}

law checkpoint_consumes_compaction:
  for history: M.History
  for summary: String
  {M.compactable(M.context_history(M.HistoryNode{history, M.ContextCheckpoint{summary}})) == False{} : Bool}

law checkpoint_is_not_recompacted:
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +status: M.Status
  for +history: M.History
  for +summary: String
  for +queued: +List<String>
  for +phase: M.Phase
  for +world: M.World
  for +operations: +List<M.Operation>
  for +notified: Bool
  {P.model_request(M.Task{id, lineage, contract, status, M.HistoryNode{history, M.ContextCheckpoint{summary}}, queued, phase, operations, notified}, world) ==
    P.model_request_direct(M.Task{id, lineage, contract, status, M.HistoryNode{history, M.ContextCheckpoint{summary}}, queued, phase, operations, notified}, world) : M.Decision}

law context_limit_after_checkpoint_stops:
  for allowed: +List<String>
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +status: M.Status
  for +history: M.History
  for +summary: String
  for +phase: M.Phase
  for +operations: +List<M.Operation>
  for +notified: Bool
  {T.model_outcome(M.ContextLimit{}, allowed,
    M.Task{id, lineage, contract, status, M.HistoryNode{history, M.ContextCheckpoint{summary}}, Nil{}, phase, operations, notified}) ==
    M.Task{id, lineage, contract, status, M.HistoryNode{M.HistoryNode{history, M.ContextCheckpoint{summary}},
      M.FailureMessage{"Model context limit persists after compaction; reduce the request, project guidance or tool catalog before resuming"}}, Nil{}, M.Idle{}, operations, notified} : M.Task}

law summary_context_limit_stops:
  for resume: Bool
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +status: M.Status
  for +history: M.History
  for phase: M.Phase
  for +operations: +List<M.Operation>
  for +notified: Bool
  {T.summary_outcome(M.ContextLimit{}, resume, M.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}) ==
    M.Task{id, lineage, contract, status, M.HistoryNode{history,
      M.FailureMessage{"The summary request exceeded the model context limit; supply a bounded checkpoint with compact"}}, Nil{}, M.Idle{}, operations, notified} : M.Task}

law checkpoint_preserves_project_contract:
  for +task: M.Task
  for summary: String
  {M.task_contract(M.append_message(M.ContextCheckpoint{summary}, task)) == M.task_contract(task) : M.Contract}

# These are requirements about the definitions the server actually executes.
# They are deliberately separate from their proofs, so a changed requirement is
# visible in review. They do not claim that an OS, database, or model obeys us.

# A step either leaves the world unchanged with no effects, or preserves the
# declared world and transition predicates. This also covers rejected replies.
def Admitted(+previous: M.World, +decision: M.Decision) -> Type:
  Result<&1, &1,
    {P.decision_world(decision) == previous : M.World} & {P.decision_effects(decision) == Nil{} : +List<M.Effect>},
    {P.valid_world(decision) == True{} : Bool} & {I.decision(previous, decision) == True{} : Bool}>

law transition_admitted:
  for world: M.World
  for input: M.Input
  Admitted(world, P.transition(input, world))

# The executable predicate includes canonical task identities, forest ancestry,
# inherited contracts, descendant quotas, and unique pending correlation tickets.
# Safety is closed under every admitted input and every finite execution trace.
law initial_world_valid:
  {I.world(M.initial()) == True{} : Bool}

law transition_preserves_world:
  for world: M.World
  for input: M.Input
  for evidence: {I.world(world) == True{} : Bool}
  {I.world(P.next(world, input)) == True{} : Bool}

law replay_preserves_world:
  for +events: +List<M.Input>
  for +world: M.World
  for evidence: {I.world(world) == True{} : Bool}
  {I.world(P.replay(events, world)) == True{} : Bool}

# Archived tasks are terminal. No later user input changes their history/queue.
law archived_terminal:
  for request: M.Control
  {M.control(M.Archived{}, request) == None{} : Maybe<&2, M.Status>}

law archived_input_unchanged:
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +history: M.History
  for +queue: +List<String>
  for +phase: M.Phase
  for text: String
  for +operations: +List<M.Operation>
  for +notified: Bool
  {T.receive(text, M.Task{id, lineage, contract, M.Archived{}, history, queue, phase, operations, notified}) ==
    M.Task{id, lineage, contract, M.Archived{}, history, queue, phase, operations, notified} : M.Task}

# Freeze suspends dispatch; stop permits settlement but never requests a model.
law frozen_no_dispatch:
  for phase: M.Phase
  {M.work(M.Frozen{}, phase) == M.NoWork{} : M.Work}

law stopped_no_model:
  for phase: M.Phase
  {M.is_model_request(M.work(M.Stopped{}, phase)) == False{} : Bool}

law stopped_input_reactivates:
  {M.after_input(M.Stopped{}) == M.Active{} : M.Status}

law interrupt_preserves_contract:
  for +task: M.Task
  {M.task_contract(T.interrupt(task)) == M.task_contract(task) : M.Contract}

law interrupt_preserves_queue:
  for +task: M.Task
  {M.task_queue(T.interrupt(task)) == M.task_queue(task) : +List<String>}

law interrupt_settles_phase:
  for task: M.Task
  {M.task_phase(T.interrupt(task)) == M.Idle{} : M.Phase}

law interrupt_idempotent:
  for +task: M.Task
  {T.interrupt(T.interrupt(task)) == T.interrupt(task) : M.Task}

# The task contract does not change when its lifecycle or work phase changes.
law status_preserves_contract:
  for status: M.Status
  for +task: M.Task
  {M.task_contract(M.with_status(status, task)) == M.task_contract(task) : M.Contract}

law phase_preserves_contract:
  for phase: M.Phase
  for +task: M.Task
  {M.task_contract(M.with_phase(phase, task)) == M.task_contract(task) : M.Contract}

# FIFO is a list-monoid law instantiated by the actual input-queue operation.
law queue_order:
  for +first: String
  for +second: String
  for +task: M.Task
  {M.task_queue(M.queue_message(second, M.queue_message(first, task))) ==
    List.append(&2, String, M.task_queue(task), [first, second]) : +List<String>}

# A child shares the parent's history prefix and immutable contract, has a new
# task-parent edge, and receives no copy of the parent's waiting user messages.
law child_contract:
  for id: Nat
  for +parent: M.Task
  for call: String
  for branch: Nat
  for remaining: +List<M.Attempt>
  for message: Maybe<&2, String>
  {M.task_contract(P.child(id, parent, call, branch, remaining, message)) == M.task_contract(parent) : M.Contract}

law child_history_prefix:
  for id: Nat
  for +parent: M.Task
  for +call: String
  for +branch: Nat
  for remaining: +List<M.Attempt>
  {M.task_history(P.child(id, parent, call, branch, remaining, None{})) ==
    M.branch_history(Ops.inherited(parent), call, branch) : M.History}

law child_lineage:
  for id: Nat
  for +parent: M.Task
  for call: String
  for branch: Nat
  for remaining: +List<M.Attempt>
  for message: Maybe<&2, String>
  {M.task_lineage(P.child(id, parent, call, branch, remaining, message)) ==
    M.task_id(parent) <> M.task_lineage(parent) : +List<Nat>}

law child_queue_empty:
  for id: Nat
  for parent: M.Task
  for call: String
  for branch: Nat
  for remaining: +List<M.Attempt>
  for message: Maybe<&2, String>
  {M.task_queue(P.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<String>}

# Recovery and inheritance do not grant permission to repeat an external effect.
law unknown_effect_not_repeated:
  for call: M.Call
  {M.may_execute(M.OutcomeUnknown{}, M.RecoveryAttempt{call}) == False{} : Bool}

law internal_effect_retry_safe:
  for attempt: M.Attempt
  {M.may_execute(M.RetrySafe{}, attempt) == True{} : Bool}

# Shell and MCP effects must never be replayed merely because their result was
# lost. Their arguments do not establish that an arbitrary command is read-only.
law bash_recovery_blocked:
  for call: M.Call
  {M.may_execute(M.recovery(M.Harness{M.Bash{}}), M.RecoveryAttempt{call}) == False{} : Bool}

law mcp_recovery_blocked:
  for server: String
  for name: String
  for call: M.Call
  {M.may_execute(M.recovery(M.Mcp{server, name}), M.RecoveryAttempt{call}) == False{} : Bool}

law recover_phase_idempotent:
  for +phase: M.Phase
  {T.recover_phase(T.recover_phase(phase)) == T.recover_phase(phase) : M.Phase}

# Rejected correlation leaves state untouched before the scheduling stage.
law unmatched_model_result_unchanged:
  for outcome: M.Outcome
  for allowed: +List<String>
  for task: M.Task
  for +world: M.World
  {P.decision_world(P.model_matched(False{}, outcome, allowed, task, world)) == world : M.World}

law unmatched_tool_result_unchanged:
  for operation: M.Operation
  for value: J.Json
  for error: Bool
  for task: M.Task
  for +world: M.World
  {P.decision_world(P.tool_matched(False{}, operation, value, error, task, world)) == world : M.World}

# History append and journal replay are actions of the list monoid: processing
# concatenated inputs equals processing the first part then the second part.
# Replay uses PROGRAM.next, not a specification-only simulator.
law history_append_composition:
  for +first: +List<M.Message>
  for +second: +List<M.Message>
  for +history: M.History
  {M.history_append(List.append(&2, M.Message, first, second), history) ==
    M.history_append(second, M.history_append(first, history)) : M.History}

law replay_composition:
  for +first: +List<M.Input>
  for +second: +List<M.Input>
  for +world: M.World
  {P.replay(List.append(&2, M.Input, first, second), world) ==
    P.replay(second, P.replay(first, world)) : M.World}

law replay_empty:
  for +world: M.World
  {P.replay(Nil{}, world) == world : M.World}

# All public queries, including invalid pages and failed output admission, leave
# the entire world unchanged and dispatch no effects. They need no journal entry.
law observation_preserves_world:
  for +query: M.Query
  for +world: M.World
  {P.decision_world(P.transition(M.UserCommand{M.Observe{query}}, world)) == world : M.World}

law observation_has_no_effects:
  for +query: M.Query
  for +world: M.World
  {P.decision_effects(P.transition(M.UserCommand{M.Observe{query}}, world)) == Nil{} : +List<M.Effect>}

law observation_not_durable:
  for query: M.Query
  {M.durable(M.UserCommand{M.Observe{query}}) == False{} : Bool}

# Inserting a query anywhere in an input trace preserves its final world.
# Query replies remain observable; this statement concerns task state, not replies.
law observation_replay:
  for +query: M.Query
  for +first: +List<M.Input>
  for +second: +List<M.Input>
  for +world: M.World
  {P.replay(List.append(&2, M.Input, first, M.UserCommand{M.Observe{query}} <> second), world) ==
    P.replay(List.append(&2, M.Input, first, second), world) : M.World}

law rejected_delivery_unchanged:
  for decision: M.Decision
  for +world: M.World
  {P.decision_world(P.output_admitted(False{}, decision, world)) == world : M.World}

law rejected_delivery_no_effects:
  for decision: M.Decision
  for world: M.World
  {P.decision_effects(P.output_admitted(False{}, decision, world)) == Nil{} : +List<M.Effect>}

law context_has_no_call_authority:
  for value: J.Json
  {T.item_calls([M.Context{value}]) == Nil{} : +List<M.Call>}

# This is an idempotent context projection, not a semantic-equivalence claim
# about model-generated text. The append-only history invariant is unchanged.
law context_projection_idempotent:
  for +history: M.History
  {M.context_history(M.context_history(history)) == M.context_history(history) : M.History}

law checkpoint_cuts_context:
  for history: M.History
  for +summary: String
  {M.context_history(M.HistoryNode{history, M.ContextCheckpoint{summary}}) ==
    M.HistoryNode{M.EmptyHistory{}, M.ContextCheckpoint{summary}} : M.History}

law summary_rejects_invocations:
  for call: M.Call
  for rest: +List<M.ModelItem>
  for resume: Bool
  for +task: M.Task
  {T.summary_outcome(M.ModelReply{M.Invoke{call} <> rest}, resume, task) ==
    T.promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{"Compaction failed: expected a nonempty bounded summary without tool calls; original history retained"}, task))) : M.Task}

law summary_failure_promotes_fifo:
  for +message: String
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +history: M.History
  for +first: String
  for +rest: +List<String>
  for phase: M.Phase
  for +operations: +List<M.Operation>
  for +notified: Bool
  {T.summary_failure(message, M.Task{id, lineage, contract, M.Active{}, history, first <> rest, phase, operations, notified}) ==
    M.Task{id, lineage, contract, M.Active{}, M.history_append(T.user_messages(first <> rest), M.HistoryNode{history, M.FailureMessage{message}}),
      Nil{}, M.Ready{Nil{}}, operations, True{}} : M.Task}

law summary_failure_empty_stops:
  for +message: String
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +status: M.Status
  for +history: M.History
  for phase: M.Phase
  for +operations: +List<M.Operation>
  for +notified: Bool
  {T.summary_failure(message, M.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}) ==
    M.Task{id, lineage, contract, status, M.HistoryNode{history, M.FailureMessage{message}}, Nil{}, M.Idle{}, operations, notified} : M.Task}

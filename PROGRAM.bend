import Base
import ./MODEL.bend as M
import ./bendlib/json.bend as J
import ./bendlib/tasks.bend as T
import ./bendlib/schema.bend as Schema
import ./bendlib/theory.bend as Theory
import ./bendlib/presentation.bend as View
import ./INVARIANTS.bend as I
import ./COMMANDS.bend as Commands
import ./bendlib/commit.bend as Commit
import ./bendlib/protocol.bend as Protocol

# Accepted updates pass through resolution, realization and bounded scheduling.
# program's state transition, and the object named by LAWS.bend and PROOF.bend.
# The host owns no task state, lifecycle table, fork rule, or recovery decision.

def tasks(world: M.World) -> +List<M.Task>:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  tasks

def environment(world: M.World) -> M.Environment:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  environment

def catalog(environment: M.Environment) -> +List<M.Tool>:
  M.Environment{catalog, profiles, max_fork, max_descendants, project} = environment
  catalog

def next_task(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  next_task

def store(task: M.Task, world: M.World) -> M.World:
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  M.World{T.replace(tasks, task), next_task, next_ticket, environment, limits}

def respond(world: M.World, result: J.Json) -> M.Decision:
  M.Decision{world, M.success(result), Nil{}}

def reject(world: M.World, code: String, message: String) -> M.Decision:
  M.Decision{world, M.failure(code, message), Nil{}}

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def execute_start(profile: M.Profile, reasoning: String, message: String, world: M.World) -> M.Decision:
  M.World{tasks, +next_task, next_ticket, +environment, limits} = world
  M.Environment{catalog, profiles, max_fork, max_descendants, project} = environment
  task : M.Task = M.Task{next_task, Nil{}, M.Contract{M.Model{profile, reasoning, project}, catalog, max_fork, max_descendants},
    M.Active{}, M.HistoryNode{M.EmptyHistory{}, M.UserMessage{message}}, Nil{}, M.Ready{Nil{}}}
  respond(M.World{List.append(&2, M.Task, tasks, [task]), 1n+next_task, next_ticket, environment, limits}, id_result(next_task))

def execute_delivery(text: String, +task: M.Task, world: M.World) -> M.Decision:
  respond(store(T.receive(text, task), world), id_result(M.task_id(task)))

def change_to(next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match next:
    case M.Archived{}:
      M.Decision{store(M.with_phase(M.Idle{}, M.with_status(M.Archived{}, task)), world),
        M.success(id_result(M.task_id(task))), [M.CancelTask{M.task_id(task)}]}
    case other:
      respond(store(T.promote(M.with_status(other, task)), world), id_result(M.task_id(task)))

def change_requested(control: M.Control, next: M.Status, +task: M.Task, world: M.World) -> M.Decision:
  match control:
    case M.Interrupt{}:
      M.Decision{store(T.interrupt(task), world), M.success(id_result(M.task_id(task))), [M.CancelTask{M.task_id(task)}]}
    case _: change_to(next, task, world)

def query(request: M.Query, world: M.World) -> J.Json:
  Commands.query(request, world)

def observe(request: M.Query, +world: M.World) -> M.Decision:
  M.Decision{world, query(request, world), Nil{}}

def child(id: Nat, parent: M.Task, call_id: String, branch: Nat, remaining: +List<M.Attempt>, message: Maybe<&2, String>) -> M.Task:
  Commands.child(id, parent, call_id, branch, remaining, message)

def children(count: Nat, +next_id: Nat, +branch: Nat, +parent: M.Task, +call_id: String,
  +remaining: +List<M.Attempt>, +messages: +List<String>) -> Commands.Children:
  Commands.children(count, next_id, branch, parent, call_id, remaining, messages)

def ids(tasks: +List<M.Task>) -> +List<J.Json>:
  Commands.identities(tasks)

def commit_fork(built: Commands.Children, call: M.Call, remaining: +List<M.Attempt>, +parent: M.Task, world: M.World) -> M.Decision:
  match built world:
    case Commands.Children{+new_tasks, end} M.World{tasks, next_task, next_ticket, environment, limits}:
      caller = T.promote(M.with_phase(M.Ready{remaining}, M.with_history(M.branch_history(M.task_history(parent), T.call_id(call), 0n), parent)))
      respond(M.World{List.append(&2, M.Task, T.replace(tasks, caller), new_tasks), end, next_ticket, environment, limits},
        J.Object{[J.Field{"children", J.Array{ids(new_tasks)}}]})

def summary_request(+task: M.Task, resume: Bool, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, environment, limits} = world
  next = M.with_phase(M.SummaryPending{next_ticket, resume}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits}, M.success(id_result(M.task_id(task))),
    [M.RequestSummary{M.task_id(task), next_ticket, T.task_model(M.task_contract(task)), M.context_history(M.task_history(task))}]}

def execute_checkpoint(summary: String, +task: M.Task, world: M.World) -> M.Decision:
  respond(store(M.append_message(M.ContextCheckpoint{summary}, task), world), id_result(M.task_id(task)))

def execute_branch(+task: M.Task, +count: Nat, +messages: +List<String>, world: M.World) -> M.Decision:
  M.World{tasks, +next_task, +next_ticket, environment, limits} = world
  +call = Commands.branch_call(next_ticket, count, messages)
  +parent = M.append_message(M.FunctionCall{call}, task)
  commit_fork(children(count, next_task, 1n, parent, T.call_id(call), Nil{}, messages), call, Nil{}, parent,
    M.World{tasks, next_task, 1n+next_ticket, environment, limits})

# PROGRAM realizes the resolved operation. The refinement proof compares the
# entire decision with COMMANDS.meaning, including replies and requested work.
def realize(operation: Commands.Operation, world: M.World) -> M.Decision:
  match operation:
    case Commands.Refuse{code, reason}: reject(world, code, reason)
    case Commands.Start{profile, reasoning, message}: execute_start(profile, reasoning, message, world)
    case Commands.Deliver{task, message}: execute_delivery(message, task, world)
    case Commands.Control{task, request, next}: change_requested(request, next, task, world)
    case Commands.Branch{task, count, messages}: execute_branch(task, count, messages, world)
    case Commands.Summarize{task}: summary_request(task, False{}, world)
    case Commands.Checkpoint{task, summary}: execute_checkpoint(summary, task, world)
    case Commands.Observe{query}: observe(query, world)

def apply_command(command: M.Command, +world: M.World) -> M.Decision:
  realize(Commands.resolve(command, world), world)

def accepted(yes: Bool) -> J.Json:
  J.Object{[J.Field{"accepted", J.Boolean{yes}}]}

def model_matched(same: Bool, outcome: M.Outcome, allowed: +List<String>, task: M.Task, world: M.World) -> M.Decision:
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.model_outcome(outcome, allowed, task), world), accepted(True{}))

def summary_matched(same: Bool, outcome: M.Outcome, resume: Bool, task: M.Task, world: M.World) -> M.Decision:
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.summary_outcome(outcome, resume, task), world), accepted(True{}))

def tool_matched(same: Bool, call: M.Call, remaining: +List<M.Attempt>, value: J.Json, error: Bool, task: M.Task, world: M.World) -> M.Decision:
  match same:
    case False{}: respond(world, accepted(False{}))
    case True{}: respond(store(T.complete_tool(call, remaining, value, error, task), world), accepted(True{}))

def recover_tasks(tasks: +List<M.Task>) -> +List<M.Task>:
  Protocol.recovery(tasks)

def realize_event(event: Protocol.Event, world: M.World) -> M.Decision:
  match event:
    case Protocol.User{operation}: realize(operation, world)
    case Protocol.Ignore{}: respond(world, accepted(False{}))
    case Protocol.ModelResult{task, outcome, allowed}: model_matched(True{}, outcome, allowed, task, world)
    case Protocol.SummaryResult{task, outcome, resume}: summary_matched(True{}, outcome, resume, task, world)
    case Protocol.ToolResult{task, call, remaining, value, error}: tool_matched(True{}, call, remaining, value, error, task, world)
    case Protocol.Settings{environment}:
      M.World{tasks, next_task, next_ticket, previous, limits} = world
      respond(M.World{tasks, next_task, next_ticket, environment, limits}, J.Null{})
    case Protocol.Restart{}:
      M.World{tasks, next_task, next_ticket, environment, limits} = world
      respond(M.World{recover_tasks(tasks), next_task, next_ticket, environment, limits}, J.Null{})
    case Protocol.Tick{}: respond(world, J.Null{})

def apply(input: M.Input, +world: M.World) -> M.Decision:
  realize_event(Protocol.resolve(input, world), world)

def decision_world(decision: M.Decision) -> M.World:
  M.Decision{world, reply, effects} = decision
  world

def decision_reply(decision: M.Decision) -> J.Json:
  M.Decision{world, reply, effects} = decision
  reply

def decision_effects(decision: M.Decision) -> +List<M.Effect>:
  M.Decision{world, reply, effects} = decision
  effects

def model_request_direct(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, +environment, limits} = world
  +contract = M.task_contract(task)
  +tools = T.task_tools(contract)
  +allowed = T.callable(tools, catalog(environment))
  next = M.with_phase(M.ModelPending{next_ticket, allowed}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits}, J.Null{},
    [M.RequestModel{M.task_id(task), next_ticket, T.task_model(contract), M.context_history(M.task_history(task)), tools, allowed}]}

def needs_summary(rendered: Result<&2, &2, String, String>) -> Bool:
  match rendered:
    case Fail{error}: True{}
    case Done{text}: Nat.is_le(M.context_threshold_bytes(), J.utf8_length(text))

def model_request_sized(large: Bool, task: M.Task, world: M.World) -> M.Decision:
  match large:
    case True{}: summary_request(task, True{}, world)
    case False{}: model_request_direct(task, world)

def rendering_budget(world: M.World) -> Nat:
  Commit.render_budget(world)

# Include the frozen guidance and tool schemas in the byte heuristic. This is
# not a token oracle. Explicit provider overflow follows the same bounded path.
def request_context(+task: M.Task) -> J.Json:
  J.Object{[J.Field{"model", View.model_json(T.task_model(M.task_contract(task)))},
    J.Field{"tools", J.Array{M.tools_json(T.task_tools(M.task_contract(task)))}},
    J.Field{"history", J.Array{T.messages_json(M.history_messages(M.context_history(M.task_history(task)), Nil{}))}}]}

def model_request(+task: M.Task, +world: M.World) -> M.Decision:
  model_request_sized(M.compactable(M.context_history(M.task_history(task))) &&
    needs_summary(J.render(rendering_budget(world), J.One{request_context(task)})), task, world)

def external_tool(tool: M.Tool, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +next_ticket, environment, limits} = world
  next = M.with_phase(M.ToolPending{next_ticket, call, remaining}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+next_ticket, environment, limits}, J.Null{},
    [M.ExecuteTool{M.task_id(task), next_ticket, tool, call}]}

def tool_error(code: String, message: String, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  respond(store(T.complete_tool(call, remaining, M.failure(code, message), True{}, task), world), J.Null{})

def finish_archived(status: M.Status, task: M.Task) -> M.Task:
  match status:
    case M.Archived{}: M.with_phase(M.Idle{}, task)
    case _: task

# Internal effects and their calling-task output are one pure transition and one
# durable commit. Looking the caller up again preserves self-send/self-archive.
def internal_result(found: Maybe<&2, M.Task>, call: M.Call, remaining: +List<M.Attempt>, +result: M.Decision) -> M.Decision:
  match found:
    case None{}:
      result
    case Some{+task}:
      +reply = decision_reply(result)
      next = finish_archived(M.task_status(task), T.complete_tool(call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task))
      M.Decision{store(next, decision_world(result)), J.Null{}, decision_effects(result)}

def finish_internal(id: Nat, call: M.Call, remaining: +List<M.Attempt>, +result: M.Decision) -> M.Decision:
  internal_result(T.find(tasks(decision_world(result)), id), call, remaining, result)

def realize_invocation(operation: Protocol.Invocation, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, +world: M.World) -> M.Decision:
  match operation:
    case Protocol.Internal{operation}:
      finish_internal(M.task_id(task), call, remaining, realize(operation, world))
    case Protocol.Branch{count, messages}:
      commit_fork(children(count, next_task(world), 1n, task, T.call_id(call), remaining, messages), call, remaining, task, world)

def builtin(tool: M.Builtin, arguments: J.Json, call: M.Call, remaining: +List<M.Attempt>, +task: M.Task, +world: M.World) -> M.Decision:
  realize_invocation(Protocol.invocation(tool, arguments, task, world), call, remaining, task, world)

def dispatch_execution(execution: M.Execution, source: M.Source, tool: M.Tool, +call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match execution source:
    case M.ExternalObservation{} _:
      external_tool(tool, call, remaining, task, world)
    case M.ExternalMutation{} _:
      external_tool(tool, call, remaining, task, world)
    case M.InternalOperation{} M.Harness{builtin_tool}:
      builtin(builtin_tool, T.call_arguments(call), call, remaining, task, world)
    case _ _:
      tool_error("internal_error", "Invalid internal tool classification", call, remaining, task, world)

def dispatch_source(+source: M.Source, tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  dispatch_execution(M.execution(source), source, tool, call, remaining, task, world)

def tool_schema(tool: M.Tool) -> J.Json:
  M.Tool{name, description, schema, source} = tool
  schema

def valid_arguments(source: M.Source, schema: J.Json, +arguments: J.Json) -> Bool:
  match source:
    case M.Mcp{server, remote}:
      J.is_object(arguments)
    case M.Harness{M.Bash{}}:
      Schema.valid(schema, arguments) && M.nonempty(J.text(J.get(arguments, "command")))
    case M.Harness{other}:
      Schema.valid(schema, arguments)

def tool_valid(valid: Bool, +tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match valid:
    case False{}:
      tool_error("invalid_arguments", "Tool arguments do not satisfy its frozen schema", call, remaining, task, world)
    case True{}:
      dispatch_source(M.tool_source(tool), tool, call, remaining, task, world)

def tool_available(available: Bool, +tool: M.Tool, +call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match available:
    case False{}:
      tool_error("tool_unavailable", "The task's frozen tool route is unavailable", call, remaining, task, world)
    case True{}:
      tool_valid(valid_arguments(M.tool_source(tool), tool_schema(tool), T.call_arguments(call)), tool, call, remaining, task, world)

def tool_retry(permitted: Bool, +tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, +world: M.World) -> M.Decision:
  match permitted:
    case False{}:
      tool_error("outcome_unknown", "The effect may already have happened; automatic repetition is forbidden", call, remaining, task, world)
    case True{}:
      tool_available(T.available(catalog(environment(world)), tool), tool, call, remaining, task, world)

def tool_found_for_work(found: Maybe<&2, M.Tool>, +attempt: M.Attempt, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> M.Decision:
  match found:
    case None{}:
      tool_error("unknown_tool", "The call does not name a tool in the task contract", M.attempt_call(attempt), remaining, task, world)
    case Some{+tool}:
      tool_retry(M.may_execute(M.recovery(M.tool_source(tool)), attempt), tool, M.attempt_call(attempt), remaining, task, world)

def run_tool(phase: M.Phase, +task: M.Task, world: M.World) -> M.Decision:
  match phase:
    case M.Ready{Con{+attempt, remaining}}:
      tool_found_for_work(T.find_tool(T.task_tools(M.task_contract(task)), T.call_name(M.attempt_call(attempt))), attempt, remaining, task, world)
    case _: respond(world, J.Null{})

def work(work: M.Work, +task: M.Task, world: M.World) -> M.Decision:
  match work:
    case M.NoWork{}: respond(world, J.Null{})
    case M.BecomeIdle{}: respond(store(M.with_phase(M.Idle{}, task), world), J.Null{})
    case M.RequestNextModel{}: model_request(task, world)
    case M.RequestContextSummary{}: summary_request(task, True{}, world)
    case M.RunNextTool{}: run_tool(M.task_phase(task), task, world)

def combine(before: M.Decision, after: M.Decision) -> M.Decision:
  match before after:
    case M.Decision{old, reply, effects} M.Decision{world, ignored, added}:
      M.Decision{world, reply, List.append(&2, M.Effect, effects, added)}

def defer(decision: M.Decision) -> M.Decision:
  M.Decision{world, reply, effects} = decision
  M.Decision{world, reply, List.append(&2, M.Effect, effects, [M.ContinueScheduling{}])}

# A finite input transition cannot promise that an agent will finish. It makes
# bounded progress and explicitly requests another turn if internal work remains.
def schedule(fuel: Nat, candidate: Maybe<&2, M.Task>, +decision: M.Decision) -> M.Decision:
  match fuel candidate:
    case 0n None{}: decision
    case 0n Some{task}: defer(decision)
    case 1n+p None{}: decision
    case 1n+p Some{+task}:
      +next = combine(decision, work(M.work(M.task_status(task), M.task_phase(task)), task, decision_world(decision)))
      schedule(p, T.runnable(tasks(decision_world(next))), next)

def scheduling_budget(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, bytes}} = world
  steps

def frame_limit(world: M.World) -> U32:
  Commit.frame_bytes(world)

def scheduled(enabled: Bool, +decision: M.Decision) -> M.Decision:
  match enabled:
    case False{}: decision
    case True{}: schedule(scheduling_budget(decision_world(decision)), T.runnable(tasks(decision_world(decision))), decision)

def output_admitted(fits: Bool, decision: M.Decision, previous: M.World) -> M.Decision:
  match fits:
    case True{}: decision
    case False{}: reject(previous, "output_limit", "The complete decision exceeds the native output bound; no state change or effect was committed")

def admission(rendered: Result<&2, &2, String, String>, decision: M.Decision, +previous: M.World) -> M.Decision:
  match rendered:
    case Fail{error}: reject(previous, "output_limit", error)
    case Done{text}:
      output_admitted(Nat.is_le(J.utf8_length(text), U32.to_nat(frame_limit(previous))), decision, previous)

def deliver(durable: Bool, +decision: M.Decision, +previous: M.World) -> M.Decision:
  admission(J.render(rendering_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous)

def live_decision(decision: M.Decision) -> M.Decision:
  M.Decision{+world, reply, effects} = decision
  M.Decision{world, reply, I.live_effects(effects, tasks(world))}

def valid_world(decision: M.Decision) -> Bool:
  I.world(decision_world(decision))

def admitted(state_valid: Bool, change_valid: Bool, decision: M.Decision, previous: M.World) -> M.Decision:
  Theory.admit(~M.Decision, state_valid, change_valid, decision,
    reject(previous, "invariant_violation", "The candidate violates a world invariant, task retention, or effect authority"))

def check_live(+decision: M.Decision, +previous: M.World) -> M.Decision:
  admitted(valid_world(decision), I.decision(previous, decision), decision, previous)

# Reflection checks the declared predicates on the actual candidate. Rejection
# retains the old state and emits no effects; output admission has the same rule.
def checked(decision: M.Decision, previous: M.World) -> M.Decision:
  check_live(live_decision(decision), previous)

def after_apply(+input: M.Input, +decision: M.Decision, +world: M.World) -> M.Decision:
  deliver(M.durable(input), checked(scheduled(Commit.schedules(input, decision), decision), world), world)

def update(+input: M.Input, +world: M.World) -> M.Decision:
  after_apply(input, apply(input, world), world)

def transition(input: M.Input, +world: M.World) -> M.Decision:
  match input:
    case M.UserCommand{M.Observe{request}}: deliver(False{}, observe(request, world), world)
    case other: update(other, world)

def next(world: M.World, input: M.Input) -> M.World:
  decision_world(transition(input, world))

def replay(events: +List<M.Input>, world: M.World) -> M.World:
  Theory.replay(~M.World, ~M.Input, ~next, events, world)

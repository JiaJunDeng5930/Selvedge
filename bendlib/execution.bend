import Base
import ../FEATURES.bend as F
import ./effects.bend as Effects
import ./component.bend as C
import ./domain.bend as D
import ./board-scheduling-spec.bend as BoardScheduling
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./protocol.bend as Protocol
import ./tasks.bend as T
import ./json.bend as J
import ./schema.bend as Schema
import ./presentation.bend as View
import ./operations.bend as Ops
import ../HOOKS.bend as Hooks
import ../WORKSPACE.bend as Workspace
import ../APPROVALS.bend as Approvals
import ./results.bend as Results
import ./reasoning-spec.bend as Reasoning

# The execution alphabet is the semantic boundary between task policy and the
# scheduler. Resolution owns authority, recovery and argument preconditions;
# meaning fixes the entire decision. Neither definition imports PROGRAM.
type Action is Data:
  Rest{}
  Idle{task: D.Task}
  Model{task: D.Task}
  Summary{task: D.Task, resume: Bool}
  External{tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Review{reviewer: D.ApprovalReviewer, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Granted{reviewer: D.ApprovalReviewer, tool: D.Tool, operation: D.Operation(), task: D.Task}
  GrantFailure{operation: D.Operation(), task: D.Task}
  Hook{plugin: D.PluginRef, pending: +List<D.PluginRef>, tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Internal{operation: Protocol.Invocation, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Failure{code: String, reason: String, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}

def catalog(world: M.World()) -> +List<D.Tool>:
  C.Frame{D.State{tasks, next_task, next_ticket, D.Environment{tools, profiles, max_fork, max_descendants, project, plugins}, limits, projects}, +board} = world
  tools

def render_budget(world: M.World()) -> Nat:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, D.ExecutionLimits{steps, render, bytes}, projects}, +board} = world
  render

def context(+task: D.Task) -> J.Json:
  J.Object{[J.Field{"model", View.model_json(T.task_model(D.task_contract(task)))},
    J.Field{"tools", J.Array{D.tools_json(T.task_tools(D.task_contract(task)))}},
    J.Field{"history", J.Array{T.messages_json(D.history_messages(D.context_history(D.task_history(task)), Nil{}))}}]}

def oversized(rendered: Result<&2, &2, String, String>) -> Bool:
  match rendered:
    case Fail{reason}: True{}
    case Done{text}: Nat.is_le(D.context_threshold_bytes(), J.utf8_length(text))

def model_with_operations(large: Bool, pending: Bool, task: D.Task) -> Action:
  match large pending:
    case True{} True{}: Idle{task}
    case True{} False{}: Summary{task, True{}}
    case False{} _: Model{task}

def model(+task: D.Task, world: M.World()) -> Action:
  model_with_operations(D.compactable(D.context_history(D.task_history(task))) &&
    oversized(J.render(render_budget(world), J.One{context(task)})), D.operations_pending(D.task_operations(task)), task)

def arguments_valid(source: D.Source, schema: J.Json, +arguments: J.Json) -> Bool:
  match source:
    case D.Extension{plugin, remote}: Schema.valid(schema, arguments)
    case D.Mcp{server, remote}: J.is_object(arguments)
    case D.Harness{D.Bash{}}:
      Schema.valid(schema, arguments) && D.nonempty(J.text(J.get(arguments, "command"))) &&
        Bool.not(String.contains(J.text(J.get(arguments, "command")), SCon{Chr{0}, SNil{}})) && Approvals.valid_request(arguments)
    case D.Harness{other}: Schema.valid(schema, arguments)

def external_review(needed: Bool, tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, +task: D.Task) -> Action:
  match needed:
    case True{}: Review{Approvals.reviewer(Workspace.approval(D.task_context(task))), call, remaining, task}
    case False{}: External{tool, call, remaining, task}

def external_capacity(available: Bool, +tool: D.Tool, +call: D.Call, remaining: +List<D.Attempt>, +task: D.Task) -> Action:
  match available:
    case True{}: external_review(Approvals.needed(D.tool_source(tool), T.call_arguments(call), Workspace.approval(D.task_context(task))),
      tool, call, remaining, task)
    case False{}: Failure{"operation_limit", "This task has reached its in-flight operation limit; wait for results or cancel an operation", call, remaining, task}

def internal_capacity(available: Bool, builtin: D.Builtin, +call: D.Call, remaining: +List<D.Attempt>, +task: D.Task, world: M.World()) -> Action:
  match available:
    case True{}: Internal{Protocol.invocation(builtin, T.call_arguments(call), task, world), call, remaining, task}
    case False{}: Failure{"operation_limit", "This task has reached its result-processing operation limit; wait for results or cancel an operation", call, remaining, task}

def classified(execution: D.Execution, source: D.Source, tool: D.Tool, +call: D.Call,
  remaining: +List<D.Attempt>, +task: D.Task, world: M.World()) -> Action:
  match execution source:
    case D.ExternalMutation{} _:
      external_capacity(Nat.is_lt(List.length(&2, D.Operation(), D.task_operations(task)), D.operation_limit()), tool, call, remaining, task)
    case D.InternalOperation{} D.Harness{builtin}:
      internal_capacity(Nat.is_eq(List.length(&2, D.PluginRef, Hooks.after(Hooks.plugins(D.task_contract(task)))), 0n) ||
        Nat.is_lt(List.length(&2, D.Operation(), D.task_operations(task)), D.operation_limit()), builtin, call, remaining, task, world)
    case _ _:
      Failure{"internal_error", "Invalid internal tool classification", call, remaining, task}

def validated(valid: Bool, +tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()) -> Action:
  match valid:
    case False{}:
      Failure{"invalid_arguments", "Tool arguments do not satisfy its frozen schema", call, remaining, task}
    case True{}:
      classified(D.execution(D.tool_source(tool)), D.tool_source(tool), tool, call, remaining, task, world)

def available(present: Bool, +tool: D.Tool, +call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()) -> Action:
  match present:
    case False{}:
      Failure{"tool_unavailable", "The task's frozen tool route is unavailable", call, remaining, task}
    case True{}:
      D.Tool{name, description, schema, source} = tool
      validated(arguments_valid(source, schema, T.call_arguments(call)), tool, call, remaining, task, world)

def hook_available(present: Bool, plugin: D.PluginRef, pending: +List<D.PluginRef>, tool: D.Tool,
  call: D.Call, remaining: +List<D.Attempt>, task: D.Task) -> Action:
  match present:
    case True{}: Hook{plugin, pending, tool, call, remaining, task}
    case False{}: Failure{"hook_unavailable", "A required frozen plugin revision is unavailable; the tool was not dispatched", call, remaining, task}

# Every route crosses this boundary before internal/external classification and
# argument validation. Each accepted rewrite is revalidated at the final gate.
def chain(pending: +List<D.PluginRef>, +tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, +world: M.World()) -> Action:
  match pending:
    case Nil{}: available(T.available(catalog(world), tool), tool, call, remaining, task, world)
    case Con{+plugin, pending}: hook_available(Hooks.available(Hooks.live(F.State(), world), plugin), plugin, pending, tool, call, remaining, task)

def authorization(repeatable: Bool, tool: D.Tool, +attempt: D.Attempt, remaining: +List<D.Attempt>, +task: D.Task, world: M.World()) -> Action:
  match repeatable:
    case False{}: Failure{"outcome_unknown", "The effect may already have happened; automatic repetition is forbidden", D.attempt_call(attempt), remaining, task}
    case True{}: chain(Hooks.queued(attempt, D.task_contract(task)), tool, D.attempt_call(attempt), remaining, task, world)

def found(found: Maybe<&2, D.Tool>, +attempt: D.Attempt, remaining: +List<D.Attempt>, task: D.Task, world: M.World()) -> Action:
  match found:
    case None{}:
      Failure{"unknown_tool", "The call does not name a tool in the task contract", D.attempt_call(attempt), remaining, task}
    case Some{+tool}:
      authorization(D.may_execute(D.recovery(D.tool_source(tool)), attempt), tool, attempt, remaining, task, world)

def tool(phase: D.Phase, +task: D.Task, world: M.World()) -> Action:
  match phase:
    case D.Ready{Con{+attempt, remaining}}:
      found(T.find_tool(T.task_tools(D.task_contract(task)), T.call_name(D.attempt_call(attempt))), attempt, remaining, task, world)
    case _: Rest{}

def grant_valid(available: Bool, reviewer: D.ApprovalReviewer, tool: D.Tool, operation: D.Operation(), task: D.Task) -> Action:
  match available:
    case True{}: Granted{reviewer, tool, operation, task}
    case False{}: GrantFailure{operation, task}

def grant_tool(found: Maybe<&2, D.Tool>, reviewer: D.ApprovalReviewer, +operation: D.Operation(), task: D.Task, world: M.World()) -> Action:
  match found:
    case None{}: GrantFailure{operation, task}
    case Some{+tool}: grant_valid(T.available(catalog(world), tool), reviewer, tool, operation, task)

def grant_stage(stage: D.OperationStage, +operation: D.Operation(), +task: D.Task, world: M.World()) -> Action:
  match stage:
    case D.ApprovalGranted{reviewer}:
      grant_tool(T.find_tool(T.task_tools(D.task_contract(task)), T.call_name(Ops.call(operation))), reviewer, operation, task, world)
    case _: Rest{}

def grant(found: Maybe<&2, D.Operation()>, task: D.Task, world: M.World()) -> Action:
  match found:
    case None{}: Rest{}
    case Some{+operation}: grant_stage(Ops.stage(operation), operation, task, world)

def grant_failure_value() -> J.Json:
  D.failure("tool_unavailable", "The approved tool route is no longer available; Bash was not started")

def resolve(work: D.Work, +task: D.Task, world: M.World()) -> Action:
  match work:
    case D.NoWork{}: Rest{}
    case D.BecomeIdle{}: Idle{task}
    case D.RequestNextModel{}: model(task, world)
    case D.RequestContextSummary{}: Summary{task, True{}}
    case D.RunNextTool{}: tool(D.task_phase(task), task, world)
    case D.RunGrantedOperation{}: grant(Ops.find_granted(D.task_operations(task)), task, world)

def meaning(action: Action, world: M.World()) -> M.Decision():
  match action world:
    case Rest{} _:
      C.Decision{world, D.success(J.Null{}), Nil{}}
    case Idle{task} _:
      C.Decision{Commands.replace(D.with_phase(D.Idle{}, task), world), D.success(J.Null{}), Nil{}}
    case Model{task} _: Reasoning.start(F.State(), F.Effect, task, world)
    case Summary{+task, +resume} C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +board}:
      C.Decision{C.Frame{D.State{T.replace(tasks, D.with_notified(False{}, D.with_phase(D.SummaryPending{ticket, resume}, task))), next_task, 1n+ticket, environment, limits, projects}, board},
        D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}]}),
        [Effects.RequestSummary{D.task_id(task), ticket, T.task_model(D.task_contract(task)), D.context_history(D.task_history(task)), D.task_context(task)}]}
    case External{+tool, +call, remaining, +task} C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +board}:
      C.Decision{C.Frame{D.State{T.replace(tasks, T.promote(Ops.started(ticket, call, remaining, task))), next_task, 1n+ticket, environment, limits, projects}, board},
        J.Null{}, [Effects.ExecuteTool{D.task_id(task), ticket, tool, call, D.task_context(task), Workspace.default_access(D.task_context(task))}]}
    case Review{+reviewer, +call, remaining, task} C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +board}:
      +prepared = T.promote(Ops.awaiting(ticket, reviewer, call, remaining, task))
      C.Decision{C.Frame{D.State{T.replace(tasks, prepared), next_task, 1n+ticket, environment, limits, projects}, board},
        J.Null{}, Approvals.review_effects(F.Effect, reviewer, prepared, ticket, call)}
    case Granted{reviewer, tool, +operation, +task} C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +board}:
      C.Decision{C.Frame{D.State{T.replace(tasks, Ops.elevated(ticket, reviewer, operation, task)), next_task, 1n+ticket, environment, limits, projects}, board},
        J.Null{}, [Effects.ExecuteTool{D.task_id(task), ticket, tool, Ops.call(operation), D.task_context(task), D.Unrestricted{}}]}
    case GrantFailure{operation, task} _:
      Results.begin(F.State(), F.Effect, operation, grant_failure_value(), True{}, task, world)
    case Hook{+plugin, pending, tool, +call, remaining, +task} C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +board}:
      C.Decision{C.Frame{D.State{T.replace(tasks, D.with_phase(D.HookPending{ticket, plugin, call, pending, remaining}, task)), next_task, 1n+ticket, environment, limits, projects}, board},
        J.Null{}, [Effects.CheckTool{D.task_id(task), ticket, plugin, tool, call}]}
    case Internal{operation, call, remaining, task} _:
      Protocol.invoked(operation, call, remaining, task, world)
    case Failure{code, reason, call, remaining, task} _:
      C.Decision{Commands.replace(T.complete_tool(call, remaining, D.failure(code, reason), True{}, task), world), D.success(J.Null{}), Nil{}}

def work(work: D.Work, +task: D.Task, +world: M.World()) -> M.Decision():
  meaning(resolve(work, task, world), world)

def world(decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

def combine(before: M.Decision(), after: M.Decision()) -> M.Decision():
  C.Decision{old, reply, effects} = before
  C.Decision{world, ignored, added} = after
  C.Decision{world, reply, List.append(&2, M.Effect(), effects, added)}

def defer(decision: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = decision
  C.Decision{world, reply, List.append(&2, M.Effect(), effects, [Effects.ContinueScheduling{}])}

# Independent finite-run specification. Exhaustion is an explicit continuation,
# not a termination/fairness claim about the remote model or operating system.
def schedule(fuel: Nat, candidate: Maybe<&2, D.Task>, +decision: M.Decision()) -> M.Decision():
  match fuel candidate:
    case 0n None{}: decision
    case 0n Some{task}: defer(decision)
    case 1n+p None{}: decision
    case 1n+p Some{+task}:
      +next = combine(decision, work(D.task_work(task), task, world(decision)))
      schedule(p, T.runnable(Commands.entries(world(next))), next)

def budget(world: M.World()) -> Nat:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, D.ExecutionLimits{steps, render, bytes}, projects}, +board} = world
  steps

def scheduled_prepared(+decision: M.Decision()) -> M.Decision():
  BoardScheduling.finish(schedule(budget(world(decision)), T.runnable(Commands.entries(world(decision))), decision))

def scheduled(enabled: Bool, +decision: M.Decision()) -> M.Decision():
  match enabled:
    case False{}: decision
    case True{}: scheduled_prepared(BoardScheduling.required_prepare(decision))

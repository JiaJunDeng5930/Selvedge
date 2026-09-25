import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./protocol.bend as Protocol
import ./tasks.bend as T
import ./json.bend as J
import ./schema.bend as Schema
import ./presentation.bend as View
import ./operations.bend as Ops

# The execution alphabet is the semantic boundary between task policy and the
# scheduler. Resolution owns authority, recovery and argument preconditions;
# meaning fixes the entire decision. Neither definition imports PROGRAM.
type Action is Data:
  Rest{}
  Idle{task: M.Task}
  Model{task: M.Task}
  Summary{task: M.Task, resume: Bool}
  External{tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task}
  Internal{operation: Protocol.Invocation, call: M.Call, remaining: +List<M.Attempt>, task: M.Task}
  Failure{code: String, reason: String, call: M.Call, remaining: +List<M.Attempt>, task: M.Task}

def catalog(world: M.World) -> +List<M.Tool>:
  M.World{tasks, next_task, next_ticket, M.Environment{tools, profiles, max_fork, max_descendants, project}, limits} = world
  tools

def render_budget(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, bytes}} = world
  render

def context(+task: M.Task) -> J.Json:
  J.Object{[J.Field{"model", View.model_json(T.task_model(M.task_contract(task)))},
    J.Field{"tools", J.Array{M.tools_json(T.task_tools(M.task_contract(task)))}},
    J.Field{"history", J.Array{T.messages_json(M.history_messages(M.context_history(M.task_history(task)), Nil{}))}}]}

def oversized(rendered: Result<&2, &2, String, String>) -> Bool:
  match rendered:
    case Fail{reason}: True{}
    case Done{text}: Nat.is_le(M.context_threshold_bytes(), J.utf8_length(text))

def model_with_operations(large: Bool, pending: Bool, task: M.Task) -> Action:
  match large pending:
    case True{} True{}: Idle{task}
    case True{} False{}: Summary{task, True{}}
    case False{} _: Model{task}

def model(+task: M.Task, world: M.World) -> Action:
  model_with_operations(M.compactable(M.context_history(M.task_history(task))) &&
    oversized(J.render(render_budget(world), J.One{context(task)})), M.operations_pending(M.task_operations(task)), task)

def arguments_valid(source: M.Source, schema: J.Json, +arguments: J.Json) -> Bool:
  match source:
    case M.Mcp{server, remote}: J.is_object(arguments)
    case M.Harness{M.Bash{}}:
      Schema.valid(schema, arguments) && M.nonempty(J.text(J.get(arguments, "command"))) &&
        Bool.not(String.contains(J.text(J.get(arguments, "command")), SCon{Chr{0}, SNil{}}))
    case M.Harness{other}: Schema.valid(schema, arguments)

def external_capacity(available: Bool, tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task) -> Action:
  match available:
    case True{}: External{tool, call, remaining, task}
    case False{}: Failure{"operation_limit", "This task has reached its in-flight operation limit; wait for results or cancel an operation", call, remaining, task}

def classified(execution: M.Execution, source: M.Source, tool: M.Tool, +call: M.Call,
  remaining: +List<M.Attempt>, +task: M.Task, world: M.World) -> Action:
  match execution source:
    case M.ExternalMutation{} _:
      external_capacity(Nat.is_lt(List.length(&2, M.Operation, M.task_operations(task)), M.operation_limit()), tool, call, remaining, task)
    case M.InternalOperation{} M.Harness{builtin}:
      Internal{Protocol.invocation(builtin, T.call_arguments(call), task, world), call, remaining, task}
    case _ _:
      Failure{"internal_error", "Invalid internal tool classification", call, remaining, task}

def validated(valid: Bool, +tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> Action:
  match valid:
    case False{}:
      Failure{"invalid_arguments", "Tool arguments do not satisfy its frozen schema", call, remaining, task}
    case True{}:
      classified(M.execution(M.tool_source(tool)), M.tool_source(tool), tool, call, remaining, task, world)

def available(present: Bool, +tool: M.Tool, +call: M.Call, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> Action:
  match present:
    case False{}:
      Failure{"tool_unavailable", "The task's frozen tool route is unavailable", call, remaining, task}
    case True{}:
      M.Tool{name, description, schema, source} = tool
      validated(arguments_valid(source, schema, T.call_arguments(call)), tool, call, remaining, task, world)

def permitted(repeatable: Bool, +tool: M.Tool, call: M.Call, remaining: +List<M.Attempt>, task: M.Task, +world: M.World) -> Action:
  match repeatable:
    case False{}:
      Failure{"outcome_unknown", "The effect may already have happened; automatic repetition is forbidden", call, remaining, task}
    case True{}:
      available(T.available(catalog(world), tool), tool, call, remaining, task, world)

def found(found: Maybe<&2, M.Tool>, +attempt: M.Attempt, remaining: +List<M.Attempt>, task: M.Task, world: M.World) -> Action:
  match found:
    case None{}:
      Failure{"unknown_tool", "The call does not name a tool in the task contract", M.attempt_call(attempt), remaining, task}
    case Some{+tool}:
      permitted(M.may_execute(M.recovery(M.tool_source(tool)), attempt), tool, M.attempt_call(attempt), remaining, task, world)

def tool(phase: M.Phase, +task: M.Task, world: M.World) -> Action:
  match phase:
    case M.Ready{Con{+attempt, remaining}}:
      found(T.find_tool(T.task_tools(M.task_contract(task)), T.call_name(M.attempt_call(attempt))), attempt, remaining, task, world)
    case _: Rest{}

def resolve(work: M.Work, +task: M.Task, world: M.World) -> Action:
  match work:
    case M.NoWork{}: Rest{}
    case M.BecomeIdle{}: Idle{task}
    case M.RequestNextModel{}: model(task, world)
    case M.RequestContextSummary{}: Summary{task, True{}}
    case M.RunNextTool{}: tool(M.task_phase(task), task, world)

def meaning(action: Action, world: M.World) -> M.Decision:
  match action world:
    case Rest{} _:
      M.Decision{world, M.success(J.Null{}), Nil{}}
    case Idle{task} _:
      M.Decision{Commands.replace(M.with_phase(M.Idle{}, task), world), M.success(J.Null{}), Nil{}}
    case Model{+task} M.World{tasks, next_task, +ticket, +environment, limits}:
      M.Environment{catalog, profiles, max_fork, max_descendants, project} = environment
      +tools = T.task_tools(M.task_contract(task))
      +allowed = T.callable(tools, catalog)
      +prepared = Ops.publish(task)
      M.Decision{M.World{T.replace(tasks, M.with_phase(M.ModelPending{ticket, allowed}, prepared)), next_task, 1n+ticket, environment, limits},
        J.Null{}, [M.RequestModel{M.task_id(task), ticket, T.task_model(M.task_contract(task)), M.context_history(M.task_history(prepared)), tools, allowed}]}
    case Summary{+task, +resume} M.World{tasks, next_task, +ticket, environment, limits}:
      M.Decision{M.World{T.replace(tasks, M.with_notified(False{}, M.with_phase(M.SummaryPending{ticket, resume}, task))), next_task, 1n+ticket, environment, limits},
        M.success(J.Object{[J.Field{"task_id", J.nat(M.task_id(task))}]}),
        [M.RequestSummary{M.task_id(task), ticket, T.task_model(M.task_contract(task)), M.context_history(M.task_history(task))}]}
    case External{+tool, +call, remaining, +task} M.World{tasks, next_task, +ticket, environment, limits}:
      M.Decision{M.World{T.replace(tasks, T.promote(Ops.started(ticket, call, remaining, task))), next_task, 1n+ticket, environment, limits},
        J.Null{}, [M.ExecuteTool{M.task_id(task), ticket, tool, call}]}
    case Internal{operation, call, remaining, task} _:
      Protocol.invoked(operation, call, remaining, task, world)
    case Failure{code, reason, call, remaining, task} _:
      M.Decision{Commands.replace(T.complete_tool(call, remaining, M.failure(code, reason), True{}, task), world), M.success(J.Null{}), Nil{}}

def work(work: M.Work, +task: M.Task, +world: M.World) -> M.Decision:
  meaning(resolve(work, task, world), world)

def world(decision: M.Decision) -> M.World:
  M.Decision{world, reply, effects} = decision
  world

def combine(before: M.Decision, after: M.Decision) -> M.Decision:
  M.Decision{old, reply, effects} = before
  M.Decision{world, ignored, added} = after
  M.Decision{world, reply, List.append(&2, M.Effect, effects, added)}

def defer(decision: M.Decision) -> M.Decision:
  M.Decision{world, reply, effects} = decision
  M.Decision{world, reply, List.append(&2, M.Effect, effects, [M.ContinueScheduling{}])}

# Independent finite-run specification. Exhaustion is an explicit continuation,
# not a termination/fairness claim about the remote model or operating system.
def schedule(fuel: Nat, candidate: Maybe<&2, M.Task>, +decision: M.Decision) -> M.Decision:
  match fuel candidate:
    case 0n None{}: decision
    case 0n Some{task}: defer(decision)
    case 1n+p None{}: decision
    case 1n+p Some{+task}:
      +next = combine(decision, work(M.task_work(task), task, world(decision)))
      schedule(p, T.runnable(Commands.entries(world(next))), next)

def budget(world: M.World) -> Nat:
  M.World{tasks, next_task, next_ticket, environment, M.ExecutionLimits{steps, render, bytes}} = world
  steps

def scheduled(enabled: Bool, +decision: M.Decision) -> M.Decision:
  match enabled:
    case False{}: decision
    case True{}: schedule(budget(world(decision)), T.runnable(Commands.entries(world(decision))), decision)

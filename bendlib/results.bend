import Base
import ../MODEL.bend as M
import ../HOOKS.bend as Hooks
import ../COMMANDS.bend as Commands
import ./json.bend as J
import ./operations.bend as Ops
import ./tasks.bend as T

# An execution receipt transfers a one-use execution right to a sequential
# result-processing right. Both are owned by the same operation, independently
# of task control. Each callback consumes a fresh committed ticket.
def finish_status(status: M.Status, task: M.Task) -> M.Task:
  match status:
    case M.Archived{}: M.with_phase(M.Idle{}, task)
    case _: task

def finished(operation: M.Operation(), value: J.Json, error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  M.Decision{Commands.replace(finish_status(M.task_status(task), T.complete_operation(operation, value, error, task)), world),
    M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}

def failed(code: String, reason: String, +plugin: M.PluginRef, +outcome: M.AfterOutcome,
  +operation: M.Operation(), +task: M.Task, world: M.World) -> M.Decision:
  finished(operation, M.failure(code, reason), True{},
    M.append_message(M.AfterRecord{M.task_id(task), Ops.ticket(operation), plugin, outcome}, task), world)

def waiting(available: Bool, +plugin: M.PluginRef, +pending: +List<M.PluginRef>, +operation: M.Operation(),
  +value: J.Json, +error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  match available world:
    case False{} _:
      failed("after_hook_unavailable", "The frozen result-processing plugin revision is unavailable; the tool has already completed",
        plugin, M.AfterFailure{"The frozen result-processing plugin revision is unavailable"}, operation, task, world)
    case True{} M.World{tasks, next_task, +ticket, environment, limits, projects}:
      updated = M.with_operations(Ops.replace(M.task_operations(task),
        Ops.with_stage(M.ResultPending{ticket, plugin, pending, value, error}, operation)), task)
      M.Decision{M.World{T.replace(tasks, updated), next_task, 1n+ticket, environment, limits, projects},
        M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}),
        [M.CheckResult{M.task_id(task), ticket, Ops.ticket(operation), plugin, Ops.call(operation), value, error}]}

def advance(chain: +List<M.PluginRef>, operation: M.Operation(), value: J.Json, error: Bool, task: M.Task, +world: M.World) -> M.Decision:
  match chain:
    case Nil{}: finished(operation, value, error, task, world)
    case Con{+plugin, pending}:
      waiting(Hooks.after_available(Hooks.live(world), plugin), plugin, pending, operation, value, error, task, world)

def received(chain: +List<M.PluginRef>, +operation: M.Operation(), +value: J.Json, +error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  match chain:
    case Nil{}: finished(operation, value, error, task, world)
    case Con{plugin, pending}:
      advance(plugin <> pending, operation, value, error,
        M.append_message(M.ToolReceipt{M.task_id(task), Ops.ticket(operation), Ops.call(operation), value, error}, task), world)

def begin(operation: M.Operation(), value: J.Json, error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  received(Hooks.after(Hooks.plugins(M.task_contract(task))), operation, value, error, task, world)

def complete_action(action: Hooks.ResultAction, pending: +List<M.PluginRef>, operation: M.Operation(), task: M.Task, world: M.World) -> M.Decision:
  match action:
    case Hooks.ResultValue{value, error}: advance(pending, operation, value, error, task, world)
    case Hooks.ResultError{code, reason}: finished(operation, M.failure(code, reason), True{}, task, world)

def completed(+outcome: M.AfterOutcome, plugin: M.PluginRef, pending: +List<M.PluginRef>, +operation: M.Operation(),
  value: J.Json, error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  complete_action(Hooks.result_action(outcome, value, error), pending, operation,
    M.append_message(M.AfterRecord{M.task_id(task), Ops.ticket(operation), plugin, outcome}, task), world)

def complete(stage: M.OperationStage, outcome: M.AfterOutcome, operation: M.Operation(), task: M.Task, world: M.World) -> M.Decision:
  match stage:
    case M.Executing{}: M.Decision{world, M.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case M.ResultPending{ticket, plugin, pending, value, error}:
      completed(outcome, plugin, pending, operation, value, error, task, world)

# Internal invocations acquire a result right only when a chain exists. Public
# commands use their own authority and do not enter model-tool hook protocols.
def internal_chain(chain: +List<M.PluginRef>, +call: M.Call, remaining: +List<M.Attempt>, value: J.Json,
  error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  match chain world:
    case Nil{} _:
      M.Decision{Commands.replace(finish_status(M.task_status(task), T.complete_tool(call, remaining, value, error, task)), world), J.Null{}, Nil{}}
    case Con{plugin, pending} M.World{tasks, next_task, +ticket, environment, limits, projects}:
      +prepared = finish_status(M.task_status(task), Ops.started(ticket, call, remaining, task))
      received(plugin <> pending, (ticket, M.OperationBody{call, False{}, M.Executing{}}), value, error, prepared,
        M.World{tasks, next_task, 1n+ticket, environment, limits, projects})

def internal(call: M.Call, remaining: +List<M.Attempt>, value: J.Json, error: Bool, +task: M.Task, world: M.World) -> M.Decision:
  internal_chain(Hooks.after(Hooks.plugins(M.task_contract(task))), call, remaining, value, error, task, world)

def attached(result: M.Decision, reply: J.Json, effects: +List<M.Effect>) -> M.Decision:
  M.Decision{world, ignored, hooks} = result
  M.Decision{world, reply, List.append(&2, M.Effect, effects, hooks)}

import Base
import ./effects.bend as Effects
import ./component.bend as C
import ./domain.bend as D
import ../HOOKS.bend as Hooks
import ./json.bend as J
import ./operations.bend as Ops
import ./tasks.bend as T

# An execution receipt transfers a one-use execution right to a sequential
# result-processing right. Both are owned by the same operation, independently
# of task control. Each callback consumes a fresh committed ticket.
def finish_status(status: D.Status, task: D.Task) -> D.Task:
  match status:
    case D.Archived{}: D.with_phase(D.Idle{}, task)
    case _: task

def finished(-StateRest: Data, -EffectRest: Data, operation: D.Operation(), value: J.Json, error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Decision{T.update_world(StateRest, finish_status(D.task_status(task), T.complete_operation(operation, value, error, task)), world),
    D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}

def failed(-StateRest: Data, -EffectRest: Data, code: String, reason: String, +plugin: D.PluginRef, +outcome: D.AfterOutcome,
  +operation: D.Operation(), +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  finished(StateRest, EffectRest, operation, D.failure(code, reason), True{},
    D.append_message(D.AfterRecord{D.task_id(task), Ops.ticket(operation), plugin, outcome}, task), world)

def waiting(-StateRest: Data, -EffectRest: Data, available: Bool, +plugin: D.PluginRef, +pending: +List<D.PluginRef>, +operation: D.Operation(),
  +value: J.Json, +error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match available world:
    case False{} _:
      failed(StateRest, EffectRest, "after_hook_unavailable", "The frozen result-processing plugin revision is unavailable; the tool has already completed",
        plugin, D.AfterFailure{"The frozen result-processing plugin revision is unavailable"}, operation, task, world)
    case True{} C.Frame{+task_state, +rest}:
      tasks = D.state_tasks(task_state)
      +ticket = D.state_next_ticket(task_state)
      updated = D.with_operations(Ops.replace(D.task_operations(task),
        Ops.with_stage(D.ResultPending{ticket, plugin, pending, value, error}, operation)), task)
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, updated), task_state)), rest},
        D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}),
        [Effects.CheckResult{D.task_id(task), ticket, Ops.ticket(operation), plugin, Ops.call(operation), value, error}]}

def advance(-StateRest: Data, -EffectRest: Data, chain: +List<D.PluginRef>, operation: D.Operation(), value: J.Json, error: Bool, task: D.Task, +world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match chain:
    case Nil{}: finished(StateRest, EffectRest, operation, value, error, task, world)
    case Con{+plugin, pending}:
      waiting(StateRest, EffectRest, Hooks.after_available(Hooks.live(StateRest, world), plugin), plugin, pending, operation, value, error, task, world)

def received(-StateRest: Data, -EffectRest: Data, chain: +List<D.PluginRef>, +operation: D.Operation(), +value: J.Json, +error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match chain:
    case Nil{}: finished(StateRest, EffectRest, operation, value, error, task, world)
    case Con{plugin, pending}:
      advance(StateRest, EffectRest, plugin <> pending, operation, value, error,
        D.append_message(D.ToolReceipt{D.task_id(task), Ops.ticket(operation), Ops.call(operation), value, error}, task), world)

def begin(-StateRest: Data, -EffectRest: Data, operation: D.Operation(), value: J.Json, error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  received(StateRest, EffectRest, Hooks.after(Hooks.plugins(D.task_contract(task))), operation, value, error, task, world)

def complete_action(-StateRest: Data, -EffectRest: Data, action: Hooks.ResultAction, pending: +List<D.PluginRef>, operation: D.Operation(), task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match action:
    case Hooks.ResultValue{value, error}: advance(StateRest, EffectRest, pending, operation, value, error, task, world)
    case Hooks.ResultError{code, reason}: finished(StateRest, EffectRest, operation, D.failure(code, reason), True{}, task, world)

def completed(-StateRest: Data, -EffectRest: Data, +outcome: D.AfterOutcome, plugin: D.PluginRef, pending: +List<D.PluginRef>, +operation: D.Operation(),
  value: J.Json, error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  complete_action(StateRest, EffectRest, Hooks.result_action(outcome, value, error), pending, operation,
    D.append_message(D.AfterRecord{D.task_id(task), Ops.ticket(operation), plugin, outcome}, task), world)

def complete(-StateRest: Data, -EffectRest: Data, stage: D.OperationStage, outcome: D.AfterOutcome, operation: D.Operation(), task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match stage:
    case D.ResultPending{ticket, plugin, pending, value, error}:
      completed(StateRest, EffectRest, outcome, plugin, pending, operation, value, error, task, world)
    case _: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}

# Internal invocations acquire a result right only when a chain exists. Public
# commands use their own authority and do not enter model-tool hook protocols.
def internal_chain(-StateRest: Data, -EffectRest: Data, chain: +List<D.PluginRef>, +call: D.Call, remaining: +List<D.Attempt>, value: J.Json,
  error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match chain world:
    case Nil{} _:
      C.Decision{T.update_world(StateRest, finish_status(D.task_status(task), T.complete_tool(call, remaining, value, error, task)), world), J.Null{}, Nil{}}
    case Con{plugin, pending} C.Frame{+task_state, +rest}:
      +ticket = D.state_next_ticket(task_state)
      +prepared = finish_status(D.task_status(task), Ops.started(ticket, call, remaining, task))
      received(StateRest, EffectRest, plugin <> pending, (ticket, D.OperationBody{call, False{}, D.Executing{}}), value, error, prepared,
        C.Frame{D.with_state_next_ticket(1n+ticket, task_state), rest})

def internal(-StateRest: Data, -EffectRest: Data, call: D.Call, remaining: +List<D.Attempt>, value: J.Json, error: Bool, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  internal_chain(StateRest, EffectRest, Hooks.after(Hooks.plugins(D.task_contract(task))), call, remaining, value, error, task, world)

def attached(-StateRest: Data, -EffectRest: Data, result: C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>, reply: J.Json, effects: +List<Effects.Effect<EffectRest>>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Decision{world, ignored, hooks} = result
  C.Decision{world, reply, List.append(&2, Effects.Effect<EffectRest>, effects, hooks)}

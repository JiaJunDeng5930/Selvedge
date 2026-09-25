import Base
import ../MODEL.bend as M
import ./json.bend as J
import ./stdlib.bend as Std

# Pending operation rights are distinct from the task's model/control phase.
# A right can be announced once and consumed once. Late events find no right.
def ticket(operation: M.Operation) -> Nat:
  M.Operation{ticket, call, announced} = operation
  ticket

def call(operation: M.Operation) -> M.Call:
  M.Operation{ticket, call, announced} = operation
  call

def announced(operation: M.Operation) -> Bool:
  M.Operation{ticket, call, announced} = operation
  announced

def chosen(same: Bool, operation: M.Operation, rest: Maybe<&2, M.Operation>) -> Maybe<&2, M.Operation>:
  match same:
    case True{}: Some{operation}
    case False{}: rest

def find(operations: +List<M.Operation>, +id: Nat) -> Maybe<&2, M.Operation>:
  match operations:
    case Nil{}: None{}
    case Con{+operation, rest}:
      chosen(Nat.is_eq(ticket(operation), id), operation, find(rest, id))

def retained(same: Bool, operation: M.Operation, rest: +List<M.Operation>) -> +List<M.Operation>:
  match same:
    case True{}: rest
    case False{}: operation <> rest

def remove(operations: +List<M.Operation>, +id: Nat) -> +List<M.Operation>:
  match operations:
    case Nil{}: Nil{}
    case Con{+operation, rest}:
      retained(Nat.is_eq(ticket(operation), id), operation, remove(rest, id))

def announce(operation: M.Operation) -> M.Operation:
  M.Operation{ticket, call, previous} = operation
  M.Operation{ticket, call, True{}}

def running(+operation: M.Operation) -> J.Json:
  M.Operation{ticket, M.Call{id, name, arguments}, announced} = operation
  J.Object{[J.Field{"status", J.Text{"running"}}, J.Field{"operation_id", J.nat(ticket)},
    J.Field{"tool", J.Text{name}}, J.Field{"message", J.Text{
      "This operation is still running, not completed. Its result will arrive as an asynchronous operation result. Continue independent work, or end your turn to wait; do not poll or sleep just to wait."}}]}

def announce_step(history: M.History, +operation: M.Operation) -> M.History:
  M.Operation{ticket, M.Call{id, name, arguments}, announced} = operation
  match announced:
    case True{}: history
    case False{}: M.HistoryNode{history, M.FunctionOutput{id, running(operation), False{}}}

def announced_history(operations: +List<M.Operation>, history: M.History) -> M.History:
  List.foldl(~&2, ~M.Operation, ~M.History, ~(history => operation => announce_step(history, operation)), operations, history)

# Running statuses enter history only when an actual model request needs them.
# Fast completions remain ordinary function results, without a gratuitous turn.
def publish(+task: M.Task) -> M.Task:
  M.with_notified(False{}, M.with_operations(Std.map(~M.Operation, ~M.Operation, ~announce, M.task_operations(task)),
    M.with_history(announced_history(M.task_operations(task), M.task_history(task)), task)))

def started(ticket: Nat, call: M.Call, remaining: +List<M.Attempt>, +task: M.Task) -> M.Task:
  M.with_operations(List.append(&2, M.Operation, M.task_operations(task), [M.Operation{ticket, call, False{}}]),
    M.with_phase(M.Ready{remaining}, task))

def result(operation: M.Operation, value: J.Json, error: Bool) -> M.Message:
  M.Operation{ticket, M.Call{id, name, arguments}, announced} = operation
  match announced:
    case False{}: M.FunctionOutput{id, value, error}
    case True{}: M.OperationResult{ticket, id, name, value, error}

def completed(+operation: M.Operation, value: J.Json, error: Bool, +task: M.Task) -> M.Task:
  M.notify(M.with_operations(remove(M.task_operations(task), ticket(operation)),
    M.append_message(result(operation, value, error), task)))

def cancelled(operation: M.Operation, task: M.Task) -> M.Task:
  completed(operation, M.failure("cancelled",
    "Cancellation requested. The operation may already have made changes; those changes are not undone."), True{}, task)

# Fold an abandonment reason through the exact live rights. This is not a retry
# queue: it records unknown outcomes and removes execution authority.
type Closure is Data:
  Closure{history: M.History, code: String, reason: String}

def close_step(state: Closure, operation: M.Operation) -> Closure:
  Closure{history, +code, +reason} = state
  Closure{M.HistoryNode{history, result(operation, M.failure(code, reason), True{})}, code, reason}

def closed(state: Closure) -> M.History:
  Closure{history, code, reason} = state
  history

def close(operations: +List<M.Operation>, history: M.History, code: String, reason: String) -> M.History:
  closed(List.foldl(~&2, ~M.Operation, ~Closure, ~close_step, operations, Closure{history, code, reason}))

def abandoned(+task: M.Task) -> M.Task:
  M.with_operations(Nil{}, M.with_history(close(M.task_operations(task), M.task_history(task),
    "outcome_unknown", "The external operation may already have run. Its side effects cannot be inferred or undone; it will not be repeated automatically."), task))

def inherited(+parent: M.Task) -> M.History:
  close(M.task_operations(parent), M.task_history(parent), "inherited_operation_not_owned",
    "This operation belongs to parent task " ++ Nat.show(M.task_id(parent)) ++
    "; its execution was not copied. Read that task for its eventual result.")

def summary(operation: M.Operation) -> J.Json:
  M.Operation{ticket, M.Call{id, name, arguments}, announced} = operation
  J.Object{[J.Field{"operation_id", J.nat(ticket)}, J.Field{"call_id", J.Text{id}},
    J.Field{"tool", J.Text{name}}, J.Field{"status", J.Text{"running"}}, J.Field{"announced", J.Boolean{announced}}]}

def summaries(operations: +List<M.Operation>) -> +List<J.Json>:
  Std.map(~M.Operation, ~J.Json, ~summary, operations)

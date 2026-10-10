import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/association-map.bend as Finite

# Pending operation rights are distinct from the task's model/control phase.
# A right can be announced once and consumed once. Late events find no right.
def ticket(operation: D.Operation()) -> Nat:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  ticket

def call(operation: D.Operation()) -> D.Call:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  call

def announced(operation: D.Operation()) -> Bool:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  announced

def stage(operation: D.Operation()) -> D.OperationStage:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  stage

def executing(stage: D.OperationStage) -> Bool:
  match stage:
    case D.Executing{}: True{}
    case D.ElevatedExecuting{ticket, reviewer}: True{}
    case _: False{}

def callback(operation: D.Operation()) -> Nat:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  match stage:
    case D.Executing{}: ticket
    case D.ElevatedExecuting{callback, reviewer}: callback
    case D.ApprovalPending{reviewer}: ticket
    case D.ApprovalGranted{reviewer}: ticket
    case D.ResultPending{callback, plugin, pending, value, error}: callback

def with_stage(stage: D.OperationStage, operation: D.Operation()) -> D.Operation():
  (ticket, D.OperationBody{call, announced, previous}) = operation
  (ticket, D.OperationBody{call, announced, stage})

def replaced(same: Bool, operation: D.Operation(), previous: D.Operation()) -> D.Operation():
  match same:
    case True{}: operation
    case False{}: previous

def replace(operations: +List<D.Operation()>, +operation: D.Operation()) -> +List<D.Operation()>:
  match operations:
    case Nil{}: Nil{}
    case Con{+previous, rest}:
      replaced(Nat.is_eq(ticket(previous), ticket(operation)), operation, previous) <> replace(rest, operation)

def binding(found: Maybe<&2, D.OperationBody>, id: Nat) -> Maybe<&2, D.Operation()>:
  match found:
    case None{}: None{}
    case Some{body}: Some{(id, body)}

def find(operations: +List<D.Operation()>, +id: Nat) -> Maybe<&2, D.Operation()>:
  binding(Finite.find(~D.OperationBody, operations, id), id)

def selected(present: Bool, operation: D.Operation(), rest: Maybe<&2, D.Operation()>) -> Maybe<&2, D.Operation()>:
  match present:
    case True{}: Some{operation}
    case False{}: rest

def find_callback(operations: +List<D.Operation()>, +id: Nat) -> Maybe<&2, D.Operation()>:
  match operations:
    case Nil{}: None{}
    case Con{+operation, rest}: selected(Nat.is_eq(callback(operation), id), operation, find_callback(rest, id))

def granted(stage: D.OperationStage) -> Bool:
  match stage:
    case D.ApprovalGranted{reviewer}: True{}
    case _: False{}

def find_granted(operations: +List<D.Operation()>) -> Maybe<&2, D.Operation()>:
  match operations:
    case Nil{}: None{}
    case Con{+operation, rest}: selected(granted(stage(operation)), operation, find_granted(rest))

def remove(operations: +List<D.Operation()>, id: Nat) -> +List<D.Operation()>:
  Finite.remove(~D.OperationBody, operations, id)

def announce(operation: D.Operation()) -> D.Operation():
  (ticket, D.OperationBody{call, previous, stage}) = operation
  (ticket, D.OperationBody{call, True{}, stage})

def stage_status(stage: D.OperationStage) -> String:
  match stage:
    case D.ApprovalPending{reviewer}: "awaiting_approval"
    case D.ApprovalGranted{reviewer}: "approved_waiting_to_run"
    case _: "running"

def stage_notice(stage: D.OperationStage) -> String:
  match stage:
    case D.ApprovalPending{D.HumanReviewer{}}:
      "Bash has not started. This exact command is waiting for the user's one-operation approval in the UI. Continue independent work or end the turn; do not poll or try to approve it yourself."
    case D.ApprovalPending{D.ModelReviewer{profile}}:
      "Bash has not started. An independent, tool-free reviewer is assessing this exact command. The result arrives automatically; do not poll or create another task to review it."
    case D.ApprovalGranted{reviewer}:
      "A one-operation grant is committed, but Bash has not started. It will run only when the task is active."
    case _:
      "This operation is still running, not completed. Its result will arrive as an asynchronous operation result. Continue independent work, or end your turn to wait; do not poll or sleep just to wait."

def running(+operation: D.Operation()) -> J.Json:
  (ticket, D.OperationBody{D.Call{id, name, arguments}, announced, +stage}) = operation
  J.Object{[J.Field{"status", J.Text{stage_status(stage)}}, J.Field{"operation_id", J.nat(ticket)},
    J.Field{"tool", J.Text{name}}, J.Field{"message", J.Text{stage_notice(stage)}}]}

def announce_step(history: D.History, +operation: D.Operation()) -> D.History:
  (ticket, D.OperationBody{D.Call{id, name, arguments}, announced, stage}) = operation
  match announced:
    case True{}: history
    case False{}: D.HistoryNode{history, D.FunctionOutput{id, running(operation), False{}}}

def announced_history(operations: +List<D.Operation()>, history: D.History) -> D.History:
  List.foldl(~&2, ~D.Operation(), ~D.History, ~(history => operation => announce_step(history, operation)), operations, history)

# Running statuses enter history only when an actual model request needs them.
# Fast completions remain ordinary function results, without a gratuitous turn.

def publish(+task: D.Task) -> D.Task:
  D.with_notified(False{}, D.with_operations(Std.map(~D.Operation(), ~D.Operation(), ~announce, D.task_operations(task)),
    D.with_history(announced_history(D.task_operations(task), D.task_history(task)), task)))

def started(ticket: Nat, call: D.Call, remaining: +List<D.Attempt>, +task: D.Task) -> D.Task:
  D.with_operations(List.append(&2, D.Operation(), D.task_operations(task), [(ticket, D.OperationBody{call, False{}, D.Executing{}})]),
    D.with_phase(D.Ready{remaining}, task))

def awaiting(ticket: Nat, reviewer: D.ApprovalReviewer, call: D.Call, remaining: +List<D.Attempt>, +task: D.Task) -> D.Task:
  D.with_operations(List.append(&2, D.Operation(), D.task_operations(task), [(ticket, D.OperationBody{call, False{}, D.ApprovalPending{reviewer}})]),
    D.with_phase(D.Ready{remaining}, task))

def permitted(reviewer: D.ApprovalReviewer, operation: D.Operation(), +task: D.Task) -> D.Task:
  D.with_operations(replace(D.task_operations(task), with_stage(D.ApprovalGranted{reviewer}, operation)), task)

def elevated(ticket: Nat, reviewer: D.ApprovalReviewer, operation: D.Operation(), +task: D.Task) -> D.Task:
  D.with_operations(replace(D.task_operations(task), with_stage(D.ElevatedExecuting{ticket, reviewer}, operation)), task)

def result(operation: D.Operation(), value: J.Json, error: Bool) -> D.Message:
  (ticket, D.OperationBody{D.Call{id, name, arguments}, announced, stage}) = operation
  match announced:
    case False{}: D.FunctionOutput{id, value, error}
    case True{}: D.OperationResult{ticket, id, name, value, error}

def completed(+operation: D.Operation(), value: J.Json, error: Bool, +task: D.Task) -> D.Task:
  D.notify(D.with_operations(remove(D.task_operations(task), ticket(operation)),
    D.append_message(result(operation, value, error), task)))

def cancelled(operation: D.Operation(), task: D.Task) -> D.Task:
  completed(operation, D.failure("cancelled",
    "Cancellation requested. The operation may already have made changes; those changes are not undone."), True{}, task)

# Fold an abandonment reason through the exact live rights. This is not a retry
# queue: it records unknown outcomes and removes execution authority.

type Closure is Data:
  Closure{history: D.History, code: String, reason: String}

def interrupted_result(+operation: D.Operation(), code: String, reason: String) -> D.Message:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  match stage:
    case D.Executing{}: result(operation, D.failure(code, reason), True{})
    case D.ElevatedExecuting{ticket, reviewer}: result(operation, D.failure(code, reason), True{})
    case D.ApprovalPending{reviewer}: result(operation, D.failure("approval_interrupted",
      "The approval request was interrupted before Bash execution. No command was started. Submit a new request if the operation is still needed."), True{})
    case D.ApprovalGranted{reviewer}: result(operation, D.failure("approval_expired",
      "The one-operation grant expired before Bash execution. No command was started. A fresh request and approval are required."), True{})
    case D.ResultPending{ticket, plugin, pending, value, error}:
      result(operation, D.failure("after_hook_interrupted",
        "Result processing was interrupted. The execution receipt remains in history; neither the tool nor its callback is repeated. " ++ reason), True{})

def close_step(state: Closure, operation: D.Operation()) -> Closure:
  Closure{history, +code, +reason} = state
  Closure{D.HistoryNode{history, interrupted_result(operation, code, reason)}, code, reason}

def closed(state: Closure) -> D.History:
  Closure{history, code, reason} = state
  history

def close(operations: +List<D.Operation()>, history: D.History, code: String, reason: String) -> D.History:
  closed(List.foldl(~&2, ~D.Operation(), ~Closure, ~close_step, operations, Closure{history, code, reason}))

def abandoned(+task: D.Task) -> D.Task:
  D.with_operations(Nil{}, D.with_history(close(D.task_operations(task), D.task_history(task),
    "outcome_unknown", "The external operation may already have run. Its side effects cannot be inferred or undone; it will not be repeated automatically."), task))

def inherited(+parent: D.Task) -> D.History:
  close(D.task_operations(parent), D.task_history(parent), "inherited_operation_not_owned",
    "This operation belongs to parent task " ++ Nat.show(D.task_id(parent)) ++
    "; its execution was not copied. Read that task for its eventual result.")

def review_fields(stage: D.OperationStage, arguments: J.Json) -> +List<J.Field>:
  match stage:
    case D.ApprovalPending{reviewer}:
      [J.Field{"reviewer", D.approval_reviewer_json(reviewer)}, J.Field{"arguments", arguments}]
    case D.ApprovalGranted{reviewer}:
      [J.Field{"reviewer", D.approval_reviewer_json(reviewer)}, J.Field{"arguments", arguments}]
    case D.ElevatedExecuting{ticket, reviewer}:
      [J.Field{"execution_ticket", J.nat(ticket)}, J.Field{"reviewer", D.approval_reviewer_json(reviewer)}]
    case _: Nil{}

def summary(operation: D.Operation()) -> J.Json:
  (ticket, D.OperationBody{D.Call{id, name, arguments}, announced, +stage}) = operation
  J.Object{List.append(&2, J.Field, [J.Field{"operation_id", J.nat(ticket)}, J.Field{"call_id", J.Text{id}},
    J.Field{"tool", J.Text{name}}, J.Field{"status", J.Text{stage_status(stage)}}, J.Field{"announced", J.Boolean{announced}}],
    review_fields(stage, arguments))}

def summaries(operations: +List<D.Operation()>) -> +List<J.Json>:
  Std.map(~D.Operation(), ~J.Json, ~summary, operations)

import Base
import ../MODEL.bend as M
import ./json.bend as J
import ./stdlib.bend as Std
import ./association-map.bend as Finite

# Pending operation rights are distinct from the task's model/control phase.
# A right can be announced once and consumed once. Late events find no right.
def ticket(operation: M.Operation()) -> Nat:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  ticket

def call(operation: M.Operation()) -> M.Call:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  call

def announced(operation: M.Operation()) -> Bool:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  announced

def stage(operation: M.Operation()) -> M.OperationStage:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  stage

def executing(stage: M.OperationStage) -> Bool:
  match stage:
    case M.Executing{}: True{}
    case M.ElevatedExecuting{ticket, reviewer}: True{}
    case _: False{}

def callback(operation: M.Operation()) -> Nat:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  match stage:
    case M.Executing{}: ticket
    case M.ElevatedExecuting{callback, reviewer}: callback
    case M.ApprovalPending{reviewer}: ticket
    case M.ApprovalGranted{reviewer}: ticket
    case M.ResultPending{callback, plugin, pending, value, error}: callback

def with_stage(stage: M.OperationStage, operation: M.Operation()) -> M.Operation():
  (ticket, M.OperationBody{call, announced, previous}) = operation
  (ticket, M.OperationBody{call, announced, stage})

def replaced(same: Bool, operation: M.Operation(), previous: M.Operation()) -> M.Operation():
  match same:
    case True{}: operation
    case False{}: previous

def replace(operations: +List<M.Operation()>, +operation: M.Operation()) -> +List<M.Operation()>:
  match operations:
    case Nil{}: Nil{}
    case Con{+previous, rest}:
      replaced(Nat.is_eq(ticket(previous), ticket(operation)), operation, previous) <> replace(rest, operation)

def binding(found: Maybe<&2, M.OperationBody>, id: Nat) -> Maybe<&2, M.Operation()>:
  match found:
    case None{}: None{}
    case Some{body}: Some{(id, body)}

def find(operations: +List<M.Operation()>, +id: Nat) -> Maybe<&2, M.Operation()>:
  binding(Finite.find(~M.OperationBody, operations, id), id)

def selected(present: Bool, operation: M.Operation(), rest: Maybe<&2, M.Operation()>) -> Maybe<&2, M.Operation()>:
  match present:
    case True{}: Some{operation}
    case False{}: rest

def find_callback(operations: +List<M.Operation()>, +id: Nat) -> Maybe<&2, M.Operation()>:
  match operations:
    case Nil{}: None{}
    case Con{+operation, rest}: selected(Nat.is_eq(callback(operation), id), operation, find_callback(rest, id))

def granted(stage: M.OperationStage) -> Bool:
  match stage:
    case M.ApprovalGranted{reviewer}: True{}
    case _: False{}

def find_granted(operations: +List<M.Operation()>) -> Maybe<&2, M.Operation()>:
  match operations:
    case Nil{}: None{}
    case Con{+operation, rest}: selected(granted(stage(operation)), operation, find_granted(rest))

def remove(operations: +List<M.Operation()>, id: Nat) -> +List<M.Operation()>:
  Finite.remove(~M.OperationBody, operations, id)

def announce(operation: M.Operation()) -> M.Operation():
  (ticket, M.OperationBody{call, previous, stage}) = operation
  (ticket, M.OperationBody{call, True{}, stage})

def stage_status(stage: M.OperationStage) -> String:
  match stage:
    case M.ApprovalPending{reviewer}: "awaiting_approval"
    case M.ApprovalGranted{reviewer}: "approved_waiting_to_run"
    case _: "running"

def stage_notice(stage: M.OperationStage) -> String:
  match stage:
    case M.ApprovalPending{M.HumanReviewer{}}:
      "Bash has not started. This exact command is waiting for the user's one-operation approval in the UI. Continue independent work or end the turn; do not poll or try to approve it yourself."
    case M.ApprovalPending{M.ModelReviewer{profile}}:
      "Bash has not started. An independent, tool-free reviewer is assessing this exact command. The result arrives automatically; do not poll or create another task to review it."
    case M.ApprovalGranted{reviewer}:
      "A one-operation grant is committed, but Bash has not started. It will run only when the task is active."
    case _:
      "This operation is still running, not completed. Its result will arrive as an asynchronous operation result. Continue independent work, or end your turn to wait; do not poll or sleep just to wait."

def running(+operation: M.Operation()) -> J.Json:
  (ticket, M.OperationBody{M.Call{id, name, arguments}, announced, +stage}) = operation
  J.Object{[J.Field{"status", J.Text{stage_status(stage)}}, J.Field{"operation_id", J.nat(ticket)},
    J.Field{"tool", J.Text{name}}, J.Field{"message", J.Text{stage_notice(stage)}}]}

def announce_step(history: M.History, +operation: M.Operation()) -> M.History:
  (ticket, M.OperationBody{M.Call{id, name, arguments}, announced, stage}) = operation
  match announced:
    case True{}: history
    case False{}: M.HistoryNode{history, M.FunctionOutput{id, running(operation), False{}}}

def announced_history(operations: +List<M.Operation()>, history: M.History) -> M.History:
  List.foldl(~&2, ~M.Operation(), ~M.History, ~(history => operation => announce_step(history, operation)), operations, history)

# Running statuses enter history only when an actual model request needs them.
# Fast completions remain ordinary function results, without a gratuitous turn.
def publish(+task: M.Task) -> M.Task:
  M.with_notified(False{}, M.with_operations(Std.map(~M.Operation(), ~M.Operation(), ~announce, M.task_operations(task)),
    M.with_history(announced_history(M.task_operations(task), M.task_history(task)), task)))

def started(ticket: Nat, call: M.Call, remaining: +List<M.Attempt>, +task: M.Task) -> M.Task:
  M.with_operations(List.append(&2, M.Operation(), M.task_operations(task), [(ticket, M.OperationBody{call, False{}, M.Executing{}})]),
    M.with_phase(M.Ready{remaining}, task))

def awaiting(ticket: Nat, reviewer: M.ApprovalReviewer, call: M.Call, remaining: +List<M.Attempt>, +task: M.Task) -> M.Task:
  M.with_operations(List.append(&2, M.Operation(), M.task_operations(task), [(ticket, M.OperationBody{call, False{}, M.ApprovalPending{reviewer}})]),
    M.with_phase(M.Ready{remaining}, task))

def permitted(reviewer: M.ApprovalReviewer, operation: M.Operation(), +task: M.Task) -> M.Task:
  M.with_operations(replace(M.task_operations(task), with_stage(M.ApprovalGranted{reviewer}, operation)), task)

def elevated(ticket: Nat, reviewer: M.ApprovalReviewer, operation: M.Operation(), +task: M.Task) -> M.Task:
  M.with_operations(replace(M.task_operations(task), with_stage(M.ElevatedExecuting{ticket, reviewer}, operation)), task)

def result(operation: M.Operation(), value: J.Json, error: Bool) -> M.Message:
  (ticket, M.OperationBody{M.Call{id, name, arguments}, announced, stage}) = operation
  match announced:
    case False{}: M.FunctionOutput{id, value, error}
    case True{}: M.OperationResult{ticket, id, name, value, error}

def completed(+operation: M.Operation(), value: J.Json, error: Bool, +task: M.Task) -> M.Task:
  M.notify(M.with_operations(remove(M.task_operations(task), ticket(operation)),
    M.append_message(result(operation, value, error), task)))

def cancelled(operation: M.Operation(), task: M.Task) -> M.Task:
  completed(operation, M.failure("cancelled",
    "Cancellation requested. The operation may already have made changes; those changes are not undone."), True{}, task)

# Fold an abandonment reason through the exact live rights. This is not a retry
# queue: it records unknown outcomes and removes execution authority.
type Closure is Data:
  Closure{history: M.History, code: String, reason: String}

def interrupted_result(+operation: M.Operation(), code: String, reason: String) -> M.Message:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  match stage:
    case M.Executing{}: result(operation, M.failure(code, reason), True{})
    case M.ElevatedExecuting{ticket, reviewer}: result(operation, M.failure(code, reason), True{})
    case M.ApprovalPending{reviewer}: result(operation, M.failure("approval_interrupted",
      "The approval request was interrupted before Bash execution. No command was started. Submit a new request if the operation is still needed."), True{})
    case M.ApprovalGranted{reviewer}: result(operation, M.failure("approval_expired",
      "The one-operation grant expired before Bash execution. No command was started. A fresh request and approval are required."), True{})
    case M.ResultPending{ticket, plugin, pending, value, error}:
      result(operation, M.failure("after_hook_interrupted",
        "Result processing was interrupted. The execution receipt remains in history; neither the tool nor its callback is repeated. " ++ reason), True{})

def close_step(state: Closure, operation: M.Operation()) -> Closure:
  Closure{history, +code, +reason} = state
  Closure{M.HistoryNode{history, interrupted_result(operation, code, reason)}, code, reason}

def closed(state: Closure) -> M.History:
  Closure{history, code, reason} = state
  history

def close(operations: +List<M.Operation()>, history: M.History, code: String, reason: String) -> M.History:
  closed(List.foldl(~&2, ~M.Operation(), ~Closure, ~close_step, operations, Closure{history, code, reason}))

def abandoned(+task: M.Task) -> M.Task:
  M.with_operations(Nil{}, M.with_history(close(M.task_operations(task), M.task_history(task),
    "outcome_unknown", "The external operation may already have run. Its side effects cannot be inferred or undone; it will not be repeated automatically."), task))

def inherited(+parent: M.Task) -> M.History:
  close(M.task_operations(parent), M.task_history(parent), "inherited_operation_not_owned",
    "This operation belongs to parent task " ++ Nat.show(M.task_id(parent)) ++
    "; its execution was not copied. Read that task for its eventual result.")

def review_fields(stage: M.OperationStage, arguments: J.Json) -> +List<J.Field>:
  match stage:
    case M.ApprovalPending{reviewer}:
      [J.Field{"reviewer", M.approval_reviewer_json(reviewer)}, J.Field{"arguments", arguments}]
    case M.ApprovalGranted{reviewer}:
      [J.Field{"reviewer", M.approval_reviewer_json(reviewer)}, J.Field{"arguments", arguments}]
    case M.ElevatedExecuting{ticket, reviewer}:
      [J.Field{"execution_ticket", J.nat(ticket)}, J.Field{"reviewer", M.approval_reviewer_json(reviewer)}]
    case _: Nil{}

def summary(operation: M.Operation()) -> J.Json:
  (ticket, M.OperationBody{M.Call{id, name, arguments}, announced, +stage}) = operation
  J.Object{List.append(&2, J.Field, [J.Field{"operation_id", J.nat(ticket)}, J.Field{"call_id", J.Text{id}},
    J.Field{"tool", J.Text{name}}, J.Field{"status", J.Text{stage_status(stage)}}, J.Field{"announced", J.Boolean{announced}}],
    review_fields(stage, arguments))}

def summaries(operations: +List<M.Operation()>) -> +List<J.Json>:
  Std.map(~M.Operation(), ~J.Json, ~summary, operations)

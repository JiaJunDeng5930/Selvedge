import Base
import ../DOMAIN.bend as D
import ./PROGRAM.bend as Tasks
import ../context/MODEL.bend as Context
import ../context/task-lifecycle.bend as ParentContext
import ../execution/OPERATIONS.bend as Ops
import ../conversation/CODEC.bend as Codec
import ../../bendlib/json.bend as J

# Side conversation control records belong to the side's execution environment,
# not to the content the user explicitly returns to its parent.
def parent_change(change: Context.Change) -> Bool:
  match change:
    case Context.Introduce{Context.Snapshot{key, revision, value}}: ParentContext.is_parent_context(key)
    case Context.Amend{key, base, revision, patch}: ParentContext.is_parent_context(key)
    case Context.Remove{key, base}: ParentContext.is_parent_context(key)

def content(message: D.Message) -> Bool:
  match message:
    case D.ContextMessage{D.SideConversation{owner, parent, start}}: False{}
    case D.ContextMessage{D.SideReturnCursor{owner, through}}: False{}
    case D.ContextMessage{D.ContextChange{change}}: Bool.not(parent_change(change))
    case _: True{}

def retained(keep: Bool, message: D.Message, rest: +List<D.Message>) -> +List<D.Message>:
  match keep:
    case True{}: message <> rest
    case False{}: rest

def content_step(+message: D.Message, rest: +List<D.Message>) -> +List<D.Message>:
  retained(content(message), message, rest)

def required_content(messages: +List<D.Message>) -> +List<D.Message>:
  List.foldr(~&2, ~D.Message, ~+List<D.Message>, ~(message => rest => content_step(message, rest)), messages, Nil{})

def selected_cursor(same: Bool, through: Nat, rest: Nat) -> Nat:
  match same:
    case True{}: through
    case False{}: rest

def return_cursor(history: D.History, +owner: Nat, +start: Nat) -> Nat:
  match history:
    case D.EmptyHistory{}: start
    case D.HistoryNode{previous, D.ContextMessage{D.SideReturnCursor{actual, through}}}:
      selected_cursor(Nat.is_eq(actual, owner), through, return_cursor(previous, owner, start))
    case D.HistoryNode{previous, other}: return_cursor(previous, owner, start)

# Snapshot-only calls acquire no execution rights. Their copied invocations get
# explicit results before the side's content boundary, while the parent runs on.
def inherited_call(call: D.Call, parent: Nat) -> D.Message:
  D.FunctionOutput{D.call_id(call), D.failure("inherited_operation_not_owned",
    "This invocation belongs to parent task " ++ Nat.show(parent) ++
    "; this side conversation cannot execute it. Use read_task for its eventual result."), True{}}

def close_attempts(attempts: +List<D.Attempt>, +parent: Nat, history: D.History) -> D.History:
  match attempts:
    case Nil{}: history
    case Con{attempt, rest}: close_attempts(rest, parent, D.HistoryNode{history, inherited_call(D.attempt_call(attempt), parent)})

def snapshot_phase(phase: D.Phase, +parent: Nat, history: D.History) -> D.History:
  match phase:
    case D.Ready{attempts}: close_attempts(attempts, parent, history)
    case D.HookPending{ticket, plugin, call, pending, remaining}:
      close_attempts(remaining, parent, D.HistoryNode{history, inherited_call(call, parent)})
    case _: history

def snapshot_history(+parent: D.Task) -> D.History:
  snapshot_phase(D.task_phase(parent), D.task_id(parent), Ops.inherited(parent))

def birth_history(+id: Nat, +parent: Nat, +history: D.History) -> D.History:
  D.HistoryNode{history, D.ContextMessage{D.SideConversation{id, parent, 1n+D.history_length(history)}}}

def required_child(+id: Nat, +parent: D.Task) -> D.Task:
  +contract = D.effective_contract(parent)
  D.Task{id, D.task_id(parent) <> D.task_lineage(parent), contract, D.execution_configuration(contract), D.Active{},
    birth_history(id, D.task_id(parent), snapshot_history(parent)), Nil{}, D.Idle{}, Nil{}, False{}}

def initial_message(empty: Bool, message: D.UserContent, task: D.Task) -> D.Task:
  match empty:
    case True{}: task
    case False{}: Tasks.receive(message, task)

def transcript(owner: Nat, parent: Nat, after: Nat, through: Nat, messages: +List<D.Message>) -> J.Json:
  J.Object{[J.Field{"side_task_id", J.nat(owner)}, J.Field{"parent_task_id", J.nat(parent)},
    J.Field{"after", J.nat(after)}, J.Field{"through", J.nat(through)}, J.Field{"messages", J.Array{Codec.messages_json(messages)}}]}

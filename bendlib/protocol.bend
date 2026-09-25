import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./json.bend as J
import ./tasks.bend as T
import ./stdlib.bend as Std
import ./operations.bend as Ops

# The other half of command meaning: an effect result is a message carrying a
# one-use ticket, not permission to overwrite a task. Resolve against the current
# phase before realization. Public commands still use COMMANDS' one resolver.
type Event is Data:
  User{operation: Commands.Operation}
  Ignore{}
  ModelResult{task: M.Task, outcome: M.Outcome, allowed: +List<String>}
  SummaryResult{task: M.Task, outcome: M.Outcome, resume: Bool}
  ToolResult{task: M.Task, operation: M.Operation, value: J.Json, error: Bool}
  Settings{environment: M.Environment}
  Restart{}
  Tick{}

def matching(same: Bool, event: Event) -> Event:
  match same:
    case True{}: event
    case False{}: Ignore{}

def model_phase(status: M.Status, phase: M.Phase, +task: M.Task, +ticket: Nat, +outcome: M.Outcome) -> Event:
  match status phase:
    case M.Archived{} _: Ignore{}
    case _ M.ModelPending{expected, allowed}:
      matching(Nat.is_eq(ticket, expected), ModelResult{task, outcome, allowed})
    case _ M.SummaryPending{expected, resume}:
      matching(Nat.is_eq(ticket, expected), SummaryResult{task, outcome, resume})
    case _ _: Ignore{}

def model(found: Maybe<&2, M.Task>, ticket: Nat, outcome: M.Outcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: model_phase(M.task_status(task), M.task_phase(task), task, ticket, outcome)

def tool_operation(found: Maybe<&2, M.Operation>, task: M.Task, value: J.Json, error: Bool) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{operation}: ToolResult{task, operation, value, error}

def tool_status(status: M.Status, +task: M.Task, ticket: Nat, value: J.Json, error: Bool) -> Event:
  match status:
    case M.Archived{}: Ignore{}
    case _: tool_operation(Ops.find(M.task_operations(task), ticket), task, value, error)

def tool(found: Maybe<&2, M.Task>, ticket: Nat, value: J.Json, error: Bool) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: tool_status(M.task_status(task), task, ticket, value, error)

def resolve(input: M.Input, +world: M.World) -> Event:
  match input:
    case M.UserCommand{command}: User{Commands.resolve(command, world)}
    case M.ModelCompleted{id, ticket, outcome}: model(T.find(Commands.entries(world), id), ticket, outcome)
    case M.ToolCompleted{id, ticket, value, error}: tool(T.find(Commands.entries(world), id), ticket, value, error)
    case M.Configure{environment}: Settings{environment}
    case M.Recover{}: Restart{}
    case M.Continue{}: Tick{}

def acknowledgement(accepted: Bool) -> J.Json:
  M.success(J.Object{[J.Field{"accepted", J.Boolean{accepted}}]})

def recover(task: M.Task) -> M.Task:
  +copy = task
  T.recover(M.task_status(copy), copy)

def recovery(tasks: +List<M.Task>) -> +List<M.Task>:
  Std.map(~M.Task, ~M.Task, ~recover, tasks)

def meaning(event: Event, world: M.World) -> M.Decision:
  match event:
    case User{operation}: Commands.meaning(operation, world)
    case Ignore{}: M.Decision{world, acknowledgement(False{}), Nil{}}
    case ModelResult{task, outcome, allowed}:
      M.Decision{Commands.replace(T.model_outcome(outcome, allowed, task), world), acknowledgement(True{}), Nil{}}
    case SummaryResult{task, outcome, resume}:
      M.Decision{Commands.replace(T.summary_outcome(outcome, resume, task), world), acknowledgement(True{}), Nil{}}
    case ToolResult{task, operation, value, error}:
      M.Decision{Commands.replace(T.complete_operation(operation, value, error, task), world), acknowledgement(True{}), Nil{}}
    case Settings{environment}:
      M.World{tasks, next_task, next_ticket, previous, limits} = world
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits}, M.success(J.Null{}), Nil{}}
    case Restart{}:
      M.World{tasks, next_task, next_ticket, environment, limits} = world
      M.Decision{M.World{recovery(tasks), next_task, next_ticket, environment, limits}, M.success(J.Null{}), Nil{}}
    case Tick{}: M.Decision{world, M.success(J.Null{}), Nil{}}

def input(+event: M.Input, +world: M.World) -> M.Decision:
  meaning(resolve(event, world), world)

# An accepted internal function call must settle even when the requested command
# is refused. A branch additionally continues already accepted calls in each
# child, subject to their recovery policy. It is not a public idle-only fork.
type Invocation is Data:
  Internal{operation: Commands.Operation}
  Branch{count: Nat, messages: +List<String>}

def number(+arguments: J.Json, name: String, fallback: Nat) -> Nat:
  J.natural_or(J.natural(J.get(arguments, name)), fallback)

def messages(values: +List<J.Json>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: J.text(value) <> messages(rest)

def branch(valid: Bool, count: Nat, texts: +List<String>) -> Invocation:
  match valid:
    case True{}: Branch{count, texts}
    case False{}: Internal{Commands.Refuse{"resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid"}}

def invocation(tool: M.Builtin, +arguments: J.Json, +task: M.Task, +world: M.World) -> Invocation:
  match tool:
    case M.ForkTask{}:
      +count = number(arguments, "child_count", 0n)
      +texts = messages(J.items(J.get(arguments, "messages")))
      branch(Commands.branch_fits(count, texts, task, world), count, texts)
    case M.ReadTask{}:
      Internal{Commands.resolve(M.Observe{M.Read{number(arguments, "task_id", 0n), number(arguments, "after", 0n), number(arguments, "limit", 100n)}}, world)}
    case M.SendMessage{}:
      Internal{Commands.resolve(M.Send{number(arguments, "task_id", 0n), J.text(J.get(arguments, "message"))}, world)}
    case M.ArchiveTask{}:
      Internal{Commands.resolve(M.ChangeStatus{number(arguments, "task_id", 0n), M.Archive{}}, world)}
    case M.CancelOperation{}:
      Internal{Commands.resolve(M.Cancel{number(arguments, "task_id", M.task_id(task)), number(arguments, "operation_id", 0n)}, world)}
    case _: Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}

def finish_status(status: M.Status, task: M.Task) -> M.Task:
  match status:
    case M.Archived{}: M.with_phase(M.Idle{}, task)
    case _: task

def result(found: Maybe<&2, M.Task>, call: M.Call, remaining: +List<M.Attempt>, decision: M.Decision) -> M.Decision:
  match found:
    case None{}: decision
    case Some{+task}:
      M.Decision{world, +reply, effects} = decision
      next = finish_status(M.task_status(task), T.complete_tool(call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task))
      M.Decision{Commands.replace(next, world), J.Null{}, effects}

def finish(id: Nat, call: M.Call, remaining: +List<M.Attempt>, +decision: M.Decision) -> M.Decision:
  M.Decision{world, reply, effects} = decision
  result(T.find(Commands.entries(world), id), call, remaining, decision)

def branched(built: Commands.Children, call: M.Call, remaining: +List<M.Attempt>, +parent: M.Task, world: M.World) -> M.Decision:
  Commands.Children{+children, end} = built
  M.World{tasks, next_task, next_ticket, environment, limits} = world
  caller = T.promote(M.with_notified(True{}, M.with_phase(M.Ready{remaining}, M.with_history(M.branch_history(M.task_history(parent), T.call_id(call), 0n), parent))))
  M.Decision{M.World{List.append(&2, M.Task, T.replace(tasks, caller), children), end, next_ticket, environment, limits},
    M.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{}}

def invoked(operation: Invocation, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, +world: M.World) -> M.Decision:
  match operation:
    case Internal{operation}: finish(M.task_id(task), call, remaining, Commands.meaning(operation, world))
    case Branch{count, texts}:
      M.World{tasks, next_task, next_ticket, environment, limits} = world
      branched(Commands.children(count, next_task, 1n, task, T.call_id(call), remaining, texts), call, remaining, task, world)

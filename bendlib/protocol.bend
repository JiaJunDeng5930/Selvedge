import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./json.bend as J
import ./tasks.bend as T
import ./stdlib.bend as Std
import ./operations.bend as Ops
import ./results.bend as Results
import ../UI.bend as UI
import ../WORKSPACE.bend as Workspace
import ../APPROVALS.bend as Approvals
import ../REASONING.bend as R
import ./reasoning-spec.bend as Reasoning

# The other half of command meaning: an effect result is a message carrying a
# one-use ticket, not permission to overwrite a task. Resolve against the current
# phase before realization. Public commands still use COMMANDS' one resolver.
type Event is Data:
  User{operation: Commands.Operation}
  Ignore{}
  ModelResult{task: M.Task, outcome: M.Outcome, allowed: +List<String>}
  ReasoningResult{task: M.Task, revision: Nat, outcome: R.Outcome}
  SummaryResult{task: M.Task, outcome: M.Outcome, resume: Bool}
  ToolResult{task: M.Task, operation: M.Operation(), value: J.Json, error: Bool}
  HookResult{task: M.Task, outcome: M.HookOutcome}
  AfterResult{task: M.Task, operation: M.Operation(), outcome: M.AfterOutcome}
  Review{resolution: Approvals.Resolution}
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

def reasoning_phase(status: M.Status, phase: M.Phase, task: M.Task, ticket: Nat, outcome: R.Outcome) -> Event:
  match status:
    case M.Archived{}: Ignore{}
    case _:
      match phase:
        case M.ReasoningPending{expected, revision}:
          matching(Nat.is_eq(ticket, expected), ReasoningResult{task, revision, outcome})
        case _: Ignore{}

def reasoning(found: Maybe<&2, M.Task>, ticket: Nat, outcome: R.Outcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: reasoning_phase(M.task_status(task), M.task_phase(task), task, ticket, outcome)

def tool_operation(found: Maybe<&2, M.Operation()>, task: M.Task, value: J.Json, error: Bool) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+operation}: matching(Ops.executing(Ops.stage(operation)), ToolResult{task, operation, value, error})

def after_stage(stage: M.OperationStage, task: M.Task, operation: M.Operation(), ticket: Nat, outcome: M.AfterOutcome) -> Event:
  match stage:
    case M.ResultPending{expected, plugin, pending, value, error}:
      matching(Nat.is_eq(ticket, expected), AfterResult{task, operation, outcome})
    case _: Ignore{}

def after_operation(found: Maybe<&2, M.Operation()>, task: M.Task, ticket: Nat, outcome: M.AfterOutcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+operation}: after_stage(Ops.stage(operation), task, operation, ticket, outcome)

def after(found: Maybe<&2, M.Task>, operation: Nat, ticket: Nat, outcome: M.AfterOutcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: after_operation(Ops.find(M.task_operations(task), operation), task, ticket, outcome)

def tool_status(status: M.Status, +task: M.Task, ticket: Nat, value: J.Json, error: Bool) -> Event:
  match status:
    case M.Archived{}: Ignore{}
    case _: tool_operation(Ops.find_callback(M.task_operations(task), ticket), task, value, error)

def tool(found: Maybe<&2, M.Task>, ticket: Nat, value: J.Json, error: Bool) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: tool_status(M.task_status(task), task, ticket, value, error)

def hook_phase(status: M.Status, phase: M.Phase, task: M.Task, ticket: Nat, outcome: M.HookOutcome) -> Event:
  match status phase:
    case M.Archived{} _: Ignore{}
    case _ M.HookPending{expected, reference, call, pending, remaining}:
      matching(Nat.is_eq(ticket, expected), HookResult{task, outcome})
    case _ _: Ignore{}

def hook(found: Maybe<&2, M.Task>, ticket: Nat, outcome: M.HookOutcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: hook_phase(M.task_status(task), M.task_phase(task), task, ticket, outcome)

def resolve(input: M.Input, +world: M.World) -> Event:
  match input:
    case M.UserCommand{command}: User{Commands.resolve(command, world)}
    case M.UserInterface{state, event}: User{Commands.resolve(UI.command(event), world)}
    case M.ModelCompleted{id, ticket, outcome}: model(T.find(Commands.entries(world), id), ticket, outcome)
    case M.ReasoningCompleted{id, ticket, outcome}: reasoning(T.find(Commands.entries(world), id), ticket, outcome)
    case M.ToolCompleted{id, ticket, value, error}: tool(T.find(Commands.entries(world), id), ticket, value, error)
    case M.HookCompleted{id, ticket, outcome}: hook(T.find(Commands.entries(world), id), ticket, outcome)
    case M.AfterCompleted{id, operation, ticket, outcome}: after(T.find(Commands.entries(world), id), operation, ticket, outcome)
    case M.ApprovalCompleted{id, ticket, outcome}:
      Review{Approvals.resolve(T.find(Commands.entries(world), id), Approvals.ModelDecision{}, ticket, outcome)}
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
    case ReasoningResult{task, revision, outcome}:
      M.Decision{Commands.replace(Reasoning.complete(revision, outcome, task), world), acknowledgement(True{}), Nil{}}
    case SummaryResult{task, outcome, resume}:
      M.Decision{Commands.replace(T.summary_outcome(outcome, resume, task), world), acknowledgement(True{}), Nil{}}
    case ToolResult{task, operation, value, error}:
      Results.begin(operation, value, error, task, world)
    case AfterResult{task, +operation, outcome}:
      Results.complete(Ops.stage(operation), outcome, operation, task, world)
    case HookResult{task, outcome}:
      M.Decision{Commands.replace(T.complete_hook(outcome, task), world), acknowledgement(True{}), Nil{}}
    case Settings{environment}:
      M.World{tasks, next_task, next_ticket, previous, limits, projects} = world
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects}, M.success(J.Null{}), Nil{}}
    case Restart{}:
      M.World{tasks, next_task, next_ticket, environment, limits, projects} = world
      M.Decision{M.World{recovery(tasks), next_task, next_ticket, environment, limits, projects}, M.success(J.Null{}), Nil{}}
    case Tick{}: M.Decision{world, M.success(J.Null{}), Nil{}}
    case Review{resolution}: Approvals.meaning(resolution, world)

def input(+event: M.Input, +world: M.World) -> M.Decision:
  meaning(resolve(event, world), world)

# An accepted internal function call must settle even when the requested command
# is refused. A branch additionally continues already accepted calls in each
# child, subject to their recovery policy. It is not a public idle-only fork.
type Invocation is Data:
  Internal{operation: Commands.Operation}
  Branch{count: Nat, messages: +List<String>, selection: Workspace.Selection}

def number(+arguments: J.Json, name: String, fallback: Nat) -> Nat:
  J.natural_or(J.natural(J.get(arguments, name)), fallback)

def messages(values: +List<J.Json>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: J.text(value) <> messages(rest)

def delegated(allowed: Bool, count: Nat, messages: +List<String>, selection: Workspace.Selection) -> Invocation:
  match allowed:
    case True{}: Branch{count, messages, selection}
    case False{}: Internal{Commands.Refuse{"approval_required", "A model-created child cannot broaden workspace or permissions. Ask the user to create a fork with those settings."}}

def branch_selection(selection: Result<&2, &2, String, Workspace.Selection>, count: Nat,
  messages: +List<String>, parent: M.TaskContext) -> Invocation:
  match selection:
    case Fail{reason}: Internal{Commands.Refuse{"invalid_settings", reason}}
    case Done{Workspace.Selection{+context, guidance}}:
      delegated(Workspace.may_delegate(context, parent), count, messages, Workspace.Selection{context, guidance})

def branch(valid: Bool, count: Nat, texts: +List<String>, selection: Result<&2, &2, String, Workspace.Selection>, parent: M.TaskContext) -> Invocation:
  match valid:
    case True{}: branch_selection(selection, count, texts, parent)
    case False{}: Internal{Commands.Refuse{"resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid"}}

def invocation(tool: M.Builtin, +arguments: J.Json, +task: M.Task, +world: M.World) -> Invocation:
  match tool:
    case M.ForkTask{}:
      +count = number(arguments, "child_count", 0n)
      +texts = messages(J.items(J.get(arguments, "messages")))
      branch(Commands.branch_fits(count, texts, task, world), count, texts,
        Commands.selected_settings(J.get(arguments, "settings"), Commands.task_selection(task), M.model_profile(T.task_model(M.task_contract(task))), world), M.task_context(task))
    case M.ReadTask{}:
      Internal{Commands.resolve(M.Observe{M.Read{number(arguments, "task_id", 0n), number(arguments, "after", 0n), number(arguments, "limit", 100n)}}, world)}
    case M.SendMessage{}:
      Internal{Commands.resolve(M.Send{number(arguments, "task_id", 0n), J.text(J.get(arguments, "message"))}, world)}
    case M.ArchiveTask{}:
      Internal{Commands.resolve(M.ChangeStatus{number(arguments, "task_id", 0n), M.Archive{}}, world)}
    case M.CancelOperation{}:
      Internal{Commands.resolve(M.Cancel{number(arguments, "task_id", M.task_id(task)), number(arguments, "operation_id", 0n)}, world)}
    case _: Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}

def result(found: Maybe<&2, M.Task>, call: M.Call, remaining: +List<M.Attempt>, decision: M.Decision) -> M.Decision:
  match found:
    case None{}: decision
    case Some{+task}:
      M.Decision{world, +reply, effects} = decision
      Results.attached(Results.internal(call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task, world), J.Null{}, effects)

def finish(id: Nat, call: M.Call, remaining: +List<M.Attempt>, +decision: M.Decision) -> M.Decision:
  M.Decision{world, reply, effects} = decision
  result(T.find(Commands.entries(world), id), call, remaining, decision)

def branched(built: Commands.Children, call: M.Call, remaining: +List<M.Attempt>, +parent: M.Task, world: M.World) -> M.Decision:
  Commands.Children{+children, end} = built
  M.World{tasks, next_task, next_ticket, environment, limits, projects} = world
  caller = T.promote(M.with_notified(True{}, M.with_phase(M.Ready{remaining}, M.with_history(M.branch_history(M.task_history(parent), T.call_id(call), 0n), parent))))
  M.Decision{M.World{List.append(&2, M.Task, T.replace(tasks, caller), children), end, next_ticket, environment, limits, projects},
    M.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{}}

def branched_invocation(built: Commands.Children, call: M.Call, remaining: +List<M.Attempt>, parent: M.Task, world: M.World) -> M.Decision:
  Commands.Children{+children, end} = built
  M.World{tasks, next_task, next_ticket, environment, limits, projects} = world
  Results.attached(Results.internal(call, remaining, J.nat(0n), False{}, parent,
    M.World{List.append(&2, M.Task, tasks, children), end, next_ticket, environment, limits, projects}),
    M.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{})

def invoked(operation: Invocation, +call: M.Call, +remaining: +List<M.Attempt>, +task: M.Task, +world: M.World) -> M.Decision:
  match operation:
    case Internal{operation}: finish(M.task_id(task), call, remaining, Commands.meaning(operation, world))
    case Branch{count, texts, selection}:
      M.World{tasks, next_task, next_ticket, environment, limits, projects} = world
      branched_invocation(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, task), T.call_id(call), remaining, texts), call, remaining, task, world)

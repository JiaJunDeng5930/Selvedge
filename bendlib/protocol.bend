import Base
import ./feature-state.bend as FeatureState
import ./feature-protocol.bend as FeatureProtocol
import ./feature-operations.bend as FeatureOps
import ./feature-spec.bend as FeatureSpec
import ../FEATURES.bend as F
import ./component.bend as C
import ./domain.bend as D
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./json.bend as J
import ./tasks.bend as T
import ./stdlib.bend as Std
import ./operations.bend as Ops
import ./results.bend as Results
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
  ModelResult{task: D.Task, outcome: D.Outcome, allowed: +List<String>}
  ReasoningResult{task: D.Task, revision: Nat, outcome: R.Outcome}
  FeatureEvent{event: FeatureOps.Event}
  SummaryResult{task: D.Task, outcome: D.Outcome, resume: Bool}
  ToolResult{task: D.Task, operation: D.Operation(), value: J.Json, error: Bool}
  HookResult{task: D.Task, outcome: D.HookOutcome}
  AfterResult{task: D.Task, operation: D.Operation(), outcome: D.AfterOutcome}
  Review{resolution: Approvals.Resolution}
  Settings{environment: D.Environment}
  Restart{}
  Tick{}

def matching(same: Bool, event: Event) -> Event:
  match same:
    case True{}: event
    case False{}: Ignore{}

def model_phase(status: D.Status, phase: D.Phase, +task: D.Task, +ticket: Nat, +outcome: D.Outcome) -> Event:
  match status phase:
    case D.Archived{} _: Ignore{}
    case _ D.ModelPending{expected, allowed}:
      matching(Nat.is_eq(ticket, expected), ModelResult{task, outcome, allowed})
    case _ D.SummaryPending{expected, resume}:
      matching(Nat.is_eq(ticket, expected), SummaryResult{task, outcome, resume})
    case _ _: Ignore{}

def model(found: Maybe<&2, D.Task>, ticket: Nat, outcome: D.Outcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: model_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

def reasoning_phase(status: D.Status, phase: D.Phase, task: D.Task, ticket: Nat, outcome: R.Outcome) -> Event:
  match status:
    case D.Archived{}: Ignore{}
    case _:
      match phase:
        case D.ReasoningPending{expected, revision}:
          matching(Nat.is_eq(ticket, expected), ReasoningResult{task, revision, outcome})
        case _: Ignore{}

def reasoning(found: Maybe<&2, D.Task>, ticket: Nat, outcome: R.Outcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: reasoning_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

def tool_operation(found: Maybe<&2, D.Operation()>, task: D.Task, value: J.Json, error: Bool) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+operation}: matching(Ops.executing(Ops.stage(operation)), ToolResult{task, operation, value, error})

def after_stage(stage: D.OperationStage, task: D.Task, operation: D.Operation(), ticket: Nat, outcome: D.AfterOutcome) -> Event:
  match stage:
    case D.ResultPending{expected, plugin, pending, value, error}:
      matching(Nat.is_eq(ticket, expected), AfterResult{task, operation, outcome})
    case _: Ignore{}

def after_operation(found: Maybe<&2, D.Operation()>, task: D.Task, ticket: Nat, outcome: D.AfterOutcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+operation}: after_stage(Ops.stage(operation), task, operation, ticket, outcome)

def after(found: Maybe<&2, D.Task>, operation: Nat, ticket: Nat, outcome: D.AfterOutcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: after_operation(Ops.find(D.task_operations(task), operation), task, ticket, outcome)

def tool_status(status: D.Status, +task: D.Task, ticket: Nat, value: J.Json, error: Bool) -> Event:
  match status:
    case D.Archived{}: Ignore{}
    case _: tool_operation(Ops.find_callback(D.task_operations(task), ticket), task, value, error)

def tool(found: Maybe<&2, D.Task>, ticket: Nat, value: J.Json, error: Bool) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: tool_status(D.task_status(task), task, ticket, value, error)

def hook_phase(status: D.Status, phase: D.Phase, task: D.Task, ticket: Nat, outcome: D.HookOutcome) -> Event:
  match status phase:
    case D.Archived{} _: Ignore{}
    case _ D.HookPending{expected, reference, call, pending, remaining}:
      matching(Nat.is_eq(ticket, expected), HookResult{task, outcome})
    case _ _: Ignore{}

def hook(found: Maybe<&2, D.Task>, ticket: Nat, outcome: D.HookOutcome) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{+task}: hook_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

def feature_result(found: Maybe<&2, FeatureOps.Event>) -> Event:
  match found:
    case None{}: Ignore{}
    case Some{event}: FeatureEvent{event}

def resolve(input: M.Input, +world: M.World()) -> Event:
  match input:
    case M.UserCommand{command}: User{Commands.resolve(command, world)}
    case M.ModelCompleted{id, ticket, outcome}: model(T.find(Commands.entries(world), id), ticket, outcome)
    case M.ReasoningCompleted{id, ticket, outcome}: reasoning(T.find(Commands.entries(world), id), ticket, outcome)
    case M.FeatureCompleted{completion}: feature_result(FeatureProtocol.resolve(completion, world))
    case M.ToolCompleted{id, ticket, value, error}: tool(T.find(Commands.entries(world), id), ticket, value, error)
    case M.HookCompleted{id, ticket, outcome}: hook(T.find(Commands.entries(world), id), ticket, outcome)
    case M.AfterCompleted{id, operation, ticket, outcome}: after(T.find(Commands.entries(world), id), operation, ticket, outcome)
    case M.ApprovalCompleted{id, ticket, outcome}:
      Review{Approvals.resolve(T.find(Commands.entries(world), id), Approvals.ModelDecision{}, ticket, outcome)}
    case M.Configure{environment}: Settings{environment}
    case M.Recover{}: Restart{}
    case M.Continue{}: Tick{}

def acknowledgement(accepted: Bool) -> J.Json:
  D.success(J.Object{[J.Field{"accepted", J.Boolean{accepted}}]})

def recover(task: D.Task) -> D.Task:
  +copy = task
  T.recover(D.task_status(copy), copy)

def recovery(tasks: +List<D.Task>) -> +List<D.Task>:
  Std.map(~D.Task, ~D.Task, ~recover, tasks)

def meaning(event: Event, world: M.World()) -> M.Decision():
  match event:
    case User{operation}: Commands.meaning(operation, world)
    case Ignore{}: C.Decision{world, acknowledgement(False{}), Nil{}}
    case ModelResult{task, outcome, allowed}:
      C.Decision{Commands.replace(T.model_outcome(outcome, allowed, task), world), acknowledgement(True{}), Nil{}}
    case ReasoningResult{task, revision, outcome}:
      C.Decision{Commands.replace(Reasoning.complete(revision, outcome, task), world), acknowledgement(True{}), Nil{}}
    case FeatureEvent{event}: FeatureSpec.event(event, world)
    case SummaryResult{task, outcome, resume}:
      C.Decision{Commands.replace(T.summary_outcome(outcome, resume, task), world), acknowledgement(True{}), Nil{}}
    case ToolResult{task, operation, value, error}:
      Results.begin(F.State(), F.Effect, operation, value, error, task, world)
    case AfterResult{task, +operation, outcome}:
      Results.complete(F.State(), F.Effect, Ops.stage(operation), outcome, operation, task, world)
    case HookResult{task, outcome}:
      C.Decision{Commands.replace(T.complete_hook(outcome, task), world), acknowledgement(True{}), Nil{}}
    case Settings{environment}:
      C.Frame{D.State{tasks, next_task, next_ticket, previous, limits, projects}, +board} = world
      C.Decision{C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, board}, D.success(J.Null{}), Nil{}}
    case Restart{}:
      C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
      C.Decision{C.Frame{D.State{recovery(tasks), next_task, next_ticket, environment, limits, projects}, FeatureState.recover(board)}, D.success(J.Null{}), Nil{}}
    case Tick{}: C.Decision{world, D.success(J.Null{}), Nil{}}
    case Review{resolution}: Approvals.meaning(F.State(), F.Effect, resolution, world)

def input(+event: M.Input, +world: M.World()) -> M.Decision():
  meaning(resolve(event, world), world)

# An accepted internal function call must settle even when the requested command
# is refused. A branch additionally continues already accepted calls in each
# child, subject to their recovery policy. It is not a public idle-only fork.
type Invocation is Data:
  Internal{operation: Commands.Operation}
  Branch{count: Nat, messages: +List<String>, selection: Workspace.Selection}

def number(+arguments: J.Json, name: String, fallback: Nat) -> Nat:
  J.natural_or(J.natural(J.get(arguments, name)), fallback)

def delegated(allowed: Bool, count: Nat, messages: +List<String>, selection: Workspace.Selection) -> Invocation:
  match allowed:
    case True{}: Branch{count, messages, selection}
    case False{}: Internal{Commands.Refuse{"approval_required", "A model-created child cannot broaden workspace or permissions. Ask the user to create a fork with those settings."}}

def branch_selection(selection: Result<&2, &2, String, Workspace.Selection>, count: Nat,
  messages: +List<String>, parent: D.TaskContext) -> Invocation:
  match selection:
    case Fail{reason}: Internal{Commands.Refuse{"invalid_settings", reason}}
    case Done{Workspace.Selection{+context, guidance}}:
      delegated(Workspace.may_delegate(context, parent), count, messages, Workspace.Selection{context, guidance})

def branch(valid: Bool, count: Nat, texts: +List<String>, selection: Result<&2, &2, String, Workspace.Selection>, parent: D.TaskContext) -> Invocation:
  match valid:
    case True{}: branch_selection(selection, count, texts, parent)
    case False{}: Internal{Commands.Refuse{"resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid"}}

def invocation(tool: D.Builtin, +arguments: J.Json, +task: D.Task, +world: M.World()) -> Invocation:
  match tool:
    case D.ForkTask{}:
      +count = number(arguments, "child_count", 0n)
      +texts = J.text_values(J.items(J.get(arguments, "messages")))
      branch(Commands.branch_fits(count, texts, task, world), count, texts,
        Commands.selected_settings(J.get(arguments, "settings"), Commands.task_selection(task), D.model_profile(T.task_model(D.task_contract(task))), world), D.task_context(task))
    case D.ReadTask{}:
      Internal{Commands.resolve(M.Observe{M.Read{number(arguments, "task_id", 0n), number(arguments, "after", 0n), number(arguments, "limit", 100n)}}, world)}
    case D.SendMessage{}:
      Internal{Commands.resolve(M.Send{number(arguments, "task_id", 0n), J.text(J.get(arguments, "message"))}, world)}
    case D.ArchiveTask{}:
      Internal{Commands.resolve(M.ChangeStatus{number(arguments, "task_id", 0n), D.Archive{}}, world)}
    case D.CancelOperation{}:
      Internal{Commands.resolve(M.Cancel{number(arguments, "task_id", D.task_id(task)), number(arguments, "operation_id", 0n)}, world)}
    case _: Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}

def result(found: Maybe<&2, D.Task>, call: D.Call, remaining: +List<D.Attempt>, decision: M.Decision()) -> M.Decision():
  match found:
    case None{}: decision
    case Some{+task}:
      C.Decision{world, +reply, effects} = decision
      Results.attached(F.State(), F.Effect, Results.internal(F.State(), F.Effect, call, remaining, reply, Bool.not(J.boolean(J.get(reply, "ok"))), task, world), J.Null{}, effects)

def finish(id: Nat, call: D.Call, remaining: +List<D.Attempt>, +decision: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = decision
  result(T.find(Commands.entries(world), id), call, remaining, decision)

def branched(built: Commands.Children, call: D.Call, remaining: +List<D.Attempt>, +parent: D.Task, world: M.World()) -> M.Decision():
  Commands.Children{+children, end} = built
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  caller = T.promote(D.with_notified(True{}, D.with_phase(D.Ready{remaining}, D.with_history(D.branch_history(D.task_history(parent), T.call_id(call), 0n), parent))))
  C.Decision{C.Frame{D.State{List.append(&2, D.Task, T.replace(tasks, caller), children), end, next_ticket, environment, limits, projects}, board},
    D.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{}}

def branched_invocation(built: Commands.Children, call: D.Call, remaining: +List<D.Attempt>, parent: D.Task, world: M.World()) -> M.Decision():
  Commands.Children{+children, end} = built
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  Results.attached(F.State(), F.Effect, Results.internal(F.State(), F.Effect, call, remaining, J.nat(0n), False{}, parent,
    C.Frame{D.State{List.append(&2, D.Task, tasks, children), end, next_ticket, environment, limits, projects}, board}),
    D.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{})

def invoked(operation: Invocation, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> M.Decision():
  match operation:
    case Internal{operation}: finish(D.task_id(task), call, remaining, Commands.meaning(operation, world))
    case Branch{count, texts, selection}:
      C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
      branched_invocation(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, task), T.call_id(call), remaining, texts), call, remaining, task, world)

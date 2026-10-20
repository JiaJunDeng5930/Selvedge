import Base
import ../../features/compaction/SPEC.bend as Compaction
import ../../features/compaction/STATE.bend as CompactionState
import ../tools/SYNTAX.bend as Native
import ../tools/discovery.bend as Discovery
import ../../bendlib/categories.bend as Categories
import ../features/STATE.bend as FeatureState
import ../features/protocol.bend as FeatureProtocol
import ../features/operations.bend as FeatureOps
import ../features/SPEC.bend as FeatureSpec
import ../features/MODEL.bend as F
import ../features/CODEC.bend as FeatureCodec
import ../features/resolution.bend as FeatureResolution
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ../tasks/CONTRACT.bend as TaskRequirements
import ../../bendlib/stdlib.bend as Std
import ../execution/OPERATIONS.bend as Ops
import ./RESULTS.bend as Results
import ../workspace/WORKSPACE.bend as Workspace
import ../workspace/PROJECTS.bend as Projects
import ../approval/MODEL.bend as Approvals
import ../reasoning/MODEL.bend as R
import ../reasoning/SPEC.bend as Reasoning
import ../transport/schema.bend as Schema

# The other half of command meaning: an effect result is a message carrying a
# one-use ticket, not permission to overwrite a task. Resolve against the current
# phase before realization. Public commands still use COMMANDS' one resolver.
type ResolvedEvent is Data:
  User{operation: Commands.Operation}
  Ignore{}
  ContextResult{task: D.Task, revision: Nat, purpose: D.ContextPurpose, outcome: Result<&2, &2, String, +List<D.ContextObservation()>>}
  ModelResult{task: D.Task, outcome: D.Outcome, allowed: +List<String>}
  ReasoningResult{task: D.Task, revision: Nat, outcome: R.Outcome}
  FeatureEvent{event: FeatureOps.ResolvedEvent}
  ToolResult{task: D.Task, operation: D.Operation(), value: J.Json, error: Bool}
  HookResult{task: D.Task, outcome: D.HookOutcome}
  AfterResult{task: D.Task, operation: D.Operation(), outcome: D.AfterOutcome}
  Review{resolution: Approvals.Resolution}
  Settings{environment: D.Environment}
  Restart{}
  Tick{}

type MatchingRequest is Data:
  MatchingRequest{ticket: Nat, expected: Nat, event: ResolvedEvent}

def matching_accepts(request: MatchingRequest) -> Bool:
  MatchingRequest{+ticket, +expected, +event} = request
  Nat.is_eq(ticket, expected)

def matching_category() -> MatchingRequest -> Type:
  Categories.holds(MatchingRequest, matching_accepts)

def matching_accepted(member: Categories.Membership<MatchingRequest, matching_category()>) -> ResolvedEvent:
  Categories.Membership{request, evidence} = member
  MatchingRequest{+ticket, +expected, +event} = request
  event

def matching_admitted(admission: Maybe<&1, Categories.Membership<MatchingRequest, matching_category()>>, request: MatchingRequest) -> ResolvedEvent:
  match admission:
    case Some{member}: matching_accepted(member)
    case None{}:
      MatchingRequest{+ticket, +expected, +event} = request
      Ignore{}

# DEFENSE: An asynchronous completion can arrive after cancellation or a newer invocation; only the current one-use ticket may settle it.
def matching(+ticket: Nat, +expected: Nat, +event: ResolvedEvent) -> ResolvedEvent:
  +request = {MatchingRequest{ticket, expected, event} : MatchingRequest}
  matching_admitted(Categories.admit(MatchingRequest, matching_accepts, request), request)

def matching_calculation(same: Bool, event: ResolvedEvent) -> ResolvedEvent:
  match same:
    case True{}: event
    case False{}: Ignore{}

# DEFENSE: Context observation may finish after task archival or phase change; discard the stale result.
def context_phase(status: D.Status, phase: D.Phase, task: D.Task, ticket: Nat,
  outcome: Result<&2, &2, String, +List<D.ContextObservation()>>) -> ResolvedEvent:
  match status phase:
    case D.Archived{} _: Ignore{}
    case _ D.ContextPending{expected, revision, purpose}:
      matching(ticket, expected, ContextResult{task, revision, purpose, outcome})
    case _ _: Ignore{}

def context_observed(found: Maybe<&2, D.Task>, ticket: Nat, outcome: Result<&2, &2, String, +List<D.ContextObservation()>>) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+task}: context_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

# DEFENSE: Model IO may finish after task archival or phase change; discard the stale result.
def model_phase(status: D.Status, phase: D.Phase, +task: D.Task, +ticket: Nat, +outcome: D.Outcome) -> ResolvedEvent:
  match status phase:
    case D.Archived{} _: Ignore{}
    case _ D.ModelPending{expected, allowed, mode}:
      matching(ticket, expected, ModelResult{task, outcome, allowed})
    case _ _: Ignore{}

def model(found: Maybe<&2, D.Task>, ticket: Nat, outcome: D.Outcome) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+task}: model_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

# DEFENSE: Evaluator IO may finish after task archival or a replaced reasoning request; discard the stale result.
def reasoning_phase(status: D.Status, phase: D.Phase, task: D.Task, ticket: Nat, outcome: R.Outcome) -> ResolvedEvent:
  match status:
    case D.Archived{}: Ignore{}
    case _:
      match phase:
        case D.ReasoningPending{expected, revision}:
          matching(ticket, expected, ReasoningResult{task, revision, outcome})
        case _: Ignore{}

def reasoning(found: Maybe<&2, D.Task>, ticket: Nat, outcome: R.Outcome) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+task}: reasoning_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

type ExecutingResultRequest is Data:
  ExecutingResultRequest{operation: D.Operation(), task: D.Task, value: J.Json, error: Bool}

# DEFENSE: A tool callback may arrive after its operation was cancelled or retired; only an executing operation may consume it.
def executing_result_accepts(request: ExecutingResultRequest) -> Bool:
  ExecutingResultRequest{+operation, +task, +value, +error} = request
  Ops.executing(Ops.stage(operation))

def executing_result_category() -> ExecutingResultRequest -> Type:
  Categories.holds(ExecutingResultRequest, executing_result_accepts)

def executing_result_accepted(member: Categories.Membership<ExecutingResultRequest, executing_result_category()>) -> ResolvedEvent:
  Categories.Membership{request, evidence} = member
  ExecutingResultRequest{+operation, +task, +value, +error} = request
  ToolResult{task, operation, value, error}

def executing_result_admitted(admission: Maybe<&1, Categories.Membership<ExecutingResultRequest, executing_result_category()>>, request: ExecutingResultRequest) -> ResolvedEvent:
  match admission:
    case Some{member}: executing_result_accepted(member)
    case None{}:
      ExecutingResultRequest{+operation, +task, +value, +error} = request
      Ignore{}

def executing_result(+operation: D.Operation(), +task: D.Task, +value: J.Json, +error: Bool) -> ResolvedEvent:
  +request = {ExecutingResultRequest{operation, task, value, error} : ExecutingResultRequest}
  executing_result_admitted(Categories.admit(ExecutingResultRequest, executing_result_accepts, request), request)
def tool_operation(found: Maybe<&2, D.Operation()>, task: D.Task, value: J.Json, error: Bool) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+operation}: executing_result(operation, task, value, error)

# DEFENSE: An after-hook callback can outlive its result-pending stage; require that stage and its current ticket.
def after_stage(stage: D.OperationStage, task: D.Task, operation: D.Operation(), ticket: Nat, outcome: D.AfterOutcome) -> ResolvedEvent:
  match stage:
    case D.ResultPending{expected, plugin, pending, value, error}:
      matching(ticket, expected, AfterResult{task, operation, outcome})
    case _: Ignore{}

def after_operation(found: Maybe<&2, D.Operation()>, task: D.Task, ticket: Nat, outcome: D.AfterOutcome) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+operation}: after_stage(Ops.stage(operation), task, operation, ticket, outcome)

def after(found: Maybe<&2, D.Task>, operation: Nat, ticket: Nat, outcome: D.AfterOutcome) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+task}: after_operation(Ops.find(D.task_operations(task), operation), task, ticket, outcome)

def tool_status(status: D.Status, +task: D.Task, ticket: Nat, value: J.Json, error: Bool) -> ResolvedEvent:
  match status:
    case D.Archived{}: Ignore{}
    case _: tool_operation(Ops.find_callback(D.task_operations(task), ticket), task, value, error)

def tool(found: Maybe<&2, D.Task>, ticket: Nat, value: J.Json, error: Bool) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+task}: tool_status(D.task_status(task), task, ticket, value, error)

# DEFENSE: A before-hook callback may arrive after archival or phase change; it cannot grant execution then.
def hook_phase(status: D.Status, phase: D.Phase, task: D.Task, ticket: Nat, outcome: D.HookOutcome) -> ResolvedEvent:
  match status phase:
    case D.Archived{} _: Ignore{}
    case _ D.HookPending{expected, reference, call, pending, remaining}:
      matching(ticket, expected, HookResult{task, outcome})
    case _ _: Ignore{}

def hook(found: Maybe<&2, D.Task>, ticket: Nat, outcome: D.HookOutcome) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{+task}: hook_phase(D.task_status(task), D.task_phase(task), task, ticket, outcome)

def feature_result(found: Maybe<&2, FeatureOps.ResolvedEvent>) -> ResolvedEvent:
  match found:
    case None{}: Ignore{}
    case Some{event}: FeatureEvent{event}

def resolve(input: M.Input, +world: M.World()) -> ResolvedEvent:
  match input:
    case M.UserCommand{command}: User{Commands.resolve(command, world)}
    case M.RemoteCommand{request, command, environment}: Ignore{}
    case M.RemoteProbe{request, command}: Ignore{}
    case M.RemoteCheck{controller_id, grant_epoch}: Ignore{}
    case M.ContextObserved{id, ticket, outcome}: context_observed(T.find(Commands.entries(world), id), ticket, outcome)
    case M.ModelCompleted{id, ticket, outcome}: model(T.find(Commands.entries(world), id), ticket, outcome)
    case M.ReasoningCompleted{id, ticket, outcome}: reasoning(T.find(Commands.entries(world), id), ticket, outcome)
    case M.FeatureCompleted{completion}: feature_result(FeatureProtocol.resolve(completion, world))
    case M.ToolCompleted{id, ticket, value, error}: tool(T.find(Commands.entries(world), id), ticket, value, error)
    case M.HookCompleted{id, ticket, outcome}: hook(T.find(Commands.entries(world), id), ticket, outcome)
    case M.AfterCompleted{id, operation, ticket, outcome}: after(T.find(Commands.entries(world), id), operation, ticket, outcome)
    case M.ApprovalCompleted{id, ticket, outcome}:
      Review{Approvals.resolution(F.State(), Approvals.construct_review(F.State(),
        Approvals.ReviewRequest{Approvals.ModelDecision{}, id, ticket, outcome, world}))}
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

def accepted_reaction(decision: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = decision
  C.Decision{world, acknowledgement(True{}), effects}

def model_result(+task: D.Task, +outcome: D.Outcome, +allowed: +List<String>, world: M.World()) -> M.Decision():
  accepted_reaction(FeatureSpec.react_outputs(~Commands.output_send, D.task_id(task), TaskRequirements.accepted_reply_outputs(outcome, allowed, task),
    Commands.replace(T.model_outcome(outcome, allowed, task), world)))

# A manual summary resumes through the assembled compaction component only
# after the source observation has committed to the task's current history.
def context_waits_active(status: D.Status, purpose: D.ContextPurpose, revision: Nat,
  +outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, +task: D.Task, world: M.World()) -> Bool:
  match status purpose:
    case D.Active{} D.GenerateContext{}:
      Nat.is_eq(revision, D.history_length(D.task_history(task))) &&
        Compaction.blocked(Reasoning.observed_context(outcome, task), CompactionState.registry(world))
    case _ _: False{}

def context_waits(revision: Nat, purpose: D.ContextPurpose, outcome: Result<&2, &2, String, +List<D.ContextObservation()>>,
  +task: D.Task, world: M.World()) -> Bool:
  context_waits_active(D.task_status(task), purpose, revision, outcome, task, world)

def context_wait(outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, task: D.Task, world: M.World()) -> M.Decision():
  C.Decision{Commands.replace(D.with_phase(D.Ready{Nil{}}, Reasoning.observed_context(outcome, task)), world), acknowledgement(True{}), Nil{}}

def context_compaction_active(status: D.Status, purpose: D.ContextPurpose, revision: Nat, length: Nat) -> Bool:
  match status purpose:
    case D.Active{} D.SummaryContext{}: Nat.is_eq(revision, length)
    case _ _: False{}

def context_compaction(purpose: D.ContextPurpose, revision: Nat, +task: D.Task) -> Bool:
  context_compaction_active(D.task_status(task), purpose, revision, D.history_length(D.task_history(task)))

def context_compaction_found(found: Maybe<&2, D.Task>, +world: M.World(), reply: J.Json, effects: +List<M.Effect()>) -> M.Decision():
  match found:
    case None{}: Compaction.attach(C.Decision{world, reply, effects})
    case Some{+task}: accepted_reaction(Compaction.meaning(Compaction.manual(task, world), world))

def context_followup(compact: Bool, id: Nat, +decision: M.Decision()) -> M.Decision():
  match compact:
    case False{}: Compaction.attach(decision)
    case True{}:
      C.Decision{+world, reply, effects} = decision
      context_compaction_found(T.find(Commands.entries(world), id), world, reply, effects)

def context_result_calculation(waiting: Bool, +task: D.Task, +revision: Nat, +purpose: D.ContextPurpose,
  outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, world: M.World()) -> M.Decision():
  match waiting:
    case True{}: context_wait(outcome, task, world)
    case False{}:
      context_followup(context_compaction(purpose, revision, task), D.task_id(task),
        Reasoning.context_completed(F.State(), F.Effect, revision, purpose, outcome, task, world))

def meaning(event: ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case User{operation}: Commands.meaning(operation, world)
    case Ignore{}: C.Decision{world, acknowledgement(False{}), Nil{}}
    case ContextResult{+task, +revision, +purpose, +outcome}:
      context_result_calculation(context_waits(revision, purpose, outcome, task, world), task, revision, purpose, outcome, world)
    case ModelResult{task, outcome, allowed}:
      model_result(task, outcome, allowed, world)
    case ReasoningResult{task, revision, outcome}:
      C.Decision{Commands.replace(Reasoning.complete(revision, outcome, task), world), acknowledgement(True{}), Nil{}}
    case FeatureEvent{event}: FeatureSpec.event(event, world)
    case ToolResult{task, operation, value, error}:
      Results.begin(F.State(), F.Effect, operation, value, error, task, world)
    case AfterResult{task, +operation, outcome}:
      Results.complete(F.State(), F.Effect, Ops.stage(operation), outcome, operation, task, world)
    case HookResult{task, outcome}:
      C.Decision{Commands.replace(T.complete_hook(outcome, task), world), acknowledgement(True{}), Nil{}}
    case Settings{environment}:
      C.Frame{+task_state, +board} = world
      tasks = D.state_tasks(task_state)
      next_task = D.state_next_task(task_state)
      next_ticket = D.state_next_ticket(task_state)
      limits = D.state_limits(task_state)
      projects = D.state_projects(task_state)
      C.Decision{C.Frame{D.with_state_environment(environment, task_state), FeatureState.reconfigure(board)}, D.success(J.Null{}), Nil{}}
    case Restart{}:
      C.Frame{+task_state_2, +board} = world
      tasks = D.state_tasks(task_state_2)
      next_task = D.state_next_task(task_state_2)
      next_ticket = D.state_next_ticket(task_state_2)
      environment = D.state_environment(task_state_2)
      limits = D.state_limits(task_state_2)
      projects = D.state_projects(task_state_2)
      C.Decision{C.Frame{D.with_state_tasks(recovery(tasks), task_state_2), FeatureState.recover(board)}, D.success(J.Null{}), Nil{}}
    case Tick{}: C.Decision{world, D.success(J.Null{}), Nil{}}
    case Review{resolution}: Approvals.meaning_calculation(F.State(), F.Effect, resolution, world)

def input(+event: M.Input, +world: M.World()) -> M.Decision():
  meaning(resolve(event, world), world)

# An accepted internal function call must settle even when the requested command
# is refused. A branch additionally continues already accepted calls in each
# child, subject to their recovery policy. It is not a public idle-only fork.

type Invocation is Data:
  Internal{operation: Commands.Operation}
  DefinitionResult{value: J.Json}
  Branch{count: Nat, messages: +List<D.UserContent>, selection: Workspace.Selection}

def number(+arguments: J.Json, name: String, fallback: Nat) -> Nat:
  J.natural_or(J.natural(J.get(arguments, name)), fallback)

type DelegatedRequest is Data:
  DelegatedRequest{count: Nat, messages: +List<D.UserContent>, selection: Workspace.Selection, parent: D.TaskContext}

def delegated_accepts(request: DelegatedRequest) -> Bool:
  DelegatedRequest{+count, +messages, +selection, +parent} = request
  Workspace.Selection{context, guidance} = selection
  Workspace.may_delegate(context, parent)

def delegated_category() -> DelegatedRequest -> Type:
  Categories.holds(DelegatedRequest, delegated_accepts)

def delegated_accepted(member: Categories.Membership<DelegatedRequest, delegated_category()>) -> Invocation:
  Categories.Membership{request, evidence} = member
  DelegatedRequest{+count, +messages, +selection, +parent} = request
  Branch{count, messages, selection}

def delegated_admitted(admission: Maybe<&1, Categories.Membership<DelegatedRequest, delegated_category()>>, request: DelegatedRequest) -> Invocation:
  match admission:
    case Some{member}: delegated_accepted(member)
    case None{}:
      DelegatedRequest{+count, +messages, +selection, +parent} = request
      Internal{Commands.Refuse{"approval_required", "A model-created child cannot broaden workspace or permissions. Ask the user to create a fork with those settings."}}

def delegated(+count: Nat, +messages: +List<D.UserContent>, +selection: Workspace.Selection, +parent: D.TaskContext) -> Invocation:
  +request = {DelegatedRequest{count, messages, selection, parent} : DelegatedRequest}
  delegated_admitted(Categories.admit(DelegatedRequest, delegated_accepts, request), request)

def delegated_calculation(allowed: Bool, count: Nat, messages: +List<D.UserContent>, selection: Workspace.Selection) -> Invocation:
  match allowed:
    case True{}: Branch{count, messages, selection}
    case False{}: Internal{Commands.Refuse{"approval_required", "A model-created child cannot broaden workspace or permissions. Ask the user to create a fork with those settings."}}

def branch_selection(selection: Result<&2, &2, String, Workspace.Selection>, count: Nat,
  messages: +List<D.UserContent>, parent: D.TaskContext) -> Invocation:
  match selection:
    case Fail{reason}: Internal{Commands.Refuse{"invalid_settings", reason}}
    case Done{Workspace.Selection{+context, guidance}}:
      delegated(count, messages, Workspace.Selection{context, guidance}, parent)

type BranchRequest is Data:
  BranchRequest{count: Nat, texts: +List<D.UserContent>, selection: Result<&2, &2, String, Workspace.Selection>, task: D.Task, world: M.World()}

def branch_accepts(request: BranchRequest) -> Bool:
  BranchRequest{+count, +texts, +selection, +task, +world} = request
  Commands.branch_fits(count, texts, task, world)

def branch_category() -> BranchRequest -> Type:
  Categories.holds(BranchRequest, branch_accepts)

def branch_workspace_available(selection: Result<&2, &2, String, Workspace.Selection>, world: M.World()) -> Bool:
  match selection:
    case Fail{reason}: True{}
    case Done{Workspace.Selection{context, guidance}}: FeatureState.workspace_available(Workspace.workspace(context), world)

def workspace_invocation(available: Bool, invocation: Invocation) -> Invocation:
  match available:
    case True{}: invocation
    case False{}: Internal{Commands.Refuse{"worktree_unavailable", "This managed worktree is not ready. Select an available workspace or wait for its operation to finish."}}

def branch_accepted(member: Categories.Membership<BranchRequest, branch_category()>) -> Invocation:
  Categories.Membership{request, evidence} = member
  BranchRequest{+count, +texts, +selection, +task, +world} = request
  workspace_invocation(branch_workspace_available(selection, world), branch_selection(selection, count, texts, D.task_context(task)))

def branch_admitted(admission: Maybe<&1, Categories.Membership<BranchRequest, branch_category()>>, request: BranchRequest) -> Invocation:
  match admission:
    case Some{member}: branch_accepted(member)
    case None{}:
      BranchRequest{+count, +texts, +selection, +task, +world} = request
      Internal{Commands.Refuse{"resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid"}}

def branch(+count: Nat, +texts: +List<D.UserContent>, +selection: Result<&2, &2, String, Workspace.Selection>, +task: D.Task, +world: M.World()) -> Invocation:
  +request = {BranchRequest{count, texts, selection, task, world} : BranchRequest}
  branch_admitted(Categories.admit(BranchRequest, branch_accepts, request), request)

def native_query(query: Native.Query, +arguments: J.Json, +caller: Nat) -> M.Query:
  match query:
    case Native.Read{target, after, limit}:
      M.Read{Native.number(target, arguments, caller), Native.number(after, arguments, caller), Native.number(limit, arguments, caller)}
    case Native.Search{query, project, work, after, limit}:
      M.Search{Native.text(query, arguments), Native.optional_number(project, arguments, caller), Native.optional_number(work, arguments, caller),
        Native.number(after, arguments, caller), Native.number(limit, arguments, caller)}
    case Native.Tasks{}: M.ListTasks{}
    case Native.Describe{}: M.Describe{}
    case Native.Projects{}: M.ListProjects{}
    case Native.Project{project}: M.ReadProject{Native.number(project, arguments, caller)}

def native_creation_permitted(options: J.Json, parent: D.TaskContext, environment: D.Environment,
  registry: D.Projects, operation: Commands.Operation) -> Bool:
  match operation:
    case Commands.Start{profile, reasoning, message, Workspace.Selection{context, guidance}}:
      Projects.native_creation_settings(options, context, parent, environment, registry)
    case _: True{}

def native_creation(operation: Commands.Operation, options: J.Json, parent: D.TaskContext, +world: M.World()) -> Invocation:
  environment = Commands.settings(world)
  registry = Projects.registry(F.State(), world)
  Internal{Commands.require((value => native_creation_permitted(options, parent, environment, registry, value)), operation,
    "invalid_settings", "Model-created tasks must use committed directory observations, omit root guidance, and remain within the caller's workspace and permissions.")}

type FeatureInvocation is Data:
  FeatureInvocation{operation: String, spec: F.CommandSpec, frozen_schema: J.Json, arguments: J.Json, caller: D.Task, world: M.World()}

def native_feature_permitted(command: M.Command, caller: D.Task, world: M.World()) -> Bool:
  match command:
    case M.FeatureCommand{command}: FeatureResolution.native_admissible(~Commands.feature_start, caller, command, world)
    case M.Observe{query}: True{}
    case _: False{}

# DEFENSE: Model-selected feature arguments may name a replaced schema or exceed caller workspace authority; reject before resolving the native command.
def feature_invocation_accepts(request: FeatureInvocation) -> Bool:
  FeatureInvocation{operation, F.CommandSpec{+name, description, +kind, +schema}, frozen_schema, +arguments, caller, world} = request
  +body = Schema.command_body(name, arguments)
  String.eq(operation, name) && J.same(schema, frozen_schema) && Schema.valid(Schema.command_arguments(schema), arguments) &&
    Schema.valid(schema, body) && FeatureCodec.valid(kind, body) &&
    native_feature_permitted(FeatureCodec.construct(kind, body), caller, world)

def feature_invocation_accepted(member: Categories.Membership<FeatureInvocation, Categories.holds(FeatureInvocation, feature_invocation_accepts)>) -> Invocation:
  Categories.Membership{request, evidence} = member
  FeatureInvocation{operation, F.CommandSpec{name, description, kind, schema}, frozen_schema, arguments, caller, world} = request
  Internal{Commands.resolve(FeatureCodec.construct(kind, Schema.command_body(name, arguments)), world)}

def feature_invocation_admitted(admission: Maybe<&1, Categories.Membership<FeatureInvocation, Categories.holds(FeatureInvocation, feature_invocation_accepts)>>) -> Invocation:
  match admission:
    case Some{member}: feature_invocation_accepted(member)
    case None{}:
      Internal{Commands.Refuse{"invalid_native_feature", "Arguments must match the frozen feature contract. New tasks must use committed directories, omit root guidance, and remain within caller authority."}}

def native_feature_choice(found: Bool, spec: F.CommandSpec, rest: Maybe<&2, F.CommandSpec>) -> Maybe<&2, F.CommandSpec>:
  match found:
    case True{}: Some{spec}
    case False{}: rest

def native_feature_spec(specs: +List<F.CommandSpec>, +operation: String) -> Maybe<&2, F.CommandSpec>:
  match specs:
    case Nil{}: None{}
    case Con{F.CommandSpec{+name, description, kind, schema}, rest}:
      native_feature_choice(String.eq(name, operation), F.CommandSpec{name, description, kind, schema}, native_feature_spec(rest, operation))

def native_feature_found(found: Maybe<&2, F.CommandSpec>, operation: String, frozen_schema: J.Json,
  arguments: J.Json, caller: D.Task, world: M.World()) -> Invocation:
  match found:
    case None{}: Internal{Commands.Refuse{"unknown_native_feature", "The frozen feature capability is not installed."}}
    case Some{spec}:
      feature_invocation_admitted(Categories.admit(FeatureInvocation, feature_invocation_accepts,
        FeatureInvocation{operation, spec, frozen_schema, arguments, caller, world}))

def native_feature(+operation: String, frozen_schema: J.Json, arguments: J.Json, caller: D.Task, world: M.World()) -> Invocation:
  native_feature_found(native_feature_spec(F.specs(D.task_settings_schema()), operation), operation, frozen_schema, arguments, caller, world)

def invocation_with_caller(tool: Native.Body, +arguments: J.Json, +caller: Nat, +task: D.Task, +world: M.World()) -> Invocation:
  match tool:
    case Native.Discover{}:
      DefinitionResult{Discovery.discover(T.task_tools(D.task_contract(task)), arguments)}
    case Native.Observe{query}:
      Internal{Commands.resolve(M.Observe{native_query(query, arguments, caller)}, world)}
    case Native.Create{profile, reasoning, message, settings}:
      +options = Native.settings(settings, arguments)
      native_creation(Commands.resolve(M.Create{Native.text(profile, arguments), Native.text(reasoning, arguments),
        D.text_content(Native.text(message, arguments)), options}, world), options, D.task_context(task), world)
    case Native.Feature{operation, schema}:
      native_feature(operation, schema, arguments, task, world)
    case Native.Send{target, message}:
      Internal{Commands.resolve(M.Send{Native.number(target, arguments, caller), D.text_content(Native.text(message, arguments))}, world)}
    case Native.Steer{target, message}:
      Internal{Commands.resolve(M.Steer{Native.number(target, arguments, caller), D.text_content(Native.text(message, arguments))}, world)}
    case Native.Archive{target}:
      Internal{Commands.resolve(M.ChangeStatus{Native.number(target, arguments, caller), D.Archive{}}, world)}
    case Native.Cancel{target, operation}:
      Internal{Commands.resolve(M.Cancel{Native.number(target, arguments, caller), Native.number(operation, arguments, caller)}, world)}
    case Native.Fork{count, messages, settings}:
      branch(Native.number(count, arguments, caller), D.text_contents(Native.texts(messages, arguments)),
        Commands.selected_settings(Native.settings(settings, arguments), Commands.task_selection(task), D.model_profile(D.task_model(task)), world), task, world)
    case Native.Process{}:
      Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}
    case Native.ProcessRead{}:
      Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}
    case Native.ProcessWrite{}:
      Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}
    case Native.ReadImage{}:
      Internal{Commands.Refuse{"internal_error", "External tools must cross the external-effect boundary"}}

def executable_invocation(allowed: Bool, invocation: Invocation) -> Invocation:
  match allowed:
    case True{}: invocation
    case False{}: Internal{Commands.Refuse{"worktree_creation_failed", "Worktree creation failed. Archive this task and create a new task to retry; native tools cannot execute in its original workspace."}}

def invocation(tool: Native.Body, +arguments: J.Json, +task: D.Task, +world: M.World()) -> Invocation:
  executable_invocation(FeatureState.execution_allowed(D.task_id(task), world), invocation_with_caller(tool, arguments, D.task_id(task), task, world))

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
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  caller = T.promote(D.with_notified(True{}, D.with_phase(D.Ready{remaining}, D.with_history(D.branch_history(D.task_history(parent), T.call_id(call), 0n), parent))))
  C.Decision{C.Frame{D.with_state_next_task(end, D.with_state_tasks(List.append(&2, D.Task, T.replace(tasks, caller), children), task_state)), board},
    D.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{}}

def branched_invocation(built: Commands.Children, call: D.Call, remaining: +List<D.Attempt>, parent: D.Task, world: M.World()) -> M.Decision():
  Commands.Children{+children, end} = built
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  Results.attached(F.State(), F.Effect, Results.internal(F.State(), F.Effect, call, remaining, J.nat(0n), False{}, parent,
    C.Frame{D.with_state_next_task(end, D.with_state_tasks(List.append(&2, D.Task, tasks, children), task_state)), board}),
    D.success(J.Object{[J.Field{"children", J.Array{Commands.identities(children)}}]}), Nil{})

def invoked(operation: Invocation, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> M.Decision():
  match operation:
    case Internal{operation}: finish(D.task_id(task), call, remaining, Commands.meaning(operation, world))
    case DefinitionResult{value}: finish(D.task_id(task), call, remaining, C.Decision{world, D.success(value), Nil{}})
    case Branch{count, texts, selection}:
      C.Frame{+task_state, +board} = world
      next_task = D.state_next_task(task_state)
      branched_invocation(Commands.children(count, next_task, 1n, Commands.selected_parent(selection, task), T.call_id(call), remaining, texts), call, remaining, task, world)


type InputRequest is Data:
  InputRequest{input: M.Input, world: M.World()}

def input_resolution(request: InputRequest) -> ResolvedEvent:
  InputRequest{input, world} = request
  resolve(input, world)

def ConstructedInput() -> Type:
  Categories.Membership<Categories.Construction<InputRequest, ResolvedEvent>,
    Categories.constructed_by(InputRequest, ResolvedEvent, input_resolution)>

def construct_input(input: M.Input, world: M.World()) -> ConstructedInput():
  Categories.construct(InputRequest, ResolvedEvent, input_resolution, InputRequest{input, world})

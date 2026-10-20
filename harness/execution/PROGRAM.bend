import Base
import ../../features/titles/SPEC.bend as TitleSpec
import ../../features/compaction/SPEC.bend as Compaction
import ../../features/compaction/STATE.bend as CompactionState
import ../tools/SYNTAX.bend as Native
import ../../bendlib/categories.bend as Categories
import ../features/MODEL.bend as F
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../../features/board/scheduling-spec.bend as BoardScheduling
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../protocol/PROGRAM.bend as Protocol
import ../tasks/PROGRAM.bend as T
import ../tasks/side-context.bend as SideContext
import ../../bendlib/json.bend as J
import ../transport/schema.bend as Schema
import ../transport/presentation.bend as View
import ./OPERATIONS.bend as Ops
import ../approval/HOOKS.bend as Hooks
import ../workspace/WORKSPACE.bend as Workspace
import ../approval/MODEL.bend as Approvals
import ../protocol/RESULTS.bend as Results
import ../reasoning/SPEC.bend as Reasoning

# The execution alphabet is the semantic boundary between task policy and the
# scheduler. Resolution owns authority, recovery and argument preconditions;
# meaning fixes the entire decision. Neither definition imports PROGRAM.
type Action is Data:
  Rest{}
  Idle{task: D.Task}
  Model{task: D.Task}
  External{tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Review{reviewer: D.ApprovalReviewer, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Granted{reviewer: D.ApprovalReviewer, tool: D.Tool, operation: D.Operation(), task: D.Task}
  GrantFailure{operation: D.Operation(), task: D.Task}
  Hook{plugin: D.PluginRef, pending: +List<D.PluginRef>, tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Internal{operation: Protocol.Invocation, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}
  Failure{code: String, reason: String, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}

def catalog_environment(world: M.World(), environment_value: D.Environment) -> +List<D.Tool>:
  match world environment_value:
    case C.Frame{+task_state, +board} D.Environment{tools, profiles, max_fork, max_descendants, project, plugins, instructions}:
      tools

def catalog(+world: M.World()) -> +List<D.Tool>:
  catalog_environment(world, D.state_environment(C.local(D.State, F.State(), world)))

def context(+task: D.Task) -> J.Json:
  J.Object{[J.Field{"model", View.model_json(D.task_model(task))},
    J.Field{"tools", J.Array{D.tools_json(T.task_tools(D.task_contract(task)))}},
    J.Field{"history", J.Array{T.messages_json(D.history_messages(D.task_history(task), Nil{}))}}]}

def model(+task: D.Task, world: M.World()) -> Action:
  Model{task}

# DEFENSE: Model calls and hook rewrites supply untrusted arguments; enforce the frozen tool schema and process approval constraints before dispatch.
def arguments_valid(source: D.Source, schema: J.Json, +arguments: J.Json, caller: Nat) -> Bool:
  match source:
    case D.Extension{plugin, remote}: Schema.valid(schema, arguments)
    case D.Mcp{server, remote}: J.is_object(arguments)
    case D.Harness{Native.Process{}}:
      Schema.valid(schema, arguments) && D.nonempty(J.text(J.get(arguments, "command"))) &&
        Bool.not(String.contains(J.text(J.get(arguments, "command")), SCon{Chr{0}, SNil{}})) && Approvals.valid_request(arguments)
    case D.Harness{other}: Schema.valid(schema, arguments) && Native.caller_arguments_valid(other, arguments, caller)

def external_review(needed: Bool, tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, +task: D.Task) -> Action:
  match needed:
    case True{}: Review{Approvals.reviewer(Workspace.approval(D.task_context(task))), call, remaining, task}
    case False{}: External{tool, call, remaining, task}

type ExternalCapacityRequest is Data:
  ExternalCapacityRequest{tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task}

# DEFENSE: A task can issue tools faster than they complete; enforce the in-flight operation limit before allocating another operation.
def external_capacity_accepts(request: ExternalCapacityRequest) -> Bool:
  ExternalCapacityRequest{+tool, +call, +remaining, +task} = request
  Nat.is_lt(List.length(&2, D.Operation(), D.task_operations(task)), D.operation_limit())

def external_capacity_category() -> ExternalCapacityRequest -> Type:
  Categories.holds(ExternalCapacityRequest, external_capacity_accepts)

def external_capacity_accepted(member: Categories.Membership<ExternalCapacityRequest, external_capacity_category()>) -> Action:
  Categories.Membership{request, evidence} = member
  ExternalCapacityRequest{+tool, +call, +remaining, +task} = request
  external_review(Approvals.needed(D.tool_source(tool), T.call_arguments(call), Workspace.approval(D.task_context(task))), tool, call, remaining, task)

def external_capacity_admitted(admission: Maybe<&1, Categories.Membership<ExternalCapacityRequest, external_capacity_category()>>, request: ExternalCapacityRequest) -> Action:
  match admission:
    case Some{member}: external_capacity_accepted(member)
    case None{}:
      ExternalCapacityRequest{+tool, +call, +remaining, +task} = request
      Failure{"operation_limit", "This task has reached its in-flight operation limit; wait for results or cancel an operation", call, remaining, task}

def external_capacity(+tool: D.Tool, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task) -> Action:
  +request = {ExternalCapacityRequest{tool, call, remaining, task} : ExternalCapacityRequest}
  external_capacity_admitted(Categories.admit(ExternalCapacityRequest, external_capacity_accepts, request), request)

type InternalCapacityRequest is Data:
  InternalCapacityRequest{builtin: Native.Body, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()}

# DEFENSE: Internal tools with after-hooks retain pending result operations; enforce the same capacity before accepting another one.
def internal_capacity_accepts(request: InternalCapacityRequest) -> Bool:
  InternalCapacityRequest{+builtin, +call, +remaining, +task, +world} = request
  Nat.is_eq(List.length(&2, D.PluginRef, Hooks.after(Hooks.plugins(D.task_contract(task)))), 0n) || Nat.is_lt(List.length(&2, D.Operation(), D.task_operations(task)), D.operation_limit())

def internal_capacity_category() -> InternalCapacityRequest -> Type:
  Categories.holds(InternalCapacityRequest, internal_capacity_accepts)

def internal_capacity_accepted(member: Categories.Membership<InternalCapacityRequest, internal_capacity_category()>) -> Action:
  Categories.Membership{request, evidence} = member
  InternalCapacityRequest{+builtin, +call, +remaining, +task, +world} = request
  Internal{Protocol.invocation(builtin, T.call_arguments(call), task, world), call, remaining, task}

def internal_capacity_admitted(admission: Maybe<&1, Categories.Membership<InternalCapacityRequest, internal_capacity_category()>>, request: InternalCapacityRequest) -> Action:
  match admission:
    case Some{member}: internal_capacity_accepted(member)
    case None{}:
      InternalCapacityRequest{+builtin, +call, +remaining, +task, +world} = request
      Failure{"operation_limit", "This task has reached its result-processing operation limit; wait for results or cancel an operation", call, remaining, task}

def internal_capacity(+builtin: Native.Body, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> Action:
  +request = {InternalCapacityRequest{builtin, call, remaining, task, world} : InternalCapacityRequest}
  internal_capacity_admitted(Categories.admit(InternalCapacityRequest, internal_capacity_accepts, request), request)

def classified(source: D.Source, tool: D.Tool, +call: D.Call,
  remaining: +List<D.Attempt>, +task: D.Task, world: M.World()) -> Action:
  match source:
    case D.Harness{Native.Process{}}:
      external_capacity(tool, call, remaining, task)
    case D.Harness{Native.ProcessRead{}}:
      external_capacity(tool, call, remaining, task)
    case D.Harness{Native.ProcessWrite{}}:
      external_capacity(tool, call, remaining, task)
    case D.Harness{builtin}:
      internal_capacity(builtin, call, remaining, task, world)
    case D.Mcp{server, remote}:
      external_capacity(tool, call, remaining, task)
    case D.Extension{plugin, remote}:
      external_capacity(tool, call, remaining, task)

type ValidatedRequest is Data:
  ValidatedRequest{tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()}

def validated_accepts(request: ValidatedRequest) -> Bool:
  ValidatedRequest{+tool, +call, +remaining, +task, +world} = request
  D.Tool{name, description, schema, source} = tool
  arguments_valid(source, schema, T.call_arguments(call), D.task_id(task))

def validated_category() -> ValidatedRequest -> Type:
  Categories.holds(ValidatedRequest, validated_accepts)

def validated_accepted(member: Categories.Membership<ValidatedRequest, validated_category()>) -> Action:
  Categories.Membership{request, evidence} = member
  ValidatedRequest{+tool, +call, +remaining, +task, +world} = request
  classified(D.tool_source(tool), tool, call, remaining, task, world)

def validated_admitted(admission: Maybe<&1, Categories.Membership<ValidatedRequest, validated_category()>>, request: ValidatedRequest) -> Action:
  match admission:
    case Some{member}: validated_accepted(member)
    case None{}:
      ValidatedRequest{+tool, +call, +remaining, +task, +world} = request
      Failure{"invalid_arguments", "Tool arguments do not satisfy its frozen schema", call, remaining, task}

def validated(+tool: D.Tool, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> Action:
  +request = {ValidatedRequest{tool, call, remaining, task, world} : ValidatedRequest}
  validated_admitted(Categories.admit(ValidatedRequest, validated_accepts, request), request)

type AvailableRequest is Data:
  AvailableRequest{tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()}

# DEFENSE: A frozen task route can outlive removal or replacement of its live provider; do not dispatch an unavailable route.
def available_accepts(request: AvailableRequest) -> Bool:
  AvailableRequest{+tool, +call, +remaining, +task, +world} = request
  T.available(catalog(world), tool)

def available_category() -> AvailableRequest -> Type:
  Categories.holds(AvailableRequest, available_accepts)

def available_validation(request: AvailableRequest) -> ValidatedRequest:
  AvailableRequest{tool, call, remaining, task, world} = request
  ValidatedRequest{tool, call, remaining, task, world}

def ready_arguments(request: AvailableRequest) -> Bool:
  validated_accepts(available_validation(request))

def ready_validation_category() -> AvailableRequest -> Type:
  Categories.inverse_image(AvailableRequest, ValidatedRequest, available_validation, validated_category())

def ReadyCategory() -> AvailableRequest -> Type:
  request => Categories.intersection(AvailableRequest, available_category(), ready_validation_category(), request)

def ready_availability() -> Categories.Inclusion<AvailableRequest, ReadyCategory(), available_category()>:
  Categories.intersection_first(AvailableRequest, available_category(), ready_validation_category())

def ready_validation() -> Categories.Inclusion<AvailableRequest, ReadyCategory(), ready_validation_category()>:
  Categories.intersection_second(AvailableRequest, available_category(), ready_validation_category())

def ready_validation_member(member: Categories.Membership<AvailableRequest, ReadyCategory()>) -> Categories.Membership<ValidatedRequest, validated_category()>:
  Categories.map_membership(AvailableRequest, ValidatedRequest, available_validation, validated_category(),
    Categories.reclassify(AvailableRequest, ReadyCategory(), ready_validation_category(), member, ready_validation()))

def ready_accepted(member: Categories.Membership<AvailableRequest, ReadyCategory()>) -> Action:
  validated_accepted(ready_validation_member(member))

def ready_invalid(request: AvailableRequest) -> Action:
  AvailableRequest{tool, call, remaining, task, world} = request
  Failure{"invalid_arguments", "Tool arguments do not satisfy its frozen schema", call, remaining, task}

def ready_checked(+request: AvailableRequest, evidence: available_category()(request), allowed: Bool,
  checked: {ready_arguments(request) == allowed : Bool}) -> Action:
  match allowed:
    case True{}:
      ready_accepted(Categories.Membership{request, Categories.Intersection{evidence, checked}})
    case False{}: ready_invalid(request)

def available_accepted(member: Categories.Membership<AvailableRequest, available_category()>) -> Action:
  Categories.Membership{+request, evidence} = member
  ready_checked(request, evidence, ready_arguments(request), {==})

def available_admitted(admission: Maybe<&1, Categories.Membership<AvailableRequest, available_category()>>, request: AvailableRequest) -> Action:
  match admission:
    case Some{member}: available_accepted(member)
    case None{}:
      AvailableRequest{+tool, +call, +remaining, +task, +world} = request
      Failure{"tool_unavailable", "The task's frozen tool route is unavailable", call, remaining, task}

def available(+tool: D.Tool, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> Action:
  +request = {AvailableRequest{tool, call, remaining, task, world} : AvailableRequest}
  available_admitted(Categories.admit(AvailableRequest, available_accepts, request), request)

type HookAvailableRequest is Data:
  HookAvailableRequest{plugin: D.PluginRef, pending: +List<D.PluginRef>, tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, world: M.World()}

def hook_available_accepts(request: HookAvailableRequest) -> Bool:
  HookAvailableRequest{+plugin, +pending, +tool, +call, +remaining, +task, +world} = request
  Hooks.available(Hooks.live(F.State(), world), plugin)

def hook_available_category() -> HookAvailableRequest -> Type:
  Categories.holds(HookAvailableRequest, hook_available_accepts)

def hook_available_accepted(member: Categories.Membership<HookAvailableRequest, hook_available_category()>) -> Action:
  Categories.Membership{request, evidence} = member
  HookAvailableRequest{+plugin, +pending, +tool, +call, +remaining, +task, +world} = request
  Hook{plugin, pending, tool, call, remaining, task}

def hook_available_admitted(admission: Maybe<&1, Categories.Membership<HookAvailableRequest, hook_available_category()>>, request: HookAvailableRequest) -> Action:
  match admission:
    case Some{member}: hook_available_accepted(member)
    case None{}:
      HookAvailableRequest{+plugin, +pending, +tool, +call, +remaining, +task, +world} = request
      Failure{"hook_unavailable", "A required frozen plugin revision is unavailable; the tool was not dispatched", call, remaining, task}

def hook_available(+plugin: D.PluginRef, +pending: +List<D.PluginRef>, +tool: D.Tool, +call: D.Call, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> Action:
  +request = {HookAvailableRequest{plugin, pending, tool, call, remaining, task, world} : HookAvailableRequest}
  hook_available_admitted(Categories.admit(HookAvailableRequest, hook_available_accepts, request), request)

# Every route crosses this boundary before internal/external classification and
# argument validation. Each accepted rewrite is revalidated at the final gate.

def chain(pending: +List<D.PluginRef>, +tool: D.Tool, call: D.Call, remaining: +List<D.Attempt>, task: D.Task, +world: M.World()) -> Action:
  match pending:
    case Nil{}: available(tool, call, remaining, task, world)
    case Con{+plugin, pending}: hook_available(plugin, pending, tool, call, remaining, task, world)

type AuthorizationRequest is Data:
  AuthorizationRequest{tool: D.Tool, attempt: D.Attempt, remaining: +List<D.Attempt>, task: D.Task, world: M.World()}

def authorization_accepts(request: AuthorizationRequest) -> Bool:
  AuthorizationRequest{+tool, +attempt, +remaining, +task, +world} = request
  D.may_execute(D.recovery(D.tool_source(tool)), attempt)

def authorization_category() -> AuthorizationRequest -> Type:
  Categories.holds(AuthorizationRequest, authorization_accepts)

def authorization_accepted(member: Categories.Membership<AuthorizationRequest, authorization_category()>) -> Action:
  Categories.Membership{request, evidence} = member
  AuthorizationRequest{+tool, +attempt, +remaining, +task, +world} = request
  chain(Hooks.queued(attempt, D.task_contract(task)), tool, D.attempt_call(attempt), remaining, task, world)

def authorization_admitted(admission: Maybe<&1, Categories.Membership<AuthorizationRequest, authorization_category()>>, request: AuthorizationRequest) -> Action:
  match admission:
    case Some{member}: authorization_accepted(member)
    case None{}:
      AuthorizationRequest{+tool, +attempt, +remaining, +task, +world} = request
      Failure{"outcome_unknown", "The effect may already have happened; automatic repetition is forbidden", D.attempt_call(attempt), remaining, task}

def authorization(+tool: D.Tool, +attempt: D.Attempt, +remaining: +List<D.Attempt>, +task: D.Task, +world: M.World()) -> Action:
  +request = {AuthorizationRequest{tool, attempt, remaining, task, world} : AuthorizationRequest}
  authorization_admitted(Categories.admit(AuthorizationRequest, authorization_accepts, request), request)


def found(found: Maybe<&2, D.Tool>, +attempt: D.Attempt, remaining: +List<D.Attempt>, task: D.Task, world: M.World()) -> Action:
  match found:
    case None{}:
      Failure{"unknown_tool", "The call does not name a tool in the task contract", D.attempt_call(attempt), remaining, task}
    case Some{+tool}:
      authorization(tool, attempt, remaining, task, world)

def tool(phase: D.Phase, +task: D.Task, world: M.World()) -> Action:
  match phase:
    case D.Ready{Con{+attempt, remaining}}:
      found(T.find_tool(T.task_tools(D.task_contract(task)), T.call_name(D.attempt_call(attempt))), attempt, remaining, task, world)
    case _: Rest{}

type GrantValidRequest is Data:
  GrantValidRequest{reviewer: D.ApprovalReviewer, tool: D.Tool, operation: D.Operation(), task: D.Task, world: M.World()}

def grant_valid_accepts(request: GrantValidRequest) -> Bool:
  GrantValidRequest{+reviewer, +tool, +operation, +task, +world} = request
  T.available(catalog(world), tool)

def grant_valid_category() -> GrantValidRequest -> Type:
  Categories.holds(GrantValidRequest, grant_valid_accepts)

def grant_available_calculation(member: Categories.Membership<GrantValidRequest, grant_valid_category()>) -> Action:
  Categories.Membership{request, evidence} = member
  GrantValidRequest{+reviewer, +tool, +operation, +task, +world} = request
  Granted{reviewer, tool, operation, task}

def grant_valid_admitted(admission: Maybe<&1, Categories.Membership<GrantValidRequest, grant_valid_category()>>, request: GrantValidRequest) -> Action:
  match admission:
    case Some{member}: grant_available_calculation(member)
    case None{}:
      GrantValidRequest{+reviewer, +tool, +operation, +task, +world} = request
      GrantFailure{operation, task}

def grant_valid(+reviewer: D.ApprovalReviewer, +tool: D.Tool, +operation: D.Operation(), +task: D.Task, +world: M.World()) -> Action:
  +request = {GrantValidRequest{reviewer, tool, operation, task, world} : GrantValidRequest}
  grant_valid_admitted(Categories.admit(GrantValidRequest, grant_valid_accepts, request), request)

def grant_tool(found: Maybe<&2, D.Tool>, reviewer: D.ApprovalReviewer, +operation: D.Operation(), task: D.Task, world: M.World()) -> Action:
  match found:
    case None{}: GrantFailure{operation, task}
    case Some{+tool}: grant_valid(reviewer, tool, operation, task, world)

def grant_stage(stage: D.OperationStage, +operation: D.Operation(), +task: D.Task, world: M.World()) -> Action:
  match stage:
    case D.ApprovalGranted{reviewer}:
      grant_tool(T.find_tool(T.task_tools(D.task_contract(task)), T.call_name(Ops.call(operation))), reviewer, operation, task, world)
    case _: Rest{}

def grant(found: Maybe<&2, D.Operation()>, task: D.Task, world: M.World()) -> Action:
  match found:
    case None{}: Rest{}
    case Some{+operation}: grant_stage(Ops.stage(operation), operation, task, world)

def grant_failure_value() -> J.Json:
  D.failure("tool_unavailable", "The approved tool route is no longer available; Bash was not started")

def resolve(work: D.Work, +task: D.Task, world: M.World()) -> Action:
  match work:
    case D.NoWork{}: Rest{}
    case D.BecomeIdle{}: Idle{task}
    case D.RequestNextModel{}: model(task, world)
    case D.RunNextTool{}: tool(D.task_phase(task), task, world)
    case D.RunGrantedOperation{}: grant(Ops.find_granted(D.task_operations(task)), task, world)

def meaning_calculation(action: Action, world: M.World()) -> M.Decision():
  match action world:
    case Rest{} _:
      C.Decision{world, D.success(J.Null{}), Nil{}}
    case Idle{task} _:
      C.Decision{Commands.replace(D.with_phase(D.Idle{}, task), world), D.success(J.Null{}), Nil{}}
    case Model{task} _: Compaction.attach(Reasoning.start(F.State(), F.Effect, task, world))
    case External{+tool, +call, remaining, +task} C.Frame{+task_state_2, +board}:
      tasks = D.state_tasks(task_state_2)
      next_task = D.state_next_task(task_state_2)
      +ticket = D.state_next_ticket(task_state_2)
      environment = D.state_environment(task_state_2)
      limits = D.state_limits(task_state_2)
      projects = D.state_projects(task_state_2)
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, T.promote(Ops.started_tool(tool, ticket, call, remaining, task))), task_state_2)), board},
        J.Null{}, [Effects.ExecuteTool{D.task_id(task), ticket, ticket, tool, call, D.task_context(task), Workspace.default_access(D.task_context(task))}]}
    case Review{+reviewer, +call, remaining, task} C.Frame{+task_state_3, +board}:
      tasks = D.state_tasks(task_state_3)
      next_task = D.state_next_task(task_state_3)
      +ticket = D.state_next_ticket(task_state_3)
      environment = D.state_environment(task_state_3)
      limits = D.state_limits(task_state_3)
      projects = D.state_projects(task_state_3)
      +prepared = T.promote(Ops.awaiting(ticket, reviewer, call, remaining, task))
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, prepared), task_state_3)), board},
        J.Null{}, Approvals.review_effects(F.Effect, reviewer, prepared, ticket, call)}
    case Granted{reviewer, +tool, +operation, +task} C.Frame{+task_state_4, +board}:
      tasks = D.state_tasks(task_state_4)
      next_task = D.state_next_task(task_state_4)
      +ticket = D.state_next_ticket(task_state_4)
      environment = D.state_environment(task_state_4)
      limits = D.state_limits(task_state_4)
      projects = D.state_projects(task_state_4)
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, Ops.elevated_tool(tool, ticket, reviewer, operation, task)), task_state_4)), board},
        J.Null{}, [Effects.ExecuteTool{D.task_id(task), ticket, Ops.ticket(operation), tool, Ops.call(operation), D.task_context(task), D.Unrestricted{}}]}
    case GrantFailure{operation, task} _:
      Results.begin(F.State(), F.Effect, operation, grant_failure_value(), True{}, task, world)
    case Hook{+plugin, pending, tool, +call, remaining, +task} C.Frame{+task_state_5, +board}:
      tasks = D.state_tasks(task_state_5)
      next_task = D.state_next_task(task_state_5)
      +ticket = D.state_next_ticket(task_state_5)
      environment = D.state_environment(task_state_5)
      limits = D.state_limits(task_state_5)
      projects = D.state_projects(task_state_5)
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, D.with_phase(D.HookPending{ticket, plugin, call, pending, remaining}, task)), task_state_5)), board},
        J.Null{}, [Effects.CheckTool{D.task_id(task), ticket, plugin, tool, call}]}
    case Internal{operation, call, remaining, task} _:
      Protocol.invoked(operation, call, remaining, task, world)
    case Failure{code, reason, call, remaining, task} _:
      C.Decision{Commands.replace(T.complete_tool(call, remaining, D.failure(code, reason), True{}, task), world), D.success(J.Null{}), Nil{}}

def work_calculation(work: D.Work, +task: D.Task, +world: M.World()) -> M.Decision():
  meaning_calculation(resolve(work, task, world), world)

def world(decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

def combine(before: M.Decision(), after: M.Decision()) -> M.Decision():
  C.Decision{old, reply, effects} = before
  C.Decision{world, ignored, added} = after
  C.Decision{world, reply, List.append(&2, M.Effect(), effects, added)}

def defer(decision: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = decision
  C.Decision{world, reply, List.append(&2, M.Effect(), effects, [Effects.ContinueScheduling{}])}

# Independent finite-run specification. Exhaustion is an explicit continuation,
# not a termination/fairness claim about the remote model or operating system.

def schedule(fuel: Nat, candidate: Maybe<&2, D.Task>, +decision: M.Decision()) -> M.Decision():
  match fuel candidate:
    case 0n None{}: decision
    case 0n Some{task}: defer(decision)
    case 1n+p None{}: decision
    case 1n+p Some{+task}:
      +next = SideContext.reconcile_dispatch(F.State(), F.Effect, combine(decision, work_calculation(D.task_work(task), task, world(decision))))
      schedule(p, Compaction.runnable(Commands.entries(world(next)), CompactionState.registry(world(next))), next)

def budget_limits(world: M.World(), limits_value: D.ExecutionLimits) -> Nat:
  match world limits_value:
    case C.Frame{+task_state, +board} D.ExecutionLimits{steps, render, bytes}:
      steps

def budget(+world: M.World()) -> Nat:
  budget_limits(world, D.state_limits(C.local(D.State, F.State(), world)))

def scheduled_prepared(decision: M.Decision()) -> M.Decision():
  +prepared = SideContext.reconcile_dispatch(F.State(), F.Effect, decision)
  BoardScheduling.finish(schedule(budget(world(prepared)), Compaction.runnable(Commands.entries(world(prepared)), CompactionState.registry(world(prepared))), prepared))

def scheduled(enabled: Bool, +decision: M.Decision()) -> M.Decision():
  match enabled:
    case False{}: decision
    case True{}: scheduled_prepared(Compaction.required_prepare(TitleSpec.prepare(BoardScheduling.required_prepare(decision))))


type WorkRequest is Data:
  WorkRequest{work: D.Work, task: D.Task, world: M.World()}

def work_resolution(request: WorkRequest) -> Action:
  WorkRequest{work, task, world} = request
  resolve(work, task, world)

def ConstructedWork() -> Type:
  Categories.Membership<Categories.Construction<WorkRequest, Action>,
    Categories.constructed_by(WorkRequest, Action, work_resolution)>

def construct_work(work: D.Work, task: D.Task, world: M.World()) -> ConstructedWork():
  Categories.construct(WorkRequest, Action, work_resolution, WorkRequest{work, task, world})

def meaning(member: ConstructedWork()) -> M.Decision():
  Categories.Membership{Categories.Construction{WorkRequest{work, task, world}, action}, evidence} = member
  meaning_calculation(action, world)

def work(work: D.Work, task: D.Task, world: M.World()) -> M.Decision():
  meaning(construct_work(work, task, world))

def work_consumer_correspondence_required(member: ConstructedWork()) -> M.Decision():
  Categories.Membership{Categories.Construction{+request, result}, evidence} = member
  WorkRequest{work, task, world} = request
  meaning_calculation(work_resolution(request), world)

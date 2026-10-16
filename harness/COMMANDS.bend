import Base
import ../bendlib/categories.bend as Categories
import ./features/STATE.bend as FeatureState
import ./features/resolution.bend as FeatureResolution
import ./features/operations.bend as FeatureOps
import ./features/SPEC.bend as FeatureSpec
import ./features/MODEL.bend as F
import ../bendlib/effects.bend as Effects
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ../bendlib/equality.bend as Same
import ./MODEL.bend as M
import ../bendlib/json.bend as J
import ./tasks/PROGRAM.bend as T
import ./execution/OPERATIONS.bend as Ops
import ./INVARIANTS.bend as I
import ../bendlib/stdlib.bend as Std
import ./workspace/WORKSPACE.bend as Workspace
import ./workspace/PROJECTS.bend as Projects
import ./transport/schema.bend as Schema
import ./approval/MODEL.bend as Approvals
import ./reasoning/context.bend as ReasoningContext
import ./reasoning/MODEL.bend as Reasoning

# A command denotes a resolved operation, not permission to make any safe change.
# Resolution owns every command precondition. The operation's meaning fixes the
# complete post-world, reply and effect list, before bounded scheduling/commit.
# The host cannot submit an Operation: only MODEL.Command crosses the wire.
type Operation is Data:
  ConfigureExecution{task: D.Task, configuration: D.ExecutionConfiguration}
  Refuse{code: String, reason: String}
  Start{profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection}
  Deliver{task: D.Task, message: String}
  Steer{task: D.Task, message: String}
  Cancel{task: D.Task, operation: D.Operation()}
  Control{task: D.Task, request: D.Control, next: D.Status}
  Branch{parent: D.Task, count: Nat, messages: +List<String>, selection: Workspace.Selection}
  Summarize{task: D.Task}
  Checkpoint{task: D.Task, summary: String}
  Observe{query: M.Query}
  StoreProject{project_id: Nat, project: D.Project, next_id: U32}
  RemoveProject{project_id: Nat}
  Review{resolution: Approvals.Resolution}
  FeatureOperation{operation: FeatureOps.Operation}

def admitted(operation: Operation) -> Bool:
  match operation:
    case Refuse{code, reason}: False{}
    case _: True{}

def entries(world: M.World()) -> +List<D.Task>:
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  tasks

def settings(world: M.World()) -> D.Environment:
  C.Frame{+task_state, +board} = world
  environment = D.state_environment(task_state)
  environment

def configured(environment: D.Environment) -> +List<D.Profile>:
  D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions} = environment
  profiles

def permitted_operation(-predicate: Operation -> Bool, member: Categories.Membership<Operation, Categories.holds(Operation, predicate)>) -> Operation:
  Categories.Membership{operation, evidence} = member
  operation

def operation_admission(-predicate: Operation -> Bool, result: Maybe<&1, Categories.Membership<Operation, Categories.holds(Operation, predicate)>>, code: String, reason: String) -> Operation:
  match result:
    case Some{member}: permitted_operation(predicate, member)
    case None{}: Refuse{code, reason}

def require(predicate: Operation -> Bool, operation: Operation, code: String, reason: String) -> Operation:
  operation_admission(predicate, Categories.admit(Operation, predicate, operation), code, reason)

def start_permitted(operation: Operation) -> Bool:
  match operation:
    case Start{profile, reasoning, message, selection}: D.profile_permitted(profile, reasoning) && D.nonempty(message)
    case _: False{}

def input_permitted(operation: Operation) -> Bool:
  match operation:
    case Deliver{task, message}: D.nonempty(message) && D.accepts_input(D.task_status(task))
    case Steer{task, message}: D.nonempty(message) && D.accepts_input(D.task_status(task))
    case _: False{}

def cancel_permitted(operation: Operation) -> Bool:
  match operation:
    case Cancel{task, action}: D.accepts_input(D.task_status(task))
    case _: False{}

def summary_permitted(operation: Operation) -> Bool:
  match operation:
    case Summarize{task}: Bool.not(D.operations_pending(D.task_operations(task)))
    case _: False{}

def checkpoint_permitted(operation: Operation) -> Bool:
  match operation:
    case Checkpoint{+task, text}:
      +context = D.context_history(D.task_history(task))
      Bool.not(D.operations_pending(D.task_operations(task))) && D.valid_summary(text) && I.settled_calls(context, context)
    case _: False{}

def task_selection(+task: D.Task) -> Workspace.Selection:
  Workspace.Selection{D.task_context(task), D.task_guidance(task)}

def environment_selection(environment: D.Environment) -> Workspace.Selection:
  D.Environment{catalog, profiles, max_fork, max_descendants, +guidance, plugins, instructions} = environment
  Workspace.Selection{Workspace.defaults(guidance), guidance}

def project_settings(base: Result<&2, &2, String, Workspace.Selection>, options: J.Json,
  profile: D.Profile, profiles: +List<D.Profile>) -> Result<&2, &2, String, Workspace.Selection>:
  match base:
    case Fail{reason}: Fail{reason}
    case Done{Workspace.Selection{context, guidance}}: Workspace.resolve(options, context, guidance, profile, profiles)

def selected_settings(+options: J.Json, base: Workspace.Selection, profile: D.Profile, +world: M.World()) -> Result<&2, &2, String, Workspace.Selection>:
  Workspace.Selection{context, guidance} = base
  project_settings(Projects.select(J.get(options, "project_id"), context, guidance, Projects.registry(F.State(), world)),
    options, profile, configured(settings(world)))

def start_selection(selection: Result<&2, &2, String, Workspace.Selection>, +profile: D.Profile,
  +reasoning: String, +message: String) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{selection}:
      require(start_permitted, Start{profile, reasoning, message, selection},
        "invalid_arguments", "Create requires a nonempty message and a permitted reasoning effort. Adaptive endpoints accept only auto.")

def selected(profile: Maybe<&2, D.Profile>, reasoning: String, message: String, options: J.Json, +world: M.World()) -> Operation:
  match profile:
    case None{}: Refuse{"unknown_profile", "Select a configured model profile"}
    case Some{+profile}:
      start_selection(selected_settings(options, environment_selection(settings(world)), profile, world),
        profile, D.profile_selection(reasoning, profile), message)

def branch_selection(selection: Result<&2, &2, String, Workspace.Selection>, parent: D.Task,
  count: Nat, messages: +List<String>) -> Operation:
  match selection:
    case Fail{reason}: Refuse{"invalid_settings", reason}
    case Done{selection}: Branch{parent, count, messages, selection}

def configure_branch(operation: Operation, options: J.Json, world: M.World()) -> Operation:
  match operation:
    case Branch{+parent, count, messages, base}:
      branch_selection(selected_settings(options, base, D.model_profile(D.task_model(parent)), world), parent, count, messages)
    case other: other

def selected_contract(selection: Workspace.Selection, contract: D.Contract) -> D.Contract:
  Workspace.Selection{context, guidance} = selection
  D.Contract{model, tools, max_fork, max_descendants, plugins, previous_context} = contract
  D.Contract{model, tools, max_fork, max_descendants, plugins, context}

def selected_execution(+selection: Workspace.Selection, +parent: D.Task) -> D.Task:
  +contract = selected_contract(selection, D.effective_contract(parent))
  D.with_execution(D.execution_configuration(contract), D.with_contract(contract, parent))

def record_selection(changed: Bool, +selection: Workspace.Selection, +parent: D.Task) -> D.Task:
  match changed:
    case False{}: selected_execution(selection, parent)
    case True{}:
      Workspace.Selection{+context, guidance} = selection
      +model = D.task_model(parent)
      D.append_context(D.TaskSettings{context, D.profile_key(D.model_profile(model)), D.model_selection(model)},
        D.append_context(D.ProjectGuidance{guidance}, selected_execution(selection, parent)))

def selected_parent(+selection: Workspace.Selection, +parent: D.Task) -> D.Task:
  Workspace.Selection{context, guidance} = selection
  record_selection(Bool.not(Same.project(guidance, D.task_guidance(parent)) &&
    Same.task_context(context, D.task_context(parent))), selection, parent)

def recipient(found: Maybe<&2, D.Task>, +message: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(input_permitted, Deliver{task, message},
        "invalid_arguments", "The message must be nonempty and the target must not be archived")

def steering(found: Maybe<&2, D.Task>, +message: String) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}:
      require(input_permitted, Steer{task, message},
        "invalid_arguments", "Steering requires a nonempty instruction and a nonarchived task")

def cancellable(found: Maybe<&2, D.Operation()>, +task: D.Task) -> Operation:
  match found:
    case None{}: Refuse{"operation_not_found", "The operation is not in flight for this task"}
    case Some{operation}:
      require(cancel_permitted, Cancel{task, operation}, "task_archived", "An archived task cannot be changed")

def cancellation(found: Maybe<&2, D.Task>, ticket: Nat) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: cancellable(Ops.find(D.task_operations(task), ticket), task)

def permitted(next: Maybe<&2, D.Status>, task: D.Task, request: D.Control) -> Operation:
  match next:
    case None{}: Refuse{"invalid_transition", "This lifecycle transition is not permitted"}
    case Some{status}: Control{task, request, status}

def controlled(found: Maybe<&2, D.Task>, +request: D.Control) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: permitted(D.control(D.task_status(task), request), task, request)

def per_fork(contract: D.Contract) -> Nat:
  D.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
  max_fork

def branch_count_valid(+count: Nat, parent: D.Task) -> Bool:
  Nat.is_le(1n, count) && Nat.is_le(count, per_fork(D.task_contract(parent)))

def branch_messages_valid(count: Nat, messages: +List<String>) -> Bool:
  +size = List.length(&2, String, messages)
  Nat.is_eq(size, 0n) || Nat.is_eq(size, count)

def branch_capacity_valid(+count: Nat, +parent: D.Task, world: M.World()) -> Bool:
  T.ancestors_fit(D.task_id(parent) <> D.task_lineage(parent), entries(world), count)

def branch_parent_valid(status: D.Status, phase: D.Phase) -> Bool:
  match status phase:
    case D.Active{} D.Idle{}: True{}
    case _ _: False{}

def branch_fits(+count: Nat, messages: +List<String>, +parent: D.Task, world: M.World()) -> Bool:
  branch_count_valid(count, parent) && branch_messages_valid(count, messages) && branch_capacity_valid(count, parent, world)

def branch_permitted(+world: M.World(), operation: Operation) -> Bool:
  match operation:
    case Branch{parent, count, messages, selection}: branch_fits(count, messages, parent, world)
    case _: False{}

def branch_ready_eligible(eligible: Bool, +parent: D.Task,
  +count: Nat, +messages: +List<String>, world: M.World()) -> Operation:
  match eligible:
    case True{}:
      require(operation => branch_permitted(world, operation), Branch{parent, count, messages, task_selection(parent)},
        "resource_limit", "Fork count, aligned messages, or an ancestor descendant limit is invalid")
    case False{}: Refuse{"task_busy", "A manual fork requires an active, idle task"}

def branch_ready(status: D.Status, phase: D.Phase, parent: D.Task,
  count: Nat, messages: +List<String>, world: M.World()) -> Operation:
  branch_ready_eligible(branch_parent_valid(status, phase), parent, count, messages, world)

def branched(found: Maybe<&2, D.Task>, count: Nat, messages: +List<String>, world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+parent}: branch_ready(D.task_status(parent), D.task_phase(parent), parent, count, messages, world)

def checkpoint_ready(status: D.Status, phase: D.Phase, +task: D.Task, summary: Maybe<&2, String>) -> Operation:
  match status phase summary:
    case D.Archived{} _ _: Refuse{"task_archived", "An archived task cannot be changed"}
    case D.Active{} D.Idle{} None{}:
      require(summary_permitted, Summarize{task},
        "task_busy", "Wait for in-flight operation results before summarizing the task")
    case _ D.Idle{} Some{+text}:
      require(checkpoint_permitted, Checkpoint{task, text},
        "invalid_summary", "A checkpoint requires a nonempty bounded summary, settled tool calls, and no in-flight operations")
    case _ _ _: Refuse{"task_busy", "Model compaction requires an active idle task; a supplied summary requires a nonarchived idle task"}

def compacted(found: Maybe<&2, D.Task>, summary: Maybe<&2, String>) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{+task}: checkpoint_ready(D.task_status(task), D.task_phase(task), task, summary)

def project_fields(+workspace: J.Json, +guidance: J.Json) -> Bool:
  (Workspace.absent(workspace) || Schema.valid(D.workspace_schema(), workspace)) &&
    (Workspace.absent(guidance) || Schema.valid(D.guidance_schema(), guidance))

def project_creation_permitted(+workspace: J.Json, +guidance: J.Json, +registry: D.Projects, operation: Operation) -> Bool:
  match operation:
    case StoreProject{id, project, next_id}:
      Schema.valid(D.workspace_schema(), workspace) && project_fields(workspace, guidance) && Projects.valid_project(project) &&
        Nat.is_lt(Projects.count(registry), 256n) && (Projects.next_word(registry) < 4294967295 : U32)
    case _: False{}

def project_update_permitted(+workspace: J.Json, +guidance: J.Json, operation: Operation) -> Bool:
  match operation:
    case StoreProject{id, project, next_id}: project_fields(workspace, guidance) && Projects.valid_project(project)
    case _: False{}

def project_removal_permitted(+world: M.World(), operation: Operation) -> Bool:
  match operation:
    case RemoveProject{+id}:
      Bool.not(Projects.missing(Projects.find(Projects.registry(F.State(), world), id))) && Nat.is_eq(Projects.task_count(entries(world), id), 0n) &&
        Bool.not(FeatureState.project_used(id, world))
    case _: False{}

def create_project(name: String, +workspace: J.Json, +guidance: J.Json, +world: M.World()) -> Operation:
  +project = Projects.proposal(Some{name}, workspace, guidance, D.Project{"", D.Workspace{Nil{}, None{}}, D.NoProject{}})
  +registry = Projects.registry(F.State(), world)
  +id = Projects.next_id(registry)
  require(operation => project_creation_permitted(workspace, guidance, registry, operation),
    StoreProject{id, project, (Projects.next_word(registry) + 1 : U32)}, "invalid_project", "A project requires a nonempty bounded name, valid workspace defaults, and available project capacity")

def update_project(found: Maybe<&2, D.Project>, id: Nat, name: Maybe<&2, String>, +workspace: J.Json,
  +guidance: J.Json, next_id: U32) -> Operation:
  match found:
    case None{}: Refuse{"project_not_found", "The project does not exist"}
    case Some{previous}:
      +project = Projects.proposal(name, workspace, guidance, previous)
      require(operation => project_update_permitted(workspace, guidance, operation), StoreProject{id, project, next_id},
        "invalid_project", "Project defaults require a valid name, workspace and matching guidance")

def delete_project(+id: Nat, +world: M.World()) -> Operation:
  require(operation => project_removal_permitted(world, operation),
    RemoveProject{id}, "project_not_empty", "The project must exist and have no tasks or board cards before it can be deleted")

def feature_start_result(operation: Operation) -> FeatureResolution.Start:
  match operation:
    case Start{profile, reasoning, message, selection}: FeatureResolution.Start{profile, reasoning, message, selection}
    case Refuse{code, reason}: FeatureResolution.StartRefused{code, reason}
    case _: FeatureResolution.InvalidStart{}

def feature_start(profile: String, reasoning: String, message: String, options: J.Json, +world: M.World()) -> FeatureResolution.Start:
  feature_start_result(selected(D.find_profile(configured(settings(world)), profile), reasoning, message, options, world))

def feature_result(resolution: FeatureResolution.Resolution) -> Operation:
  match resolution:
    case FeatureResolution.Refuse{code, reason}: Refuse{code, reason}
    case FeatureResolution.Accept{operation}: FeatureOperation{operation}

# Exhaustiveness is checked by Bend. Client schemas describe MODEL.Command;
# these clauses give each decoded constructor its operational meaning.

def configuration_lease(lease: Reasoning.Lease) -> Bool:
  match lease:
    case Reasoning.NoLease{}: True{}
    case _: False{}

def configuration_quiescent(+task: D.Task) -> Bool:
  D.task_execution_quiescent(task) &&
    configuration_lease(ReasoningContext.lease(D.task_history(task), D.task_id(task)))

def configuration_ready(allowed: Bool, task: D.Task, configuration: D.ExecutionConfiguration) -> Operation:
  match allowed:
    case True{}: ConfigureExecution{task, configuration}
    case False{}: Refuse{"task_busy", "Execution settings require an idle task without queued messages, outstanding operations, scheduled work or a reasoning lease"}

def configuration_policy(valid: Bool, +task: D.Task, configuration: D.ExecutionConfiguration) -> Operation:
  match valid:
    case False{}: Refuse{"invalid_policy", "Execution approval policy requires a configured, valid reviewer profile"}
    case True{}: configuration_ready(configuration_quiescent(task), task, configuration)

def configuration_reasoning(permitted: Bool, +task: D.Task, +profile: D.Profile, +reasoning: String, sandbox: D.Sandbox, +approval: D.ApprovalPolicy) -> Operation:
  match permitted:
    case False{}: Refuse{"invalid_reasoning", "Select a permitted reasoning effort for the execution profile"}
    case True{}:
      model : D.Model = D.Model{profile, reasoning}
      configuration_policy(Workspace.valid_approval(approval), task, D.ExecutionConfiguration{D.profile_key(profile), reasoning, model, sandbox, approval})

def configuration_profile(found: Maybe<&2, D.Profile>, task: D.Task, +reasoning: String, sandbox: D.Sandbox, approval: D.ApprovalPolicy) -> Operation:
  match found:
    case None{}: Refuse{"invalid_profile", "Select a configured model profile"}
    case Some{+profile}: configuration_reasoning(D.profile_valid(profile) && D.profile_permitted(profile, reasoning), task, profile, reasoning, sandbox, approval)

def configuration_review(found: Maybe<&2, D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match found:
    case None{}: Fail{"Approval reviewer is not configured"}
    case Some{profile}: Done{D.ApprovalForMe{profile}}

def configuration_approval(policy: D.ApprovalPolicy, profiles: +List<D.Profile>) -> Result<&2, &2, String, D.ApprovalPolicy>:
  match policy:
    case D.ApprovalForMe{profile}: configuration_review(D.find_profile(profiles, D.profile_key(profile)))
    case other: Done{other}

def configuration_reviewed(policy: Result<&2, &2, String, D.ApprovalPolicy>, task: D.Task, profile: String, reasoning: String, sandbox: D.Sandbox, world: M.World()) -> Operation:
  match policy:
    case Fail{reason}: Refuse{"invalid_policy", reason}
    case Done{approval}: configuration_profile(D.find_profile(configured(settings(world)), profile), task, reasoning, sandbox, approval)

def configure_execution(found: Maybe<&2, D.Task>, profile: String, reasoning: String, sandbox: D.Sandbox, approval: D.ApprovalPolicy, +world: M.World()) -> Operation:
  match found:
    case None{}: Refuse{"task_not_found", "The target task does not exist"}
    case Some{task}: configuration_reviewed(configuration_approval(approval, configured(settings(world))), task, profile, reasoning, sandbox, world)

def resolve(command: M.Command, +world: M.World()) -> Operation:
  match command:
    case M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}:
      configure_execution(T.find(entries(world), id), profile, reasoning, sandbox, approval, world)
    case M.Create{profile, reasoning, message, options}:
      selected(D.find_profile(configured(settings(world)), profile), reasoning, message, options, world)
    case M.Send{id, message}: recipient(T.find(entries(world), id), message)
    case M.Steer{id, message}: steering(T.find(entries(world), id), message)
    case M.Cancel{id, ticket}: cancellation(T.find(entries(world), id), ticket)
    case M.ChangeStatus{id, control}: controlled(T.find(entries(world), id), control)
    case M.Fork{id, count, messages, options}: configure_branch(branched(T.find(entries(world), id), count, messages, world), options, world)
    case M.Compact{id, summary}: compacted(T.find(entries(world), id), summary)
    case M.Observe{query}: Observe{query}
    case M.CreateProject{name, workspace, guidance}: create_project(name, workspace, guidance, world)
    case M.UpdateProject{+id, name, workspace, guidance}:
      update_project(Projects.find(Projects.registry(F.State(), world), id), id, name, workspace, guidance, Projects.next_word(Projects.registry(F.State(), world)))
    case M.DeleteProject{id}: delete_project(id, world)
    case M.ReviewApproval{id, operation, outcome}:
      Review{Approvals.resolution(F.State(), Approvals.construct_review(F.State(),
        Approvals.ReviewRequest{Approvals.HumanDecision{}, id, operation, outcome, world}))}
    case M.FeatureCommand{command}: feature_result(FeatureResolution.resolve(feature_start, command, world))

type ConfigurationTarget is Data:
  ConfigurationTarget{task: Nat, configuration: D.ExecutionConfiguration}

def configuration_target(operation: Operation) -> Maybe<&2, ConfigurationTarget>:
  match operation:
    case ConfigureExecution{task, configuration}: Some{ConfigurationTarget{D.task_id(task), configuration}}
    case _: None{}

def configuration_choose(target: Bool, configuration: D.ExecutionConfiguration, before: D.Task) -> D.ExecutionConfiguration:
  match target:
    case True{}: configuration
    case False{}: D.task_execution(before)

def configuration_expected(target: Maybe<&2, ConfigurationTarget>, +before: D.Task) -> D.ExecutionConfiguration:
  match target:
    case None{}: D.task_execution(before)
    case Some{ConfigurationTarget{id, configuration}}:
      configuration_choose(Nat.is_eq(id, D.task_id(before)), configuration, before)

def configuration_retained(before: +List<D.Task>, after: +List<D.Task>, +target: Maybe<&2, ConfigurationTarget>, +budget: Nat) -> Bool:
  match before after:
    case Nil{} _: True{}
    case Con{+before, rest_before} Con{+after, rest_after}:
      Nat.is_eq(D.task_id(before), D.task_id(after)) && Same.execution(budget, configuration_expected(target, before), D.task_execution(after)) &&
        configuration_retained(rest_before, rest_after, target, budget)
    case _ _: False{}

def configuration_input(input: M.Input, +before: M.World()) -> Maybe<&2, ConfigurationTarget>:
  match input:
    case M.UserCommand{M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}}:
      configuration_target(resolve(M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}, before))
    case _: None{}

# Provider continuation binds the complete current execution configuration.
# Unlike bounded persisted-state validation, this comparison cannot run out of fuel.
def configuration_session_same(left: D.ExecutionConfiguration, right: D.ExecutionConfiguration) -> Bool:
  match left right:
    case D.ExecutionConfiguration{profile_a, reasoning_a, model_a, D.Sandbox{mode_a, network_a}, approval_a} D.ExecutionConfiguration{profile_b, reasoning_b, model_b, D.Sandbox{mode_b, network_b}, approval_b}:
      String.eq(profile_a, profile_b) && String.eq(reasoning_a, reasoning_b) && Same.model(model_a, model_b) &&
        String.eq(D.sandbox_mode_name(mode_a), D.sandbox_mode_name(mode_b)) && Same.booleans(network_a, network_b) && Same.approval(approval_a, approval_b)

def configuration_changed(found: Maybe<&2, D.Task>, configuration: D.ExecutionConfiguration) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: Bool.not(configuration_session_same(D.task_execution(task), configuration))

def configuration_reset_required(target: Maybe<&2, ConfigurationTarget>, before: +List<D.Task>) -> Bool:
  match target:
    case None{}: False{}
    case Some{ConfigurationTarget{id, configuration}}: configuration_changed(T.find(before, id), configuration)

def configuration_reset_target(target: Maybe<&2, ConfigurationTarget>, id: Nat, before: +List<D.Task>) -> Bool:
  match target:
    case None{}: False{}
    case Some{ConfigurationTarget{+expected, configuration}}:
      Nat.is_eq(expected, id) && configuration_changed(T.find(before, expected), configuration)

def configuration_has_reset(effects: +List<M.Effect()>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{Effects.ResetModelSession{id}, rest}: True{}
    case Con{other, rest}: configuration_has_reset(rest)

def configuration_reset_effects(effects: +List<M.Effect()>, +target: Maybe<&2, ConfigurationTarget>, +before: +List<D.Task>) -> Bool:
  match effects:
    case Nil{}: True{}
    case Con{Effects.ResetModelSession{id}, +rest}:
      configuration_reset_target(target, id, before) && Bool.not(configuration_has_reset(rest)) && configuration_reset_effects(rest, target, before)
    case Con{other, rest}: configuration_reset_effects(rest, target, before)

def configuration_allowed(input: M.Input, +before: M.World(), candidate: M.Decision()) -> Bool:
  C.Decision{after, reply, +effects} = candidate
  +target = configuration_input(input, before)
  configuration_retained(entries(before), entries(after), target, D.state_render_budget(C.local(D.State, F.State(), before))) &&
    configuration_reset_effects(effects, target, entries(before)) &&
    Same.booleans(configuration_reset_required(target, entries(before)), configuration_has_reset(effects))

def id_result(id: Nat) -> J.Json:
  J.Object{[J.Field{"task_id", J.nat(id)}]}

def replace(task: D.Task, world: M.World()) -> M.World():
  T.update_world(F.State(), task, world)

def changed(id: Nat, task: D.Task, world: M.World(), effects: +List<M.Effect()>) -> M.Decision():
  C.Decision{replace(task, world), D.success(id_result(id)), effects}

def start_environment(profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection, world: M.World(), environment_value: D.Environment) -> M.Decision():
  match selection world environment_value:
    case Workspace.Selection{context, guidance} C.Frame{+task_state, +board} D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions}:
      tasks = D.state_tasks(task_state)
      +next_task = D.state_next_task(task_state)
      +contract : D.Contract = D.Contract{D.Model{profile, reasoning}, catalog, max_fork, max_descendants, plugins, context}
      task : D.Task = D.Task{next_task, Nil{}, contract, D.execution_configuration(contract),
        D.Active{}, D.EmptyHistory{}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}}
      task = D.initialize_history(instructions, guidance, message, task)
      C.Decision{C.Frame{D.with_state_next_task(1n+next_task, D.with_state_tasks(List.append(&2, D.Task, tasks, [task]), task_state)), board},
        D.success(id_result(next_task)), Nil{}}

def start(profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  start_environment(profile, reasoning, message, selection, world, D.state_environment(C.local(D.State, F.State(), world)))

def status_change(next: D.Status, +task: D.Task, world: M.World()) -> M.Decision():
  match next:
    case D.Archived{}:
      changed(D.task_id(task), T.archive(task), world, [Effects.CancelTask{D.task_id(task)}])
    case status: changed(D.task_id(task), T.promote(D.with_status(status, task)), world, Nil{})

def lifecycle(request: D.Control, next: D.Status, +task: D.Task, world: M.World()) -> M.Decision():
  match request:
    case D.Interrupt{}: changed(D.task_id(task), T.interrupt(task), world, [Effects.CancelTask{D.task_id(task)}])
    case _: status_change(next, task, world)

def initial_message(message: Maybe<&2, String>, history: D.History) -> D.History:
  match message:
    case None{}: history
    case Some{text}: D.HistoryNode{history, D.UserMessage{text}}

def child_selected(+id: Nat, +parent: D.Task, +contract: D.Contract, call_id: String, branch: Nat, remaining: +List<D.Attempt>, message: Maybe<&2, String>) -> D.Task:
  D.Task{id, D.task_id(parent) <> D.task_lineage(parent), contract, D.execution_configuration(contract), D.Active{},
    initial_message(message, D.child_history(Ops.inherited(parent), id, call_id, branch)), Nil{}, D.Ready{D.inherit_attempts(remaining)}, Nil{}, True{}}

def child(id: Nat, +parent: D.Task, call_id: String, branch: Nat, remaining: +List<D.Attempt>, message: Maybe<&2, String>) -> D.Task:
  child_selected(id, parent, D.effective_contract(parent), call_id, branch, remaining, message)

type Children is Data:
  Children{tasks: +List<D.Task>, next_id: Nat}

def prepend(task: D.Task, children: Children) -> Children:
  Children{rest, end} = children
  Children{task <> rest, end}

def children(count: Nat, +next_id: Nat, +branch: Nat, +parent: D.Task, +call_id: String,
  +remaining: +List<D.Attempt>, +messages: +List<String>) -> Children:
  match count:
    case 0n: Children{Nil{}, next_id}
    case 1n+p:
      prepend(child(next_id, parent, call_id, branch, remaining, List.head(&2, String, messages)),
        children(p, 1n+next_id, 1n+branch, parent, call_id, remaining, List.tail(&2, String, messages)))

def identity(task: D.Task) -> J.Json:
  J.nat(D.task_id(task))

def identities(tasks: +List<D.Task>) -> +List<J.Json>:
  Std.map(~D.Task, ~J.Json, ~identity, tasks)

def branch_call(ticket: Nat, count: Nat, messages: +List<String>) -> D.Call:
  D.Call{"manual-fork-" ++ Nat.show(ticket), "fork_task",
    J.Object{[J.Field{"child_count", J.nat(count)}, J.Field{"messages", J.Array{J.text_items(messages)}}]}}

def branch_commit(built: Children, +parent: D.Task, call_id: String, world: M.World()) -> M.Decision():
  Children{+spawned, end} = built
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  next_ticket = D.state_next_ticket(task_state)
  caller = T.promote(D.with_notified(True{}, D.with_phase(D.Ready{Nil{}}, D.with_history(D.branch_history(D.task_history(parent), call_id, 0n), parent))))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+next_ticket, D.with_state_next_task(end, D.with_state_tasks(List.append(&2, D.Task, T.replace(tasks, caller), spawned), task_state))), board},
    D.success(J.Object{[J.Field{"children", J.Array{identities(spawned)}}]}), Nil{}}

def branch(+task: D.Task, +count: Nat, +messages: +List<String>, selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  +next_task = D.state_next_task(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  +call = branch_call(next_ticket, count, messages)
  +parent = D.append_message(D.FunctionCall{call}, task)
  branch_commit(children(count, next_task, 1n, selected_parent(selection, parent), T.call_id(call), Nil{}, messages), parent, T.call_id(call), world)

def summarize(task: D.Task, world: M.World()) -> M.Decision():
  C.Frame{+task_state, +board} = world
  +task = D.append_message(D.UserMessage{D.summary_instructions()}, task)
  tasks = D.state_tasks(task_state)
  +next_ticket = D.state_next_ticket(task_state)
  next = D.with_notified(False{}, D.with_phase(D.SummaryPending{next_ticket, False{}}, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+next_ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), board}, D.success(id_result(D.task_id(task))),
    [Effects.RequestSummary{D.task_id(task), next_ticket, D.task_model(task), D.context_history(D.task_history(task)), D.task_context(task)}]}

def page_checked(valid: Bool, task: D.Task, after: Nat, limit: Nat) -> J.Json:
  match valid:
    case False{}: D.failure("invalid_page", "The page requires 1..100 messages and an offset on the task history")
    case True{}: D.success(T.page(task, after, limit))

def page(found: Maybe<&2, D.Task>, +after: Nat, +limit: Nat) -> J.Json:
  match found:
    case None{}: D.failure("task_not_found", "The target task does not exist")
    case Some{+task}:
      page_checked(Nat.is_le(1n, limit) && Nat.is_le(limit, 100n) && Nat.is_le(after, D.history_length(D.task_history(task))), task, after, limit)

def listing_environment(world: M.World(), environment_value: D.Environment) -> J.Json:
  match world environment_value:
    case C.Frame{+task_state, +board} D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins, instructions}:
      tasks = D.state_tasks(task_state)
      D.success(J.Object{[J.Field{"tasks", J.Array{T.summaries(tasks)}},
        J.Field{"profiles", J.Array{D.profiles_json(profiles)}}, J.Field{"tools", J.Array{D.tools_json(catalog)}},
        J.Field{"plugins", D.plugins_json(plugins)},
        J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]})

def listing(+world: M.World()) -> J.Json:
  listing_environment(world, D.state_environment(C.local(D.State, F.State(), world)))

def query(query: M.Query, +world: M.World()) -> J.Json:
  match query:
    case M.Read{id, after, limit}: page(T.find(entries(world), id), after, limit)
    case M.ListTasks{}: listing(world)
    case M.Describe{}: D.success(M.description())
    case M.ListProjects{}: D.success(J.Array{Projects.summaries(Projects.entries(Projects.registry(F.State(), world)), entries(world))})
    case M.ReadProject{+id}: Projects.detail(id, Projects.find(Projects.registry(F.State(), world), id))
    case M.FeatureQuery{query}: FeatureState.query(query, world)

def configuration_effects(same: Bool, id: Nat) -> +List<M.Effect()>:
  match same:
    case True{}: Nil{}
    case False{}: [Effects.ResetModelSession{id}]

def configured_history(same: Bool, +task: D.Task, configuration: D.ExecutionConfiguration) -> D.Task:
  match same:
    case True{}: D.with_execution(configuration, task)
    case False{}:
      +updated = D.with_execution(configuration, task)
      D.append_context(D.TaskSettings{D.task_context(updated), D.task_profile(updated), D.task_reasoning(updated)}, updated)

def configured_task(+task: D.Task, +configuration: D.ExecutionConfiguration, world: M.World()) -> M.Decision():
  changed(D.task_id(task), configured_history(configuration_session_same(D.task_execution(task), configuration), task, configuration), world,
    configuration_effects(configuration_session_same(D.task_execution(task), configuration), D.task_id(task)))

def meaning(operation: Operation, +world: M.World()) -> M.Decision():
  match operation:
    case ConfigureExecution{task, configuration}: configured_task(task, configuration, world)
    case Refuse{code, reason}: C.Decision{world, D.failure(code, reason), Nil{}}
    case Review{resolution}: Approvals.meaning_calculation(F.State(), F.Effect, resolution, world)
    case Start{profile, reasoning, message, selection}: start(profile, reasoning, message, selection, world)
    case FeatureOperation{operation}: FeatureSpec.meaning(start, operation, world)
    case Deliver{+task, message}:
      C.Decision{replace(T.receive(message, task), world), D.success(id_result(D.task_id(task))), Nil{}}
    case Steer{+task, message}:
      C.Decision{replace(T.steer(message, task), world), D.success(id_result(D.task_id(task))),
        T.steering_effects(F.Effect, D.task_phase(task), D.task_id(task))}
    case Cancel{+task, +operation}:
      C.Decision{replace(T.promote(Ops.cancelled(operation, task)), world),
        D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}, J.Field{"operation_id", J.nat(Ops.ticket(operation))}]}),
        [Effects.CancelTicket{D.task_id(task), Ops.callback(operation)}]}
    case Control{task, request, next}: lifecycle(request, next, task, world)
    case Branch{task, count, messages, selection}: branch(task, count, messages, selection, world)
    case Summarize{task}: summarize(task, world)
    case Checkpoint{+task, summary}:
      C.Decision{replace(D.append_message(D.ContextCheckpoint{summary}, task), world), D.success(id_result(D.task_id(task))), Nil{}}
    case Observe{request}: C.Decision{world, query(request, world), Nil{}}
    case StoreProject{+id, project, next_id}:
      C.Decision{Projects.store(F.State(), Projects.put(id, project, Projects.registry(F.State(), world), next_id), world),
        D.success(J.Object{[J.Field{"project_id", J.nat(id)}]}), Nil{}}
    case RemoveProject{+id}:
      C.Decision{Projects.store(F.State(), Projects.remove(id, Projects.registry(F.State(), world)), world),
        D.success(J.Object{[J.Field{"project_id", J.nat(id)}]}), Nil{}}

def command(+request: M.Command, +world: M.World()) -> M.Decision():
  meaning(resolve(request, world), world)


type CommandRequest is Data:
  CommandRequest{command: M.Command, world: M.World()}

def command_resolution(request: CommandRequest) -> Operation:
  CommandRequest{command, world} = request
  resolve(command, world)

def ConstructedCommand() -> Type:
  Categories.Membership<Categories.Construction<CommandRequest, Operation>,
    Categories.constructed_by(CommandRequest, Operation, command_resolution)>

def construct_command(command: M.Command, world: M.World()) -> ConstructedCommand():
  Categories.construct(CommandRequest, Operation, command_resolution, CommandRequest{command, world})

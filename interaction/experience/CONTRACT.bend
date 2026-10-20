import Base
import ../../harness/features/MODEL.bend as F
import ../../harness/features/STATE.bend as FeatureState
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/MODEL.bend as World
import ../../harness/COMMANDS.bend as Commands
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../features/board/MODEL.bend as Board
import ../../bendlib/json.bend as J
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./ACTIVITY.bend as Activity
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../harness/transport/schema.bend as Schema

def property_editor_meaning(property: M.Property) -> U.Editor:
  match property:
    case M.ProjectObservation{editor, selected, found}: editor
    case M.WorkspaceObservation{editor, observation, source}: editor
    case M.PermissionsObservation{editor, observation}: editor
    case M.ModelObservation{editor, profile, effort, found}: editor
    case M.DeliveryObservation{editor, delivery}: editor
def property_kind_meaning(property: M.Property) -> M.PropertyKind:
  match property:
    case M.ProjectObservation{editor, selected, found}: M.ProjectProperty{}
    case M.WorkspaceObservation{editor, observation, source}: M.WorkspaceProperty{}
    case M.PermissionsObservation{editor, observation}: M.PermissionsProperty{}
    case M.ModelObservation{editor, profile, effort, found}: M.ModelProperty{}
    case M.DeliveryObservation{editor, delivery}: M.DeliveryProperty{}
def property_state_meaning(property: M.Property) -> M.PropertyState:
  match property:
    case M.ProjectObservation{editor, selected, found}: P.project_state(selected, found)
    case M.WorkspaceObservation{editor, observation, source}: P.workspace_state(P.observed_workspace(observation))
    case M.PermissionsObservation{editor, observation}: P.observation_state(observation)
    case M.ModelObservation{editor, profile, effort, found}: P.model_state(found, effort)
    case M.DeliveryObservation{editor, delivery}: M.Selected{}
def property_value_meaning(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, selected, found}: P.project_value(selected, found)
    case M.WorkspaceObservation{editor, observation, source}: P.primary_value(P.observed_workspace(observation))
    case M.PermissionsObservation{editor, observation}: P.permission_value(observation)
    case M.ModelObservation{editor, profile, effort, found}: P.model_value(profile, found)
    case M.DeliveryObservation{editor, delivery}: U.delivery_caption(delivery)
def property_summary_meaning(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, selected, found}: P.project_value(selected, found)
    case M.WorkspaceObservation{editor, observation, source}: P.primary_value(P.observed_workspace(observation))
    case M.PermissionsObservation{editor, observation}: P.summary_parts_join(P.permission_property_parts(observation))
    case M.ModelObservation{editor, profile, effort, found}: P.model_value(profile, found) ++ " · " ++ effort
    case M.DeliveryObservation{editor, delivery}: U.delivery_caption(delivery)

def property_summary_parts_meaning(property: M.Property) -> +List<String>:
  match property:
    case M.ProjectObservation{editor, selected, found}: [P.project_value(selected, found)]
    case M.WorkspaceObservation{editor, observation, source}: [P.primary_value(P.observed_workspace(observation))]
    case M.PermissionsObservation{editor, observation}: P.permission_property_parts(observation)
    case M.ModelObservation{editor, profile, effort, found}: [P.model_value(profile, found) ++ " · " ++ effort]
    case M.DeliveryObservation{editor, delivery}: [U.delivery_caption(delivery)]

def property_detail_meaning(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, None{}, found}: "Optional"
    case M.ProjectObservation{editor, Some{id}, None{}}: "Invalid reference"
    case M.ProjectObservation{editor, Some{id}, Some{project}}: "Task context"
    case M.WorkspaceObservation{editor, observation, source}: P.workspace_detail(observation)
    case M.PermissionsObservation{editor, observation}: P.permission_detail(observation)
    case M.ModelObservation{editor, key, effort, found}: "Reasoning · " ++ effort
    case M.DeliveryObservation{editor, U.Send{}}: "Send a new message"
    case M.DeliveryObservation{editor, U.Steer{}}: "Guide the current task"
def property_source_key_meaning(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, selected, found}: "project/" ++ U.optional_key(selected)
    case M.WorkspaceObservation{editor, observation, source}: P.observation_source(observation)
    case M.PermissionsObservation{editor, observation}: P.permission_source_key(observation)
    case M.ModelObservation{editor, profile, effort, found}: "model/" ++ profile
    case M.DeliveryObservation{editor, delivery}: U.editor_key(editor)
def property_source_description_meaning(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, None{}, found}: "Environment defaults"
    case M.ProjectObservation{editor, Some{id}, None{}}: "The selected project is no longer available"
    case M.ProjectObservation{editor, Some{id}, Some{project}}: "Project configuration"
    case M.WorkspaceObservation{editor, observation, source}: P.workspace_detail(observation) ++ P.source_name(source)
    case M.PermissionsObservation{editor, observation}: P.permission_source_description(observation)
    case M.ModelObservation{editor, profile, effort, found}: P.model_source_description(editor)
    case M.DeliveryObservation{editor, delivery}: "Message delivery for this task"

def property_help_meaning(+property: M.Property) -> String:
  match property:
    case M.WorkspaceObservation{editor, +observation, source}:
      P.property_source_description(M.WorkspaceObservation{editor, observation, source}) ++ "\n" ++ P.workspace_paths(P.observed_workspace(observation))
    case M.PermissionsObservation{editor, +observation}:
      "Permissions: " ++ P.permission_value(observation) ++ " · " ++ P.permission_detail(observation) ++ "\n" ++ P.permission_source_detail(observation)
    case _: P.property_title(property) ++ ": " ++ P.property_value(property) ++ " · " ++ P.property_detail(property)

def permission_draft_source_meaning(origin: Context.Origin, sandbox: Context.SandboxValue, approval: Context.ApprovalValue) -> String:
  match origin sandbox approval:
    case Context.EnvironmentDefaults{} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ "environment" ++ ";approval/" ++ "environment"
    case Context.EnvironmentDefaults{} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ "environment" ++ ";approval/" ++ "custom"
    case Context.EnvironmentDefaults{} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ "environment"
    case Context.EnvironmentDefaults{} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ "custom"
    case Context.ProjectDefaults{id} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ "environment" ++ ";approval/" ++ "environment"
    case Context.ProjectDefaults{id} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ "environment" ++ ";approval/" ++ "custom"
    case Context.ProjectDefaults{id} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ "environment"
    case Context.ProjectDefaults{id} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ "custom"
    case Context.ParentTask{+task} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ ("task/" ++ Nat.show(task)) ++ ";approval/" ++ ("task/" ++ Nat.show(task))
    case Context.ParentTask{+task} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ ("task/" ++ Nat.show(task)) ++ ";approval/" ++ "custom"
    case Context.ParentTask{+task} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ ("task/" ++ Nat.show(task))
    case Context.ParentTask{+task} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ "custom"
    case Context.ProjectForParent{+task, id} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ ("task/" ++ Nat.show(task)) ++ ";approval/" ++ ("task/" ++ Nat.show(task))
    case Context.ProjectForParent{+task, id} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ ("task/" ++ Nat.show(task)) ++ ";approval/" ++ "custom"
    case Context.ProjectForParent{+task, id} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ ("task/" ++ Nat.show(task))
    case Context.ProjectForParent{+task, id} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: "sandbox/" ++ "custom" ++ ";approval/" ++ "custom"

def assessment_result_observation(result: M.AssessmentResult) -> (M.AssessmentState & +List<M.Obstruction>):
  match result:
    case M.PreparationReady{}: (M.Ready{}, Nil{})
    case M.DirectoryObservationRequired{}: (M.NeedsDirectoryObservation{}, Nil{})
    case M.PreparationBlocked{first, rest}: (M.Blocked{}, first <> rest)

type SharedRequirements is Type:
  SharedRequirements{
    project_lookup: @editor:U.Editor -> @+selected:Maybe<&2, Nat> -> @world:World.World() -> {P.project_property(editor, selected, world) == M.ProjectObservation{editor, selected, P.selected_project(selected, world)} : M.Property},
    workspace_lookup: @editor:U.Editor -> @+observation:Context.Observation -> @world:World.World() -> {P.workspace_property(editor, observation, world) == M.WorkspaceObservation{editor, observation, P.selected_project(P.observation_project(observation), world)} : M.Property},
    permissions_observation: @editor:U.Editor -> @observation:Context.Observation -> {P.permissions_property(editor, observation) == M.PermissionsObservation{editor, observation} : M.Property},
    model_lookup: @editor:U.Editor -> @+profile:String -> @effort:String -> @world:World.World() -> {P.model_property(editor, profile, effort, world) == M.ModelObservation{editor, profile, effort, D.find_profile(Commands.configured(Commands.settings(world)), profile)} : M.Property},
    delivery_observation: @editor:U.Editor -> @delivery:U.Delivery -> {P.delivery_property(editor, delivery) == M.DeliveryObservation{editor, delivery} : M.Property},
    property_editor: @+property:M.Property -> {P.property_editor(property) == property_editor_meaning(property) : U.Editor},
    property_kind: @+property:M.Property -> {P.property_kind(property) == property_kind_meaning(property) : M.PropertyKind},
    property_state: @+property:M.Property -> {P.property_state(property) == property_state_meaning(property) : M.PropertyState},
    property_value: @+property:M.Property -> {P.property_value(property) == property_value_meaning(property) : String},
    property_summary: @+property:M.Property -> {P.property_summary(property) == property_summary_meaning(property) : String},
    sandbox_summary_parts: @mode:D.SandboxMode -> @network:Bool -> @choice:Context.ApprovalChoice ->
      {P.sandbox_summary_parts(D.Sandbox{mode, network}, choice) == D.sandbox_mode_name(mode) <> List.append(&2, String, P.summary_network_parts(network), P.summary_approval_parts(choice)) : +List<String>},
    committed_unrestricted_parts: @sandbox:D.Sandbox -> @choice:Context.ApprovalChoice ->
      {P.committed_summary_parts(D.Unrestricted{}, sandbox, choice) == ["Full access", "Network available", "No approval"] : +List<String>},
    committed_sandboxed_parts: @sandbox:D.Sandbox -> @choice:Context.ApprovalChoice ->
      {P.committed_summary_parts(D.Sandboxed{}, sandbox, choice) == P.sandbox_summary_parts(sandbox, choice) : +List<String>},
    unavailable_permission_parts: @reason:String ->
      {P.permission_summary_parts(Context.DraftExecution{Context.ContextUnavailable{reason}}) == ["Unavailable"] : +List<String>},
    draft_permission_parts: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview ->
      {P.permission_summary_parts(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}) == P.preview_summary_access(Some{Context.approval_access(Context.observed_approval(approval))}, Context.unwrap_sandbox(sandbox), Context.observed_approval(approval)) : +List<String>},
    committed_permission_parts: @task:Nat -> @workspace:D.Workspace -> @+sandbox:D.Sandbox -> @+approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> -> @guidance:D.ProjectContext -> @+access:D.ExecutionAccess ->
      {P.permission_summary_parts(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}) == P.committed_summary_parts(access, sandbox, Context.approval_choice(approval)) : +List<String>},
    property_summary_parts: @+property:M.Property -> {P.property_summary_parts(property) == property_summary_parts_meaning(property) : +List<String>},
    summary_network_enabled: {P.summary_network_parts(True{}) == ["Network on"] : +List<String>},
    summary_network_disabled: {P.summary_network_parts(False{}) == Nil{} : +List<String>},
    summary_unrestricted: {P.summary_approval_parts(Context.Unrestricted{}) == ["Unrestricted"] : +List<String>},
    summary_ask: {P.summary_approval_parts(Context.Ask{}) == Nil{} : +List<String>},
    summary_review: @profile:String -> {P.summary_approval_parts(Context.AutomaticReview{profile}) == Nil{} : +List<String>},
    property_detail: @+property:M.Property -> {P.property_detail(property) == property_detail_meaning(property) : String},
    permission_draft_sources: @+editor:U.Editor -> @+origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview ->
      {P.property_source_key(P.permissions_property(editor, Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}})) == permission_draft_source_meaning(origin, sandbox, approval) : String},
    permission_committed_source: @editor:U.Editor -> @+task:Nat -> @context:D.TaskContext -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess ->
      {P.property_source_key(P.permissions_property(editor, Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}})) == "task/" ++ Nat.show(task) : String},
    property_source_description: @+property:M.Property -> {P.property_source_description(property) == property_source_description_meaning(property) : String},
    property_source_key: @+property:M.Property -> {P.property_source_key(property) == property_source_key_meaning(property) : String},
    property_help: @+property:M.Property -> {P.property_help(property) == property_help_meaning(property) : String},
    property_fields: @+property:M.Property -> {P.property_fields(property) == P.kind_fields(P.property_kind(property)) : +List<Forms.Field>},
    property_subjects: @+property:M.Property -> {P.property_subjects(property) == P.subjects(P.property_fields(property), P.property_editor(property)) : +List<M.Subject>},
    property_owner: @+property:M.Property -> {P.property_owner(property) == P.group_owner(P.property_editor(property), P.property_fields(property)) : M.Object},
    property_title: @+property:M.Property -> {P.property_title(property) == P.kind_title(P.property_kind(property)) : String},
    project_optional: @editor:U.Editor -> @world:World.World() -> {P.property_state(P.project_property(editor, None{}, world)) == M.Absent{} : M.PropertyState},
    project_invalid: @editor:U.Editor -> @id:Nat -> {P.property_state(M.ProjectObservation{editor, Some{id}, None{}}) == M.Invalid{} : M.PropertyState},
    project_none_caption: @editor:U.Editor -> @world:World.World() -> {P.property_value(P.project_property(editor, None{}, world)) == "No project" : String},
    permissions_tuple: @editor:U.Editor -> @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> {P.property_value(P.permissions_property(editor, Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}})) == P.sandbox_caption(Context.unwrap_sandbox(sandbox)) : String},
    workspace_entered: @editor:U.Editor -> @+origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:D.Workspace -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @source:Maybe<&2, D.Project> -> {P.property_detail(M.WorkspaceObservation{editor, Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.EnteredWorkspace{workspace}, sandbox, approval, guidance}}, source}) == P.override_detail(origin) : String},
    property_support: @+action:M.ActionUnit -> @+property:M.Property -> {P.property_support(action, property) == P.scoped_property_support(U.same_editor(P.action_editor(action), P.property_editor(property)), action, property) : M.Support},
    support_same: @action:M.ActionUnit -> @+property:M.Property -> {P.scoped_property_support(True{}, action, property) == P.support(action, P.property_fields(property)) : M.Support},
    support_mismatch: @action:M.ActionUnit -> @property:M.Property -> {P.scoped_property_support(False{}, action, property) == P.support(action, Nil{}) : M.Support},
    requirements: @+body:U.Body -> @pending:Bool -> @+world:World.World() -> {P.requirements(body, pending, world) == List.append(&2, M.Obstruction, P.failed_requirement(Bool.not(pending), M.Obstruction{P.root_object(U.owner(body)), None{}, "pending", "Wait for the current submission"}), List.append(&2, M.Obstruction, P.failed_requirement(U.valid_origin(body), P.obstruction(U.owner(body), Forms.ContextOrigin{}, "invalid_origin", "Choose a valid task context")), List.append(&2, M.Obstruction, P.context_requirements(body, world), List.append(&2, M.Obstruction, P.record_requirements(body, world), P.body_requirements(body, world))))) : +List<M.Obstruction>},
    can_prepare: @body:U.Body -> @pending:Bool -> @world:World.World() -> {P.can_prepare(body, pending, world) == P.requirements_empty(P.requirements(body, pending, world)) : Bool},
    assessment: @+body:U.Body -> @revision:Nat -> @pending:Bool -> @now:U32 -> @+world:World.World() -> {P.assess(body, revision, pending, now, world) == P.assessed_requirements(P.requirements(body, pending, world), body, revision, now, world) : M.Assessment},
    blocked_retains: @+first:M.Obstruction -> @+rest:+List<M.Obstruction> -> @body:U.Body -> @revision:Nat -> @now:U32 -> @world:World.World() -> {P.assessed_requirements(first <> rest, body, revision, now, world) == M.Assessment{M.ActionIdentity{U.owner(body), revision}, M.PreparationBlocked{first, rest}} : M.Assessment},
    directory_next: @workspace:D.Workspace -> @body:U.Body -> @revision:Nat -> @now:U32 -> @world:World.World() -> {P.prepared_assessment(Some{workspace}, body, revision, now, world) == M.Assessment{M.ActionIdentity{U.owner(body), revision}, M.DirectoryObservationRequired{}} : M.Assessment},
    actual_resolution: @+body:U.Body -> @+revision:Nat -> @now:U32 -> @world:World.World() -> {P.prepared_assessment(None{}, body, revision, now, world) == P.resolved_assessment(Commands.resolve(U.command(body, now), world), M.ActionIdentity{U.owner(body), revision}, U.owner(body)) : M.Assessment},
    actual_refusal: @+code:String -> @+reason:String -> @+identity:M.ActionIdentity -> @editor:U.Editor -> {P.resolved_assessment(Commands.Refuse{code, reason}, identity, editor) == M.Assessment{identity, M.PreparationBlocked{M.Obstruction{P.root_object(editor), None{}, code, reason}, Nil{}}} : M.Assessment},
    assessment_identity: @+identity:M.ActionIdentity -> @result:M.AssessmentResult -> {P.assessment_identity(M.Assessment{identity, result}) == identity : M.ActionIdentity},
    assessment_observation: @+identity:M.ActionIdentity -> @+result:M.AssessmentResult -> {(P.assessment_state(M.Assessment{identity, result}), P.assessment_obstructions(M.Assessment{identity, result})) == assessment_result_observation(result) : (M.AssessmentState & +List<M.Obstruction>)},
    assessment_reason: @+assessment:M.Assessment -> {P.assessment_reason(assessment) == P.first_reason(P.assessment_obstructions(assessment)) : String},
    assessment_field: @+assessment:M.Assessment -> {P.assessment_field(assessment) == P.first_field(P.assessment_obstructions(assessment)) : Maybe<&2, M.Subject>},
    assessment_ready: @+assessment:M.Assessment -> {P.assessment_ready(assessment) == P.state_ready(P.assessment_state(assessment)) : Bool},
    directory_ready: {P.state_ready(M.NeedsDirectoryObservation{}) == True{} : Bool},
    blocked_not_ready: {P.state_ready(M.Blocked{}) == False{} : Bool},
    new_task_content: @message:U.Text -> @+profile:String -> @+reasoning:String -> @context:Context.Configuration -> @+world:World.World() -> {P.body_requirements(U.NewTask{message, profile, reasoning, context, False{}, None{}}, world) == List.append(&2, M.Obstruction, P.failed_requirement(U.has_content(message), P.obstruction(U.NewTaskEditor{None{}}, Forms.MessageText{}, "empty_message", "Write a task to start")), P.model_requirements(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning, U.NewTaskEditor{None{}})) : +List<M.Obstruction>},
    message_content: @+task:Nat -> @message:U.Text -> @delivery:U.Delivery -> @world:World.World() -> {P.body_requirements(U.Message{task, message, delivery}, world) == P.failed_requirement(U.has_content(message), P.obstruction(U.MessageEditor{task}, Forms.MessageText{}, "empty_message", "Write a message to send")) : +List<M.Obstruction>},
    project_name: @+id:Maybe<&2, Nat> -> @name:String -> @workspace:D.Workspace -> @world:World.World() -> {P.body_requirements(U.Project{id, name, workspace, False{}}, world) == P.failed_requirement(Projects.name_valid(name), P.obstruction(U.ProjectEditor{id}, Forms.ProjectName{}, "invalid_project_name", "Enter a project name of at most 256 UTF-8 bytes")) : +List<M.Obstruction>},
    agent_guard: @revision:Nat -> @+name:String -> @+profile:String -> @+reasoning:String -> @+instructions:String -> @settings:J.Json -> @+concurrency:Nat -> {Board.valid_agent(Board.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}) == Board.agent_name_valid(name) && Board.agent_profile_valid(profile) && Board.agent_reasoning_valid(reasoning) && Board.agent_instructions_valid(instructions) && Board.agent_concurrency_valid(concurrency) : Bool},
    fork_guard: @+count:Nat -> @+messages:+List<D.UserContent> -> @+parent:D.Task -> @+world:World.World() -> {Commands.branch_fits(count, messages, parent, world) == FeatureState.execution_allowed(D.task_id(parent), world) && Commands.branch_count_valid(count, parent) && Commands.branch_messages_valid(count, messages) && Commands.branch_capacity_valid(count, parent, world) : Bool},
    lookup_selected: @+id:Nat -> @world:World.World() -> {P.selected_project(Some{id}, world) == Projects.find(Projects.registry(F.State(), world), id) : Maybe<&2, D.Project>},
    project_name_guard: @+name:String -> {Projects.name_valid(name) == D.nonempty(name) && Nat.is_le(J.utf8_length(name), 256n) : Bool},
    agent_name_valid: @+name:String -> {Board.agent_name_valid(name) == D.nonempty(name) && Board.limited(name, 160n) : Bool},
    agent_profile_valid: @+profile:String -> {Board.agent_profile_valid(profile) == D.nonempty(profile) && Board.limited(profile, 1024n) : Bool},
    agent_reasoning_valid: @+reasoning:String -> {Board.agent_reasoning_valid(reasoning) == D.nonempty(reasoning) && Board.limited(reasoning, 64n) : Bool},
    agent_instructions_valid: @+instructions:String -> {Board.agent_instructions_valid(instructions) == Board.limited(instructions, 100000n) : Bool},
    agent_concurrency_valid: @+count:Nat -> {Board.agent_concurrency_valid(count) == Nat.is_le(1n, count) && Nat.is_le(count, 64n) : Bool},
    branch_count_guard: @+count:Nat -> @+parent:D.Task -> {Commands.branch_count_valid(count, parent) == Nat.is_le(1n, count) && Nat.is_le(count, Commands.per_fork(D.task_contract(parent))) : Bool},
    branch_messages_guard: @+count:Nat -> @+messages:+List<D.UserContent> -> {Commands.branch_messages_valid(count, messages) == (Nat.is_eq(List.length(&2, D.UserContent, messages), 0n) || Nat.is_eq(List.length(&2, D.UserContent, messages), count)) && D.contents_valid(messages) : Bool},
    branch_capacity_guard: @+count:Nat -> @+parent:D.Task -> @world:World.World() -> {Commands.branch_capacity_valid(count, parent, world) == Tasks.ancestors_fit(D.task_id(parent) <> D.task_lineage(parent), Commands.entries(world), count) : Bool},
    context_failure: @+editor:U.Editor -> @+reason:String -> {P.origin_failure(Context.ContextUnavailable{reason}, editor) == [P.obstruction(editor, Forms.ContextOrigin{}, "context_unavailable", reason)] : +List<M.Obstruction>},
    model_missing: @effort:String -> @+editor:U.Editor -> {P.model_requirements(None{}, effort, editor) == [P.obstruction(editor, Forms.ModelProfile{}, "model_not_found", "Choose a configured model")] : +List<M.Obstruction>},
    model_permitted: @+profile:D.Profile -> @+effort:String -> @+editor:U.Editor -> {P.model_requirements(Some{profile}, effort, editor) == P.failed_requirement(D.profile_permitted(profile, D.profile_selection(effort, profile)), P.obstruction(editor, Forms.ReasoningEffort{}, "invalid_reasoning", "Choose an allowed reasoning effort")) : +List<M.Obstruction>},
    project_record: @+id:Maybe<&2, Nat> -> @name:String -> @workspace:D.Workspace -> @world:World.World() -> {P.record_requirements(U.Project{id, name, workspace, False{}}, world) == P.failed_requirement(Projects.reference_valid(id, Projects.registry(F.State(), world)), M.Obstruction{P.root_object(U.ProjectEditor{id}), None{}, "project_not_found", "The project does not exist"}) : +List<M.Obstruction>},
    agent_record: @+editor:U.Editor -> {P.agent_reference_requirement(None{}, editor) == [M.Obstruction{P.root_object(editor), None{}, "agent_not_found", "The agent does not exist"}] : +List<M.Obstruction>},
    obstruction_failure: @+obstruction:M.Obstruction -> {P.failed_requirement(False{}, obstruction) == [obstruction] : +List<M.Obstruction>},
    obstruction_pass: @obstruction:M.Obstruction -> {P.failed_requirement(True{}, obstruction) == Nil{} : +List<M.Obstruction>},
    obstruction_target: @+target:M.Object -> @+field:Maybe<&2, M.Subject> -> @+code:String -> @+message:String -> {P.obstruction_target(M.Obstruction{target, field, code, message}) == target : M.Object},
    obstruction_field: @+target:M.Object -> @+field:Maybe<&2, M.Subject> -> @+code:String -> @+message:String -> {P.obstruction_field(M.Obstruction{target, field, code, message}) == field : Maybe<&2, M.Subject>},
    obstruction_code: @+target:M.Object -> @+field:Maybe<&2, M.Subject> -> @+code:String -> @+message:String -> {P.obstruction_code(M.Obstruction{target, field, code, message}) == code : String},
    obstruction_message: @+target:M.Object -> @+field:Maybe<&2, M.Subject> -> @+code:String -> @+message:String -> {P.obstruction_message(M.Obstruction{target, field, code, message}) == message : String},
    restricted_identity: @+assessment:M.Assessment -> @reason:String -> {P.assessment_identity(P.restricted(assessment, reason)) == P.assessment_identity(assessment) : M.ActionIdentity},
    restricted_obstructions: @+assessment:M.Assessment -> @+reason:String -> {P.assessment_obstructions(P.restricted(assessment, reason)) == P.restriction_obstructions(assessment, reason) : +List<M.Obstruction>},
    restricted_state: @assessment:M.Assessment -> @reason:String -> {P.assessment_state(P.restricted(assessment, reason)) == M.Blocked{} : M.AssessmentState},
    restricted_first_reason: @+assessment:M.Assessment -> @+reason:String -> {P.assessment_reason(P.restricted(assessment, reason)) == P.first_reason(P.restriction_obstructions(assessment, reason)) : String},
    restriction_append: @+assessment:M.Assessment -> @+reason:String -> {P.restriction_obstructions(assessment, reason) == List.append(&2, M.Obstruction, P.assessment_obstructions(assessment), [M.Obstruction{P.root_object(P.identity_editor(P.assessment_identity(assessment))), None{}, "control_unavailable", reason}]) : +List<M.Obstruction>}
  }

type Requirements is Type:
  Requirements{
    admission_subject: @+subject:M.Subject -> @observation:Forms.Observed -> @question:String -> @alternatives:+List<M.Alternative> ->
      {P.decision_subject(P.decision(subject, observation, question, alternatives)) == subject : M.Subject},
    admission_observation: @subject:M.Subject -> @+observation:Forms.Observed -> @question:String -> @alternatives:+List<M.Alternative> ->
      {P.decision_observation(P.decision(subject, observation, question, alternatives)) == observation : Forms.Observed},
    admission_question: @subject:M.Subject -> @observation:Forms.Observed -> @+question:String -> @alternatives:+List<M.Alternative> ->
      {P.decision_question(P.decision(subject, observation, question, alternatives)) == question : String},
    admission_options: @+subject:M.Subject -> @+observation:Forms.Observed -> @question:String -> @+alternatives:+List<M.Alternative> ->
      {P.decision_alternatives(P.decision(subject, observation, question, alternatives)) == P.admitted_alternatives(P.admissible(alternatives, subject, observation, Nil{}) && P.alternatives_present(alternatives), alternatives) : +List<M.Alternative>},
    admission_status: @+subject:M.Subject -> @+observation:Forms.Observed -> @question:String -> @+alternatives:+List<M.Alternative> ->
      {P.decision_availability(P.decision(subject, observation, question, alternatives)) == P.decision_status(P.admissible(alternatives, subject, observation, Nil{}), P.alternatives_present(alternatives)) : M.Availability},
    empty_status: @subject:M.Subject -> @observation:Forms.Observed -> @question:String -> {P.decision_availability(P.decision(subject, observation, question, Nil{})) == M.Unavailable{"No alternatives are available"} : M.Availability},
    empty_choice: @subject:M.Subject -> @observation:Forms.Observed -> @question:String -> @candidate:M.Value -> {P.choose(P.decision(subject, observation, question, Nil{}), candidate) == None{} : Maybe<&2, U.Input>},
    duplicate_rejection: @compatible:Bool -> @rest:Bool -> {P.admitted_candidate(compatible, True{}, rest) == False{} : Bool},
    incompatible_rejection: @duplicate:Bool -> @rest:Bool -> {P.admitted_candidate(False{}, duplicate, rest) == False{} : Bool},
    duplicate_input: @label:String -> @explanation:String -> @+value:M.Value -> @rest:+List<M.Alternative> -> @subject:M.Subject -> @observation:Forms.Observed -> @+seen:+List<String> ->
      {P.admissible(M.Alternative{label, explanation, value} <> rest, subject, observation, P.value_key(value) <> seen) == False{} : Bool},
    lookup_identity: @label:String -> @explanation:String -> @+value:M.Value -> @rest:+List<M.Alternative> -> @+candidate:M.Value ->
      {P.admitted_value(M.Alternative{label, explanation, value} <> rest, candidate) == P.matching_value(P.value_same(value, candidate), value, P.admitted_value(rest, candidate)) : Maybe<&2, M.Value>},
    rejection_options: @values:+List<M.Alternative> -> {P.admitted_alternatives(False{}, values) == Nil{} : +List<M.Alternative>},
    rejection_status: {P.admission_availability(False{}) == M.Unavailable{"Alternatives are incompatible with this property or contain duplicate values"} : M.Availability},
    option_admission: @label:String -> @explanation:String -> @+value:M.Value -> @rest:+List<M.Alternative> -> @+subject:M.Subject -> @+observation:Forms.Observed -> @+seen:+List<String> ->
      {P.admissible(M.Alternative{label, explanation, value} <> rest, subject, observation, seen) == P.admitted_candidate(P.has_intent(P.canonical(subject, observation, value)), Schema.contains(seen, P.value_key(value)), P.admissible(rest, subject, observation, P.value_key(value) <> seen)) : Bool},
    selected_observation: @+decision:M.Decision -> @+candidate:M.Value ->
      {P.selected(decision, candidate) == P.observed_selection(subject_field(P.decision_subject(decision)), P.decision_observation(decision), candidate) : Bool},
    choose_membership: @+decision:M.Decision -> @+candidate:M.Value ->
      {P.choose(decision, candidate) == P.choose_admitted(P.admitted_value(P.decision_alternatives(decision), candidate), P.decision_subject(decision), P.decision_observation(decision)) : Maybe<&2, U.Input>},
    choose_missing: @subject:M.Subject -> @observation:Forms.Observed -> {P.choose_admitted(None{}, subject, observation) == None{} : Maybe<&2, U.Input>},
    choose_present: @+subject:M.Subject -> @+observation:Forms.Observed -> @+value:M.Value -> {P.choose_admitted(Some{value}, subject, observation) == P.canonical(subject, observation, value) : Maybe<&2, U.Input>},
    scope_admission: @+editor:U.Editor -> @+field:Forms.Field -> @+observation:Forms.Observed -> @+value:M.Value ->
      {P.scoped_intent(editor, field, observation, value) == P.workspace_scope(P.editable_property(editor, field), P.property_intent(field, observation, value)) : Maybe<&2, U.Edit>},
    scope_rejection: @intent:Maybe<&2, U.Edit> -> {P.workspace_scope(False{}, intent) == None{} : Maybe<&2, U.Edit>},
    canonical_target: @+editor:U.Editor -> @+field:Forms.Field -> @+observation:Forms.Observed -> @+value:M.Value ->
      {P.canonical(M.Subject{editor, field}, observation, value) == P.bind_editor(editor, P.scoped_intent(editor, field, observation, value)) : Maybe<&2, U.Input>},
    task_draft_key: {P.object_key(M.TaskDraft{}) == "task-draft" : String},
    task_key: @+task:Nat -> {P.object_key(M.Task{task}) == "task/" ++ Nat.show(task) : String},
    project_key: @+project:Maybe<&2, Nat> -> {P.object_key(M.Project{project}) == "project/" ++ U.optional_key(project) : String},
    message_draft_key: @+task:Nat -> {P.object_key(M.MessageDraft{task}) == "message-draft/" ++ Nat.show(task) : String},
    editor_object_key: @+editor:U.Editor -> {P.object_key(M.EditorObject{editor}) == "editor/" ++ U.editor_key(editor) : String},
    workspace_key: @+editor:U.Editor -> {P.object_key(M.WorkspaceOf{editor}) == "workspace/" ++ U.editor_key(editor) : String},
    execution_configuration_key: @+editor:U.Editor -> {P.object_key(M.ExecutionConfigurationOf{editor}) == "execution-configuration/" ++ U.editor_key(editor) : String},
    subject_key: @+editor:U.Editor -> @+field:Forms.Field -> {P.subject_key(M.Subject{editor, field}) == P.object_key(P.owner(M.Subject{editor, field})) ++ "/" ++ Forms.key(field) : String},
    action_key: @+editor:U.Editor -> @+revision:Nat -> {P.action_key(M.ActionIdentity{editor, revision}) == U.editor_key(editor) ++ "/" ++ Nat.show(revision) : String},
    empty_group_owner: @+editor:U.Editor -> {P.group_owner(editor, Nil{}) == P.root_object(editor) : M.Object},
    group_owner_head: @+editor:U.Editor -> @+first:Forms.Field -> @+rest:+List<Forms.Field> ->
      {P.group_owner(editor, first <> rest) == P.resolved_group_owner(P.same_group_owner(rest, editor, P.owner(M.Subject{editor, first})), P.owner(M.Subject{editor, first}), editor) : M.Object},
    empty_owner_fold: @editor:U.Editor -> @object:M.Object -> {P.same_group_owner(Nil{}, editor, object) == True{} : Bool},
    owner_fold_step: @+editor:U.Editor -> @field:Forms.Field -> @+rest:+List<Forms.Field> -> @+object:M.Object ->
      {P.same_group_owner(field <> rest, editor, object) == String.eq(P.object_key(P.owner(M.Subject{editor, field})), P.object_key(object)) && P.same_group_owner(rest, editor, object) : Bool},
    common_group_owner: @+object:M.Object -> @editor:U.Editor -> {P.resolved_group_owner(True{}, object, editor) == object : M.Object},
    mixed_group_owner: @object:M.Object -> @+editor:U.Editor -> {P.resolved_group_owner(False{}, object, editor) == P.root_object(editor) : M.Object},
    creation_root: {P.root_object(U.NewTaskEditor{None{}}) == M.TaskDraft{} : M.Object},
    task_root: @+task:Nat -> {P.root_object(U.MessageEditor{task}) == M.Task{task} : M.Object},
    project_root: @+project:Maybe<&2, Nat> -> {P.root_object(U.ProjectEditor{project}) == M.Project{project} : M.Object},
    task_message_owner: @+task:Nat -> {P.owner(M.Subject{U.MessageEditor{task}, Forms.MessageText{}}) == M.MessageDraft{task} : M.Object},
    model_owner: @+editor:U.Editor -> {P.owner(M.Subject{editor, Forms.ModelProfile{}}) == M.ExecutionConfigurationOf{editor} : M.Object},
    workspace_owner: @+editor:U.Editor -> {P.owner(M.Subject{editor, Forms.WorkspaceDirectories{}}) == M.WorkspaceOf{editor} : M.Object},
    configuration_parent: @+editor:U.Editor -> {P.parent(M.ExecutionConfigurationOf{editor}) == Some{P.root_object(editor)} : Maybe<&2, M.Object>},
    property_filesystem: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+mode:D.SandboxMode -> @+reviewers:+List<D.Profile> ->
      {P.property_intent(Forms.SandboxMode{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Filesystem{mode}) == P.filesystem_intent(Context.unwrap_sandbox(sandbox), mode) : Maybe<&2, U.Edit>},
    property_network: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+enabled:Bool -> @+reviewers:+List<D.Profile> ->
      {P.property_intent(Forms.NetworkAccess{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Network{enabled}) == P.network_intent(Context.unwrap_sandbox(sandbox), enabled) : Maybe<&2, U.Edit>},
    property_approval: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+choice:Context.ApprovalChoice -> @+reviewers:+List<D.Profile> ->
      {P.property_intent(Forms.ApprovalPolicy{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Approval{choice}) == P.approval_intent(choice, reviewers) : Maybe<&2, U.Edit>},
    selected_filesystem: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+mode:D.SandboxMode -> @+reviewers:+List<D.Profile> ->
      {P.observed_selection(Forms.SandboxMode{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Filesystem{mode}) == P.filesystem_selected(Context.unwrap_sandbox(sandbox), mode) : Bool},
    selected_network: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+network:Bool -> @+reviewers:+List<D.Profile> ->
      {P.observed_selection(Forms.NetworkAccess{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Network{network}) == P.network_selected(Context.unwrap_sandbox(sandbox), network) : Bool},
    selected_approval: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+choice:Context.ApprovalChoice -> @+reviewers:+List<D.Profile> ->
      {P.observed_selection(Forms.ApprovalPolicy{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Approval{choice}) == P.value_same(M.Approval{Context.observed_approval(approval)}, M.Approval{choice}) : Bool},
    selected_model: @+current:String -> @effort:String -> @+key:String -> @provider:String -> @name:String -> @policy:Reasoning.Policy -> @options:Maybe<&2, D.ReasoningOptions> ->
      {P.observed_selection(Forms.ModelProfile{}, Forms.ModelValue{current, effort}, M.Model{D.Profile{key, provider, name, policy, options}}) == String.eq(current, key) : Bool},
    selected_effort: @profile:String -> @+current:String -> @+effort:String -> {P.observed_selection(Forms.ReasoningEffort{}, Forms.ModelValue{profile, current}, M.Effort{effort}) == String.eq(current, effort) : Bool},
    selected_primary: @roots:+List<String> -> @+primary:String -> @+path:String -> {P.observed_selection(Forms.WorkspacePrimary{}, Forms.WorkspaceValue{D.Workspace{roots, Some{primary}}}, M.PrimaryDirectory{path}) == String.eq(primary, path) : Bool},
    mismatch_intent: @observation:Forms.Observed -> @value:M.Value -> {P.property_intent(Forms.MessageText{}, observation, value) == None{} : Maybe<&2, U.Edit>},
    mismatch_selection: @observation:Forms.Observed -> @value:M.Value -> {P.observed_selection(Forms.MessageText{}, observation, value) == False{} : Bool},
    filesystem_preserves_network: @old:D.SandboxMode -> @+network:Bool -> @+mode:D.SandboxMode ->
      {P.filesystem_intent(D.Sandbox{old, network}, mode) == Some{U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}} : Maybe<&2, U.Edit>},
    network_preserves_filesystem: @+mode:D.SandboxMode -> @old:Bool -> @+network:Bool ->
      {P.network_intent(D.Sandbox{mode, old}, network) == Some{U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}} : Maybe<&2, U.Edit>},
    model_permitted: @+profile:D.Profile -> @+effort:String ->
      {P.model_intent(profile, effort) == P.permitted_model(D.profile_permitted(profile, P.model_effort(D.profile_permitted(profile, effort), effort, profile)), profile_key(profile), P.model_effort(D.profile_permitted(profile, effort), effort, profile)) : Maybe<&2, U.Edit>},
    effort_preserves_model: @+profile:String -> @old:String -> @+effort:String ->
      {P.property_intent(Forms.ReasoningEffort{}, Forms.ModelValue{profile, old}, M.Effort{effort}) == Some{U.ChooseModel{profile, effort}} : Maybe<&2, U.Edit>},
    primary_requires_membership: @+roots:+List<String> -> @primary:Maybe<&2, String> -> @+path:String ->
      {P.property_intent(Forms.WorkspacePrimary{}, Forms.WorkspaceValue{D.Workspace{roots, primary}}, M.PrimaryDirectory{path}) == P.member_edit(Schema.contains(roots, path), U.EditWorkspace{Context.ChoosePrimary{path}}) : Maybe<&2, U.Edit>},
    task_workspace_readonly: @task:Nat -> @observation:Forms.Observed -> @value:M.Value ->
      {P.scoped_intent(U.MessageEditor{task}, Forms.WorkspacePrimary{}, observation, value) == None{} : Maybe<&2, U.Edit>},
    task_creation_readonly: @task:Nat -> @observation:Forms.Observed -> @value:M.Value ->
      {P.scoped_intent(U.MessageEditor{task}, Forms.ContextOrigin{}, observation, value) == None{} : Maybe<&2, U.Edit>},
    collection_observation: @editor:U.Editor -> @+workspace:D.Workspace -> {P.collection_workspace(P.collection(editor, workspace)) == workspace : D.Workspace},
    collection_owner: @+editor:U.Editor -> @workspace:D.Workspace -> {P.collection_editor(P.collection(editor, workspace)) == editor : U.Editor},
    collection_members: @editor:U.Editor -> @+workspace:D.Workspace -> {P.collection_members(P.collection(editor, workspace)) == Workspace.roots(workspace) : +List<String>},
    collection_primary: @editor:U.Editor -> @+workspace:D.Workspace -> @+path:String -> {P.is_primary(P.collection(editor, workspace), path) == P.primary_matches(Workspace.primary(workspace), path) : Bool},
    primary_reference: @+editor:U.Editor -> @+workspace:D.Workspace ->
      {P.primary_decision(P.collection(editor, workspace)) == P.decision(M.Subject{editor, Forms.WorkspacePrimary{}}, Forms.WorkspaceValue{workspace}, "Primary working directory", P.primary_alternatives(Workspace.roots(workspace))) : M.Decision},
    choose_primary: @+collection:M.Collection -> @+path:String -> {P.choose_primary(collection, path) == P.choose(P.primary_decision(collection), M.PrimaryDirectory{path}) : Maybe<&2, U.Input>},
    remove_membership: @+editor:U.Editor -> @+workspace:D.Workspace -> @+path:String ->
      {P.remove_member(P.collection(editor, workspace), path) == P.bind_editor(editor, P.member_edit(P.editable_workspace(editor) && Schema.contains(Workspace.roots(workspace), path), U.EditWorkspace{Context.RemoveRoot{path}})) : Maybe<&2, U.Input>},
    action_editor: @+editor:U.Editor -> @revision:Nat -> @pending:Bool -> {P.action_editor(P.action(editor, revision, pending)) == editor : U.Editor},
    action_pending: @editor:U.Editor -> @revision:Nat -> @+pending:Bool -> {P.action_pending(P.action(editor, revision, pending)) == pending : Bool},
    action_identity: @+editor:U.Editor -> @+revision:Nat -> @pending:Bool -> {P.identity(P.action(editor, revision, pending)) == M.ActionIdentity{editor, revision} : M.ActionIdentity},
    action_content: @+editor:U.Editor -> @revision:Nat -> @pending:Bool -> {P.content_subject(P.action(editor, revision, pending)) == M.Subject{editor, P.content_field(editor)} : M.Subject},
    action_commit: @+editor:U.Editor -> @revision:Nat -> @pending:Bool -> {P.commit(P.action(editor, revision, pending)) == U.Activate{U.Submit{editor}} : U.Input},
    action_context: @+editor:U.Editor -> @revision:Nat -> @pending:Bool -> {P.action_context(P.action(editor, revision, pending)) == P.editor_context(editor) : M.ActionContext},
    support_identity: @+editor:U.Editor -> @+revision:Nat -> @pending:Bool -> @fields:+List<Forms.Field> -> {P.support_identity(P.support(P.action(editor, revision, pending), fields)) == M.ActionIdentity{editor, revision} : M.ActionIdentity},
    support_scope: @+editor:U.Editor -> @revision:Nat -> @pending:Bool -> @+fields:+List<Forms.Field> -> {P.support_fields(P.support(P.action(editor, revision, pending), fields)) == P.permitted_support(fields, P.editor_context(editor)) : +List<Forms.Field>},
    support_subjects: @+support:M.Support -> {P.support_subjects(support) == P.subjects(P.support_fields(support), identity_editor(P.support_identity(support))) : +List<M.Subject>},
    creation_support: @+field:Forms.Field -> {P.support_field(M.Creation{}, field) == P.configuration_field(field) || P.workspace_field(field) || P.creation_field(field) : Bool},
    continuation_support: @task:Nat -> @+field:Forms.Field -> {P.support_field(M.Continuation{task}, field) == P.configuration_field(field) || P.delivery_field(field) : Bool},
    object_support: @field:Forms.Field -> {P.support_field(M.ObjectEditing{}, field) == False{} : Bool},
    continuation_excludes_workspace: @task:Nat -> {P.support_field(M.Continuation{task}, Forms.WorkspaceDirectories{}) == False{} : Bool},
    creation_excludes_delivery: {P.support_field(M.Creation{}, Forms.DeliveryIntent{}) == False{} : Bool},
    shared: SharedRequirements,
    feedback_retention: @+editor:U.Editor -> @+revision:Nat -> @+reason:String -> {P.feedback(editor, U.Rejected{revision, reason}) == Some{M.Feedback{editor, revision, reason}} : Maybe<&2, M.Feedback>},
    graph_key: @+graph:Maybe<&2, Nat> -> {P.object_key(M.TaskGraph{graph}) == "task-graph/" ++ U.optional_key(graph) : String},
    graph_root: @+graph:Maybe<&2, Nat> -> {P.root_object(U.TaskGraphEditor{graph}) == M.TaskGraph{graph} : M.Object},
    graph_declaration_owner: @+graph:Maybe<&2, Nat> -> {P.owner(M.Subject{U.TaskGraphEditor{graph}, Forms.TaskGraphDeclaration{}}) == M.TaskGraph{graph} : M.Object},
    graph_action_content: @graph:Maybe<&2, Nat> -> {P.content_field(U.TaskGraphEditor{graph}) == Forms.TaskGraphDeclaration{} : Forms.Field},
    graph_invalid_json_requirement: @+graph:Maybe<&2, Nat> -> @source:String -> @world:World.World() ->
      {P.body_requirements(U.TaskGraph{graph, source, None{}, None{}}, world) ==
        [P.obstruction(U.TaskGraphEditor{graph}, Forms.TaskGraphDeclaration{}, "invalid_task_graph_declaration", "Enter a valid task graph declaration")] : +List<M.Obstruction>},
    graph_failed_parse_replaces_previous: @+graph:Maybe<&2, Nat> -> @old:String -> @previous:Maybe<&2, J.Json> -> @+source:String -> @world:World.World() ->
      {U.apply_edit(U.WriteTaskGraph{source, None{}}, U.TaskGraph{graph, old, previous, None{}}, world) ==
        Done{U.TaskGraph{graph, source, None{}, None{}}} : Result<&2, &2, String, U.Body>}
  }

def subject_field(subject: M.Subject) -> Forms.Field:
  M.Subject{editor, field} = subject
  field

def profile_key(profile: D.Profile) -> String:
  D.Profile{key, provider, name, policy, options} = profile
  key

def identity_editor(identity: M.ActionIdentity) -> U.Editor:
  M.ActionIdentity{editor, revision} = identity
  editor

law experience_evidence:
  Requirements

law draft_workspace_requirement:
  @+revision:Nat -> @+submitted:Nat -> @+body:U.Body -> @+reason:String -> @entry:String -> @pending:Bool -> @world:World.World() ->
  {P.draft_requirements(U.Draft{revision, body, U.WorkspaceRejected{submitted, reason}, entry}, pending, world) ==
    List.append(&2, M.Obstruction, P.known_workspace_requirement(Nat.is_eq(submitted, revision), U.owner(body), reason), List.append(&2, M.Obstruction, P.project_edit_requirements(body, entry, world), P.requirements(body, pending, world))) : +List<M.Obstruction>}

law editing_draft_requirements:
  @revision:Nat -> @+body:U.Body -> @entry:String -> @pending:Bool -> @world:World.World() ->
  {P.draft_requirements(U.Draft{revision, body, U.Editing{}, entry}, pending, world) == List.append(&2, M.Obstruction, P.project_edit_requirements(body, entry, world), P.requirements(body, pending, world)) : +List<M.Obstruction>}

law draft_preparation_requirements:
  @draft:U.Draft -> @pending:Bool -> @world:World.World() ->
  {P.draft_can_prepare(draft, pending, world) == P.requirements_empty(P.draft_requirements(draft, pending, world)) : Bool}

law property_repair_observation:
  @property:M.Property -> @assessment:M.Assessment ->
  {P.property_obstruction(property, assessment) == P.property_obstruction_found(property, P.attention_obstruction(assessment)) : Maybe<&2, M.Obstruction>}

law empty_message_obstruction_is_passive:
  @target:M.Object -> @field:Maybe<&2, M.Subject> -> @reason:String ->
  {P.passive_obstruction(M.Obstruction{target, field, "empty_message", reason}) == True{} : Bool}

def workspace_operation_meaning(body: U.Body) -> Bool:
  match body:
    case U.NewTask{message, profile, reasoning, context, create_worktree, work}: True{}
    case U.WorkName{work, name}: False{}
    case U.Project{id, name, workspace, create_worktree}: True{}
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: True{}
    case U.Fork{task, count, messages, context}: True{}
    case U.Message{task, message, delivery}: False{}
    case U.Card{id, revision, value, assist, profile, keep_open}: False{}
    case U.Compact{task, summary}: False{}
    case U.TaskGraph{graph, declaration, parsed, work}: False{}
    case U.TitlePrompts{revision, prompts}: False{}

law workspace_operation_classification:
  @+body:U.Body -> {U.workspace_operation(body) == workspace_operation_meaning(body) : Bool}

law assessment_attention_uses_all_obstructions:
  @assessment:M.Assessment -> {P.attention_obstruction(assessment) == P.attention_obstruction_list(P.assessment_obstructions(assessment)) : Maybe<&2, M.Obstruction>}

law attention_keeps_first_repair:
  @+obstruction:M.Obstruction -> @rest:+List<M.Obstruction> -> @repair:{P.passive_obstruction(obstruction) == False{} : Bool} ->
  {P.attention_obstruction_list(obstruction <> rest) == Some{obstruction} : Maybe<&2, M.Obstruction>}

law attention_skips_passive_obstruction:
  @+obstruction:M.Obstruction -> @+rest:+List<M.Obstruction> -> @passive:{P.passive_obstruction(obstruction) == True{} : Bool} ->
  {P.attention_obstruction_list(obstruction <> rest) == P.attention_obstruction_list(rest) : Maybe<&2, M.Obstruction>}

# Compact display preserves principal mode and omits only secondary detail.
# Activities expose observations, never caller-supplied selection or layout flags.
def project_edit_meaning(+draft: U.Draft, +pending: Bool, now: U32, +world: World.World()) -> M.ProjectEdit:
  U.Draft{+revision, +body, feedback, entry} = draft
  M.ProjectEdit{P.project_original(body, world), draft, pending, P.draft_changed(draft, world),
    P.assessed_requirements(P.draft_requirements(draft, pending, world), body, revision, now, world)}

type ActivityRequirements is Type:
  ActivityRequirements{
    root_owned_dependencies: @+decision:M.Decision -> @children:+List<Activity.Dependency> ->
      {Activity.root_decision(decision, children) == Activity.RootDecision{decision, Activity.dependencies(decision, children)} : Activity.Relation},
    comparison_construction: @+property:M.Property -> @+decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @+catalog:+List<D.Profile> ->
      {Activity.comparison(property, decision, children, facts, catalog) == Activity.ComparisonActivity{property, Activity.observed_relations(property, decision, children, facts, catalog), catalog} : Activity.Activity},
    explanation_construction: @+property:M.Property -> @+decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @+catalog:+List<D.Profile> ->
      {Activity.explanation(property, decision, children, facts, catalog) == Activity.ExplanationActivity{property, Activity.observed_relations(property, decision, children, facts, catalog), catalog} : Activity.Activity},
    required_value_retained: @+property:M.Property -> @+rest:+List<Activity.Relation> ->
      {Activity.required_relations(Activity.RequiredValue{property} <> rest) == Activity.RequiredValue{property} <> Activity.required_relations(rest) : +List<Activity.Relation>},
    blocked_action_retained: @+action:M.ActionUnit -> @+assessment:M.Assessment -> @+rest:+List<Activity.Relation> ->
      {Activity.required_relations(Activity.AssessedAction{action, assessment} <> rest) == Activity.AssessedAction{action, assessment} <> Activity.required_relations(rest) : +List<Activity.Relation>},
    source_not_required: @property:M.Property -> @rest:+List<Activity.Relation> ->
      {Activity.required_relations(Activity.SupportingValue{property} <> rest) == Activity.required_relations(rest) : +List<Activity.Relation>},
    members_observed: @collection:M.Collection ->
      {Activity.collection_members(collection) == P.collection_members(collection) : +List<String>},
    comparison_reading: @property:M.Property -> @decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @catalog:+List<D.Profile> ->
      {Activity.reading_units(Activity.comparison(property, decision, children, facts, catalog)) == 12n : Nat},
    explanation_reading: @property:M.Property -> @decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @catalog:+List<D.Profile> ->
      {Activity.reading_units(Activity.explanation(property, decision, children, facts, catalog)) == 16n : Nat},
    comparison_catalog: @property:M.Property -> @decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @+catalog:+List<D.Profile> ->
      {Activity.catalog(Activity.comparison(property, decision, children, facts, catalog)) == catalog : +List<D.Profile>},
    explanation_catalog: @property:M.Property -> @decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @+catalog:+List<D.Profile> ->
      {Activity.catalog(Activity.explanation(property, decision, children, facts, catalog)) == catalog : +List<D.Profile>},
    editing_reading: @edit:M.ProjectEdit ->
      {Activity.reading_units(Activity.editing(edit)) == 24n : Nat},
    project_observation: @+draft:U.Draft -> @+pending:Bool -> @+now:U32 -> @+world:World.World() ->
      {P.project_edit(draft, pending, now, world) == project_edit_meaning(draft, pending, now, world) : M.ProjectEdit},
    draft_complete: @+revision:Nat -> @+body:U.Body -> @+feedback:U.Feedback -> @+entry:String -> @+pending:Bool -> @+world:World.World() ->
      {P.draft_requirements(U.Draft{revision, body, feedback, entry}, pending, world) == List.append(&2, M.Obstruction, P.known_workspace_requirement(P.workspace_rejection_current(feedback, revision), U.owner(body), P.workspace_rejection_reason(feedback)), List.append(&2, M.Obstruction, P.project_edit_requirements(body, entry, world), P.requirements(body, pending, world))) : +List<M.Obstruction>},
    unchanged_project: @+id:Maybe<&2, Nat> -> @+name:String -> @+workspace:D.Workspace -> @+entry:String -> @+world:World.World() ->
      {P.project_edit_requirements(U.Project{id, name, workspace, False{}}, entry, world) == List.append(&2, M.Obstruction, P.failed_requirement(String.eq(entry, ""), P.obstruction(U.ProjectEditor{id}, Forms.WorkspaceDirectories{}, "unadded_directory", "Add or clear the directory before saving")), P.failed_requirement(P.project_draft_changed(P.project_original(U.Project{id, name, workspace, False{}}, world), name, workspace, False{}, entry), M.Obstruction{P.root_object(U.ProjectEditor{id}), None{}, "unchanged_project", "No project changes to save"})) : +List<M.Obstruction>},
    reviewer_intent: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+choice:Context.ApprovalChoice -> @+reviewers:+List<D.Profile> ->
      {P.property_intent(Forms.ApprovalReviewer{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.Approval{choice}) == P.reviewer_intent(Context.observed_approval(approval), choice, reviewers) : Maybe<&2, U.Edit>}}

law activity_evidence:
  ActivityRequirements

def project_relations_order_requirement(+property:M.Property, +edit:M.ProjectEdit, +revision:Nat, +body:U.Body, +feedback:U.Feedback, +entry:String) -> Type:
  match body:
    case U.Project{+id, name, +workspace, create_worktree}:
      {Activity.project_relations_from_draft(property, edit, U.Draft{revision, body, feedback, entry}) ==
        [Activity.RequiredValue{property}, Activity.CollectionMembers{P.collection(U.ProjectEditor{id}, workspace)},
          Activity.SupportingValue{property}, Activity.AssessedAction{P.action(U.ProjectEditor{id}, revision, P.project_edit_pending(edit)), P.project_edit_assessment(edit)}] : +List<Activity.Relation>}
    case _:
      {Activity.project_relations_from_draft(property, edit, U.Draft{revision, body, feedback, entry}) ==
        [Activity.RequiredValue{property}, Activity.SupportingValue{property}, Activity.AssessedAction{P.action(U.owner(body), revision, P.project_edit_pending(edit)), P.project_edit_assessment(edit)}] : +List<Activity.Relation>}

law project_relations_order:
  @+property:M.Property -> @+edit:M.ProjectEdit -> @+revision:Nat -> @+body:U.Body -> @+feedback:U.Feedback -> @+entry:String ->
    project_relations_order_requirement(property, edit, revision, body, feedback, entry)

law editing_relations_order:
  @+edit:M.ProjectEdit ->
    {Activity.relations(Activity.editing(edit)) == Activity.project_relations_from_draft(P.project_edit_property(edit), edit, P.project_edit_draft(edit)) : +List<Activity.Relation>}

# Candidate disclosure follows the activity and its retained decision identities.
type DecisionDisclosureRequirements is Type:
  DecisionDisclosureRequirements{
    comparison_purpose: @property:M.Property -> @decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @catalog:+List<D.Profile> ->
      {Activity.purpose(Activity.comparison(property, decision, children, facts, catalog)) == Activity.Comparison{} : Activity.Purpose},
    explanation_purpose: @property:M.Property -> @decision:M.Decision -> @children:+List<Activity.Dependency> -> @facts:+List<M.Property> -> @catalog:+List<D.Profile> ->
      {Activity.purpose(Activity.explanation(property, decision, children, facts, catalog)) == Activity.EffectExplanation{} : Activity.Purpose},
    editing_purpose: @edit:M.ProjectEdit ->
      {Activity.purpose(Activity.editing(edit)) == Activity.ObjectEditing{} : Activity.Purpose},
    disclosure_complete: @+activity:Activity.Activity -> @+decision:M.Decision -> @+focused:Maybe<&2, M.Subject> ->
      {Activity.decision_disclosure(activity, decision, focused) == Activity.view_disclosure(activity, decision, Activity.view(activity, focused, False{})) : Activity.DecisionDisclosure},
    absent_relation: @purpose:Activity.Purpose -> @focused:Bool ->
      {Activity.retained_disclosure(False{}, purpose, focused) == Activity.Summary{} : Activity.DecisionDisclosure},
    direct_comparison: @focused:Bool ->
      {Activity.retained_disclosure(True{}, Activity.Comparison{}, focused) == Activity.Candidates{} : Activity.DecisionDisclosure},
    explanation_closed: {Activity.retained_disclosure(True{}, Activity.EffectExplanation{}, False{}) == Activity.Summary{} : Activity.DecisionDisclosure},
    editing_closed: {Activity.retained_disclosure(True{}, Activity.ObjectEditing{}, False{}) == Activity.Summary{} : Activity.DecisionDisclosure},
    explanation_focused: {Activity.retained_disclosure(True{}, Activity.EffectExplanation{}, True{}) == Activity.Candidates{} : Activity.DecisionDisclosure},
    editing_focused: {Activity.retained_disclosure(True{}, Activity.ObjectEditing{}, True{}) == Activity.Candidates{} : Activity.DecisionDisclosure},
    focus_absent: @decision:M.Decision -> {Activity.focused_decision(decision, None{}) == False{} : Bool},
    focus_identity: @+decision:M.Decision -> @+subject:M.Subject ->
      {Activity.focused_decision(decision, Some{subject}) == Activity.same_subject(P.decision_subject(decision), subject) : Bool},
    inactive_dependency: @+parent:M.Decision -> @+prerequisite:M.Value -> @+child:M.Decision -> @+rest:+List<Activity.Relation> -> @+subject:M.Subject ->
      {Activity.retained_decisions(Activity.DependentDecision{parent, prerequisite, child} <> rest, subject) == (Activity.dependency_applies(parent, prerequisite, child) && Activity.decision_subject_matches(child, subject)) || Activity.retained_decisions(rest, subject) : Bool}}

law decision_disclosure_evidence:
  DecisionDisclosureRequirements

type CandidateRequirements is Type:
  CandidateRequirements{
    admission: @+parent:M.Decision -> @+alternative:M.Alternative ->
      {P.candidate_admission(parent, alternative) == P.decision(P.decision_subject(parent), P.decision_observation(parent), P.decision_question(parent), [alternative]) : M.Decision},
    construction: @+parent:M.Decision -> @+alternative:M.Alternative ->
      {P.candidate(parent, alternative) == M.CandidateObservation{parent, alternative, P.candidate_canonical(parent, alternative), P.candidate_admission(parent, alternative), P.candidate_input(P.candidate_admission(parent, alternative), alternative)} : M.CandidateObservation},
    canonical: @+parent:M.Decision -> @label:String -> @explanation:String -> @+value:M.Value ->
      {P.candidate_canonical(parent, M.Alternative{label, explanation, value}) == P.canonical(P.decision_subject(parent), P.decision_observation(parent), value) : Maybe<&2, U.Input>},
    selection: @+admission:M.Decision -> @label:String -> @explanation:String -> @+value:M.Value ->
      {P.candidate_input(admission, M.Alternative{label, explanation, value}) == P.choose(admission, value) : Maybe<&2, U.Input>},
    availability: @+observation:M.CandidateObservation ->
      {P.candidate_availability(observation) == P.candidate_reasoned_availability(P.decision_availability(P.candidate_admitted_decision(observation)), P.candidate_decision(observation), P.candidate_alternative(observation)) : M.Availability},
    reason: @+observation:M.CandidateObservation ->
      {P.candidate_reason(observation) == P.candidate_reason_from_availability(P.candidate_availability(observation)) : Maybe<&2, String>},
    independent_candidates: @+parent:M.Decision -> @+first:M.Alternative -> @+rest:+List<M.Alternative> ->
      {P.candidate_observations(parent, first <> rest) == P.candidate(parent, first) <> P.candidate_observations(parent, rest) : +List<M.CandidateObservation>},
    retained_catalog: @+activity:Activity.Activity -> @+parent:M.Decision ->
      {Activity.decision_candidates(activity, parent) == Activity.retained_candidates(Activity.retains_decision(activity, parent), activity, parent) : +List<M.CandidateObservation>},
    search_projection: @+activity:Activity.Activity -> @+parent:M.Decision -> @query:String ->
      {Activity.visible_candidate_observations(activity, parent, query) == Activity.project_candidate_observations(Activity.decision_candidates(activity, parent), query) : +List<M.CandidateObservation>}}

law candidate_evidence:
  CandidateRequirements

type RelationViewRequirements is Type:
  RelationViewRequirements{
    root: @+decision:M.Decision -> @+children:+List<Activity.Relation> -> {Activity.relation_view(Activity.RootDecision{decision, children}) == Activity.RootDecisionView{decision, children} : Activity.RelationView},
    dependent: @+parent:M.Decision -> @+prerequisite:M.Value -> @+decision:M.Decision -> {Activity.relation_view(Activity.DependentDecision{parent, prerequisite, decision}) == Activity.DependentDecisionView{parent, prerequisite, decision} : Activity.RelationView},
    required: @+property:M.Property -> {Activity.relation_view(Activity.RequiredValue{property}) == Activity.RequiredValueView{property} : Activity.RelationView},
    supporting: @+property:M.Property -> {Activity.relation_view(Activity.SupportingValue{property}) == Activity.SupportingValueView{property} : Activity.RelationView},
    collection: @+collection:M.Collection -> {Activity.relation_view(Activity.CollectionMembers{collection}) == Activity.CollectionMembersView{collection} : Activity.RelationView},
    action: @+action:M.ActionUnit -> @+assessment:M.Assessment -> {Activity.relation_view(Activity.AssessedAction{action, assessment}) == Activity.AssessedActionView{action, assessment} : Activity.RelationView},
    field: @+parent:M.Decision -> @+subject:M.Subject -> @+entry:Forms.Entry -> @+profile:D.Profile -> {Activity.relation_view(Activity.FieldSpecification{parent, subject, entry, profile}) == Activity.FieldSpecificationView{parent, subject, entry, profile} : Activity.RelationView}}

law relation_view_evidence:
  RelationViewRequirements

type FieldSpecificationRequirements is Type:
  FieldSpecificationRequirements{
    actual_catalog: @+parent:M.Decision -> @profiles:+List<D.Profile> -> {Activity.effort_field_specification(parent, profiles) == Activity.effort_field_for_observation(P.decision_observation(parent), profiles, parent) : +List<Activity.Relation>},
    actual_entry: @+parent:M.Decision -> @+profile:D.Profile -> {Activity.effort_field_for_profile(Some{profile}, parent) == Activity.effort_field_for_subject(P.decision_subject(parent), parent, profile, Forms.profile_effort_entry(profile)) : +List<Activity.Relation>},
    current_model_singleline: @+editor:U.Editor -> @+parent:M.Decision -> @+profile:D.Profile -> {Activity.effort_field_for_subject(M.Subject{editor, Forms.ModelProfile{}}, parent, profile, Forms.SingleLine{}) == Activity.admitted_effort_field(P.selected(parent, M.Model{profile}) && Activity.field_owner_matches(parent, M.Subject{editor, Forms.ReasoningEffort{}}), parent, M.Subject{editor, Forms.ReasoningEffort{}}, Forms.SingleLine{}, profile) : +List<Activity.Relation>},
    catalog_root: @+parent:M.Decision -> @children:+List<Activity.Dependency> -> @catalog:+List<D.Profile> -> {Activity.root_decision_for_catalog(parent, children, catalog) == Activity.RootDecision{parent, List.append(&2, Activity.Relation, Activity.dependencies(parent, children), Activity.effort_field_specification(parent, catalog))} : Activity.Relation},
    inactive_field: @parent:M.Decision -> @subject:M.Subject -> @entry:Forms.Entry -> @profile:D.Profile -> {Activity.admitted_effort_field(False{}, parent, subject, entry, profile) == Nil{} : +List<Activity.Relation>},
    missing_profile: @parent:M.Decision -> {Activity.effort_field_for_profile(None{}, parent) == Nil{} : +List<Activity.Relation>}}

law field_specification_evidence:
  FieldSpecificationRequirements

type ReviewerCatalogueRequirements is Type:
  ReviewerCatalogueRequirements{
    automatic: @+profile:String -> @+reviewers:+List<D.Profile> -> {P.approval_intent(Context.AutomaticReview{profile}, reviewers) == P.member_edit(P.reviewer_present(D.find_profile(reviewers, profile)), U.ConfigureContext{Context.SetApproval{Context.AutomaticReview{profile}}}) : Maybe<&2, U.Edit>},
    empty_rejection: @profile:String -> {P.approval_intent(Context.AutomaticReview{profile}, Nil{}) == None{} : Maybe<&2, U.Edit>},
    empty_reason: @key:String -> {P.reviewer_catalog_reason(Nil{}, key) == Some{"No automatic review models are available"} : Maybe<&2, String>},
    missing_reason: {P.missing_reviewer_reason(None{}) == Some{"The automatic review model is not available"} : Maybe<&2, String>},
    existing_reason: @profile:D.Profile -> {P.missing_reviewer_reason(Some{profile}) == None{} : Maybe<&2, String>},
    admitted_has_no_refusal: @parent:M.Decision -> @alternative:M.Alternative -> {P.candidate_reasoned_availability(M.Available{}, parent, alternative) == M.Available{} : M.Availability}}

law reviewer_catalogue_evidence:
  ReviewerCatalogueRequirements

type StrategyRequirements is Type:
  StrategyRequirements{
    ask_view: {P.observed_strategy(Context.Ask{}) == M.Ask{} : M.Strategy},
    full_view: {P.observed_strategy(Context.Unrestricted{}) == M.FullAccess{} : M.Strategy},
    automatic_view: @profile:String -> {P.observed_strategy(Context.AutomaticReview{profile}) == M.AutomaticReview{} : M.Strategy},
    current_reviewer: @+profile:D.Profile -> @reviewers:+List<D.Profile> -> {P.current_reviewer(Some{profile}, reviewers) == Some{Context.AutomaticReview{D.profile_key(profile)}} : Maybe<&2, Context.ApprovalChoice>},
    fallback_reviewer: @+reviewers:+List<D.Profile> -> {P.current_reviewer(None{}, reviewers) == P.first_reviewer(reviewers) : Maybe<&2, Context.ApprovalChoice>},
    automatic_resolution: @+strategy:M.Strategy -> @+current:Context.ApprovalChoice -> @+reviewers:+List<D.Profile> -> {P.strategy_intent(strategy, current, reviewers) == P.resolved_strategy(P.strategy_approval(strategy, current, reviewers)) : Maybe<&2, U.Edit>},
    strategy_canonical: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+strategy:M.Strategy -> @+reviewers:+List<D.Profile> -> {P.property_intent(Forms.ApprovalPolicy{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.ExecutionStrategy{strategy}) == P.strategy_intent(strategy, Context.observed_approval(approval), reviewers) : Maybe<&2, U.Edit>},
    strategy_selection: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+strategy:M.Strategy -> @reviewers:+List<D.Profile> -> {P.observed_selection(Forms.ApprovalPolicy{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}, M.ExecutionStrategy{strategy}) == P.strategy_same(P.observed_strategy(Context.observed_approval(approval)), strategy) : Bool},
    empty_reason: {P.automatic_strategy_reason(Nil{}) == Some{"No automatic review models are available"} : Maybe<&2, String>}}

law strategy_evidence:
  StrategyRequirements

# The actual recursive carrier is traversed before a view is supplied to a client.
type RelationFoldRequirements<-Context: Data, -Result: Data, -handler: Context -> Activity.RelationView -> +List<Result> -> Result, -context: Context> is Type:
  RelationFoldRequirements{
    empty: {Activity.fold_relations(~Context, ~Result, ~handler, context, Nil{}) == Nil{} : +List<Result>},
    root: @+decision:M.Decision -> @+children:+List<Activity.Relation> -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.RootDecision{decision, children} <> rest) == handler(context, Activity.relation_view(Activity.RootDecision{decision, children}), Activity.fold_relations(~Context, ~Result, ~handler, context, children)) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>},
    dependent: @+parent:M.Decision -> @+prerequisite:M.Value -> @+decision:M.Decision -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.DependentDecision{parent, prerequisite, decision} <> rest) == handler(context, Activity.relation_view(Activity.DependentDecision{parent, prerequisite, decision}), Nil{}) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>},
    required: @+property:M.Property -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.RequiredValue{property} <> rest) == handler(context, Activity.relation_view(Activity.RequiredValue{property}), Nil{}) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>},
    supporting: @+property:M.Property -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.SupportingValue{property} <> rest) == handler(context, Activity.relation_view(Activity.SupportingValue{property}), Nil{}) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>},
    collection: @+collection:M.Collection -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.CollectionMembers{collection} <> rest) == handler(context, Activity.relation_view(Activity.CollectionMembers{collection}), Nil{}) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>},
    action: @+action:M.ActionUnit -> @+assessment:M.Assessment -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.AssessedAction{action, assessment} <> rest) == handler(context, Activity.relation_view(Activity.AssessedAction{action, assessment}), Nil{}) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>},
    field: @+parent:M.Decision -> @+subject:M.Subject -> @+entry:Forms.Entry -> @+profile:D.Profile -> @+rest:+List<Activity.Relation> ->
      {Activity.fold_relations(~Context, ~Result, ~handler, context, Activity.FieldSpecification{parent, subject, entry, profile} <> rest) == handler(context, Activity.relation_view(Activity.FieldSpecification{parent, subject, entry, profile}), Nil{}) <> Activity.fold_relations(~Context, ~Result, ~handler, context, rest) : +List<Result>}}

law relation_fold_evidence:
  @-Context:Data -> @-Result:Data -> @-handler:(Context -> Activity.RelationView -> +List<Result> -> Result) -> @-context:Context -> RelationFoldRequirements<Context, Result, handler, context>

# Evidence expressions retain the observed fact and its real presentation witness.
type ViewConstructionRequirements is Type:
  ViewConstructionRequirements{
    admitted_focus: @+activity:Activity.Activity -> @+subject:M.Subject ->
      {Activity.requested_focus(activity, Some{subject}) == Activity.admitted_focus(Activity.retained_subject(Activity.relations(activity), subject), subject) : Maybe<&2, M.Subject>},
    rejected_focus: @subject:M.Subject -> {Activity.admitted_focus(False{}, subject) == None{} : Maybe<&2, M.Subject>},
    root_initial: @+activity:Activity.Activity -> @decision:M.Decision -> @children:+List<Activity.Relation> ->
      {Activity.relation_exposure(activity, Activity.PrincipalView{}, Activity.RootDecision{decision, children}) == Activity.CandidateChoices{} : Activity.Exposure},
    root_inspection: @activity:Activity.Activity -> @decision:M.Decision -> @children:+List<Activity.Relation> ->
      {Activity.relation_exposure(activity, Activity.InspectionView{None{}}, Activity.RootDecision{decision, children}) == Activity.DependencySummary{} : Activity.Exposure},
    principal_completion: @property:M.Property -> @relations:+List<Activity.Relation> -> @catalog:+List<D.Profile> ->
      {Activity.completion(Activity.ComparisonActivity{property, relations, catalog}, Activity.PrincipalView{}) == Activity.ApplyAndDismiss{} : Activity.Completion},
    permission_completion: @property:M.Property -> @relations:+List<Activity.Relation> -> @catalog:+List<D.Profile> ->
      {Activity.completion(Activity.ExplanationActivity{property, relations, catalog}, Activity.PrincipalView{}) == Activity.ApplyAndDismiss{} : Activity.Completion},
    dependent_completion: @property:M.Property -> @relations:+List<Activity.Relation> -> @catalog:+List<D.Profile> -> @subject:M.Subject ->
      {Activity.completion(Activity.ComparisonActivity{property, relations, catalog}, Activity.DependentView{subject}) == Activity.ApplyAndReturn{} : Activity.Completion},
    inspection_completion: @property:M.Property -> @relations:+List<Activity.Relation> -> @catalog:+List<D.Profile> ->
      {Activity.completion(Activity.ExplanationActivity{property, relations, catalog}, Activity.InspectionView{None{}}) == Activity.ReturnToOwner{} : Activity.Completion},
    inspection_selection_completion: @property:M.Property -> @relations:+List<Activity.Relation> -> @catalog:+List<D.Profile> -> @subject:M.Subject ->
      {Activity.completion(Activity.ExplanationActivity{property, relations, catalog}, Activity.InspectionView{Some{subject}}) == Activity.ApplyAndReturn{} : Activity.Completion},
    inspected_root_request: @+activity:Activity.Activity -> @+decision:M.Decision -> @+subject:M.Subject -> @children:+List<Activity.Relation> ->
      {Activity.relation_exposure(activity,Activity.InspectionView{Some{subject}},Activity.RootDecision{decision,children}) == Activity.candidate_exposure(Activity.retains_decision(activity,decision) && Activity.same_subject(P.decision_subject(decision),subject)) : Activity.Exposure},
    compound_completion: @property:M.Property -> @edit:M.ProjectEdit -> @relations:+List<Activity.Relation> -> @current:Activity.View ->
      {Activity.completion(Activity.EditingActivity{property, edit, relations}, current) == Activity.CommitOrDiscard{} : Activity.Completion},
    selected_preserved: @matches:Bool -> @+observation:M.CandidateObservation -> @rest:+List<M.CandidateObservation> ->
      {Activity.selected_candidate_projection(True{}, matches, observation, rest) == observation <> rest : +List<M.CandidateObservation>},
    selected_projection: @+first:M.CandidateObservation -> @rest:+List<M.CandidateObservation> -> @+query:String ->
      {Activity.project_candidate_observations(first <> rest, query) == Activity.selected_candidate_projection(P.candidate_selected(first), Activity.candidate_matches(P.candidate_alternative(first), query), first, Activity.project_candidate_observations(rest, query)) : +List<M.CandidateObservation>},
    required_retained: @activity:Activity.Activity -> @current:Activity.View -> @property:M.Property ->
      {Activity.relation_exposure(activity, current, Activity.RequiredValue{property}) == Activity.RequiredExpression{} : Activity.Exposure},
    necessary_fallback: @+property:M.Property ->
      {Activity.expression_or_inline(None{}, property) == Activity.NecessaryInline{Activity.fact_identity(property)} : Activity.Coverage},
    selection_witness: @+fact:Activity.FactIdentity -> @+decision:M.Decision -> @+children:+List<Activity.Relation> ->
      {Activity.selected_expression(True{}, fact, decision, children) == Some{Activity.SelectedPrincipal{fact, decision, children}} : Maybe<&2,Activity.Coverage>},
    rejected_expression: @fact:Activity.FactIdentity -> @decision:M.Decision -> @children:+List<Activity.Relation> ->
      {Activity.selected_expression(False{}, fact, decision, children) == None{} : Maybe<&2,Activity.Coverage>},
    current_identity: @+property:M.Property ->
      {Activity.fact_identity(property) == Activity.FactIdentity{P.property_owner(property), P.property_subjects(property), property, Activity.property_reference(property)} : Activity.FactIdentity},
    draft_identity: @+edit:M.ProjectEdit -> @+subject:M.Subject ->
      {Activity.draft_field_identity(edit, subject) == Activity.DraftFieldIdentity{P.owner(subject), subject, P.project_edit_draft(edit)} : Activity.DraftFieldIdentity},
    requested_inspection: @activity:Activity.Activity -> @focused:Maybe<&2,M.Subject> -> @+property:M.Property ->
      {Activity.coverage(activity, Activity.InspectionView{focused}, property) == Activity.RequestedInspection{Activity.fact_identity(property)} : Activity.Coverage},
    initial_coverage: @+activity:Activity.Activity -> @+property:M.Property ->
      {Activity.coverage(activity, Activity.PrincipalView{}, property) == Activity.expression_or_inline(Activity.expressions_from_relations(activity, property, Activity.PrincipalView{}, Activity.relations(activity)), property) : Activity.Coverage},
    original_identity: @+property:M.Property -> @+edit:M.ProjectEdit -> @+relations:+List<Activity.Relation> ->
      {Activity.coverage(Activity.EditingActivity{property, edit, relations}, Activity.CompoundView{}, property) == Activity.OriginalObject{Activity.fact_identity(property), edit} : Activity.Coverage},
    model_search: @property:M.Property -> @relations:+List<Activity.Relation> -> @+catalog:+List<D.Profile> ->
      {Activity.search_required(Activity.ComparisonActivity{property, relations, catalog}, Activity.PrincipalView{}) == Activity.search_for_kind(P.property_kind(property), Activity.Comparison{}, Activity.PrincipalView{}, catalog) : Bool},
    inspection_search: @property:M.Property -> @relations:+List<Activity.Relation> -> @catalog:+List<D.Profile> -> @focused:Maybe<&2,M.Subject> ->
      {Activity.search_required(Activity.ComparisonActivity{property, relations, catalog}, Activity.InspectionView{focused}) == False{} : Bool},
    observed_owner: @+property:M.Property -> @+decision:M.Decision ->
      {Activity.property_observation_matches(property,decision) == String.eq(P.object_key(P.property_owner(property)),P.object_key(P.owner(P.decision_subject(decision)))) && Activity.observation_matches(property,P.decision_observation(decision),Activity.decision_editor(decision)) : Bool},
    comparison_parameter_need: {Activity.initial_dependency_exposure(Activity.Comparison{}) == Activity.DependencySummary{} : Activity.Exposure},
    explanation_configuration_need: {Activity.initial_dependency_exposure(Activity.EffectExplanation{}) == Activity.HiddenRelation{} : Activity.Exposure},
    principal_dependency_need: @+activity:Activity.Activity -> @subject:M.Subject ->
      {Activity.dependency_view_exposure(activity,Activity.PrincipalView{},subject) == Activity.initial_dependency_exposure(Activity.purpose(activity)) : Activity.Exposure},
    permission_consequence_need: @+subject:M.Subject -> @property:M.Property -> @decision:M.Decision -> @dependencies:+List<Activity.Relation> ->
      {Activity.remaining_principal_expression(M.PermissionsProperty{},subject,property,decision,dependencies) == Activity.consequence_expression(subject,property,decision) : Activity.SubjectExpression},
    public_fold_exposure: @+activity:Activity.Activity -> @+current:Activity.View -> @+value:Activity.RelationView ->
      {Activity.relation_view_exposure(activity,current,value) == Activity.relation_exposure(activity,current,Activity.relation_for_view(value)) : Activity.Exposure},
    required_subjects: @+property:M.Property -> @+decision:M.Decision -> @+dependencies:+List<Activity.Relation> ->
      {Activity.coverage_expressions(Activity.SelectedPrincipal{Activity.fact_identity(property),decision,dependencies}) == Activity.principal_expressions(P.property_subjects(property),property,decision,dependencies) : +List<Activity.SubjectExpression>},
    subject_choice: @+subject:M.Subject -> @property:M.Property -> @+decision:M.Decision -> @dependencies:+List<Activity.Relation> ->
      {Activity.principal_subject_expression(True{},subject,property,decision,dependencies) == Activity.SelectedSubject{subject,decision} : Activity.SubjectExpression},
    admitted_parameter: @+subject:M.Subject -> @+relation:Activity.Relation ->
      {Activity.admitted_parameter_expression(True{},subject,relation) == Some{Activity.OwnedParameter{subject,relation}} : Maybe<&2,Activity.SubjectExpression>},
    unexpressed_subject: @+subject:M.Subject -> @+property:M.Property ->
      {Activity.inline_expressions(subject <> Nil{},property) == Activity.InlineSubject{subject,property} <> Nil{} : +List<Activity.SubjectExpression>},
    subject_sequence: @+subject:M.Subject -> @rest:+List<M.Subject> -> @+property:M.Property -> @+decision:M.Decision -> @+dependencies:+List<Activity.Relation> ->
      {Activity.principal_expressions(subject <> rest,property,decision,dependencies) == Activity.principal_subject_expression(Activity.same_subject(subject,P.decision_subject(decision)),subject,property,decision,dependencies) <> Activity.principal_expressions(rest,property,decision,dependencies) : +List<Activity.SubjectExpression>},
    dependency_admission: @+activity:Activity.Activity -> @+current:Activity.View -> @+parent:M.Decision -> @+prerequisite:M.Value -> @+decision:M.Decision ->
      {Activity.relation_exposure(activity,current,Activity.DependentDecision{parent,prerequisite,decision}) ==
        Activity.admitted_exposure(Activity.dependency_applies(parent,prerequisite,decision) && Activity.retains_decision(activity,decision), Activity.dependency_view_exposure(activity,current,P.decision_subject(decision))) : Activity.Exposure},
    inspection_field_summary: @subject:M.Subject ->
      {Activity.field_exposure(Activity.InspectionView{None{}},subject) == Activity.DependencySummary{} : Activity.Exposure},
    inspection_field_admission: @+activity:Activity.Activity -> @+parent:M.Decision -> @+subject:M.Subject -> @entry:Forms.Entry -> @+profile:D.Profile ->
      {Activity.relation_exposure(activity,Activity.InspectionView{None{}},Activity.FieldSpecification{parent,subject,entry,profile}) ==
        Activity.admitted_exposure(Activity.field_specification_applies(parent,subject,profile) && Activity.retained_subject(Activity.relations(activity),subject),Activity.DependencySummary{}) : Activity.Exposure}}

law view_construction_evidence:
  ViewConstructionRequirements


# Read-only context access is bound to the actual owning observation producers.
type PropertyContextRequirements is Type:
  PropertyContextRequirements{
    model_producer: @editor:U.Editor -> @+profile:String -> @+effort:String -> @world:World.World() ->
      {P.property_model_context(P.model_property(editor,profile,effort,world)) == Some{Forms.ModelValue{profile,effort}} : Maybe<&2,Forms.Observed>},
    permission_producer: @editor:U.Editor -> @+observation:Context.Observation ->
      {P.property_permission_context(P.permissions_property(editor,observation)) == Some{observation} : Maybe<&2,Context.Observation>},
    model_has_no_permissions: @editor:U.Editor -> @profile:String -> @effort:String -> @world:World.World() ->
      {P.property_permission_context(P.model_property(editor,profile,effort,world)) == None{} : Maybe<&2,Context.Observation>},
    permission_has_no_model: @editor:U.Editor -> @observation:Context.Observation ->
      {P.property_model_context(P.permissions_property(editor,observation)) == None{} : Maybe<&2,Forms.Observed>}}

law property_context_evidence:
  PropertyContextRequirements

# The complete observation anchors recognition; projection only removes its dependent detail.
type RecognitionSummaryRequirements is Type:
  RecognitionSummaryRequirements{
    observation: @+property:M.Property ->
      {P.summary_property(P.property_recognition_summary(property)) == property : M.Property},
    project_roles: @+editor:U.Editor -> @+selected:Maybe<&2,Nat> -> @+found:Maybe<&2,D.Project> ->
      {P.property_recognition_summary(M.ProjectObservation{editor,selected,found}) ==
        M.RecognitionSummary{M.ProjectObservation{editor,selected,found},M.SummaryValue{M.Subject{editor,Forms.ContextOrigin{}},P.project_value(selected,found)},None{}} : M.RecognitionSummary},
    workspace_roles: @+editor:U.Editor -> @+observation:Context.Observation -> @+source:Maybe<&2,D.Project> ->
      {P.property_recognition_summary(M.WorkspaceObservation{editor,observation,source}) ==
        M.RecognitionSummary{M.WorkspaceObservation{editor,observation,source},M.SummaryValue{M.Subject{editor,Forms.WorkspacePrimary{}},P.primary_value(P.observed_workspace(observation))},None{}} : M.RecognitionSummary},
    delivery_roles: @+editor:U.Editor -> @+delivery:U.Delivery ->
      {P.property_recognition_summary(M.DeliveryObservation{editor,delivery}) ==
        M.RecognitionSummary{M.DeliveryObservation{editor,delivery},M.SummaryValue{M.Subject{editor,Forms.DeliveryIntent{}},U.delivery_caption(delivery)},None{}} : M.RecognitionSummary},
    model_roles: @+editor:U.Editor -> @+profile:String -> @+effort:String -> @+found:Maybe<&2,D.Profile> ->
      {P.property_recognition_summary(M.ModelObservation{editor,profile,effort,found}) ==
        M.RecognitionSummary{M.ModelObservation{editor,profile,effort,found}, M.SummaryValue{M.Subject{editor,Forms.ModelProfile{}},P.model_value(profile,found)}, Some{M.SummaryValue{M.Subject{editor,Forms.ReasoningEffort{}},effort}}} : M.RecognitionSummary},
    permission_roles: @+editor:U.Editor -> @+observation:Context.Observation ->
      {P.property_recognition_summary(M.PermissionsObservation{editor,observation}) ==
        M.RecognitionSummary{M.PermissionsObservation{editor,observation}, M.SummaryValue{M.Subject{editor,Forms.ApprovalPolicy{}},P.permission_recognition_value(observation)}, P.permission_recognition_secondary(observation,editor)} : M.RecognitionSummary},
    ask_identity: {P.strategy_caption(M.Ask{}) == "Ask" : String},
    review_identity: {P.strategy_caption(M.AutomaticReview{}) == "Automatic review" : String},
    unrestricted_identity: {P.strategy_caption(M.FullAccess{}) == "Full access" : String},
    complete_permission_description: @+choice:Context.ApprovalChoice -> @observation:Context.Observation ->
      {P.permission_property_parts_for_choice(choice,observation) == P.strategy_caption(P.observed_strategy(choice)) <> P.permission_secondary_parts(P.observed_strategy(choice),P.permission_summary_parts(observation)) : +List<String>},
    unavailable_identity: @reason:String ->
      {P.permission_recognition_value(Context.DraftExecution{Context.ContextUnavailable{reason}}) == "Unavailable" : String},
    draft_strategy_identity: @origin:Context.Origin -> @project:Maybe<&2,Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview ->
      {P.permission_recognition_value(Context.DraftExecution{Context.ProspectiveContext{origin,project,workspace,sandbox,approval,guidance}}) == P.strategy_caption(P.observed_strategy(Context.observed_approval(approval))) : String},
    sandboxed_strategy_identity: @task:Nat -> @workspace:D.Workspace -> @sandbox:D.Sandbox -> @approval:D.ApprovalPolicy -> @project:Maybe<&2,Nat> -> @guidance:D.ProjectContext ->
      {P.permission_recognition_value(Context.CommittedExecution{Context.EffectiveContext{task,D.TaskContext{workspace,sandbox,approval,project},guidance,D.Sandboxed{}}}) == P.strategy_caption(P.observed_strategy(Context.approval_choice(approval))) : String},
    effective_full_access: @+editor:U.Editor -> @+task:Nat -> @+workspace:D.Workspace -> @+sandbox:D.Sandbox -> @+approval:D.ApprovalPolicy -> @+project:Maybe<&2,Nat> -> @+guidance:D.ProjectContext ->
      {P.summary_principal(P.property_recognition_summary(M.PermissionsObservation{editor,Context.CommittedExecution{Context.EffectiveContext{task,D.TaskContext{workspace,sandbox,approval,project},guidance,D.Unrestricted{}}}})) ==
        M.SummaryValue{M.Subject{editor,Forms.ApprovalPolicy{}},"Full access"} : M.SummaryValue},
    full_access_has_no_inactive_limit: @editor:U.Editor -> @task:Nat -> @workspace:D.Workspace -> @sandbox:D.Sandbox -> @approval:D.ApprovalPolicy -> @project:Maybe<&2,Nat> -> @guidance:D.ProjectContext ->
      {P.summary_secondary(P.property_recognition_summary(M.PermissionsObservation{editor,Context.CommittedExecution{Context.EffectiveContext{task,D.TaskContext{workspace,sandbox,approval,project},guidance,D.Unrestricted{}}}})) == None{} : Maybe<&2,M.SummaryValue>},
    sandboxed_detail: @+editor:U.Editor -> @+mode:D.SandboxMode -> @network:Bool ->
      {P.permission_recognition_secondary_access(Some{D.Sandboxed{}},D.Sandbox{mode,network},editor) ==
        Some{M.SummaryValue{M.Subject{editor,Forms.SandboxMode{}},P.filesystem_recognition_value(mode)}} : Maybe<&2,M.SummaryValue>},
    workspace_label: {P.filesystem_recognition_value(D.WorkspaceWrite{}) == "Workspace write" : String},
    readonly_label: {P.filesystem_recognition_value(D.ReadOnly{}) == "Read only" : String},
    projection_owner: @+full:Bool -> @+property:M.Property -> @principal:M.SummaryValue -> @secondary:Maybe<&2,M.SummaryValue> ->
      {P.summary_property(P.summary_projection(full,M.RecognitionSummary{property,principal,secondary})) == property : M.Property},
    projection_identity: @+full:Bool -> @property:M.Property -> @+principal:M.SummaryValue -> @secondary:Maybe<&2,M.SummaryValue> ->
      {P.summary_principal(P.summary_projection(full,M.RecognitionSummary{property,principal,secondary})) == principal : M.SummaryValue},
    compact_detail: @summary:M.RecognitionSummary ->
      {P.summary_secondary(P.summary_projection(False{},summary)) == None{} : Maybe<&2,M.SummaryValue>},
    full_detail: @+summary:M.RecognitionSummary ->
      {P.summary_projection(True{},summary) == summary : M.RecognitionSummary}}

law recognition_summary_evidence:
  RecognitionSummaryRequirements

# Completeness is relative to the current activity's applicable subjects. A
# retained inactive condition is evidence for omission, not an admitted edit.
type InformationRequirements is Type:
  InformationRequirements{
    retained_condition: @+parent:M.Decision -> @+prerequisite:M.Value -> @+child:M.Decision ->
      {Activity.retained_dependency(True{},parent,prerequisite,child) == [Activity.DependentDecision{parent,prerequisite,child}] : +List<Activity.Relation>},
    dependency_source: @+parent:M.Decision -> @+prerequisite:M.Value -> @+child:M.Decision -> @+rest:+List<Activity.Dependency> ->
      {Activity.dependencies(parent,Activity.Dependency{prerequisite,child} <> rest) == List.append(&2,Activity.Relation,Activity.retained_dependency(Activity.same_owner(parent,child) && U.same_editor(Activity.decision_editor(parent),Activity.decision_editor(child)),parent,prerequisite,child),Activity.dependencies(parent,rest)) : +List<Activity.Relation>},
    selected_condition: @+parent:M.Decision -> @+prerequisite:M.Value -> @+child:M.Decision -> @+subject:M.Subject ->
      {Activity.relation_dependency(Activity.DependentDecision{parent,prerequisite,child},subject) == Activity.dependency_condition(Activity.same_subject(P.decision_subject(child),subject),Activity.dependency_applies(parent,prerequisite,child)) : Activity.DependencyState},
    inactive_condition: @observed:M.InformationStatus ->
      {Activity.conditional_information(Activity.InactiveInformation{},observed) == M.NotApplicable{"This setting does not apply to the current selection"} : M.InformationStatus},
    active_condition: @+observed:M.InformationStatus ->
      {Activity.conditional_information(Activity.ActiveInformation{},observed) == observed : M.InformationStatus},
    optional_project: @found:Maybe<&2,D.Project> ->
      {P.selected_project_information(None{},found) == M.OptionalAbsence{} : M.InformationStatus},
    missing_project: @id:Nat ->
      {P.selected_project_information(Some{id},None{}) == M.RequiredAbsence{"Choose an available project"} : M.InformationStatus},
    missing_model: {P.model_field_information(None{},Forms.ModelProfile{},"") == M.RequiredAbsence{"Choose a configured model"} : M.InformationStatus},
    missing_reviewer: {P.reviewer_presence(None{}) == M.RequiredAbsence{"Choose an available reviewing model"} : M.InformationStatus},
    observed_information: @+activity:Activity.Activity -> @current:Activity.View -> @+property:M.Property -> @+subject:M.Subject ->
      {Activity.information_status(activity,current,property,subject) == Activity.conditional_information(Activity.subject_dependency(Activity.relations(activity),subject),Activity.editing_information(Activity.editing_observation(activity),subject,P.property_information(property,subject,Activity.catalog(activity)))) : M.InformationStatus},
    inactive_visibility: @+current:Activity.View -> @+subject:M.Subject -> @reason:String ->
      {Activity.information_visible(current,subject,M.NotApplicable{reason}) == Activity.requested_subject(current,subject) : Bool},
    required_visibility: @current:Activity.View -> @subject:M.Subject -> @reason:String ->
      {Activity.information_visible(current,subject,M.RequiredAbsence{reason}) == True{} : Bool},
    unavailable_visibility: @current:Activity.View -> @subject:M.Subject -> @reason:String ->
      {Activity.information_visible(current,subject,M.UnavailableInformation{reason}) == True{} : Bool},
    preserve_expression: @+expression:Activity.SubjectExpression -> @+rest:+List<Activity.SubjectExpression> ->
      {Activity.admitted_information(True{},expression,rest) == expression <> rest : +List<Activity.SubjectExpression>},
    omit_expression: @expression:Activity.SubjectExpression -> @+rest:+List<Activity.SubjectExpression> ->
      {Activity.admitted_information(False{},expression,rest) == rest : +List<Activity.SubjectExpression>},
    complete_expression: @+activity:Activity.Activity -> @+current:Activity.View -> @+property:M.Property -> @+expression:Activity.SubjectExpression -> @+rest:+List<Activity.SubjectExpression> ->
      {Activity.required_information_expressions(activity,current,property,expression <> rest) == Activity.admitted_information(Activity.information_visible(current,Activity.expression_subject(expression),Activity.information_status(activity,current,property,Activity.expression_subject(expression))),expression,Activity.required_information_expressions(activity,current,property,rest)) : +List<Activity.SubjectExpression>},
    production_coverage: @+activity:Activity.Activity -> @+current:Activity.View -> @+coverage:Activity.Coverage ->
      {Activity.information_expressions(activity,current,coverage) == Activity.required_information_expressions(activity,current,Activity.coverage_property(coverage),Activity.coverage_expressions(coverage)) : +List<Activity.SubjectExpression>}}

law information_evidence: InformationRequirements

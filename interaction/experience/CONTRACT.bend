import Base
import ../../harness/features/MODEL.bend as F
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/MODEL.bend as World
import ../../harness/COMMANDS.bend as Commands
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../features/board/MODEL.bend as Board
import ../../bendlib/json.bend as J
import ./MODEL.bend as M
import ./PROGRAM.bend as P
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
    case M.PermissionsObservation{editor, observation}: P.permission_summary(observation)
    case M.ModelObservation{editor, profile, effort, found}: P.model_value(profile, found) ++ " · " ++ effort
    case M.DeliveryObservation{editor, delivery}: U.delivery_caption(delivery)

def property_summary_parts_meaning(property: M.Property) -> +List<String>:
  match property:
    case M.ProjectObservation{editor, selected, found}: [P.project_value(selected, found)]
    case M.WorkspaceObservation{editor, observation, source}: [P.primary_value(P.observed_workspace(observation))]
    case M.PermissionsObservation{editor, observation}: P.permission_summary_parts(observation)
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
      {P.committed_summary_parts(D.Unrestricted{}, sandbox, choice) == "Full access" <> List.append(&2, String, ["Network on"], P.summary_approval_parts(choice)) : +List<String>},
    committed_sandboxed_parts: @sandbox:D.Sandbox -> @choice:Context.ApprovalChoice ->
      {P.committed_summary_parts(D.Sandboxed{}, sandbox, choice) == P.sandbox_summary_parts(sandbox, choice) : +List<String>},
    unavailable_permission_parts: @reason:String ->
      {P.permission_summary_parts(Context.DraftExecution{Context.ContextUnavailable{reason}}) == ["Unavailable"] : +List<String>},
    draft_permission_parts: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview ->
      {P.permission_summary_parts(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}) == P.sandbox_summary_parts(Context.unwrap_sandbox(sandbox), Context.observed_approval(approval)) : +List<String>},
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
    blocked_retains: @+first:M.Obstruction -> @+rest:+List<M.Obstruction> -> @body:U.Body -> @revision:Nat -> @now:U32 -> @world:World.World() -> {P.assessed_requirements(first <> rest, body, revision, now, world) == M.Assessment{M.ActionIdentity{U.owner(body), revision}, first <> rest, M.Blocked{}, None{}} : M.Assessment},
    directory_next: @workspace:D.Workspace -> @body:U.Body -> @revision:Nat -> @now:U32 -> @world:World.World() -> {P.prepared_assessment(Some{workspace}, body, revision, now, world) == M.Assessment{M.ActionIdentity{U.owner(body), revision}, Nil{}, M.NeedsDirectoryObservation{}, None{}} : M.Assessment},
    actual_resolution: @+body:U.Body -> @+revision:Nat -> @now:U32 -> @world:World.World() -> {P.prepared_assessment(None{}, body, revision, now, world) == P.resolved_assessment(Commands.resolve(U.command(body, now), world), M.ActionIdentity{U.owner(body), revision}, U.owner(body)) : M.Assessment},
    actual_refusal: @+code:String -> @+reason:String -> @+identity:M.ActionIdentity -> @editor:U.Editor -> {P.resolved_assessment(Commands.Refuse{code, reason}, identity, editor) == M.Assessment{identity, Nil{}, M.Blocked{}, Some{M.Obstruction{P.root_object(editor), None{}, code, reason}}} : M.Assessment},
    assessment_identity: @+identity:M.ActionIdentity -> @+requirements:+List<M.Obstruction> -> @+state:M.AssessmentState -> @+refusal:Maybe<&2, M.Obstruction> -> {P.assessment_identity(M.Assessment{identity, requirements, state, refusal}) == identity : M.ActionIdentity},
    assessment_state: @+identity:M.ActionIdentity -> @+requirements:+List<M.Obstruction> -> @+state:M.AssessmentState -> @+refusal:Maybe<&2, M.Obstruction> -> {P.assessment_state(M.Assessment{identity, requirements, state, refusal}) == state : M.AssessmentState},
    assessment_obstructions: @+identity:M.ActionIdentity -> @+requirements:+List<M.Obstruction> -> @+state:M.AssessmentState -> @+refusal:Maybe<&2, M.Obstruction> -> {P.assessment_obstructions(M.Assessment{identity, requirements, state, refusal}) == List.append(&2, M.Obstruction, requirements, P.refusal_obstructions(refusal)) : +List<M.Obstruction>},
    assessment_reason: @+assessment:M.Assessment -> {P.assessment_reason(assessment) == P.first_reason(P.assessment_obstructions(assessment)) : String},
    assessment_field: @+assessment:M.Assessment -> {P.assessment_field(assessment) == P.first_field(P.assessment_obstructions(assessment)) : Maybe<&2, M.Subject>},
    assessment_ready: @+assessment:M.Assessment -> {P.assessment_ready(assessment) == P.state_ready(P.assessment_state(assessment)) : Bool},
    directory_ready: {P.state_ready(M.NeedsDirectoryObservation{}) == True{} : Bool},
    blocked_not_ready: {P.state_ready(M.Blocked{}) == False{} : Bool},
    new_task_content: @message:U.Text -> @+profile:String -> @+reasoning:String -> @context:Context.Configuration -> @+world:World.World() -> {P.body_requirements(U.NewTask{message, profile, reasoning, context}, world) == List.append(&2, M.Obstruction, P.failed_requirement(D.nonempty(U.text(message)), P.obstruction(U.NewTaskEditor{}, Forms.MessageText{}, "empty_message", "Write a task to start")), P.model_requirements(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning, U.NewTaskEditor{})) : +List<M.Obstruction>},
    message_content: @+task:Nat -> @message:U.Text -> @delivery:U.Delivery -> @world:World.World() -> {P.body_requirements(U.Message{task, message, delivery}, world) == P.failed_requirement(D.nonempty(U.text(message)), P.obstruction(U.MessageEditor{task}, Forms.MessageText{}, "empty_message", "Write a message to send")) : +List<M.Obstruction>},
    project_name: @+id:Maybe<&2, Nat> -> @name:String -> @workspace:D.Workspace -> @world:World.World() -> {P.body_requirements(U.Project{id, name, workspace}, world) == P.failed_requirement(Projects.name_valid(name), P.obstruction(U.ProjectEditor{id}, Forms.ProjectName{}, "invalid_project_name", "Enter a project name of at most 256 UTF-8 bytes")) : +List<M.Obstruction>},
    agent_guard: @revision:Nat -> @+name:String -> @+profile:String -> @+reasoning:String -> @+instructions:String -> @settings:J.Json -> @+concurrency:Nat -> {Board.valid_agent(Board.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}) == Board.agent_name_valid(name) && Board.agent_profile_valid(profile) && Board.agent_reasoning_valid(reasoning) && Board.agent_instructions_valid(instructions) && Board.agent_concurrency_valid(concurrency) : Bool},
    fork_guard: @+count:Nat -> @+messages:+List<String> -> @+parent:D.Task -> @+world:World.World() -> {Commands.branch_fits(count, messages, parent, world) == Commands.branch_count_valid(count, parent) && Commands.branch_messages_valid(count, messages) && Commands.branch_capacity_valid(count, parent, world) : Bool},
    lookup_selected: @+id:Nat -> @world:World.World() -> {P.selected_project(Some{id}, world) == Projects.find(Projects.registry(F.State(), world), id) : Maybe<&2, D.Project>},
    project_name_guard: @+name:String -> {Projects.name_valid(name) == D.nonempty(name) && Nat.is_le(J.utf8_length(name), 256n) : Bool},
    agent_name_valid: @+name:String -> {Board.agent_name_valid(name) == D.nonempty(name) && Board.limited(name, 160n) : Bool},
    agent_profile_valid: @+profile:String -> {Board.agent_profile_valid(profile) == D.nonempty(profile) && Board.limited(profile, 1024n) : Bool},
    agent_reasoning_valid: @+reasoning:String -> {Board.agent_reasoning_valid(reasoning) == D.nonempty(reasoning) && Board.limited(reasoning, 64n) : Bool},
    agent_instructions_valid: @+instructions:String -> {Board.agent_instructions_valid(instructions) == Board.limited(instructions, 100000n) : Bool},
    agent_concurrency_valid: @+count:Nat -> {Board.agent_concurrency_valid(count) == Nat.is_le(1n, count) && Nat.is_le(count, 64n) : Bool},
    branch_count_guard: @+count:Nat -> @+parent:D.Task -> {Commands.branch_count_valid(count, parent) == Nat.is_le(1n, count) && Nat.is_le(count, Commands.per_fork(D.task_contract(parent))) : Bool},
    branch_messages_guard: @+count:Nat -> @+messages:+List<String> -> {Commands.branch_messages_valid(count, messages) == Nat.is_eq(List.length(&2, String, messages), 0n) || Nat.is_eq(List.length(&2, String, messages), count) : Bool},
    branch_capacity_guard: @+count:Nat -> @+parent:D.Task -> @world:World.World() -> {Commands.branch_capacity_valid(count, parent, world) == Tasks.ancestors_fit(D.task_id(parent) <> D.task_lineage(parent), Commands.entries(world), count) : Bool},
    context_failure: @+editor:U.Editor -> @+reason:String -> {P.origin_failure(Context.ContextUnavailable{reason}, editor) == [P.obstruction(editor, Forms.ContextOrigin{}, "context_unavailable", reason)] : +List<M.Obstruction>},
    model_missing: @effort:String -> @+editor:U.Editor -> {P.model_requirements(None{}, effort, editor) == [P.obstruction(editor, Forms.ModelProfile{}, "model_not_found", "Choose a configured model")] : +List<M.Obstruction>},
    model_permitted: @+profile:D.Profile -> @+effort:String -> @+editor:U.Editor -> {P.model_requirements(Some{profile}, effort, editor) == P.failed_requirement(D.profile_permitted(profile, D.profile_selection(effort, profile)), P.obstruction(editor, Forms.ReasoningEffort{}, "invalid_reasoning", "Choose an allowed reasoning effort")) : +List<M.Obstruction>},
    project_record: @+id:Maybe<&2, Nat> -> @name:String -> @workspace:D.Workspace -> @world:World.World() -> {P.record_requirements(U.Project{id, name, workspace}, world) == P.failed_requirement(Projects.reference_valid(id, Projects.registry(F.State(), world)), M.Obstruction{P.root_object(U.ProjectEditor{id}), None{}, "project_not_found", "The project does not exist"}) : +List<M.Obstruction>},
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
    creation_root: {P.root_object(U.NewTaskEditor{}) == M.TaskDraft{} : M.Object},
    task_root: @+task:Nat -> {P.root_object(U.MessageEditor{task}) == M.Task{task} : M.Object},
    project_root: @+project:Maybe<&2, Nat> -> {P.root_object(U.ProjectEditor{project}) == M.Project{project} : M.Object},
    task_message_owner: @+task:Nat -> {P.owner(M.Subject{U.MessageEditor{task}, Forms.MessageText{}}) == M.MessageDraft{task} : M.Object},
    model_owner: @+editor:U.Editor -> {P.owner(M.Subject{editor, Forms.ModelProfile{}}) == M.ExecutionConfigurationOf{editor} : M.Object},
    workspace_owner: @+editor:U.Editor -> {P.owner(M.Subject{editor, Forms.WorkspaceDirectories{}}) == M.WorkspaceOf{editor} : M.Object},
    configuration_parent: @+editor:U.Editor -> {P.parent(M.ExecutionConfigurationOf{editor}) == Some{P.root_object(editor)} : Maybe<&2, M.Object>},
    property_filesystem: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+mode:D.SandboxMode ->
      {P.property_intent(Forms.SandboxMode{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, M.Filesystem{mode}) == P.filesystem_intent(Context.unwrap_sandbox(sandbox), mode) : Maybe<&2, U.Edit>},
    property_network: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+enabled:Bool ->
      {P.property_intent(Forms.NetworkAccess{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, M.Network{enabled}) == P.network_intent(Context.unwrap_sandbox(sandbox), enabled) : Maybe<&2, U.Edit>},
    property_approval: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+choice:Context.ApprovalChoice ->
      {P.property_intent(Forms.ApprovalPolicy{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, M.Approval{choice}) == Some{U.ConfigureContext{Context.SetApproval{choice}}} : Maybe<&2, U.Edit>},
    selected_filesystem: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+mode:D.SandboxMode ->
      {P.observed_selection(Forms.SandboxMode{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, M.Filesystem{mode}) == P.filesystem_selected(Context.unwrap_sandbox(sandbox), mode) : Bool},
    selected_network: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+network:Bool ->
      {P.observed_selection(Forms.NetworkAccess{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, M.Network{network}) == P.network_selected(Context.unwrap_sandbox(sandbox), network) : Bool},
    selected_approval: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @+choice:Context.ApprovalChoice ->
      {P.observed_selection(Forms.ApprovalPolicy{}, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, M.Approval{choice}) == P.value_same(M.Approval{Context.observed_approval(approval)}, M.Approval{choice}) : Bool},
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
    action_content: @+editor:U.Editor -> @revision:Nat -> @pending:Bool -> {P.content_subject(P.action(editor, revision, pending)) == M.Subject{editor, Forms.MessageText{}} : M.Subject},
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
    feedback_retention: @+editor:U.Editor -> @+revision:Nat -> @+reason:String -> {P.feedback(editor, U.Rejected{revision, reason}) == Some{M.Feedback{editor, revision, reason}} : Maybe<&2, M.Feedback>}
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
    List.append(&2, M.Obstruction, P.known_workspace_requirement(Nat.is_eq(submitted, revision), U.owner(body), reason), P.requirements(body, pending, world)) : +List<M.Obstruction>}

law editing_draft_requirements:
  @revision:Nat -> @+body:U.Body -> @entry:String -> @pending:Bool -> @world:World.World() ->
  {P.draft_requirements(U.Draft{revision, body, U.Editing{}, entry}, pending, world) == P.requirements(body, pending, world) : +List<M.Obstruction>}

law draft_preparation_requirements:
  @draft:U.Draft -> @pending:Bool -> @world:World.World() ->
  {P.draft_can_prepare(draft, pending, world) == P.requirements_empty(P.draft_requirements(draft, pending, world)) : Bool}

law property_repair_observation:
  @property:M.Property -> @assessment:M.Assessment ->
  {P.property_obstruction(property, assessment) == P.property_obstruction_found(property, P.attention_obstruction(assessment)) : Maybe<&2, M.Obstruction>}

law empty_message_obstruction_is_passive:
  @target:M.Object -> @field:Maybe<&2, M.Subject> -> @reason:String ->
  {P.passive_obstruction(M.Obstruction{target, field, "empty_message", reason}) == True{} : Bool}

law permission_summary_retains_consequences:
  @+mode:D.SandboxMode ->
  {P.summary_permissions(D.Sandbox{mode, True{}}, Context.Unrestricted{}) == D.sandbox_mode_name(mode) ++ " · Network on" ++ " · Unrestricted" : String}

law ordinary_permission_summary_is_compact:
  @+mode:D.SandboxMode ->
  {P.summary_permissions(D.Sandbox{mode, False{}}, Context.Ask{}) == D.sandbox_mode_name(mode) ++ "" ++ "" : String}

def workspace_operation_meaning(body: U.Body) -> Bool:
  match body:
    case U.NewTask{message, profile, reasoning, context}: True{}
    case U.Project{id, name, workspace}: True{}
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: True{}
    case U.Fork{task, count, messages, context}: True{}
    case U.Message{task, message, delivery}: False{}
    case U.Card{id, revision, value, assist, profile, keep_open}: False{}
    case U.Compact{task, summary}: False{}

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

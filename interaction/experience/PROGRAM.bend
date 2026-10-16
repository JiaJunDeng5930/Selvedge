import Base
import ../../features/board/STATE.bend as BoardState
import ../../harness/MODEL.bend as World
import ../../harness/COMMANDS.bend as Commands
import ../../harness/features/MODEL.bend as F
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../features/board/MODEL.bend as Board
import ./MODEL.bend as M
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D
import ../../harness/transport/schema.bend as Schema
import ../../harness/workspace/WORKSPACE.bend as Workspace

def root_object(editor: U.Editor) -> M.Object:
  match editor:
    case U.NewTaskEditor{}: M.TaskDraft{}
    case U.MessageEditor{task}: M.Task{task}
    case U.ProjectEditor{project}: M.Project{project}
    case _: M.EditorObject{editor}

def workspace_field(field: Forms.Field) -> Bool:
  match field:
    case Forms.WorkspaceDirectories{}: True{}
    case Forms.WorkspacePrimary{}: True{}
    case _: False{}

def configuration_field(field: Forms.Field) -> Bool:
  match field:
    case Forms.ModelProfile{}: True{}
    case Forms.ReasoningEffort{}: True{}
    case Forms.SandboxMode{}: True{}
    case Forms.NetworkAccess{}: True{}
    case Forms.ApprovalPolicy{}: True{}
    case Forms.ApprovalReviewer{}: True{}
    case _: False{}

def scalar_owner(editor: U.Editor, field: Forms.Field) -> M.Object:
  match editor field:
    case U.MessageEditor{task} Forms.MessageText{}: M.MessageDraft{task}
    case U.MessageEditor{task} Forms.DeliveryIntent{}: M.MessageDraft{task}
    case U.ProjectEditor{project} _: M.Project{project}
    case _ _: M.EditorObject{editor}

def owner_fields(workspace: Bool, configuration: Bool, +editor: U.Editor, field: Forms.Field) -> M.Object:
  match workspace configuration:
    case True{} _: M.WorkspaceOf{editor}
    case _ True{}: M.ExecutionConfigurationOf{editor}
    case _ _: scalar_owner(editor, field)

def owner(subject: M.Subject) -> M.Object:
  M.Subject{+editor, +field} = subject
  owner_fields(workspace_field(field), configuration_field(field), editor, field)

def parent(object: M.Object) -> Maybe<&2, M.Object>:
  match object:
    case M.WorkspaceOf{editor}: Some{root_object(editor)}
    case M.ExecutionConfigurationOf{editor}: Some{root_object(editor)}
    case M.MessageDraft{task}: Some{M.Task{task}}
    case _: None{}

def object_key(object: M.Object) -> String:
  match object:
    case M.TaskDraft{}: "task-draft"
    case M.Task{task}: "task/" ++ Nat.show(task)
    case M.Project{project}: "project/" ++ U.optional_key(project)
    case M.MessageDraft{task}: "message-draft/" ++ Nat.show(task)
    case M.EditorObject{editor}: "editor/" ++ U.editor_key(editor)
    case M.WorkspaceOf{editor}: "workspace/" ++ U.editor_key(editor)
    case M.ExecutionConfigurationOf{editor}: "execution-configuration/" ++ U.editor_key(editor)

def subject_key(subject: M.Subject) -> String:
  M.Subject{+editor, +field} = subject
  object_key(owner(M.Subject{editor, field})) ++ "/" ++ Forms.key(field)

def action_key(identity: M.ActionIdentity) -> String:
  M.ActionIdentity{editor, revision} = identity
  U.editor_key(editor) ++ "/" ++ Nat.show(revision)

def same_group_owner(fields: +List<Forms.Field>, +editor: U.Editor, +object: M.Object) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{field, rest}: String.eq(object_key(owner(M.Subject{editor, field})), object_key(object)) && same_group_owner(rest, editor, object)

def resolved_group_owner(same: Bool, object: M.Object, editor: U.Editor) -> M.Object:
  match same:
    case True{}: object
    case False{}: root_object(editor)

def group_owner(+editor: U.Editor, fields: +List<Forms.Field>) -> M.Object:
  match fields:
    case Nil{}: root_object(editor)
    case Con{first, rest}:
      +object: M.Object = owner(M.Subject{editor, first})
      resolved_group_owner(same_group_owner(rest, editor, object), object, editor)

def editable_workspace(editor: U.Editor) -> Bool:
  match editor:
    case U.NewTaskEditor{}: True{}
    case U.ProjectEditor{project}: True{}
    case U.AgentEditor{agent}: True{}
    case U.ForkEditor{task}: True{}
    case _: False{}

def strategy_key(strategy: M.Strategy) -> String:
  match strategy:
    case M.Ask{}: "strategy/ask"
    case M.AutomaticReview{}: "strategy/automatic-review"
    case M.FullAccess{}: "strategy/full-access"

def observed_strategy(choice: Context.ApprovalChoice) -> M.Strategy:
  match choice:
    case Context.Ask{}: M.Ask{}
    case Context.Unrestricted{}: M.FullAccess{}
    case Context.AutomaticReview{profile}: M.AutomaticReview{}

def strategy_same(left: M.Strategy, right: M.Strategy) -> Bool:
  String.eq(strategy_key(left), strategy_key(right))

def value_key(value: M.Value) -> String:
  match value:
    case M.ExecutionStrategy{strategy}: strategy_key(strategy)
    case M.Filesystem{mode}: "filesystem/" ++ D.sandbox_mode_name(mode)
    case M.Network{False{}}: "network/disabled"
    case M.Network{True{}}: "network/enabled"
    case M.Approval{Context.Ask{}}: "approval/ask"
    case M.Approval{Context.Unrestricted{}}: "approval/unrestricted"
    case M.Approval{Context.AutomaticReview{profile}}: "approval/automatic/" ++ profile
    case M.Model{D.Profile{key, provider, name, policy, options}}: "model/" ++ key
    case M.Effort{effort}: "effort/" ++ effort
    case M.PrimaryDirectory{path}: "directory/" ++ path

def value_same(left: M.Value, right: M.Value) -> Bool:
  String.eq(value_key(left), value_key(right))

def permitted_model(permitted: Bool, profile: String, effort: String) -> Maybe<&2, U.Edit>:
  match permitted:
    case True{}: Some{U.ChooseModel{profile, effort}}
    case False{}: None{}

def model_effort(permitted: Bool, effort: String, profile: D.Profile) -> String:
  match permitted:
    case True{}: effort
    case False{}: D.profile_default(profile)

def model_intent(profile: D.Profile, +current: String) -> Maybe<&2, U.Edit>:
  D.Profile{+key, provider, name, policy, options} = profile
  +candidate: D.Profile = D.Profile{key, provider, name, policy, options}
  +effort: String = model_effort(D.profile_permitted(candidate, current), current, candidate)
  permitted_model(D.profile_permitted(candidate, effort), key, effort)

def member_edit(member: Bool, edit: U.Edit) -> Maybe<&2, U.Edit>:
  match member:
    case True{}: Some{edit}
    case False{}: None{}

def filesystem_intent(sandbox: D.Sandbox, mode: D.SandboxMode) -> Maybe<&2, U.Edit>:
  D.Sandbox{old, network} = sandbox
  Some{U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}}

def network_intent(sandbox: D.Sandbox, enabled: Bool) -> Maybe<&2, U.Edit>:
  D.Sandbox{mode, old} = sandbox
  Some{U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, enabled}}}}

def filesystem_selected(sandbox: D.Sandbox, mode: D.SandboxMode) -> Bool:
  D.Sandbox{current, network} = sandbox
  String.eq(D.sandbox_mode_name(current), D.sandbox_mode_name(mode))

def network_selected(sandbox: D.Sandbox, enabled: Bool) -> Bool:
  D.Sandbox{mode, current} = sandbox
  match current enabled:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def reviewer_present(found: Maybe<&2, D.Profile>) -> Bool:
  match found:
    case None{}: False{}
    case Some{profile}: True{}

def approval_intent(choice: Context.ApprovalChoice, reviewers: +List<D.Profile>) -> Maybe<&2, U.Edit>:
  match choice:
    case Context.AutomaticReview{+profile}: member_edit(reviewer_present(D.find_profile(reviewers, profile)), U.ConfigureContext{Context.SetApproval{Context.AutomaticReview{profile}}})
    case _: Some{U.ConfigureContext{Context.SetApproval{choice}}}

def first_reviewer(reviewers: +List<D.Profile>) -> Maybe<&2, Context.ApprovalChoice>:
  match reviewers:
    case Nil{}: None{}
    case Con{profile, rest}: Some{Context.AutomaticReview{D.profile_key(profile)}}

def current_reviewer(found: Maybe<&2, D.Profile>, reviewers: +List<D.Profile>) -> Maybe<&2, Context.ApprovalChoice>:
  match found:
    case None{}: first_reviewer(reviewers)
    case Some{profile}: Some{Context.AutomaticReview{D.profile_key(profile)}}

def automatic_strategy(current: Context.ApprovalChoice, +reviewers: +List<D.Profile>) -> Maybe<&2, Context.ApprovalChoice>:
  match current:
    case Context.AutomaticReview{profile}: current_reviewer(D.find_profile(reviewers, profile), reviewers)
    case _: first_reviewer(reviewers)

def strategy_approval(strategy: M.Strategy, current: Context.ApprovalChoice, reviewers: +List<D.Profile>) -> Maybe<&2, Context.ApprovalChoice>:
  match strategy:
    case M.Ask{}: Some{Context.Ask{}}
    case M.FullAccess{}: Some{Context.Unrestricted{}}
    case M.AutomaticReview{}: automatic_strategy(current, reviewers)

def resolved_strategy(choice: Maybe<&2, Context.ApprovalChoice>) -> Maybe<&2, U.Edit>:
  match choice:
    case None{}: None{}
    case Some{choice}: Some{U.ConfigureContext{Context.SetApproval{choice}}}

def strategy_intent(strategy: M.Strategy, current: Context.ApprovalChoice, reviewers: +List<D.Profile>) -> Maybe<&2, U.Edit>:
  resolved_strategy(strategy_approval(strategy, current, reviewers))

def reviewer_intent(current: Context.ApprovalChoice, choice: Context.ApprovalChoice, reviewers: +List<D.Profile>) -> Maybe<&2, U.Edit>:
  match current choice:
    case Context.AutomaticReview{old} Context.AutomaticReview{profile}: approval_intent(Context.AutomaticReview{profile}, reviewers)
    case _ _: None{}

def property_intent(field: Forms.Field, observation: Forms.Observed, value: M.Value) -> Maybe<&2, U.Edit>:
  match field observation value:
    case Forms.SandboxMode{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Filesystem{mode}:
      filesystem_intent(Context.unwrap_sandbox(sandbox), mode)
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Network{enabled}:
      network_intent(Context.unwrap_sandbox(sandbox), enabled)
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.ExecutionStrategy{strategy}: strategy_intent(strategy, Context.observed_approval(approval), reviewers)
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Approval{choice}: approval_intent(choice, reviewers)
    case Forms.ApprovalReviewer{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Approval{choice}: reviewer_intent(Context.observed_approval(approval), choice, reviewers)
    case Forms.ModelProfile{} Forms.ModelValue{current, effort} M.Model{profile}: model_intent(profile, effort)
    case Forms.ReasoningEffort{} Forms.ModelValue{profile, old} M.Effort{effort}: Some{U.ChooseModel{profile, effort}}
    case Forms.WorkspacePrimary{} Forms.WorkspaceValue{D.Workspace{+roots, primary}} M.PrimaryDirectory{+path}:
      member_edit(Schema.contains(roots, path), U.EditWorkspace{Context.ChoosePrimary{path}})
    case _ _ _: None{}

def workspace_scope(allowed: Bool, intent: Maybe<&2, U.Edit>) -> Maybe<&2, U.Edit>:
  match allowed:
    case True{}: intent
    case False{}: None{}

def editable_model(editor: U.Editor) -> Bool:
  match editor:
    case U.NewTaskEditor{}: True{}
    case U.AgentEditor{agent}: True{}
    case U.MessageEditor{task}: True{}
    case _: False{}

def editable_configuration(editor: U.Editor) -> Bool:
  match editor:
    case U.NewTaskEditor{}: True{}
    case U.AgentEditor{agent}: True{}
    case U.ForkEditor{task}: True{}
    case U.MessageEditor{task}: True{}
    case _: False{}

def editable_property(editor: U.Editor, field: Forms.Field) -> Bool:
  match field:
    case Forms.WorkspacePrimary{}: editable_workspace(editor)
    case Forms.ModelProfile{}: editable_model(editor)
    case Forms.ReasoningEffort{}: editable_model(editor)
    case Forms.SandboxMode{}: editable_configuration(editor)
    case Forms.NetworkAccess{}: editable_configuration(editor)
    case Forms.ApprovalPolicy{}: editable_configuration(editor)
    case Forms.ApprovalReviewer{}: editable_configuration(editor)
    case _: False{}

def scoped_intent(+editor: U.Editor, +field: Forms.Field, observation: Forms.Observed, value: M.Value) -> Maybe<&2, U.Edit>:
  workspace_scope(editable_property(editor, field), property_intent(field, observation, value))

def bind_editor(editor: U.Editor, intent: Maybe<&2, U.Edit>) -> Maybe<&2, U.Input>:
  match intent:
    case None{}: None{}
    case Some{edit}: Some{U.EditDraft{editor, edit}}

def canonical(subject: M.Subject, observation: Forms.Observed, value: M.Value) -> Maybe<&2, U.Input>:
  M.Subject{+editor, field} = subject
  bind_editor(editor, scoped_intent(editor, field, observation, value))

def has_intent(value: Maybe<&2, U.Input>) -> Bool:
  match value:
    case None{}: False{}
    case Some{input}: True{}

def admitted_candidate(compatible: Bool, duplicate: Bool, rest: Bool) -> Bool:
  compatible && Bool.not(duplicate) && rest

def alternatives_present(values: +List<M.Alternative>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{first, rest}: True{}

# Intent compatibility and uniqueness are checked together before any option is exposed.
def admissible(alternatives: +List<M.Alternative>, +subject: M.Subject, +observation: Forms.Observed, +seen: +List<String>) -> Bool:
  match alternatives:
    case Nil{}: True{}
    case Con{M.Alternative{label, explanation, +value}, rest}:
      +key: String = value_key(value)
      admitted_candidate(has_intent(canonical(subject, observation, value)), Schema.contains(seen, key), admissible(rest, subject, observation, key <> seen))

def admitted_alternatives(valid: Bool, values: +List<M.Alternative>) -> +List<M.Alternative>:
  match valid:
    case True{}: values
    case False{}: Nil{}

def admission_availability(valid: Bool) -> M.Availability:
  match valid:
    case True{}: M.Available{}
    case False{}: M.Unavailable{"Alternatives are incompatible with this property or contain duplicate values"}

def decision_status(compatible: Bool, present: Bool) -> M.Availability:
  match present:
    case False{}: M.Unavailable{"No alternatives are available"}
    case True{}: admission_availability(compatible)

def decision(+subject: M.Subject, +observation: Forms.Observed, question: String, +alternatives: +List<M.Alternative>) -> M.Decision:
  +valid: Bool = admissible(alternatives, subject, observation, Nil{})
  +present: Bool = alternatives_present(alternatives)
  M.Decision{subject, observation, question, admitted_alternatives(valid && present, alternatives), decision_status(valid, present)}

def decision_subject(value: M.Decision) -> M.Subject:
  M.Decision{subject, observation, question, alternatives, availability} = value
  subject

def decision_observation(value: M.Decision) -> Forms.Observed:
  M.Decision{subject, observation, question, alternatives, availability} = value
  observation

def decision_question(value: M.Decision) -> String:
  M.Decision{subject, observation, question, alternatives, availability} = value
  question

def decision_alternatives(value: M.Decision) -> +List<M.Alternative>:
  M.Decision{subject, observation, question, alternatives, availability} = value
  alternatives

def decision_availability(value: M.Decision) -> M.Availability:
  M.Decision{subject, observation, question, alternatives, availability} = value
  availability

def observed_selection(field: Forms.Field, observation: Forms.Observed, value: M.Value) -> Bool:
  match field observation value:
    case Forms.SandboxMode{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Filesystem{mode}:
      filesystem_selected(Context.unwrap_sandbox(sandbox), mode)
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Network{enabled}:
      network_selected(Context.unwrap_sandbox(sandbox), enabled)
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.ExecutionStrategy{strategy}: strategy_same(observed_strategy(Context.observed_approval(approval)), strategy)
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Approval{choice}: value_same(M.Approval{Context.observed_approval(approval)}, M.Approval{choice})
    case Forms.ApprovalReviewer{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers} M.Approval{choice}: value_same(M.Approval{Context.observed_approval(approval)}, M.Approval{choice})
    case Forms.ModelProfile{} Forms.ModelValue{current, effort} M.Model{D.Profile{key, provider, name, policy, options}}: String.eq(current, key)
    case Forms.ReasoningEffort{} Forms.ModelValue{profile, current} M.Effort{effort}: String.eq(current, effort)
    case Forms.WorkspacePrimary{} Forms.WorkspaceValue{D.Workspace{roots, Some{primary}}} M.PrimaryDirectory{path}: String.eq(primary, path)
    case _ _ _: False{}

def selected(value: M.Decision, candidate: M.Value) -> Bool:
  M.Decision{M.Subject{editor, field}, observation, question, alternatives, availability} = value
  observed_selection(field, observation, candidate)

def matching_value(same: Bool, value: M.Value, other: Maybe<&2, M.Value>) -> Maybe<&2, M.Value>:
  match same:
    case True{}: Some{value}
    case False{}: other

def admitted_value(values: +List<M.Alternative>, +candidate: M.Value) -> Maybe<&2, M.Value>:
  match values:
    case Nil{}: None{}
    case Con{M.Alternative{label, explanation, +value}, rest}: matching_value(value_same(value, candidate), value, admitted_value(rest, candidate))

def choose_admitted(value: Maybe<&2, M.Value>, subject: M.Subject, observation: Forms.Observed) -> Maybe<&2, U.Input>:
  match value:
    case None{}: None{}
    case Some{candidate}: canonical(subject, observation, candidate)

def choose(value: M.Decision, candidate: M.Value) -> Maybe<&2, U.Input>:
  M.Decision{subject, observation, question, alternatives, availability} = value
  choose_admitted(admitted_value(alternatives, candidate), subject, observation)

def collection(editor: U.Editor, workspace: D.Workspace) -> M.Collection:
  M.Collection{editor, workspace}

def collection_editor(value: M.Collection) -> U.Editor:
  M.Collection{editor, workspace} = value
  editor

def collection_workspace(value: M.Collection) -> D.Workspace:
  M.Collection{editor, workspace} = value
  workspace

def collection_members(value: M.Collection) -> +List<String>:
  M.Collection{editor, workspace} = value
  Workspace.roots(workspace)

def primary_matches(primary: Maybe<&2, String>, path: String) -> Bool:
  match primary:
    case None{}: False{}
    case Some{current}: String.eq(current, path)

def is_primary(value: M.Collection, path: String) -> Bool:
  M.Collection{editor, workspace} = value
  primary_matches(Workspace.primary(workspace), path)

def primary_alternatives(roots: +List<String>) -> +List<M.Alternative>:
  match roots:
    case Nil{}: Nil{}
    case Con{+path, rest}: M.Alternative{path, "Use this member as the primary working directory", M.PrimaryDirectory{path}} <> primary_alternatives(rest)

def primary_decision(value: M.Collection) -> M.Decision:
  M.Collection{editor, +workspace} = value
  decision(M.Subject{editor, Forms.WorkspacePrimary{}}, Forms.WorkspaceValue{workspace}, "Primary working directory", primary_alternatives(Workspace.roots(workspace)))

def choose_primary(value: M.Collection, path: String) -> Maybe<&2, U.Input>:
  choose(primary_decision(value), M.PrimaryDirectory{path})

def remove_member(value: M.Collection, +path: String) -> Maybe<&2, U.Input>:
  M.Collection{+editor, workspace} = value
  bind_editor(editor, member_edit(editable_workspace(editor) && Schema.contains(Workspace.roots(workspace), path), U.EditWorkspace{Context.RemoveRoot{path}}))

def action(editor: U.Editor, revision: Nat, pending: Bool) -> M.ActionUnit:
  M.ActionUnit{M.ActionIdentity{editor, revision}, pending}

def identity(value: M.ActionUnit) -> M.ActionIdentity:
  M.ActionUnit{identity, pending} = value
  identity

def action_editor(value: M.ActionUnit) -> U.Editor:
  M.ActionUnit{M.ActionIdentity{editor, revision}, pending} = value
  editor

def action_pending(value: M.ActionUnit) -> Bool:
  M.ActionUnit{identity, pending} = value
  pending

def content_subject(value: M.ActionUnit) -> M.Subject:
  M.Subject{action_editor(value), Forms.MessageText{}}

def commit(value: M.ActionUnit) -> U.Input:
  U.Activate{U.Submit{action_editor(value)}}

def editor_context(editor: U.Editor) -> M.ActionContext:
  match editor:
    case U.NewTaskEditor{}: M.Creation{}
    case U.MessageEditor{task}: M.Continuation{task}
    case _: M.ObjectEditing{}

def action_context(value: M.ActionUnit) -> M.ActionContext:
  editor_context(action_editor(value))

def creation_field(field: Forms.Field) -> Bool:
  match field:
    case Forms.ContextOrigin{}: True{}
    case _: False{}

def delivery_field(field: Forms.Field) -> Bool:
  match field:
    case Forms.DeliveryIntent{}: True{}
    case _: False{}

def support_field(context: M.ActionContext, +field: Forms.Field) -> Bool:
  match context:
    case M.Creation{}: configuration_field(field) || workspace_field(field) || creation_field(field)
    case M.Continuation{task}: configuration_field(field) || delivery_field(field)
    case M.ObjectEditing{}: False{}

def support_fields(value: M.Support) -> +List<Forms.Field>:
  M.Support{identity, fields} = value
  fields

def support_identity(value: M.Support) -> M.ActionIdentity:
  M.Support{identity, fields} = value
  identity

def retain_support(allowed: Bool, field: Forms.Field, rest: +List<Forms.Field>) -> +List<Forms.Field>:
  match allowed:
    case True{}: field <> rest
    case False{}: rest

def permitted_support(fields: +List<Forms.Field>, +context: M.ActionContext) -> +List<Forms.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}: retain_support(support_field(context, field), field, permitted_support(rest, context))

def support(value: M.ActionUnit, fields: +List<Forms.Field>) -> M.Support:
  M.ActionUnit{+identity, pending} = value
  M.ActionIdentity{+editor, revision} = identity
  M.Support{M.ActionIdentity{editor, revision}, permitted_support(fields, editor_context(editor))}

def subjects(fields: +List<Forms.Field>, +editor: U.Editor) -> +List<M.Subject>:
  match fields:
    case Nil{}: Nil{}
    case Con{field, rest}: M.Subject{editor, field} <> subjects(rest, editor)

def support_subjects(value: M.Support) -> +List<M.Subject>:
  M.Support{M.ActionIdentity{editor, revision}, fields} = value
  subjects(fields, editor)

def fields_present(fields: +List<Forms.Field>) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{first, rest}: True{}

def support_visible(value: M.Support) -> Bool:
  fields_present(support_fields(value))

def feedback(editor: U.Editor, value: U.Feedback) -> Maybe<&2, M.Feedback>:
  match value:
    case U.Rejected{revision, reason}: Some{M.Feedback{editor, revision, reason}}
    case _: None{}

# Property observations preserve the source values rather than authored captions.
def selected_project(selected: Maybe<&2, Nat>, world: World.World()) -> Maybe<&2, D.Project>:
  match selected:
    case None{}: None{}
    case Some{id}: Projects.find(Projects.registry(F.State(), world), id)

def project_property(editor: U.Editor, +selected: Maybe<&2, Nat>, world: World.World()) -> M.Property:
  M.ProjectObservation{editor, selected, selected_project(selected, world)}

def origin_project(origin: Context.Origin) -> Maybe<&2, Nat>:
  match origin:
    case Context.ProjectDefaults{id}: Some{id}
    case Context.ProjectForParent{task, id}: Some{id}
    case _: None{}
def observation_project(observation: Context.Observation) -> Maybe<&2, Nat>:
  match observation:
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: origin_project(origin)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}: project
    case _: None{}

def workspace_property(editor: U.Editor, +observation: Context.Observation, world: World.World()) -> M.Property:
  M.WorkspaceObservation{editor, observation, selected_project(observation_project(observation), world)}

def permissions_property(editor: U.Editor, observation: Context.Observation) -> M.Property:
  M.PermissionsObservation{editor, observation}

def model_property(editor: U.Editor, +profile: String, effort: String, world: World.World()) -> M.Property:
  M.ModelObservation{editor, profile, effort, D.find_profile(Commands.configured(Commands.settings(world)), profile)}

def delivery_property(editor: U.Editor, delivery: U.Delivery) -> M.Property:
  M.DeliveryObservation{editor, delivery}

def property_editor(property: M.Property) -> U.Editor:
  match property:
    case M.ProjectObservation{editor, selected, found}: editor
    case M.WorkspaceObservation{editor, observation, source}: editor
    case M.PermissionsObservation{editor, observation}: editor
    case M.ModelObservation{editor, profile, effort, found}: editor
    case M.DeliveryObservation{editor, delivery}: editor

def property_model_context(property: M.Property) -> Maybe<&2,Forms.Observed>:
  match property:
    case M.ModelObservation{editor,profile,effort,found}: Some{Forms.ModelValue{profile,effort}}
    case _: None{}

def property_permission_context(property: M.Property) -> Maybe<&2,Context.Observation>:
  match property:
    case M.PermissionsObservation{editor,observation}: Some{observation}
    case _: None{}

def property_kind(property: M.Property) -> M.PropertyKind:
  match property:
    case M.ProjectObservation{editor, selected, found}: M.ProjectProperty{}
    case M.WorkspaceObservation{editor, observation, source}: M.WorkspaceProperty{}
    case M.PermissionsObservation{editor, observation}: M.PermissionsProperty{}
    case M.ModelObservation{editor, profile, effort, found}: M.ModelProperty{}
    case M.DeliveryObservation{editor, delivery}: M.DeliveryProperty{}

def kind_fields(kind: M.PropertyKind) -> +List<Forms.Field>:
  match kind:
    case M.ProjectProperty{}: [Forms.ContextOrigin{}]
    case M.WorkspaceProperty{}: [Forms.WorkspaceDirectories{}, Forms.WorkspacePrimary{}]
    case M.PermissionsProperty{}: [Forms.SandboxMode{}, Forms.NetworkAccess{}, Forms.ApprovalPolicy{}, Forms.ApprovalReviewer{}]
    case M.ModelProperty{}: [Forms.ModelProfile{}, Forms.ReasoningEffort{}]
    case M.DeliveryProperty{}: [Forms.DeliveryIntent{}]

def property_fields(property: M.Property) -> +List<Forms.Field>:
  kind_fields(property_kind(property))

def property_subjects(+property: M.Property) -> +List<M.Subject>:
  subjects(property_fields(property), property_editor(property))

def first_property_field(fields: +List<Forms.Field>) -> Forms.Field:
  match fields:
    case Con{field, rest}: field
    case Nil{}: Forms.MessageText{}

def property_repair_field(property: M.Property) -> Forms.Field:
  first_property_field(property_fields(property))

def property_owner(+property: M.Property) -> M.Object:
  group_owner(property_editor(property), property_fields(property))

def project_state(selected: Maybe<&2, Nat>, found: Maybe<&2, D.Project>) -> M.PropertyState:
  match selected found:
    case None{} _: M.Absent{}
    case Some{id} None{}: M.Invalid{}
    case Some{id} Some{project}: M.Selected{}

def observed_workspace(observation: Context.Observation) -> Maybe<&2, D.Workspace>:
  match observation:
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.InheritedWorkspace{workspace}, sandbox, approval, guidance}}: Some{workspace}
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.EnteredWorkspace{workspace}, sandbox, approval, guidance}}: Some{workspace}
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}: Some{workspace}
    case _: None{}

def primary_state(primary: Maybe<&2, String>) -> M.PropertyState:
  match primary:
    case None{}: M.Absent{}
    case Some{path}: M.Selected{}

def workspace_state(workspace: Maybe<&2, D.Workspace>) -> M.PropertyState:
  match workspace:
    case None{}: M.UnavailableObservation{}
    case Some{workspace}: primary_state(Workspace.primary(workspace))

def observation_state(observation: Context.Observation) -> M.PropertyState:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: M.UnavailableObservation{}
    case _: M.Selected{}

def permitted_state(permitted: Bool) -> M.PropertyState:
  match permitted:
    case True{}: M.Selected{}
    case False{}: M.Invalid{}

def model_state(found: Maybe<&2, D.Profile>, effort: String) -> M.PropertyState:
  match found:
    case None{}: M.Invalid{}
    case Some{+profile}: permitted_state(D.profile_permitted(profile, D.profile_selection(effort, profile)))

def property_state(property: M.Property) -> M.PropertyState:
  match property:
    case M.ProjectObservation{editor, selected, found}: project_state(selected, found)
    case M.WorkspaceObservation{editor, observation, source}: workspace_state(observed_workspace(observation))
    case M.PermissionsObservation{editor, observation}: observation_state(observation)
    case M.ModelObservation{editor, profile, effort, found}: model_state(found, effort)
    case M.DeliveryObservation{editor, delivery}: M.Selected{}

def kind_title(kind: M.PropertyKind) -> String:
  match kind:
    case M.ProjectProperty{}: "Project"
    case M.WorkspaceProperty{}: "Working directory"
    case M.PermissionsProperty{}: "Permissions"
    case M.ModelProperty{}: "Model"
    case M.DeliveryProperty{}: "Delivery"

def property_title(property: M.Property) -> String:
  kind_title(property_kind(property))

def project_value(selected: Maybe<&2, Nat>, found: Maybe<&2, D.Project>) -> String:
  match selected found:
    case None{} _: "No project"
    case Some{id} None{}: "Missing project " ++ Nat.show(id)
    case Some{id} Some{D.Project{name, workspace, guidance}}: name

def segment_fallback(nonempty: Bool, segment: String, fallback: String) -> String:
  match nonempty:
    case True{}: segment
    case False{}: fallback

def last_segment(segments: +List<String>, fallback: String) -> String:
  match segments:
    case Nil{}: fallback
    case Con{+segment, rest}: last_segment(rest, segment_fallback(D.nonempty(segment), segment, fallback))

def primary_caption(primary: Maybe<&2, String>) -> String:
  match primary:
    case None{}: "No directory"
    case Some{+path}: last_segment(String.split(path, '/'), path)

def primary_value(workspace: Maybe<&2, D.Workspace>) -> String:
  match workspace:
    case None{}: "Unavailable"
    case Some{workspace}: primary_caption(Workspace.primary(workspace))

def sandbox_caption(sandbox: D.Sandbox) -> String:
  D.Sandbox{mode, network} = sandbox
  D.sandbox_mode_name(mode)

def permission_value(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      sandbox_caption(Context.unwrap_sandbox(sandbox))
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, access}}:
      Context.filesystem_summary(access, mode)
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "Unavailable"

def model_value(key: String, found: Maybe<&2, D.Profile>) -> String:
  match found:
    case None{}: "Missing model " ++ key
    case Some{D.Profile{key, provider, name, policy, options}}: name

def property_value(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, selected, found}: project_value(selected, found)
    case M.WorkspaceObservation{editor, observation, source}: primary_value(observed_workspace(observation))
    case M.PermissionsObservation{editor, observation}: permission_value(observation)
    case M.ModelObservation{editor, profile, effort, found}: model_value(profile, found)
    case M.DeliveryObservation{editor, delivery}: U.delivery_caption(delivery)

def summary_network_parts(enabled: Bool) -> +List<String>:
  match enabled:
    case True{}: ["Network on"]
    case False{}: Nil{}

def summary_approval_parts(choice: Context.ApprovalChoice) -> +List<String>:
  match choice:
    case Context.Unrestricted{}: ["Unrestricted"]
    case _: Nil{}

def summary_parts_join(parts: +List<String>) -> String:
  match parts:
    case Nil{}: ""
    case Con{part, Nil{}}: part
    case Con{part, rest}: part ++ " · " ++ summary_parts_join(rest)

def sandbox_summary_parts(sandbox: D.Sandbox, choice: Context.ApprovalChoice) -> +List<String>:
  D.Sandbox{mode, network} = sandbox
  D.sandbox_mode_name(mode) <> List.append(&2, String, summary_network_parts(network), summary_approval_parts(choice))

def unrestricted_execution_parts(sandbox: D.Sandbox) -> +List<String>:
  D.Sandbox{mode, network} = sandbox
  [Context.filesystem_summary(D.Unrestricted{}, mode), "Network " ++ String.to_lower(Context.network_summary(D.Unrestricted{}, network)), "No approval"]

def committed_summary_parts(access: D.ExecutionAccess, sandbox: D.Sandbox, choice: Context.ApprovalChoice) -> +List<String>:
  match access:
    case D.Unrestricted{}: unrestricted_execution_parts(sandbox)
    case D.Sandboxed{}: sandbox_summary_parts(sandbox, choice)

def preview_summary_access(access: Maybe<&2, D.ExecutionAccess>, sandbox: D.Sandbox, choice: Context.ApprovalChoice) -> +List<String>:
  match access:
    case None{}: ["Unavailable"]
    case Some{D.Unrestricted{}}: unrestricted_execution_parts(sandbox)
    case Some{D.Sandboxed{}}: sandbox_summary_parts(sandbox, choice)

def preview_permission_parts(+preview: Context.Preview) -> +List<String>:
  match preview:
    case Context.ContextUnavailable{reason}: ["Unavailable"]
    case Context.ProspectiveContext{origin, project, workspace, +sandbox, +approval, guidance}:
      preview_summary_access(Context.preview_access(preview), Context.unwrap_sandbox(sandbox), Context.observed_approval(approval))

def permission_summary_parts(observation: Context.Observation) -> +List<String>:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: ["Unavailable"]
    case Context.DraftExecution{preview}: preview_permission_parts(preview)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}:
      committed_summary_parts(access, sandbox, Context.approval_choice(approval))

def permission_summary(observation: Context.Observation) -> String:
  summary_parts_join(permission_summary_parts(observation))

def strategy_caption(strategy: M.Strategy) -> String:
  match strategy:
    case M.Ask{}: "Ask"
    case M.AutomaticReview{}: "Automatic review"
    case M.FullAccess{}: "Full access"

def permission_secondary_parts(strategy: M.Strategy, values: +List<String>) -> +List<String>:
  match strategy values:
    case M.FullAccess{} Con{filesystem,remaining}: remaining
    case _ values: values

def permission_property_parts_for_choice(+choice: Context.ApprovalChoice, observation: Context.Observation) -> +List<String>:
  strategy_caption(observed_strategy(choice)) <> permission_secondary_parts(observed_strategy(choice),permission_summary_parts(observation))

def permission_property_parts(+observation: Context.Observation) -> +List<String>:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: ["Unavailable"]
    case Context.DraftExecution{Context.ProspectiveContext{origin,project,workspace,sandbox,approval,guidance}}:
      permission_property_parts_for_choice(Context.observed_approval(approval),observation)
    case Context.CommittedExecution{Context.EffectiveContext{task,D.TaskContext{workspace,sandbox,approval,project},guidance,access}}:
      permission_property_parts_for_choice(Context.approval_choice(approval),observation)

def permission_recognition_value(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "Unavailable"
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      strategy_caption(observed_strategy(Context.observed_approval(approval)))
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, D.Unrestricted{}}}: "Full access"
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, D.Sandboxed{}}}:
      strategy_caption(observed_strategy(Context.approval_choice(approval)))

def filesystem_recognition_value(mode: D.SandboxMode) -> String:
  match mode:
    case D.WorkspaceWrite{}: "Workspace write"
    case D.ReadOnly{}: "Read only"

def sandbox_recognition_value(sandbox: D.Sandbox) -> String:
  D.Sandbox{mode, network} = sandbox
  filesystem_recognition_value(mode)

def permission_recognition_secondary_access(access: Maybe<&2, D.ExecutionAccess>, sandbox: D.Sandbox, editor: U.Editor) -> Maybe<&2, M.SummaryValue>:
  match access:
    case Some{D.Sandboxed{}}:
      Some{M.SummaryValue{M.Subject{editor, Forms.SandboxMode{}}, sandbox_recognition_value(sandbox)}}
    case _: None{}

def permission_recognition_secondary(observation: Context.Observation, +editor: U.Editor) -> Maybe<&2, M.SummaryValue>:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: None{}
    case Context.DraftExecution{+preview}:
      match preview:
        case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}:
          permission_recognition_secondary_access(Context.preview_access(preview), Context.unwrap_sandbox(sandbox), editor)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}:
      permission_recognition_secondary_access(Some{access}, sandbox, editor)

def property_recognition_summary(+property: M.Property) -> M.RecognitionSummary:
  match property:
    case M.ProjectObservation{+editor, selected, found}:
      M.RecognitionSummary{property, M.SummaryValue{M.Subject{editor, Forms.ContextOrigin{}}, project_value(selected, found)}, None{}}
    case M.WorkspaceObservation{+editor, observation, source}:
      M.RecognitionSummary{property, M.SummaryValue{M.Subject{editor, Forms.WorkspacePrimary{}}, primary_value(observed_workspace(observation))}, None{}}
    case M.PermissionsObservation{+editor, +observation}:
      M.RecognitionSummary{property, M.SummaryValue{M.Subject{editor, Forms.ApprovalPolicy{}}, permission_recognition_value(observation)}, permission_recognition_secondary(observation, editor)}
    case M.ModelObservation{+editor, profile, effort, found}:
      M.RecognitionSummary{property, M.SummaryValue{M.Subject{editor, Forms.ModelProfile{}}, model_value(profile, found)}, Some{M.SummaryValue{M.Subject{editor, Forms.ReasoningEffort{}}, effort}}}
    case M.DeliveryObservation{editor, delivery}:
      M.RecognitionSummary{property, M.SummaryValue{M.Subject{editor, Forms.DeliveryIntent{}}, U.delivery_caption(delivery)}, None{}}

def summary_property(summary: M.RecognitionSummary) -> M.Property:
  M.RecognitionSummary{property, principal, secondary} = summary
  property

def summary_principal(summary: M.RecognitionSummary) -> M.SummaryValue:
  M.RecognitionSummary{property, principal, secondary} = summary
  principal

def summary_secondary(summary: M.RecognitionSummary) -> Maybe<&2, M.SummaryValue>:
  M.RecognitionSummary{property, principal, secondary} = summary
  secondary

def summary_projection(full: Bool, summary: M.RecognitionSummary) -> M.RecognitionSummary:
  match full summary:
    case True{} value: value
    case False{} M.RecognitionSummary{property, principal, secondary}: M.RecognitionSummary{property, principal, None{}}

def property_summary_parts(property: M.Property) -> +List<String>:
  match property:
    case M.ProjectObservation{editor, selected, found}: [project_value(selected, found)]
    case M.WorkspaceObservation{editor, observation, source}: [primary_value(observed_workspace(observation))]
    case M.PermissionsObservation{editor, observation}: permission_property_parts(observation)
    case M.ModelObservation{editor, profile, effort, found}: [model_value(profile, found) ++ " · " ++ effort]
    case M.DeliveryObservation{editor, delivery}: [U.delivery_caption(delivery)]

def property_summary(property: M.Property) -> String:
  summary_parts_join(property_summary_parts(property))

def origin_detail(origin: Context.Origin) -> String:
  match origin:
    case Context.EnvironmentDefaults{}: "Environment defaults"
    case Context.ProjectDefaults{id}: "From project"
    case Context.ParentTask{id}: "From parent task"
    case Context.ProjectForParent{task, project}: "From project"

def override_detail(origin: Context.Origin) -> String:
  match origin:
    case Context.ProjectDefaults{id}: "Custom · overrides project defaults"
    case Context.ProjectForParent{task, id}: "Custom · overrides project defaults"
    case Context.ParentTask{id}: "Custom · overrides parent task defaults"
    case Context.EnvironmentDefaults{}: "Custom · overrides environment defaults"

def workspace_detail(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: reason
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.InheritedWorkspace{workspace}, sandbox, approval, guidance}}: origin_detail(origin)
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, Context.EnteredWorkspace{workspace}, sandbox, approval, guidance}}: override_detail(origin)
    case Context.CommittedExecution{context}: "Task workspace"

def network_detail(network: Bool) -> String:
  match network:
    case True{}: "Network on"
    case False{}: "Network off"

def approval_detail(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.Ask{}: "Ask"
    case Context.Unrestricted{}: "Unrestricted"
    case Context.AutomaticReview{profile}: "Review " ++ profile

def sandbox_network_caption(sandbox: D.Sandbox) -> String:
  D.Sandbox{mode, network} = sandbox
  network_detail(network)
def permission_base_key(origin: Context.Origin) -> String:
  match origin:
    case Context.EnvironmentDefaults{}: "environment"
    case Context.ProjectDefaults{id}: "environment"
    case Context.ParentTask{id}: "task/" ++ Nat.show(id)
    case Context.ProjectForParent{task, id}: "task/" ++ Nat.show(task)

def sandbox_source_key(origin: Context.Origin, sandbox: Context.SandboxValue) -> String:
  match sandbox:
    case Context.InheritedSandbox{value}: permission_base_key(origin)
    case Context.ChosenSandbox{value}: "custom"

def approval_source_key(origin: Context.Origin, approval: Context.ApprovalValue) -> String:
  match approval:
    case Context.InheritedApproval{value}: permission_base_key(origin)
    case Context.ChosenApproval{value}: "custom"

def permission_source_key(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "unavailable"
    case Context.DraftExecution{Context.ProspectiveContext{+origin, project, workspace, sandbox, approval, guidance}}:
      "sandbox/" ++ sandbox_source_key(origin, sandbox) ++ ";approval/" ++ approval_source_key(origin, approval)
    case Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}}: "task/" ++ Nat.show(task)

def permission_inheritance_detail(sandbox: Context.SandboxValue, approval: Context.ApprovalValue) -> String:
  match sandbox approval:
    case Context.InheritedSandbox{value} Context.InheritedApproval{policy}: "Defaults"
    case _ _: "Custom"

def permission_base_label(origin: Context.Origin) -> String:
  match origin:
    case Context.EnvironmentDefaults{}: "Environment defaults"
    case Context.ProjectDefaults{id}: "Environment defaults"
    case Context.ParentTask{id}: "Parent task " ++ Nat.show(id)
    case Context.ProjectForParent{task, id}: "Parent task " ++ Nat.show(task)

def sandbox_source_label(origin: Context.Origin, sandbox: Context.SandboxValue) -> String:
  match sandbox:
    case Context.InheritedSandbox{value}: permission_base_label(origin)
    case Context.ChosenSandbox{value}: "Custom"

def approval_source_label(origin: Context.Origin, approval: Context.ApprovalValue) -> String:
  match approval:
    case Context.InheritedApproval{value}: permission_base_label(origin)
    case Context.ChosenApproval{value}: "Custom"

def permission_source_detail(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: reason
    case Context.DraftExecution{Context.ProspectiveContext{+origin, project, workspace, sandbox, approval, guidance}}:
      "Filesystem/network: " ++ sandbox_source_label(origin, sandbox) ++ "; Approval: " ++ approval_source_label(origin, approval)
    case Context.CommittedExecution{Context.EffectiveContext{+task, context, guidance, access}}:
      "Filesystem/network: Task " ++ Nat.show(task) ++ "; Approval: Task " ++ Nat.show(task)

def permission_detail(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: reason
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, +sandbox, +approval, guidance}}:
      sandbox_network_caption(Context.unwrap_sandbox(sandbox)) ++ " · " ++ approval_detail(Context.observed_approval(approval)) ++ " · " ++ permission_inheritance_detail(sandbox, approval)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, access}}:
      Context.network_summary(access, network) ++ " · " ++ approval_detail(Context.approval_choice(approval)) ++ " · Task permissions"

def property_detail(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, None{}, found}: "Optional"
    case M.ProjectObservation{editor, Some{id}, None{}}: "Invalid reference"
    case M.ProjectObservation{editor, Some{id}, Some{project}}: "Task context"
    case M.WorkspaceObservation{editor, observation, source}: workspace_detail(observation)
    case M.PermissionsObservation{editor, observation}: permission_detail(observation)
    case M.ModelObservation{editor, key, effort, found}: "Reasoning · " ++ effort
    case M.DeliveryObservation{editor, U.Send{}}: "Send a new message"
    case M.DeliveryObservation{editor, U.Steer{}}: "Guide the current task"

def origin_key(origin: Context.Origin) -> String:
  match origin:
    case Context.EnvironmentDefaults{}: "environment"
    case Context.ProjectDefaults{id}: "project/" ++ Nat.show(id)
    case Context.ParentTask{id}: "task/" ++ Nat.show(id)
    case Context.ProjectForParent{task, id}: "project/" ++ Nat.show(id)

def observation_source(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "unavailable"
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: origin_key(origin)
    case Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}}: "task/" ++ Nat.show(task)

def property_source_key(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, selected, found}: "project/" ++ U.optional_key(selected)
    case M.WorkspaceObservation{editor, observation, source}: observation_source(observation)
    case M.PermissionsObservation{editor, observation}: permission_source_key(observation)
    case M.ModelObservation{editor, profile, effort, found}: "model/" ++ profile
    case M.DeliveryObservation{editor, delivery}: U.editor_key(editor)

def join_paths(roots: +List<String>) -> String:
  match roots:
    case Nil{}: ""
    case Con{path, rest}: path ++ "\n" ++ join_paths(rest)

def workspace_paths(workspace: Maybe<&2, D.Workspace>) -> String:
  match workspace:
    case None{}: ""
    case Some{D.Workspace{roots, primary}}: join_paths(roots)

def source_name(source: Maybe<&2, D.Project>) -> String:
  match source:
    case None{}: ""
    case Some{D.Project{name, workspace, guidance}}: " · " ++ name

def permission_source_description(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: reason
    case Context.DraftExecution{Context.ProspectiveContext{+origin, project, workspace, sandbox, approval, guidance}}:
      "Filesystem and network: " ++ sandbox_source_label(origin, sandbox) ++ "\nApproval: " ++ approval_source_label(origin, approval)
    case Context.CommittedExecution{Context.EffectiveContext{+task, context, guidance, access}}:
      "Filesystem and network: Task " ++ Nat.show(task) ++ "\nApproval: Task " ++ Nat.show(task)

def model_source_description(editor: U.Editor) -> String:
  match editor:
    case U.NewTaskEditor{}: "Configured model list for this new task"
    case U.MessageEditor{task}: "Configured model list for this task"
    case U.AgentEditor{agent}: "Configured model list for this agent profile"
    case U.ForkEditor{task}: "Configured model list for the new fork"
    case _: "Configured model list for this editor"

def property_source_description(property: M.Property) -> String:
  match property:
    case M.ProjectObservation{editor, None{}, found}: "Environment defaults"
    case M.ProjectObservation{editor, Some{id}, None{}}: "The selected project is no longer available"
    case M.ProjectObservation{editor, Some{id}, Some{project}}: "Project configuration"
    case M.WorkspaceObservation{editor, observation, source}: workspace_detail(observation) ++ source_name(source)
    case M.PermissionsObservation{editor, observation}: permission_source_description(observation)
    case M.ModelObservation{editor, profile, effort, found}: model_source_description(editor)
    case M.DeliveryObservation{editor, delivery}: "Message delivery for this task"

def property_help(+property: M.Property) -> String:
  match property:
    case M.WorkspaceObservation{editor, +observation, source}:
      property_source_description(M.WorkspaceObservation{editor, observation, source}) ++ "\n" ++ workspace_paths(observed_workspace(observation))
    case M.PermissionsObservation{editor, +observation}:
      "Permissions: " ++ permission_value(observation) ++ " · " ++ permission_detail(observation) ++ "\n" ++ permission_source_detail(observation)
    case _: property_title(property) ++ ": " ++ property_value(property) ++ " · " ++ property_detail(property)

def scoped_property_support(matches: Bool, action: M.ActionUnit, property: M.Property) -> M.Support:
  match matches:
    case True{}: support(action, property_fields(property))
    case False{}: support(action, Nil{})

def property_support(+action: M.ActionUnit, +property: M.Property) -> M.Support:
  scoped_property_support(U.same_editor(action_editor(action), property_editor(property)), action, property)


def obstruction(editor: U.Editor, field: Forms.Field, code: String, message: String) -> M.Obstruction:
  +subject: M.Subject = M.Subject{editor, field}
  M.Obstruction{owner(subject), Some{subject}, code, message}

def failed_requirement(valid: Bool, obstruction: M.Obstruction) -> +List<M.Obstruction>:
  match valid:
    case True{}: Nil{}
    case False{}: [obstruction]

def origin_failure(preview: Context.Preview, editor: U.Editor) -> +List<M.Obstruction>:
  match preview:
    case Context.ContextUnavailable{reason}: [obstruction(editor, Forms.ContextOrigin{}, "context_unavailable", reason)]
    case _: Nil{}

def context_requirements(+body: U.Body, +world: World.World()) -> +List<M.Obstruction>:
  match body:
    case U.NewTask{message, profile, reasoning, context}: origin_failure(Context.preview(context, world), U.NewTaskEditor{})
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: origin_failure(Context.preview(context, world), U.AgentEditor{id})
    case U.Fork{task, count, messages, context}: origin_failure(Context.preview(context, world), U.ForkEditor{task})
    case _: Nil{}

def model_requirements(found: Maybe<&2, D.Profile>, +effort: String, +editor: U.Editor) -> +List<M.Obstruction>:
  match found:
    case None{}: [obstruction(editor, Forms.ModelProfile{}, "model_not_found", "Choose a configured model")]
    case Some{+profile}: failed_requirement(D.profile_permitted(profile, D.profile_selection(effort, profile)),
      obstruction(editor, Forms.ReasoningEffort{}, "invalid_reasoning", "Choose an allowed reasoning effort"))

def fork_requirements(found: Maybe<&2, D.Task>, +count: Nat, +messages: +List<String>, +task: Nat, +world: World.World()) -> +List<M.Obstruction>:
  match found:
    case None{}: [M.Obstruction{M.Task{task}, None{}, "task_not_found", "The target task does not exist"}]
    case Some{+parent}:
      List.append(&2, M.Obstruction, failed_requirement(Commands.branch_parent_valid(D.task_status(parent), D.task_phase(parent)),
        M.Obstruction{M.Task{task}, None{}, "task_busy", "A manual fork requires an active, idle task"}),
      List.append(&2, M.Obstruction, failed_requirement(Commands.branch_count_valid(count, parent),
        obstruction(U.ForkEditor{task}, Forms.ForkCount{}, "invalid_fork_count", "Choose a fork count within the task limit")),
      List.append(&2, M.Obstruction, failed_requirement(Commands.branch_messages_valid(count, messages),
        obstruction(U.ForkEditor{task}, Forms.ForkMessages{}, "invalid_fork_messages", "Provide one message per fork, or no messages")),
      failed_requirement(Commands.branch_capacity_valid(count, parent, world),
        M.Obstruction{M.Task{task}, None{}, "resource_limit", "An ancestor descendant limit prevents this fork"}))))

def body_requirements(body: U.Body, +world: World.World()) -> +List<M.Obstruction>:
  match body:
    case U.NewTask{message, profile, reasoning, context}:
      List.append(&2, M.Obstruction, failed_requirement(D.nonempty(U.text(message)),
        obstruction(U.NewTaskEditor{}, Forms.MessageText{}, "empty_message", "Write a task to start")),
        model_requirements(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning, U.NewTaskEditor{}))
    case U.Message{task, message, delivery}:
      failed_requirement(D.nonempty(U.text(message)), obstruction(U.MessageEditor{task}, Forms.MessageText{}, "empty_message", "Write a message to send"))
    case U.Project{id, name, workspace}:
      failed_requirement(Projects.name_valid(name), obstruction(U.ProjectEditor{id}, Forms.ProjectName{}, "invalid_project_name", "Enter a project name of at most 256 UTF-8 bytes"))
    case U.Agent{+id, revision, +name, +profile, +reasoning, instructions, context, concurrency}:
      List.append(&2, M.Obstruction, failed_requirement(Board.agent_name_valid(name), obstruction(U.AgentEditor{id}, Forms.AgentName{}, "invalid_agent_name", "Enter a valid agent name")),
      List.append(&2, M.Obstruction, failed_requirement(Board.agent_profile_valid(profile), obstruction(U.AgentEditor{id}, Forms.ModelProfile{}, "invalid_agent_profile", "Enter a valid model profile")),
      List.append(&2, M.Obstruction, failed_requirement(Board.agent_reasoning_valid(reasoning), obstruction(U.AgentEditor{id}, Forms.ReasoningEffort{}, "invalid_agent_reasoning", "Enter a valid reasoning effort")),
      List.append(&2, M.Obstruction, failed_requirement(Board.agent_instructions_valid(instructions), obstruction(U.AgentEditor{id}, Forms.AgentInstructions{}, "invalid_agent_instructions", "Shorten the agent instructions")),
      List.append(&2, M.Obstruction, failed_requirement(Board.agent_concurrency_valid(concurrency), obstruction(U.AgentEditor{id}, Forms.AgentConcurrency{}, "invalid_agent_concurrency", "Choose concurrency from 1 to 64")),
      model_requirements(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning, U.AgentEditor{id}))))))
    case U.Fork{+task, count, messages, context}:
      fork_requirements(Tasks.find(Commands.entries(world), task), count, messages, task, world)
    case _: Nil{}

def agent_reference_requirement(found: Maybe<&2, Board.AgentProfile>, editor: U.Editor) -> +List<M.Obstruction>:
  match found:
    case Some{agent}: Nil{}
    case None{}: [M.Obstruction{root_object(editor), None{}, "agent_not_found", "The agent does not exist"}]

def existing_agent_requirement(selected: Maybe<&2, Nat>, +world: World.World()) -> +List<M.Obstruction>:
  match selected:
    case None{}: Nil{}
    case Some{+id}: agent_reference_requirement(Board.find_agent(BoardState.registry(world), id), U.AgentEditor{Some{id}})

def record_requirements(body: U.Body, world: World.World()) -> +List<M.Obstruction>:
  match body:
    case U.Project{+id, name, workspace}: failed_requirement(Projects.reference_valid(id, Projects.registry(F.State(), world)),
      M.Obstruction{root_object(U.ProjectEditor{id}), None{}, "project_not_found", "The project does not exist"})
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: existing_agent_requirement(id, world)
    case _: Nil{}
def requirements(+body: U.Body, pending: Bool, +world: World.World()) -> +List<M.Obstruction>:
  List.append(&2, M.Obstruction, failed_requirement(Bool.not(pending),
    M.Obstruction{root_object(U.owner(body)), None{}, "pending", "Wait for the current submission"}),
  List.append(&2, M.Obstruction, failed_requirement(U.valid_origin(body),
    obstruction(U.owner(body), Forms.ContextOrigin{}, "invalid_origin", "Choose a valid task context")),
  List.append(&2, M.Obstruction, context_requirements(body, world), List.append(&2, M.Obstruction, record_requirements(body, world), body_requirements(body, world)))))

def requirements_empty(requirements: +List<M.Obstruction>) -> Bool:
  match requirements:
    case Nil{}: True{}
    case Con{obstruction, rest}: False{}

def workspace_rejection_current(feedback: U.Feedback, revision: Nat) -> Bool:
  match feedback:
    case U.WorkspaceRejected{submitted, reason}: Nat.is_eq(submitted, revision)
    case _: False{}

def workspace_rejection_reason(feedback: U.Feedback) -> String:
  match feedback:
    case U.WorkspaceRejected{revision, reason}: reason
    case _: ""

def known_workspace_requirement(current: Bool, editor: U.Editor, reason: String) -> +List<M.Obstruction>:
  match current:
    case True{}: [obstruction(editor, Forms.WorkspaceDirectories{}, "workspace_observation_failed", reason)]
    case False{}: Nil{}

def same_paths(left: +List<String>, right: +List<String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{first, rest} Con{other, remaining}: String.eq(first, other) && same_paths(rest, remaining)
    case _ _: False{}

def same_primary(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{first} Some{other}: String.eq(first, other)
    case _ _: False{}

def same_workspace(left: D.Workspace, right: D.Workspace) -> Bool:
  D.Workspace{roots, primary} = left
  D.Workspace{other, selected} = right
  same_paths(roots, other) && same_primary(primary, selected)

def project_original(body: U.Body, world: World.World()) -> Maybe<&2, D.Project>:
  match body:
    case U.Project{id, name, workspace}: selected_project(id, world)
    case _: None{}

def project_changed(original: Maybe<&2, D.Project>, +name: String, workspace: D.Workspace) -> Bool:
  match original:
    case None{}: True{}
    case Some{D.Project{other, previous, guidance}}: Bool.not(String.eq(name, other) && same_workspace(workspace, previous))

def project_draft_changed(original: Maybe<&2, D.Project>, name: String, workspace: D.Workspace, +entry: String) -> Bool:
  Bool.not(String.eq(entry, "")) || project_changed(original, name, workspace)

def draft_changed(+draft: U.Draft, world: World.World()) -> Bool:
  U.Draft{revision, +body, feedback, entry} = draft
  match body:
    case U.Project{id, name, workspace}: project_draft_changed(project_original(body, world), name, workspace, entry)
    case _: True{}

def project_edit_requirements(+body: U.Body, +entry: String, +world: World.World()) -> +List<M.Obstruction>:
  match body:
    case U.Project{+id, name, workspace}:
      List.append(&2, M.Obstruction,
        failed_requirement(String.eq(entry, ""), obstruction(U.ProjectEditor{id}, Forms.WorkspaceDirectories{}, "unadded_directory", "Add or clear the directory before saving")),
        failed_requirement(project_draft_changed(project_original(body, world), name, workspace, entry),
          M.Obstruction{root_object(U.ProjectEditor{id}), None{}, "unchanged_project", "No project changes to save"}))
    case _: Nil{}

def draft_requirements(draft: U.Draft, pending: Bool, +world: World.World()) -> +List<M.Obstruction>:
  U.Draft{revision, +body, +feedback, entry} = draft
  List.append(&2, M.Obstruction,
    known_workspace_requirement(workspace_rejection_current(feedback, revision), U.owner(body), workspace_rejection_reason(feedback)),
    List.append(&2, M.Obstruction, project_edit_requirements(body, entry, world), requirements(body, pending, world)))

def draft_can_prepare(draft: U.Draft, pending: Bool, world: World.World()) -> Bool:
  requirements_empty(draft_requirements(draft, pending, world))

def can_prepare(body: U.Body, pending: Bool, world: World.World()) -> Bool:
  requirements_empty(requirements(body, pending, world))

def resolved_assessment(operation: Commands.Operation, identity: M.ActionIdentity, editor: U.Editor) -> M.Assessment:
  match operation:
    case Commands.Refuse{code, reason}: M.Assessment{identity, Nil{}, M.Blocked{}, Some{M.Obstruction{root_object(editor), None{}, code, reason}}}
    case _: M.Assessment{identity, Nil{}, M.Ready{}, None{}}

def prepared_assessment(workspace: Maybe<&2, D.Workspace>, +body: U.Body, revision: Nat, now: U32, world: World.World()) -> M.Assessment:
  match workspace:
    case Some{workspace}: M.Assessment{M.ActionIdentity{U.owner(body), revision}, Nil{}, M.NeedsDirectoryObservation{}, None{}}
    case None{}: resolved_assessment(Commands.resolve(U.command(body, now), world), M.ActionIdentity{U.owner(body), revision}, U.owner(body))

def assessed_requirements(requirements: +List<M.Obstruction>, +body: U.Body, revision: Nat, now: U32, world: World.World()) -> M.Assessment:
  match requirements:
    case Nil{}: prepared_assessment(U.required_workspace(body), body, revision, now, world)
    case Con{first, rest}: M.Assessment{M.ActionIdentity{U.owner(body), revision}, first <> rest, M.Blocked{}, None{}}

def assess(+body: U.Body, revision: Nat, pending: Bool, now: U32, +world: World.World()) -> M.Assessment:
  assessed_requirements(requirements(body, pending, world), body, revision, now, world)

def assessment_identity(assessment: M.Assessment) -> M.ActionIdentity:
  M.Assessment{identity, requirements, state, refusal} = assessment
  identity

def assessment_state(assessment: M.Assessment) -> M.AssessmentState:
  M.Assessment{identity, requirements, state, refusal} = assessment
  state

def refusal_obstructions(refusal: Maybe<&2, M.Obstruction>) -> +List<M.Obstruction>:
  match refusal:
    case None{}: Nil{}
    case Some{obstruction}: [obstruction]

def assessment_obstructions(assessment: M.Assessment) -> +List<M.Obstruction>:
  M.Assessment{identity, requirements, state, refusal} = assessment
  List.append(&2, M.Obstruction, requirements, refusal_obstructions(refusal))

def obstruction_target(obstruction: M.Obstruction) -> M.Object:
  M.Obstruction{target, field, code, message} = obstruction
  target

def obstruction_field(obstruction: M.Obstruction) -> Maybe<&2, M.Subject>:
  M.Obstruction{target, field, code, message} = obstruction
  field

def obstruction_code(obstruction: M.Obstruction) -> String:
  M.Obstruction{target, field, code, message} = obstruction
  code

def obstruction_message(obstruction: M.Obstruction) -> String:
  M.Obstruction{target, field, code, message} = obstruction
  message

def first_reason(obstructions: +List<M.Obstruction>) -> String:
  match obstructions:
    case Nil{}: ""
    case Con{first, rest}: obstruction_message(first)

def first_field(obstructions: +List<M.Obstruction>) -> Maybe<&2, M.Subject>:
  match obstructions:
    case Nil{}: None{}
    case Con{first, rest}: obstruction_field(first)

def field_member(fields: +List<Forms.Field>, +field: Forms.Field) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{current, rest}: String.eq(Forms.key(current), Forms.key(field)) || field_member(rest, field)

def property_subject_matches(+property: M.Property, subject: Maybe<&2, M.Subject>) -> Bool:
  match subject:
    case None{}: False{}
    case Some{M.Subject{editor, field}}: U.same_editor(property_editor(property), editor) && field_member(property_fields(property), field)

def obstruction_has_field(field: Maybe<&2, M.Subject>) -> Bool:
  match field:
    case None{}: False{}
    case Some{subject}: True{}

def passive_obstruction(obstruction: M.Obstruction) -> Bool:
  M.Obstruction{target, field, +code, message} = obstruction
  String.eq(code, "empty_message") || String.eq(code, "pending")

def attention_obstruction_select(passive: Bool, obstruction: M.Obstruction, rest: Maybe<&2, M.Obstruction>) -> Maybe<&2, M.Obstruction>:
  match passive:
    case True{}: rest
    case False{}: Some{obstruction}

def attention_obstruction_list(obstructions: +List<M.Obstruction>) -> Maybe<&2, M.Obstruction>:
  match obstructions:
    case Nil{}: None{}
    case Con{+obstruction, rest}: attention_obstruction_select(passive_obstruction(obstruction), obstruction, attention_obstruction_list(rest))

def attention_obstruction(assessment: M.Assessment) -> Maybe<&2, M.Obstruction>:
  attention_obstruction_list(assessment_obstructions(assessment))

def matched_obstruction(matches: Bool, obstruction: M.Obstruction) -> Maybe<&2, M.Obstruction>:
  match matches:
    case True{}: Some{obstruction}
    case False{}: None{}

def property_obstruction_found(property: M.Property, found: Maybe<&2, M.Obstruction>) -> Maybe<&2, M.Obstruction>:
  match found:
    case None{}: None{}
    case Some{+obstruction}: matched_obstruction(property_subject_matches(property, obstruction_field(obstruction)), obstruction)

def property_obstruction(property: M.Property, assessment: M.Assessment) -> Maybe<&2, M.Obstruction>:
  property_obstruction_found(property, attention_obstruction(assessment))

def same_subject(+left: M.Subject, +right: M.Subject) -> Bool:
  String.eq(subject_key(left), subject_key(right))

def subject_obstruction_matches(subject: M.Subject, field: Maybe<&2, M.Subject>) -> Bool:
  match field:
    case None{}: False{}
    case Some{field}: same_subject(subject, field)

def subject_obstruction_found(subject: M.Subject, found: Maybe<&2, M.Obstruction>) -> Maybe<&2, M.Obstruction>:
  match found:
    case None{}: None{}
    case Some{+obstruction}: matched_obstruction(subject_obstruction_matches(subject, obstruction_field(obstruction)), obstruction)

def subject_obstruction(subject: M.Subject, assessment: M.Assessment) -> Maybe<&2, M.Obstruction>:
  subject_obstruction_found(subject, attention_obstruction(assessment))

def assessment_reason(assessment: M.Assessment) -> String:
  first_reason(assessment_obstructions(assessment))

def assessment_field(assessment: M.Assessment) -> Maybe<&2, M.Subject>:
  first_field(assessment_obstructions(assessment))

def state_ready(state: M.AssessmentState) -> Bool:
  match state:
    case M.Ready{}: True{}
    case M.NeedsDirectoryObservation{}: True{}
    case M.Blocked{}: False{}

# Readiness permits the next preparation step; it is not directory validation.
def assessment_ready(assessment: M.Assessment) -> Bool:
  state_ready(assessment_state(assessment))


def identity_editor(identity: M.ActionIdentity) -> U.Editor:
  M.ActionIdentity{editor, revision} = identity
  editor

def restriction_obstructions(+assessment: M.Assessment, reason: String) -> +List<M.Obstruction>:
  List.append(&2, M.Obstruction, assessment_obstructions(assessment),
    [M.Obstruction{root_object(identity_editor(assessment_identity(assessment))), None{}, "control_unavailable", reason}])

# A final control refusal is an observed service obstruction. Earlier causes,
# including backend refusal, survive in the same ordered observation list.
def restricted(+assessment: M.Assessment, reason: String) -> M.Assessment:
  M.Assessment{assessment_identity(assessment), restriction_obstructions(assessment, reason), M.Blocked{}, None{}}

def project_edit(+draft: U.Draft, +pending: Bool, now: U32, +world: World.World()) -> M.ProjectEdit:
  U.Draft{+revision, +body, feedback, entry} = draft
  M.ProjectEdit{project_original(body, world), draft, pending, draft_changed(draft, world),
    assessed_requirements(draft_requirements(draft, pending, world), body, revision, now, world)}

def project_edit_original(edit: M.ProjectEdit) -> Maybe<&2, D.Project>:
  M.ProjectEdit{original, draft, pending, dirty, assessment} = edit
  original

def project_edit_draft(edit: M.ProjectEdit) -> U.Draft:
  M.ProjectEdit{original, draft, pending, dirty, assessment} = edit
  draft

def project_edit_pending(edit: M.ProjectEdit) -> Bool:
  M.ProjectEdit{original, draft, pending, dirty, assessment} = edit
  pending

def project_edit_changed(edit: M.ProjectEdit) -> Bool:
  M.ProjectEdit{original, draft, pending, dirty, assessment} = edit
  dirty

def project_edit_assessment(edit: M.ProjectEdit) -> M.Assessment:
  M.ProjectEdit{original, draft, pending, dirty, assessment} = edit
  assessment

def project_edit_property_from_body(body: U.Body, edit: M.ProjectEdit) -> M.Property:
  match body:
    case U.Project{+id, name, workspace}: M.ProjectObservation{U.ProjectEditor{id}, id, project_edit_original(edit)}
    case _: M.ProjectObservation{U.owner(body), None{}, None{}}

def project_edit_property_from_draft(draft: U.Draft, edit: M.ProjectEdit) -> M.Property:
  U.Draft{revision, body, feedback, entry} = draft
  project_edit_property_from_body(body, edit)

def project_edit_property(+edit: M.ProjectEdit) -> M.Property:
  project_edit_property_from_draft(project_edit_draft(edit), edit)

def candidate_admission(+parent: M.Decision, +alternative: M.Alternative) -> M.Decision:
  decision(decision_subject(parent), decision_observation(parent), decision_question(parent), [alternative])

def candidate_input(admission: M.Decision, alternative: M.Alternative) -> Maybe<&2, U.Input>:
  M.Alternative{label, explanation, value} = alternative
  choose(admission, value)

def candidate_canonical(+decision: M.Decision, alternative: M.Alternative) -> Maybe<&2, U.Input>:
  M.Alternative{label, explanation, value} = alternative
  canonical(decision_subject(decision), decision_observation(decision), value)

def candidate(+decision: M.Decision, +alternative: M.Alternative) -> M.CandidateObservation:
  +admission: M.Decision = candidate_admission(decision, alternative)
  M.CandidateObservation{decision, alternative, candidate_canonical(decision, alternative), admission, candidate_input(admission, alternative)}

def candidate_decision(observation: M.CandidateObservation) -> M.Decision:
  M.CandidateObservation{decision, alternative, canonical, admission, input} = observation
  decision

def candidate_alternative(observation: M.CandidateObservation) -> M.Alternative:
  M.CandidateObservation{decision, alternative, canonical, admission, input} = observation
  alternative

def candidate_canonical_result(observation: M.CandidateObservation) -> Maybe<&2, U.Input>:
  M.CandidateObservation{decision, alternative, canonical, admission, input} = observation
  canonical

def candidate_admitted_decision(observation: M.CandidateObservation) -> M.Decision:
  M.CandidateObservation{decision, alternative, canonical, admission, input} = observation
  admission

def missing_reviewer_reason(found: Maybe<&2, D.Profile>) -> Maybe<&2, String>:
  match found:
    case None{}: Some{"The automatic review model is not available"}
    case Some{profile}: None{}

def reviewer_catalog_reason(+reviewers: +List<D.Profile>, key: String) -> Maybe<&2, String>:
  match reviewers:
    case Nil{}: Some{"No automatic review models are available"}
    case Con{first, rest}: missing_reviewer_reason(D.find_profile(reviewers, key))

def automatic_strategy_reason(reviewers: +List<D.Profile>) -> Maybe<&2, String>:
  match reviewers:
    case Nil{}: Some{"No automatic review models are available"}
    case Con{first, rest}: None{}

def approval_value_reason(value: M.Value, reviewers: +List<D.Profile>) -> Maybe<&2, String>:
  match value:
    case M.ExecutionStrategy{M.AutomaticReview{}}: automatic_strategy_reason(reviewers)
    case M.Approval{Context.AutomaticReview{key}}: reviewer_catalog_reason(reviewers, key)
    case _: None{}

def candidate_field_reason(field: Forms.Field, observation: Forms.Observed, value: M.Value) -> Maybe<&2, String>:
  match field observation:
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}: approval_value_reason(value, reviewers)
    case Forms.ApprovalReviewer{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}: approval_value_reason(value, reviewers)
    case _ _: None{}

def candidate_subject_reason(subject: M.Subject, observation: Forms.Observed, value: M.Value) -> Maybe<&2, String>:
  M.Subject{editor, field} = subject
  candidate_field_reason(field, observation, value)

def candidate_alternative_reason(+decision: M.Decision, alternative: M.Alternative) -> Maybe<&2, String>:
  M.Alternative{label, explanation, value} = alternative
  candidate_subject_reason(decision_subject(decision), decision_observation(decision), value)

def reasoned_refusal(reason: Maybe<&2, String>, fallback: String) -> M.Availability:
  match reason:
    case None{}: M.Unavailable{fallback}
    case Some{reason}: M.Unavailable{reason}

def candidate_reasoned_availability(availability: M.Availability, decision: M.Decision, alternative: M.Alternative) -> M.Availability:
  match availability:
    case M.Available{}: M.Available{}
    case M.Unavailable{reason}: reasoned_refusal(candidate_alternative_reason(decision, alternative), reason)

def candidate_availability(+observation: M.CandidateObservation) -> M.Availability:
  candidate_reasoned_availability(decision_availability(candidate_admitted_decision(observation)), candidate_decision(observation), candidate_alternative(observation))

def candidate_reason_from_availability(availability: M.Availability) -> Maybe<&2, String>:
  match availability:
    case M.Available{}: None{}
    case M.Unavailable{reason}: Some{reason}

def candidate_reason(observation: M.CandidateObservation) -> Maybe<&2, String>:
  candidate_reason_from_availability(candidate_availability(observation))

def candidate_selection_input(observation: M.CandidateObservation) -> Maybe<&2, U.Input>:
  M.CandidateObservation{decision, alternative, canonical, admission, input} = observation
  input

def candidate_selected_from_alternative(decision: M.Decision, alternative: M.Alternative) -> Bool:
  M.Alternative{label, explanation, value} = alternative
  selected(decision, value)

def candidate_selected(+observation: M.CandidateObservation) -> Bool:
  candidate_selected_from_alternative(candidate_decision(observation), candidate_alternative(observation))

def candidate_observations(+decision: M.Decision, alternatives: +List<M.Alternative>) -> +List<M.CandidateObservation>:
  match alternatives:
    case Nil{}: Nil{}
    case Con{alternative, rest}: candidate(decision, alternative) <> candidate_observations(decision, rest)


# Presence comes from typed observations and catalog lookups at the property owner.
def reviewer_presence(found: Maybe<&2,D.Profile>) -> M.InformationStatus:
  match found:
    case Some{profile}: M.PresentInformation{}
    case None{}: M.RequiredAbsence{"Choose an available reviewing model"}

def approval_information(choice: Context.ApprovalChoice, field: Forms.Field, profiles: +List<D.Profile>) -> M.InformationStatus:
  match choice field:
    case Context.AutomaticReview{key} Forms.ApprovalReviewer{}: reviewer_presence(D.find_profile(profiles, key))
    case _ _: M.PresentInformation{}

def permission_information(observation: Context.Observation, field: Forms.Field, profiles: +List<D.Profile>) -> M.InformationStatus:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: M.UnavailableInformation{reason}
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      approval_information(Context.observed_approval(approval), field, profiles)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}:
      approval_information(Context.approval_choice(approval), field, profiles)

def selected_project_information(selected: Maybe<&2,Nat>, found: Maybe<&2,D.Project>) -> M.InformationStatus:
  match selected found:
    case None{} _: M.OptionalAbsence{}
    case Some{id} None{}: M.RequiredAbsence{"Choose an available project"}
    case Some{id} Some{project}: M.PresentInformation{}

def permitted_information(permitted: Bool) -> M.InformationStatus:
  match permitted:
    case True{}: M.PresentInformation{}
    case False{}: M.RequiredAbsence{"Choose an allowed reasoning effort"}

def model_field_information(found: Maybe<&2,D.Profile>, field: Forms.Field, effort: String) -> M.InformationStatus:
  match found field:
    case None{} Forms.ModelProfile{}: M.RequiredAbsence{"Choose a configured model"}
    case None{} _: M.UnavailableInformation{"Choose a configured model before inspecting its parameters"}
    case Some{+profile} Forms.ReasoningEffort{}:
      permitted_information(D.profile_permitted(profile, D.profile_selection(effort, profile)))
    case Some{profile} _: M.PresentInformation{}


def information_field(subject: M.Subject) -> Forms.Field:
  M.Subject{editor, field} = subject
  field

def workspace_information(found: Maybe<&2,D.Workspace>) -> M.InformationStatus:
  match found:
    case None{}: M.UnavailableInformation{"Workspace information is unavailable"}
    case Some{workspace}: M.PresentInformation{}


def property_field_information(observed: M.Property, field: Forms.Field, profiles: +List<D.Profile>) -> M.InformationStatus:
  match observed:
    case M.ProjectObservation{editor, selected, found}: selected_project_information(selected, found)
    case M.PermissionsObservation{editor, observation}: permission_information(observation, field, profiles)
    case M.ModelObservation{editor, profile, effort, found}: model_field_information(found, field, effort)
    case M.WorkspaceObservation{editor, observation, source}: workspace_information(observed_workspace(observation))
    case M.DeliveryObservation{editor, delivery}: M.PresentInformation{}


def property_information(property: M.Property, subject: M.Subject, profiles: +List<D.Profile>) -> M.InformationStatus:
  property_field_information(property, information_field(subject), profiles)

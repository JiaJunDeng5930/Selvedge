import Base
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

def value_key(value: M.Value) -> String:
  match value:
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

def property_intent(field: Forms.Field, observation: Forms.Observed, value: M.Value) -> Maybe<&2, U.Edit>:
  match field observation value:
    case Forms.SandboxMode{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}} M.Filesystem{mode}:
      filesystem_intent(Context.unwrap_sandbox(sandbox), mode)
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}} M.Network{enabled}:
      network_intent(Context.unwrap_sandbox(sandbox), enabled)
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}} M.Approval{choice}: Some{U.ConfigureContext{Context.SetApproval{choice}}}
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
    case Forms.SandboxMode{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}} M.Filesystem{mode}:
      filesystem_selected(Context.unwrap_sandbox(sandbox), mode)
    case Forms.NetworkAccess{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}} M.Network{enabled}:
      network_selected(Context.unwrap_sandbox(sandbox), enabled)
    case Forms.ApprovalPolicy{} Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}} M.Approval{choice}: value_same(M.Approval{Context.observed_approval(approval)}, M.Approval{choice})
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

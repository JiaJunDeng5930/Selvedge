import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../harness/transport/schema.bend as Schema

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

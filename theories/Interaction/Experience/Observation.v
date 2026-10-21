From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Domain Codec ModelCapabilities WorkspaceBackend.
From Selvedge.Features Require Domain BoardParameters.
From Selvedge.Interaction Require Import Codec Identity Context Resource Services CommandAssessment DocumentState ModelSelection.
From Selvedge.Interaction.Session Require Draft State Observation Initialize.
From Selvedge.Interaction.Submission Require Fields Parameters Values Command.
From Selvedge.Interaction.Experience Require Import Model Activity.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition profile_label (value:Selvedge.Kernel.Domain.profile):string:=
 match string_field "name"(Selvedge.Kernel.Domain.profile_metadata value)with
 |Some name=>name|None=>Selvedge.Kernel.Domain.profile_provider value++" / "++Selvedge.Kernel.Domain.profile_model value end.
Definition observe_subject snapshot state {e}(subject:Model.subject e):Fields.observed:=
 Session.Observation.observe_field_in_state snapshot state(State.current_draft state e)(subject_declaration subject).
Definition profile_for_subject snapshot {e}(subject:Model.subject e) key:=match e with
|Identity.Message task=>Session.Observation.task_profile task snapshot
|_=>ModelSelection.observed_profile snapshot key end.
Definition project_choices snapshot caption:=Fields.ChoiceValue "" caption::
 fold_right(fun project rest=>match natural_field "id" project,string_field "name" project with
 |Some id,Some name=>Fields.ChoiceValue(show_natural id)name::rest|_,_=>rest end)[](items "projects" snapshot).
Definition current_frozen_choice snapshot {e}(subject:Model.subject e):option Selvedge.Kernel.Domain.profile:=let declaration:=subject_declaration subject in match e,declaration with
|Identity.Message task,Fields.ModelProfile=>Session.Observation.task_profile task snapshot
|Identity.Message task,Fields.ApprovalReviewer=>settings<-Session.Observation.task_settings task snapshot;;
 match Selvedge.Kernel.Domain.settings_approval settings with Selvedge.Kernel.Domain.ReviewWith reviewer=>Some reviewer|_=>None end
|_,_=>None end.
Definition retain_observed_choice snapshot {e}(subject:Model.subject e)(profiles:list Selvedge.Kernel.Domain.profile):list Selvedge.Kernel.Domain.profile:=
 match current_frozen_choice snapshot subject with
 |Some current=>if existsb(fun profile=>String.eqb(Selvedge.Kernel.Domain.profile_key current)(Selvedge.Kernel.Domain.profile_key profile))profiles then profiles else current::profiles
 |None=>profiles end.
Definition explicit_choices snapshot state {e}(subject:Model.subject e):list Fields.choice_value:=
 let profiles:=Session.Observation.catalog snapshot in
 let models:=map(fun profile=>Fields.ChoiceValue(Selvedge.Kernel.Domain.profile_key profile)(profile_label profile))(retain_observed_choice snapshot subject profiles)in
 match subject_declaration subject with
 |Fields.ContextOrigin=>project_choices snapshot "No project"
 |Fields.CardProject=>project_choices snapshot "No project"
 |Fields.ModelProfile|Fields.AssistanceProfile=>models
 |Fields.ApprovalReviewer=>map(fun profile=>Fields.ChoiceValue(Selvedge.Kernel.Domain.profile_key profile)(profile_label profile))
   (retain_observed_choice snapshot subject(filter Selvedge.Kernel.ModelCapabilities.valid_reviewer_profile profiles))
 |Fields.ReasoningEffort=>let value:=observe_subject snapshot state subject in
   match value with Fields.ModelValue profile _=>map(fun effort=>Fields.ChoiceValue effort
      (if String.eqb effort "default"then "Configured default"else effort))(match profile_for_subject snapshot subject profile with Some selected=>ModelSelection.reasoning_values_for selected|None=>[]end)|_=>[]end
 |Fields.TaskEnvironment=>[Fields.ChoiceValue "current" "Current workspace";
   Fields.ChoiceValue(WorkspaceBackend.name WorkspaceBackend.Local)"Local worktree";
   Fields.ChoiceValue(WorkspaceBackend.name WorkspaceBackend.TencentCvm)"Tencent Cloud CVM"]
 |Fields.SandboxMode=>[Fields.ChoiceValue "workspace-write" "Workspace write";Fields.ChoiceValue "read-only" "Read only"]
 |Fields.NetworkAccess=>[Fields.ChoiceValue "false" "Restricted";Fields.ChoiceValue "true" "Allowed"]
 |Fields.ApprovalPolicy=>[Fields.ChoiceValue "ask-for-approval" "Ask for approval";
   Fields.ChoiceValue "approval-for-me" "Automatic review";Fields.ChoiceValue "full-access" "Unrestricted"]
 |Fields.DeliveryIntent=>[Fields.ChoiceValue "send" "Send message";Fields.ChoiceValue "steer" "Steer current response"]
 |Fields.CardStage=>map(fun stage=>let name:=Selvedge.Features.Domain.stage_name stage in Fields.ChoiceValue name(Selvedge.Features.Domain.stage_label stage))Selvedge.Features.Domain.stages
 |Fields.CardPriority=>map(fun priority=>let name:=Selvedge.Features.Domain.priority_name priority in Fields.ChoiceValue name(Selvedge.Features.Domain.priority_label priority))Selvedge.Features.Domain.priorities
 |Fields.CardOwner=>[Fields.ChoiceValue "none" "未分配";Fields.ChoiceValue "self" "我"]++
    map(fun profile=>Fields.ChoiceValue("profile/"++Selvedge.Kernel.Domain.profile_key profile)(profile_label profile))profiles++
    fold_right(fun agent rest=>match natural_field "id" agent,string_field "name" agent with
    |Some id,Some name=>Fields.ChoiceValue("agent/"++show_natural id)name::rest|_,_=>rest end)[]
      (match field "board" snapshot with Some board=>items "agents" board|None=>[]end)
 |Fields.WorkspacePrimary=>match observe_subject snapshot state subject with
   |Fields.WorkspaceValue workspace=>map(fun path=>Fields.ChoiceValue path path)(Selvedge.Kernel.Domain.workspace_roots workspace)
   |Fields.ContextValue(Context.ProspectiveContext _ _ workspace _ _ _)_=>let value:=match workspace with
      Context.InheritedWorkspace value|Context.EnteredWorkspace value=>value end in
      map(fun path=>Fields.ChoiceValue path path)(Selvedge.Kernel.Domain.workspace_roots value)|_=>[]end
 |Fields.CreateWorktree|Fields.ContinueCapture|Fields.AssistedCapture=>[Fields.ChoiceValue "false" "No";Fields.ChoiceValue "true" "Yes"]
 |_=>[]end.
Definition choices snapshot state {e}(subject:Model.subject e):list Fields.choice_value:=
 let explicit:=explicit_choices snapshot state subject in
 match subject_declaration subject with
  |Fields.SandboxMode|Fields.NetworkAccess|Fields.ApprovalPolicy|Fields.ApprovalReviewer=>
  if Parameters.inheritable e then Fields.ChoiceValue "" "Use inherited setting"::explicit else explicit
 |_=>explicit end.
Definition entry snapshot state {e}(subject:Model.subject e):Fields.entry:=
 match subject_declaration subject with
 |Fields.ReasoningEffort=>match observe_subject snapshot state subject with
  |Fields.ModelValue key _=>match profile_for_subject snapshot subject key with
   |Some profile=>match Selvedge.Kernel.Domain.profile_policy profile with
    |Selvedge.Kernel.Domain.AdaptivePolicy _=>Fields.DisplayOnly
    |Selvedge.Kernel.Domain.FixedReasoning=>match Selvedge.Kernel.Domain.profile_reasoning_options profile with
      |[]=>Fields.SingleLine|_=>Fields.Choice end end
   |None=>Fields.DisplayOnly end
  |_=>Fields.DisplayOnly end
 |_=>Parameters.entry_for(subject_declaration subject)end.
Definition related_summary {e} field value:option(summary_value e):=
 subject<-Model.admit_subject e(Parameters.name field);;Some(SummaryValue subject value).
Definition sandbox_label sandbox:=match Selvedge.Kernel.Domain.sandbox_access sandbox with
|Selvedge.Kernel.Domain.ReadOnly=>"Read only"|Selvedge.Kernel.Domain.WorkspaceWrite=>"Workspace write"end.
Definition network_label sandbox:=if Selvedge.Kernel.Domain.sandbox_network sandbox then "Network allowed"else "Network restricted".
Definition approval_caption approval:=match approval with
|Selvedge.Kernel.Domain.FullAccess=>"Unrestricted"|Selvedge.Kernel.Domain.AskForApproval=>"Ask for approval"
|Selvedge.Kernel.Domain.ReviewWith _=>"Automatic review"end.
Definition resolve_approval snapshot value:=match value with
|Context.InheritedApproval approval=>Some approval
|Context.ChosenApproval Context.Ask=>Some Selvedge.Kernel.Domain.AskForApproval
|Context.ChosenApproval Context.Unrestricted=>Some Selvedge.Kernel.Domain.FullAccess
|Context.ChosenApproval(Context.AutomaticReview key)=>profile<-ModelSelection.observed_profile snapshot key;;
 if Selvedge.Kernel.ModelCapabilities.valid_reviewer_profile profile then Some(Selvedge.Kernel.Domain.ReviewWith profile)else None end.
Definition workspace_information {e}(subject:Model.subject e) workspace inherited:information e:=
 match Selvedge.Kernel.Domain.workspace_primary workspace,Selvedge.Kernel.Domain.workspace_roots workspace with
 |None,[]=>OptionalAbsence
 |None,_=>RequiredAbsence "Choose a primary working directory."
 |Some _,_=>PresentInformation(SummaryValue subject(Model.WorkspaceValue
    (Selvedge.Kernel.Domain.workspace_roots workspace)(Selvedge.Kernel.Domain.workspace_primary workspace)inherited))None end.
Definition context_information snapshot {e}(subject:Model.subject e) project workspace inherited sandbox approval:information e:=
 let present value:=PresentInformation(SummaryValue subject value)None in
 match subject_declaration subject with
 |Fields.ContextOrigin=>match project with
  |None=>OptionalAbsence
  |Some id=>match Session.Observation.project_name id snapshot with
   |Some name=>present(NamedReference id name)
   |None=>UnavailableInformation "The selected project is no longer available."end end
 |Fields.WorkspaceDirectories|Fields.WorkspacePrimary=>workspace_information subject workspace inherited
 |Fields.SandboxMode=>present(NamedChoice(sandbox_label sandbox)(network_label sandbox))
 |Fields.NetworkAccess=>present(Model.TextValue(network_label sandbox))
 |Fields.ApprovalReviewer=>match approval with
  |Some(Selvedge.Kernel.Domain.ReviewWith reviewer)=>present(NamedChoice(profile_label reviewer)"Reviewing model")
  |Some _=>NotApplicable "A reviewing model is used only for automatic review."
  |None=>RequiredAbsence "Select an available reviewing model."end
 |Fields.ApprovalPolicy=>match approval with
  |None=>InvalidInformation "The selected reviewing model is not available for automatic review."
  |Some policy=>PresentInformation(SummaryValue subject(Model.TextValue(approval_caption policy)))
   (match policy with
   |Selvedge.Kernel.Domain.FullAccess=>None
   |Selvedge.Kernel.Domain.ReviewWith reviewer=>
     related_summary(e:=e)Fields.ApprovalReviewer(Model.TextValue
       (profile_label reviewer++" · "++sandbox_label sandbox++" · "++network_label sandbox))
   |Selvedge.Kernel.Domain.AskForApproval=>related_summary(e:=e)Fields.SandboxMode
     (Model.TextValue(sandbox_label sandbox++" · "++network_label sandbox))end)end
 |_=>NotApplicable "This context does not observe that field."end.
Definition information_of snapshot {e}(subject:Model.subject e)(value:Fields.observed):information e:=
 let present readable:=PresentInformation(SummaryValue subject readable)None in
 match value with
 |Fields.TextValue text=>if String.eqb text ""then OptionalAbsence else present(Model.TextValue text)
 |Fields.ModelValue key effort=>match profile_for_subject snapshot subject key with
  |None=>UnavailableInformation "The selected model is no longer available."
  |Some profile=>if ModelSelection.permitted_profile profile effort then
    match subject_declaration subject with
    |Fields.ReasoningEffort=>present(Model.TextValue effort)
    |_=>PresentInformation(SummaryValue subject(NamedChoice(profile_label profile)"Model"))
      (related_summary(e:=e)Fields.ReasoningEffort(Model.TextValue effort))end
    else InvalidInformation "The selected reasoning effort is not available for this model."end
 |Fields.WorkspaceValue workspace=>workspace_information subject workspace false
 |Fields.ContextValue(Context.ContextUnavailable reason)_=>UnavailableInformation reason
 |Fields.ContextValue(Context.ProspectiveContext _ project workspace sandbox approval _)_=>
   let '(workspace,inherited):=match workspace with Context.InheritedWorkspace value=>(value,true)|Context.EnteredWorkspace value=>(value,false)end in
   let sandbox:=match sandbox with Context.InheritedSandbox value|Context.ChosenSandbox value=>value end in
   context_information snapshot subject project workspace inherited sandbox(resolve_approval snapshot approval)
 |Fields.CommittedContextValue _ settings _=>context_information snapshot subject
   (Selvedge.Kernel.Domain.settings_project settings)(Selvedge.Kernel.Domain.settings_workspace settings)false
   (Selvedge.Kernel.Domain.settings_sandbox settings)(Some(Selvedge.Kernel.Domain.settings_approval settings))
 |Fields.DeliveryValue intent=>present(NamedChoice(match intent with Fields.Send=>"Send"|Fields.Steer=>"Steer"end)"")
 |Fields.ProjectValue None=>OptionalAbsence
 |Fields.ProjectValue(Some id)=>match Session.Observation.project_name id snapshot with Some name=>present(NamedReference id name)|None=>UnavailableInformation "The selected project is no longer available."end
 |Fields.ToggleValue value=>present(Model.TextValue(if value then "Yes"else "No"))
 |Fields.CountValue count=>present(Model.TextValue(show_natural count))
 |Fields.TextsValue values=>present(Model.TextValue(String.concat ", " values))
 |Fields.StageValue value=>present(Model.TextValue(Selvedge.Features.Domain.stage_label value))
 |Fields.PriorityValue value=>present(Model.TextValue(Selvedge.Features.Domain.priority_label value))
 |Fields.OwnerValue value=>present(Model.TextValue(match value with
   |Selvedge.Features.Domain.Unassigned=>"未分配"|Selvedge.Features.Domain.Self=>"我"
   |Selvedge.Features.Domain.ProfileOwner key=>match ModelSelection.observed_profile snapshot key with Some profile=>profile_label profile|None=>"Unavailable model"end
   |Selvedge.Features.Domain.AgentOwner id=>match Session.Initialize.board_object "agents" id snapshot with Some agent=>text "name" agent|None=>"Unavailable agent"end end))
 |Fields.AttachmentsValue files=>present(Model.TextValue(String.concat ", "(map Selvedge.Features.Domain.attachment_name files)))
 |Fields.AssistanceValue enabled _=>present(Model.TextValue(if enabled then "Assisted capture"else "Manual capture"))
 |Fields.OptionalTextValue None=>OptionalAbsence|Fields.OptionalTextValue(Some text)=>present(Model.TextValue text)
 |Fields.NotApplicable=>NotApplicable "This setting does not apply to this object."end.
Definition property_field kind:=match kind with ProjectProperty=>Fields.ContextOrigin|WorkspaceProperty=>Fields.WorkspaceDirectories
|PermissionsProperty=>Fields.ApprovalPolicy|ModelProperty=>Fields.ModelProfile|DeliveryProperty=>Fields.DeliveryIntent end.
Definition property_members_fields kind:=match kind with ProjectProperty=>[]|WorkspaceProperty=>[Fields.WorkspacePrimary;Fields.TaskEnvironment]
|PermissionsProperty=>[Fields.SandboxMode;Fields.NetworkAccess;Fields.ApprovalReviewer]|ModelProperty=>[Fields.ReasoningEffort]|DeliveryProperty=>[]end.
Definition subjects_for e fields:=fold_right(fun field rest=>match Model.admit_subject e(Parameters.name field)with Some subject=>subject::rest|None=>rest end)[]fields.
Definition observe_property snapshot state e kind:option(property e):=
 subject<-Model.admit_subject e(Parameters.name(property_field kind));;
 Some(Property kind subject(subjects_for e(property_members_fields kind))(information_of snapshot subject(observe_subject snapshot state subject))).
Definition observe_properties snapshot state e:list(property e):=
 fold_right(fun kind rest=>match observe_property snapshot state e kind with Some value=>value::rest|None=>rest end)[]
 [ProjectProperty;WorkspaceProperty;PermissionsProperty;ModelProperty;DeliveryProperty].
Definition action_context e:=match e with Identity.NewTask _=>Creation|Identity.Message task=>Continuation task|_=>ObjectEditing end.
Definition action_unit_for state e:Model.action_unit e:=let draft:=State.current_draft state e in
 ActionUnit(ActionIdentity(Draft.revision draft))(action_context e)
 (State.pending_editor e state||Services.preparing e(State.service_state state)).
Definition candidate_owner {e}(subject:Model.subject e)incoming:=CommandAssessment.CandidateOwner e(subject_name subject)(TextJson.render_json incoming).
Definition admission snapshot state owner revision command:availability:=
 let sequence:=natural_field "sequence" snapshot in
 match sequence with None=>Unavailable "The current state has not been observed."
 |Some sequence=>match find(Services.owned_assessment owner)(Services.command_assessments(State.service_state state))with
 |Some(Loaded _ request observation)=>if CommandAssessment.matches owner revision sequence command request && CommandAssessment.current_owned owner revision sequence observation then
   match CommandAssessment.observed_admission observation with CommandAssessment.Admitted=>Available|CommandAssessment.Refused _ reason=>Unavailable reason end
   else Unavailable "Checking this action against the current state."
 |Some(Failed _ request reason)=>if CommandAssessment.matches owner revision sequence command request
   then Unavailable reason else Unavailable "Checking this action against the current state."
 | _=>Unavailable "Checking this action against the current state."end end.
Definition project_directory_buffer state owner:=
 match find(fun layer=>match State.layer_panel layer with State.PropertyPanel e _|State.EditorPanel e=>same_editor owner e|_=>false end)
   (State.layers(State.navigation_state state))with
 |Some layer=>match State.layer_parameter_buffer layer with Some value=>value|None=>""end
 |None=>""end.
Definition project_precondition snapshot state (draft:Draft.draft):option(option Fields.field*string*string):=
 match Draft.contents draft with
 |Draft.ProjectBody project name workspace worktree=>
   if negb(String.eqb(Draft.directory_entry draft)"") ||
      negb(String.eqb(project_directory_buffer state(Draft.owner draft))"")
   then Some(Some Fields.WorkspaceDirectories,"unadded_directory","Add or clear the directory before saving.")
   else match project with
    |None=>None
    |Some id=>match Session.Observation.project_by_id id snapshot with
     |Some original=>match string_field "name" original,bind(field "workspace" original)Selvedge.Kernel.Codec.parse_workspace,bool_field "create_worktree" original with
      |Some previous,Some previous_workspace,Some previous_worktree=>
       if String.eqb name previous&&Json.equal(Selvedge.Kernel.Codec.workspace_json workspace)(Selvedge.Kernel.Codec.workspace_json previous_workspace)&&Bool.eqb worktree previous_worktree
       then Some(None,"unchanged_project","No project changes to save.")else None
      |_,_,_=>Some(None,"unavailable_project","The current project configuration has not been observed.")end
     |None=>None end end
 |_=>None end.
Definition requirement_obstruction e(field:option Fields.field)(code reason:string):obstruction e:=
 Obstruction(match field with Some field=>match Model.admit_subject e(Parameters.name field)with
   Some subject=>RepairField subject|None=>RepairEditor end|None=>RepairEditor end)code reason.
Definition preparation_admission snapshot state e draft command:availability:=
 match admission snapshot state(CommandAssessment.DraftOwner e)(Draft.revision draft)command with
 |Unavailable reason=>Unavailable reason
 |Available=>match Session.Observation.worktree_preference snapshot state draft with
  |Some update=>admission snapshot state(CommandAssessment.DirectOwner(CommandAssessment.command_identity update))
    (State.generation(State.navigation_state state))update
  |None=>Available end end.
Definition observe_assessment snapshot state e:assessment e:=
 let draft:=State.current_draft state e in
 let obstruction (reason:string):assessment_result e:=PreparationBlocked(Obstruction RepairEditor "NotAdmitted" reason)[]in
 Assessment(ActionIdentity(Draft.revision draft))
 (match project_precondition snapshot state draft with
 |Some(field,code,reason)=>PreparationBlocked(requirement_obstruction e field code reason)[]
 |None=>if State.pending_editor e state then obstruction "Wait for the current submission to finish."else if Services.blocks e(State.service_state state)then obstruction "Finish or cancel the attachment transfer before submitting."
 else if negb(Session.Observation.worktree_submission_allowed snapshot state draft)then obstruction "Wait for Git verification of the primary workspace before creating a worktree."
 else match Draft.contents draft,State.now state with
 |Draft.CardBody _ _ _ _ _ _,None=>obstruction "The current time has not yet been observed."
 |_,_=>match Draft.explicit_workspace draft with
 |Some workspace=>match Session.Observation.directory_evidence state draft with
   |Some(Loaded _ request observation)=>match Command.observed_command(State.now state)draft(Services.observed_workspace observation,Services.observed_guidance observation)with
     |Some command=>match preparation_admission snapshot state e draft command with Available=>PreparationReady|Unavailable reason=>obstruction reason end
     |None=>obstruction "The draft does not yet form a command."end
   |Some(Failed _ _ reason)=>obstruction reason|_=>DirectoryObservationRequired workspace end
 |None=>match Command.command(State.now state)draft with
   |Some command=>match preparation_admission snapshot state e draft command with Available=>PreparationReady|Unavailable reason=>obstruction reason end
   |None=>obstruction "The draft does not yet form a command."end end end end).
Definition information_summaries {e}(value:information e):list(summary_value e):=
 match value with PresentInformation first None=>[first]|PresentInformation first(Some second)=>[first;second]|_=>[]end.
Definition assignment_shape_available snapshot state {e}(assignment:assignment e):bool:=
 let subject:=assignment_subject assignment in
 let incoming:=Schema.encode_value(subject_kind subject)(assignment_value assignment)in
 Parameters.editable e(subject_declaration subject) &&
 match entry snapshot state subject with
 |Fields.DisplayOnly=>false
 |Fields.Choice=>existsb(fun choice=>Json.equal incoming(Parameters.choice_input e(subject_declaration subject)choice))(choices snapshot state subject)
 |Fields.PositiveInteger=>match Codec.natural incoming with Some count=>N.ltb 0 count|None=>false end
 |_=>match subject_declaration subject with
   |Fields.ReasoningEffort=>match observe_subject snapshot state subject,as_string incoming with
     |Fields.ModelValue key _,Some effort=>match profile_for_subject snapshot subject key with
       Some profile=>ModelSelection.permitted_profile profile effort|None=>false end
     |_,_=>false end
   |_=>true end end.
Definition workspace_choice_available snapshot state (draft:Draft.draft) incoming:availability:=
 if Json.equal incoming(JString(WorkspaceBackend.name WorkspaceBackend.Local))then
 match bind(Session.Observation.workspace_for snapshot draft)Selvedge.Kernel.Domain.workspace_primary with
 |None=>Unavailable "Choose a primary working directory before creating a local worktree."
 |Some _=>match Session.Observation.worktree_observation snapshot state draft with
   |Some(Loaded _ _ true)=>Available
   |Some(Loaded _ _ false)=>Unavailable "The primary working directory is not a Git repository."
   |Some(Failed _ _ reason)=>Unavailable reason
   |_=>Unavailable "Checking the primary working directory for Git."end end
 else Available.
Definition assignment_available snapshot state {e}(assignment:assignment e):availability:=
 let subject:=assignment_subject assignment in
 let current:=State.current_draft state e in
 if assignment_shape_available snapshot state assignment then
 if Parameters.live_configuration e(subject_declaration subject)then
  match Values.candidate_command snapshot(State.now state)current assignment with
  |Some command=>admission snapshot state(candidate_owner subject
    (Schema.encode_value(subject_kind subject)(assignment_value assignment)))(Draft.revision current)command
  |None=>Unavailable "This configuration change is not available in the current task."end
 else match (match subject_declaration subject with Fields.TaskEnvironment=>workspace_choice_available snapshot state current
    (Schema.encode_value(subject_kind subject)(assignment_value assignment))|_=>Available end)with
  |Unavailable reason=>Unavailable reason
  |Available=>match Values.apply_assignment snapshot current assignment with
   |Some _=>Available
   |None=>Unavailable "This field cannot be changed in the current context."end end
 else Unavailable "Select a value permitted by the current field specification.".
Definition candidate_consequences snapshot state {e}(subject:Model.subject e)(value:Schema.denote(subject_kind subject))
    (label:string)(command:option State.public_command):list(summary_value e):=
 let current:=State.current_draft state e in
 match Values.apply_assignment snapshot current(Activity.Assignment subject value)with
 |Some updated=>let candidate:=State.save_draft updated state in
   let kinds:=match subject_declaration subject with
    |Fields.ContextOrigin=>[ProjectProperty;WorkspaceProperty;PermissionsProperty]
    |Fields.ModelProfile|Fields.ReasoningEffort=>[ModelProperty]
    |Fields.WorkspaceDirectories|Fields.WorkspacePrimary|Fields.TaskEnvironment=>[WorkspaceProperty]
    |Fields.DeliveryIntent=>[DeliveryProperty]|_=>[PermissionsProperty]end in
   flat_map(fun kind=>match observe_property snapshot candidate e kind with
    |Some property=>information_summaries(property_information property)|None=>[]end)kinds
 |None=>SummaryValue subject(Model.TextValue label)::
   match subject_declaration subject,command with
   |Fields.ModelProfile,Some command=>match string_field "reasoning"(Schema.encode_command command)with
     |Some effort=>match related_summary(e:=e)Fields.ReasoningEffort(Model.TextValue effort)with Some summary=>[summary]|None=>[]end
     |None=>[]end
   |_,_=>[]end
 end.
Definition observed_approval snapshot value:=match value with
 |Fields.ContextValue(Context.ProspectiveContext _ _ _ _ approval _)_=>resolve_approval snapshot approval
 |Fields.CommittedContextValue _ settings _=>Some(Selvedge.Kernel.Domain.settings_approval settings)
 |_=>None end.
Definition selected_value snapshot state {e}(subject:subject e)incoming:bool:=
 match subject_declaration subject with
 |Fields.ApprovalPolicy=>match observed_approval snapshot(observe_subject snapshot state subject)with
   |Some policy=>Json.equal incoming(JString(match policy with Selvedge.Kernel.Domain.FullAccess=>"full-access"
      |Selvedge.Kernel.Domain.AskForApproval=>"ask-for-approval"|Selvedge.Kernel.Domain.ReviewWith _=>"approval-for-me"end))
   |None=>false end
 |_=>Json.equal incoming(Parameters.native_value(subject_declaration subject)(observe_subject snapshot state subject))end.
Definition alternative_from_choice snapshot state {e}(subject:Model.subject e)(choice:Fields.choice_value):option(alternative e subject):=
 if Parameters.editable e(subject_declaration subject)then
 let incoming:=Parameters.choice_input e(subject_declaration subject)choice in
 value<-Schema.decode_value(subject_kind subject)incoming;;
 let assignment:=Activity.Assignment subject value in
 let current:=State.current_draft state e in
 let command:=if Parameters.live_configuration e(subject_declaration subject)
   then Values.candidate_command snapshot(State.now state)current assignment else None in
 Some(Alternative(Fields.choice_label choice)""value
   (selected_value snapshot state subject incoming)
   (assignment_available snapshot state assignment)
   (candidate_consequences snapshot state subject value(Fields.choice_label choice)command))
 else None.
Definition decision_for snapshot state {e}(subject:Model.subject e):decision e:=
 Decision subject(information_of snapshot subject(observe_subject snapshot state subject))(Parameters.label(subject_declaration subject))
 (fold_right(fun choice rest=>match alternative_from_choice snapshot state subject choice with Some alternative=>alternative::rest|None=>rest end)[](match subject_declaration subject with Fields.ApprovalPolicy=>explicit_choices snapshot state subject|_=>choices snapshot state subject end))
 (if Parameters.editable e(subject_declaration subject)then Available
  else Unavailable "This is part of the task's committed context.").
Definition selected_alternative {e}(decision:decision e):option(alternative e(decision_subject decision)):=
 find(fun alternative=>alternative_selected alternative)(decision_alternatives decision).
Definition collection_relation {e} workspace inherited:list(relation e):=[CollectionMembers(Collection workspace inherited)].
Definition observe_collection snapshot state e:option(collection e):=
 subject<-Model.admit_subject e(Parameters.name Fields.WorkspaceDirectories);;
 match observe_subject snapshot state subject with
 |Fields.WorkspaceValue workspace=>Some(Collection workspace false)
 |Fields.ContextValue(Context.ProspectiveContext _ _ workspace _ _ _)_=>match workspace with
  |Context.InheritedWorkspace value=>Some(Collection value true)
  |Context.EnteredWorkspace value=>Some(Collection value false)end
 |Fields.CommittedContextValue _ settings _=>Some(Collection(Selvedge.Kernel.Domain.settings_workspace settings)false)
 |_=>None end.
Definition workspace_relation snapshot state {e}(property:property e):list(relation e):=
 let relevant:=match property_kind_of property,e with
 |WorkspaceProperty,_|ProjectProperty,Identity.Project _=>true|_,_=>false end in
 if relevant then match observe_collection snapshot state e with
 |Some collection=>[CollectionMembers collection]|None=>[]end else [].
Definition dependent_field snapshot state {e}(parent:decision e)(field:Fields.field):list(relation e):=
 match selected_alternative parent,Model.admit_subject e(Parameters.name field)with
 |Some prerequisite,Some subject=>match entry snapshot state subject with
   |Fields.Choice=>[DependentDecision parent prerequisite(decision_for snapshot state subject)]|_=>[]end
 |_,_=>[]end.
Definition profile_specification snapshot state {e}(parent:decision e):list(relation e):=
 match observe_subject snapshot state(decision_subject parent)with
 |Fields.ModelValue key _=>match profile_for_subject snapshot(decision_subject parent)key,
   Model.admit_subject e(Parameters.name Fields.ReasoningEffort)with
  |Some profile,Some subject=>match entry snapshot state subject with
    |Fields.SingleLine|Fields.DisplayOnly=>[FieldSpecification parent subject profile]|_=>[]end
  |_,_=>[]end
 |_=>[]end.
Definition relation_body snapshot state {e}(property:property e):list(relation e):=
 let root:=decision_for snapshot state(property_subject property)in
 match property_kind_of property with
 |WorkspaceProperty=>workspace_relation snapshot state property++
   match Model.admit_subject e(Parameters.name Fields.TaskEnvironment)with
    |Some subject=>[RootDecision(decision_for snapshot state subject)[]]|None=>[]end
 |ModelProperty=>[RootDecision root(dependent_field snapshot state root Fields.ReasoningEffort++profile_specification snapshot state root)]
 |PermissionsProperty=>
   let dependencies:=flat_map(fun prerequisite=>
     let fields:=match as_string(Schema.encode_value(subject_kind(decision_subject root))(alternative_value prerequisite))with
      |Some "ask-for-approval"=>[Fields.SandboxMode;Fields.NetworkAccess]
      |Some "approval-for-me"=>[Fields.ApprovalReviewer;Fields.SandboxMode;Fields.NetworkAccess]
      |_=>[]end in
     fold_right(fun field rest=>match Model.admit_subject e(Parameters.name field)with
       |Some subject=>DependentDecision root prerequisite(decision_for snapshot state subject)::rest|None=>rest end)[]fields)
      (decision_alternatives root)in
   [RootDecision root dependencies]
 |_=>[RootDecision root []]end.
Definition relations_for snapshot state {e}(property:property e):list(relation e):=
 RequiredValue property::relation_body snapshot state property++
 [SupportingValue property;AssessedAction(action_unit_for state e)(assessment_outcome(observe_assessment snapshot state e))].
Definition explanation_relations snapshot state {e}(property:property e):list(relation e):=
 RequiredValue property::relation_body snapshot state property++
 fold_right(fun subject rest=>let information:=information_of snapshot subject(observe_subject snapshot state subject)in
  match information with NotApplicable _=>rest
  |_=>SupportingValue(Property(property_kind_of property)subject[]information)::rest end)[](property_members property)++
 [SupportingValue property;AssessedAction(action_unit_for state e)(assessment_outcome(observe_assessment snapshot state e))].
Definition property_kind_for_field field:=match field with
 |Fields.ModelProfile|Fields.ReasoningEffort=>ModelProperty
 |Fields.ContextOrigin=>ProjectProperty
 |Fields.WorkspaceDirectories|Fields.WorkspacePrimary|Fields.TaskEnvironment=>WorkspaceProperty
 |Fields.DeliveryIntent=>DeliveryProperty|_=>PermissionsProperty end.
Definition request_kind e request:=match request with
 |PropertyActivity kind=>Some kind|WorkspaceActivity=>Some WorkspaceProperty
 |SubjectActivity name=>subject<-Model.admit_subject e name;;Some(property_kind_for_field(subject_declaration subject))end.
Definition observe_activity snapshot state e request:option(Activity.activity e):=
 kind<-(match e with Identity.Project _=>Some ProjectProperty|_=>request_kind e request end);;
 property<-observe_property snapshot state e kind;;
 match e,kind with
 |Identity.Project _,_=>Some(EditingActivity property []
   (RequiredValue property::workspace_relation snapshot state property++
    [SupportingValue property;AssessedAction(action_unit_for state e)(assessment_outcome(observe_assessment snapshot state e))]))
 |_,WorkspaceProperty=>None
 |_,PermissionsProperty=>Some(ExplanationActivity property(explanation_relations snapshot state property)(Session.Observation.catalog snapshot))
 |_,_=>Some(ComparisonActivity property(relations_for snapshot state property)(Session.Observation.catalog snapshot))end.
Definition same_subject {e}(left right:subject e):bool:=
 if Parameters.field_eq_dec(subject_declaration left)(subject_declaration right)then true else false.
Definition object_eq_dec :forall left right:Model.object,{left=right}+{left<>right}.
Proof. decide equality;try apply Identity.editor_eq_dec;try apply N.eq_dec;decide equality;apply N.eq_dec. Defined.
Definition same_subject_owner {e}(left right:subject e):bool:=
 if object_eq_dec(subject_object left)(subject_object right)then true else false.
Fixpoint relation_retains {e}(subject:subject e)(relation:relation e):bool:=match relation with
|RootDecision decision children=>same_subject(decision_subject decision)subject||existsb(relation_retains subject)children
|DependentDecision parent prerequisite child=>alternative_selected prerequisite&&
 same_subject_owner(decision_subject parent)(decision_subject child)&&same_subject(decision_subject child)subject
|FieldSpecification parent child _=>same_subject_owner(decision_subject parent)child&&same_subject child subject
|_=>false end.
Definition retained_subject {e}(activity:activity e)(subject:subject e):bool:=
 existsb(relation_retains subject)(activity_relations activity).
Definition root_subject {e}(activity:activity e)(subject:subject e):bool:=
 existsb(fun relation=>match relation with RootDecision decision _=>same_subject(decision_subject decision)subject|_=>false end)(activity_relations activity).
Definition view_for {e}(activity:activity e)(focus:option(subject e))(inspection:bool):Activity.view e:=
 match activity with EditingActivity _ _ _=>CompoundView
 |_=>let focus:=match focus with Some subject=>if retained_subject activity subject then Some subject else None|None=>None end in
 if inspection then InspectionView focus else match focus with
 |None=>PrincipalView|Some subject=>if root_subject activity subject then PrincipalView else DependentView subject end end.
Definition view_focus {e}(view:Activity.view e):option(subject e):=match view with
|DependentView subject=>Some subject|InspectionView focus=>focus|_=>None end.
Definition requested_subject {e}(view:Activity.view e)(subject:subject e):bool:=
 match view_focus view with Some focus=>same_subject focus subject|None=>false end.
Inductive completion:=ApplyAndDismiss|ApplyAndReturn|ReturnToOwner|CommitOrDiscard.
Definition completion_for {e}(activity:activity e)(view:Activity.view e):completion:=
 match activity with EditingActivity _ _ _=>CommitOrDiscard
 |_=>match view with PrincipalView=>ApplyAndDismiss|DependentView _=>ApplyAndReturn
  |InspectionView(Some _)=>ApplyAndReturn|InspectionView None=>ReturnToOwner|CompoundView=>CommitOrDiscard end end.
Definition layer_focus {e}(layer:State.layer):option(subject e):=
 field<-State.layer_decision_field layer;;Model.admit_subject e(Parameters.name field).
Definition current_view snapshot state e request:option(Activity.view e):=
 activity<-observe_activity snapshot state e request;;
 match State.layers(State.navigation_state state)with
 |layer::_=>Some(view_for activity(layer_focus layer)(State.layer_source_expanded layer))
 |[]=>Some(view_for activity None false)end.
Definition activity_completion snapshot state e request:completion:=
 match observe_activity snapshot state e request,current_view snapshot state e request with
 |Some activity,Some view=>completion_for activity view
 |_,_=>ApplyAndDismiss end.
Definition activity_complete snapshot state e request:bool:=
 match activity_completion snapshot state e request with
 |CommitOrDiscard=>match assessment_outcome(observe_assessment snapshot state e)with PreparationReady=>true|_=>false end
 |_=>true end.
Inductive exposure:=HiddenRelation|CandidateChoices|DependencySummary|ParameterControl
|RequiredExpression|RequestedInformation|CompoundContent.
Definition root_exposure {e}(view:Activity.view e):exposure:=match view with
|PrincipalView=>CandidateChoices|InspectionView None=>DependencySummary|_=>HiddenRelation end.
Definition initial_dependency_exposure {e}(activity:activity e):exposure:=match activity with
|ComparisonActivity _ _ _=>DependencySummary|_=>HiddenRelation end.
Definition dependent_exposure {e}(activity:activity e)(view:Activity.view e)(subject:subject e):exposure:=
 match view with PrincipalView=>initial_dependency_exposure activity
 |InspectionView None=>DependencySummary
 |_=>if requested_subject view subject then CandidateChoices else HiddenRelation end.
Definition parameter_exposure {e}(activity:activity e)(view:Activity.view e)(subject:subject e):exposure:=
 match view with PrincipalView=>initial_dependency_exposure activity
 |InspectionView None=>DependencySummary
 |_=>if requested_subject view subject then ParameterControl else HiddenRelation end.
Definition relation_exposure {e}(activity:activity e)(view:Activity.view e)(relation:relation e):exposure:=
 match relation with
 |RootDecision decision _=>match view with
   |InspectionView(Some subject)=>if retained_subject activity(decision_subject decision)&&same_subject(decision_subject decision)subject then CandidateChoices else HiddenRelation
   |_=>root_exposure view end
 |DependentDecision parent prerequisite child=>
   if alternative_selected prerequisite&&same_subject_owner(decision_subject parent)(decision_subject child)&&retained_subject activity(decision_subject child)
   then dependent_exposure activity view(decision_subject child)else HiddenRelation
 |FieldSpecification parent subject _=>if same_subject_owner(decision_subject parent)subject&&retained_subject activity subject
   then parameter_exposure activity view subject else HiddenRelation
 |RequiredValue _=>RequiredExpression
 |SupportingValue _=>match view with InspectionView _|CompoundView=>RequestedInformation|_=>HiddenRelation end
 |CollectionMembers _|AssessedAction _ _=>match view with CompoundView=>CompoundContent|_=>HiddenRelation end end.
Definition search_required {e}(activity:activity e)(view:Activity.view e):bool:=
 match activity,view,property_kind_of(activity_property activity)with
 |ComparisonActivity _ _ catalog,PrincipalView,ModelProperty=>Nat.ltb 8(List.length catalog)
 |_,_,_=>false end.
Definition support_field context field:=match context with
 |Creation=>match field with
   |Fields.ContextOrigin|Fields.WorkspaceDirectories|Fields.WorkspacePrimary|Fields.ModelProfile|Fields.ReasoningEffort
   |Fields.SandboxMode|Fields.NetworkAccess|Fields.ApprovalPolicy|Fields.ApprovalReviewer=>true|_=>false end
 |Continuation _=>match field with
   |Fields.DeliveryIntent|Fields.ModelProfile|Fields.ReasoningEffort|Fields.SandboxMode|Fields.NetworkAccess
   |Fields.ApprovalPolicy|Fields.ApprovalReviewer=>true|_=>false end
 |ObjectEditing=>false end.
Definition property_support {e}(action:action_unit e)(property:property e):support e:=
 Support(action_identity_of action)
  (filter(fun subject=>support_field(action_context_of action)(subject_declaration subject))(property_subjects property)).
Definition support_visible {e}(value:support e):bool:=match support_fields value with []=>false|_=>true end.

(** Required facts are assigned to their real expression before presentation.
    A selected option already expresses its subject; a dependent control owns
    its parameter.  Remaining context and missing information stay explicit. *)
Inductive coverage (e:editor):=
|SelectedPrincipal(decision:decision e)(dependencies:list(relation e))
|CurrentDependency(dependency:relation e)
|OriginalObject|RequestedInspection|NecessaryInline.
Arguments SelectedPrincipal {e}.
Arguments CurrentDependency {e}.
Arguments OriginalObject {e}.
Arguments RequestedInspection {e}.
Arguments NecessaryInline {e}.
Definition first_coverage {e}(left right:option(coverage e)):=match left with Some _=>left|None=>right end.
Fixpoint expression_from_relation {e}(view:Activity.view e)(property:property e)(value:relation e):option(coverage e):=
 match value with
 |RootDecision decision children=>first_coverage
   (match view,selected_alternative decision with
    |PrincipalView,Some _=>if same_subject_owner(property_subject property)(decision_subject decision)
      then Some(SelectedPrincipal decision children)else None
    |_,_=>None end)
   (fold_right(fun child rest=>first_coverage(expression_from_relation view property child)rest)None children)
 |DependentDecision parent prerequisite child=>
   if requested_subject view(decision_subject child)&&alternative_selected prerequisite&&
     same_subject_owner(decision_subject parent)(decision_subject child)&&
     same_subject_owner(property_subject property)(decision_subject child)
   then Some(CurrentDependency value)else None
 |FieldSpecification parent subject _=>
   if requested_subject view subject&&same_subject_owner(decision_subject parent)subject&&
     same_subject_owner(property_subject property)subject
   then Some(CurrentDependency value)else None
 |_=>None end.
Definition coverage_for {e}(activity:activity e)(view:Activity.view e)(property:property e):coverage e:=
 match view with
 |InspectionView _=>RequestedInspection
 |CompoundView=>OriginalObject
 |_=>match fold_right(fun relation rest=>first_coverage(expression_from_relation view property relation)rest)
       None(activity_relations activity)with Some covered=>covered|None=>NecessaryInline end end.
Definition parameter_subject {e}(relation:relation e):option(subject e):=match relation with
 |DependentDecision parent prerequisite child=>if alternative_selected prerequisite&&
   same_subject_owner(decision_subject parent)(decision_subject child)then Some(decision_subject child)else None
 |FieldSpecification parent subject _=>if same_subject_owner(decision_subject parent)subject then Some subject else None
 |_=>None end.
Fixpoint parameter_from_relation {e}(subject:subject e)(relation:relation e):option(Activity.relation e):=
 match relation with
 |RootDecision _ children=>fold_right(fun child rest=>match parameter_from_relation subject child with
   Some found=>Some found|None=>rest end)None children
 |_=>match parameter_subject relation with Some parameter=>if same_subject subject parameter then Some relation else None|None=>None end end.
Definition parameter_from_relations {e}(subject:subject e)(relations:list(relation e)):=
 fold_right(fun relation rest=>match parameter_from_relation subject relation with Some found=>Some found|None=>rest end)None relations.
Inductive expression_kind(e:editor):=SelectedSubject(decision:decision e)|OwnedParameter(parameter:relation e)
 |PermissionConsequence(decision:decision e)|OwnerContext|OriginalIdentity|InspectionFact|InlineSubject.
Arguments SelectedSubject {e}.
Arguments OwnedParameter {e}.
Arguments PermissionConsequence {e}.
Arguments OwnerContext {e}.
Arguments OriginalIdentity {e}.
Arguments InspectionFact {e}.
Arguments InlineSubject {e}.
Record subject_expression(e:editor):=SubjectExpression{
 expression_subject:subject e;
 expression_kind_of:expression_kind e;
 expression_information:information e
}.
Arguments SubjectExpression {e}.
Arguments expression_subject {e}.
Arguments expression_kind_of {e}.
Arguments expression_information {e}.
Definition permission_subject field:=match field with Fields.SandboxMode|Fields.NetworkAccess|Fields.ApprovalReviewer=>true|_=>false end.
Definition consequence_kind {e}(property:property e)(decision:decision e)(subject:subject e):expression_kind e:=
 if match property_kind_of property with PermissionsProperty=>permission_subject(subject_declaration subject)|_=>false end
 then PermissionConsequence decision else InlineSubject.
Definition expression_kind_for {e}(property:property e)(coverage:coverage e)(subject:subject e):expression_kind e:=
 match coverage with
 |SelectedPrincipal decision dependencies=>if same_subject subject(decision_subject decision)then SelectedSubject decision
   else match property_kind_of property with PermissionsProperty=>consequence_kind property decision subject
   |_=>match parameter_from_relations subject dependencies with Some parameter=>OwnedParameter parameter
      |None=>consequence_kind property decision subject end end
 |CurrentDependency relation=>match parameter_subject relation with
   |Some parameter=>if same_subject subject parameter then OwnedParameter relation
     else match subject_declaration subject with Fields.ModelProfile|Fields.ApprovalPolicy=>OwnerContext|_=>InlineSubject end
   |None=>InlineSubject end
 |OriginalObject=>OriginalIdentity|RequestedInspection=>InspectionFact|NecessaryInline=>InlineSubject end.
Definition obstruction_matches_subject {e}(subject:subject e)(obstruction:obstruction e):bool:=
 match obstruction_target obstruction with RepairField target=>same_subject target subject|RepairEditor=>false end.
Definition field_obstruction {e}(subject:subject e)(outcome:assessment_result e):option string:=
 match outcome with PreparationBlocked first rest=>option_map obstruction_message(find(obstruction_matches_subject subject)(first::rest))|_=>None end.
Inductive dependency_state:=IndependentInformation|InactiveInformation|ActiveInformation.
Definition merge_dependency left right:=match left,right with
 |ActiveInformation,_|_,ActiveInformation=>ActiveInformation
 |InactiveInformation,_|_,InactiveInformation=>InactiveInformation|_,_=>IndependentInformation end.
Fixpoint relation_dependency {e}(subject:subject e)(relation:relation e):dependency_state:=
 match relation with
 |RootDecision _ children=>fold_right(fun child rest=>merge_dependency(relation_dependency subject child)rest)IndependentInformation children
 |DependentDecision parent prerequisite child=>if same_subject subject(decision_subject child)then
   if alternative_selected prerequisite&&same_subject_owner(decision_subject parent)(decision_subject child)
   then ActiveInformation else InactiveInformation else IndependentInformation
 |FieldSpecification parent child _=>if same_subject subject child then
   if same_subject_owner(decision_subject parent)child then ActiveInformation else InactiveInformation
   else IndependentInformation
 |_=>IndependentInformation end.
Definition subject_dependency {e}(activity:activity e)(subject:subject e):dependency_state:=
 fold_right(fun relation rest=>merge_dependency(relation_dependency subject relation)rest)IndependentInformation(activity_relations activity).
Definition information_status snapshot state {e}(activity:activity e)(subject:subject e):information e:=
 let observed:=information_of snapshot subject(observe_subject snapshot state subject)in
 let observed:=match activity with
 |EditingActivity _ _ _=>match field_obstruction subject(assessment_outcome(observe_assessment snapshot state e))with
   |Some reason=>RequiredAbsence reason|None=>observed end
 |_=>observed end in
 match subject_dependency activity subject with
 |InactiveInformation=>NotApplicable "This setting does not apply to the current selection."
 |_=>observed end.
Definition information_visible {e}(view:Activity.view e)(subject:subject e)(status:information e):bool:=
 match status with NotApplicable _=>requested_subject view subject|_=>true end.
Definition information_expressions snapshot state {e}(activity:activity e)(view:Activity.view e)(property:property e):list(subject_expression e):=
 let coverage:=coverage_for activity view property in
 fold_right(fun subject rest=>let status:=information_status snapshot state activity subject in
   if information_visible view subject status then SubjectExpression subject(expression_kind_for property coverage subject)status::rest else rest)
  [](property_subjects property).

Definition property_for_request snapshot state e request:option(property e):=
 kind<-(match e with Identity.Project _=>Some ProjectProperty|_=>request_kind e request end);;
 observe_property snapshot state e kind.
Open Scope string_scope.
Definition context_origin_label source:=match source with
 |Context.EnvironmentDefaults=>"Environment defaults"
 |Context.ProjectDefaults _|Context.ProjectForParent _ _=>"Project configuration"
 |Context.ParentTask task=>"Parent task "++show_natural task end.
Definition permission_origin_label source:=match source with
 |Context.EnvironmentDefaults|Context.ProjectDefaults _=>"Environment defaults"
 |Context.ParentTask task|Context.ProjectForParent task _=>"Parent task "++show_natural task end.
Definition prospective_source kind source workspace sandbox approval:=match kind with
 |WorkspaceProperty=>match workspace with
   |Context.InheritedWorkspace _=>context_origin_label source
   |Context.EnteredWorkspace _=>"Custom workspace; overrides "++context_origin_label source end
 |PermissionsProperty=>"Filesystem and network: "++
   (match sandbox with Context.InheritedSandbox _=>permission_origin_label source|Context.ChosenSandbox _=>"Custom"end)++
   String (Ascii.ascii_of_nat 10)("Approval: "++match approval with
    Context.InheritedApproval _=>permission_origin_label source|Context.ChosenApproval _=>"Custom"end)
 |_=>context_origin_label source end.
Definition property_source_description snapshot state {e}(property:property e):string:=
 match property_kind_of property with
 |ModelProperty=>match e with
   |Identity.NewTask _=>"Configured model list for this new task"
   |Identity.Message _=>"Configured model list for this task; the current selection retains its captured model definition"
   |Identity.Agent _=>"Configured model list for this agent profile"
   |Identity.Fork _=>"Configured model list for the new fork"|_=>"Configured model list for this editor"end
 |DeliveryProperty=>"Message delivery for this task"
 |kind=>match observe_subject snapshot state(property_subject property)with
   |Fields.ContextValue(Context.ContextUnavailable reason)_=>reason
   |Fields.ContextValue(Context.ProspectiveContext source project workspace sandbox approval _)_=>
     prospective_source kind source workspace sandbox approval++
      (match kind,project with WorkspaceProperty,Some id=>match Session.Observation.project_name id snapshot with
        Some name=>" · "++name|None=>""end|_,_=>""end)
   |Fields.CommittedContextValue task _ _=>match kind with
      |WorkspaceProperty=>"Task workspace"
      |PermissionsProperty=>"Filesystem and network: Task "++show_natural task++
        String (Ascii.ascii_of_nat 10)("Approval: Task "++show_natural task)
      |_=>"Task context"end
   |Fields.ProjectValue None=>"Environment defaults"
   |Fields.ProjectValue(Some id)=>match Session.Observation.project_name id snapshot with
     Some name=>"Project configuration · "++name|None=>"The selected project is no longer available"end
   |Fields.WorkspaceValue _=>"Project workspace configuration"
   |_=>"The settings source is unavailable"end end.

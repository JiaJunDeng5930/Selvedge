From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Domain Codec ModelCapabilities WorkspaceBackend Commands.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Import Codec Identity Context ModelSelection DocumentState.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Interaction.Session Require Draft DraftCodec Observation.
From Selvedge.Interaction.Submission Require Fields Parameters Command.
Import ListNotations.
Open Scope string_scope.
Module SO:=Selvedge.Interaction.Session.Observation.

Definition with_configuration configuration value := match value with
|Draft.NewTaskBody message profile reasoning _ mode work=>Draft.NewTaskBody message profile reasoning configuration mode work
|Draft.AgentBody id revision name profile reasoning instructions _ count=>Draft.AgentBody id revision name profile reasoning instructions configuration count
|Draft.ForkBody task count messages _=>Draft.ForkBody task count messages configuration|body=>body end.
Definition with_context_origin source configuration:=Context.Configuration source
 (Context.workspace_override configuration)(Context.sandbox_override configuration)(Context.approval_override configuration).
Definition with_context_workspace workspace configuration:=Context.Configuration(Context.context_origin configuration)
 workspace(Context.sandbox_override configuration)(Context.approval_override configuration).
Definition with_context_sandbox sandbox configuration:=Context.Configuration(Context.context_origin configuration)
 (Context.workspace_override configuration)sandbox(Context.approval_override configuration).
Definition with_context_approval approval configuration:=Context.Configuration(Context.context_origin configuration)
 (Context.workspace_override configuration)(Context.sandbox_override configuration)approval.
Definition current_workspace snapshot configuration:=match Context.workspace_override configuration with
|Some value=>Some value|None=>option_map Selvedge.Kernel.Domain.settings_workspace(Observation.origin_settings(Context.context_origin configuration)snapshot)end.
Definition current_sandbox snapshot configuration:=match Context.sandbox_override configuration with
|Some value=>Some value|None=>option_map Selvedge.Kernel.Domain.settings_sandbox(Observation.origin_settings(Context.context_origin configuration)snapshot)end.
Definition context_origin_choice body text :option Context.origin:=
 if String.eqb text "environment"then Some Context.EnvironmentDefaults else
 if String.eqb text "parent"then match body with
 |Draft.ForkBody task _ _ _=>Some(Context.ParentTask task)|_=>None end else
 if String.prefix "project/"text then
 option_map (fun project=>match body with
 |Draft.ForkBody task _ _ _=>Context.ProjectForParent task project
 |_=>Context.ProjectDefaults project end)(parse_natural(String.substring 8(String.length text)text))else
 if String.prefix "parent-project/"text then match body with
 |Draft.ForkBody task _ _ _=>option_map(Context.ProjectForParent task)
   (parse_natural(String.substring 15(String.length text)text))|_=>None end else None.
Definition body_model snapshot value:=match value with
|Draft.NewTaskBody _ profile _ _ _ _|Draft.AgentBody _ _ _ profile _ _ _ _=>ModelSelection.observed_profile snapshot profile
|Draft.ForkBody task _ _ _|Draft.MessageBody task _ _=>Observation.task_profile task snapshot
|_=>None end.
Definition configured_reviewer snapshot key:=
 reviewer<-ModelSelection.observed_profile snapshot key;;
 if ModelCapabilities.valid_reviewer_profile reviewer then Some key else None.
Definition body_configuration value:=match value with
 |Draft.NewTaskBody _ _ _ configuration _ _|Draft.AgentBody _ _ _ _ _ _ configuration _
 |Draft.ForkBody _ _ _ configuration=>Some configuration|_=>None end.
Definition policy_reviewer snapshot policy:=match policy with
 |Domain.ReviewWith reviewer=>configured_reviewer snapshot(Domain.profile_key reviewer)|_=>None end.
Definition default_reviewer snapshot model:=
 let catalog:=Observation.catalog snapshot in
 let preferred:=match model with
 |Some model=>configured_reviewer snapshot(Domain.profile_key(ModelCapabilities.default_reviewer model catalog))
 |None=>None end in
 match preferred with Some key=>Some key
 |None=>option_map Domain.profile_key(find ModelCapabilities.valid_reviewer_profile catalog)end.
Definition reviewer_profiles snapshot body:=
 let profiles:=filter ModelCapabilities.valid_reviewer_profile(Observation.catalog snapshot)in
 match default_reviewer snapshot(body_model snapshot body)with
 |Some key=>match find(fun profile=>String.eqb key(Domain.profile_key profile))profiles with
  |Some preferred=>preferred::filter(fun profile=>negb(String.eqb key(Domain.profile_key profile)))profiles
  |None=>profiles end|None=>profiles end.
Definition choose_policy_reviewer snapshot task policy:=match policy_reviewer snapshot policy with
 |Some key=>Some key|None=>default_reviewer snapshot(Observation.task_profile task snapshot)end.
Definition current_reviewer snapshot value:=
 match body_configuration value with
 |Some configuration=>match Context.approval_override configuration with
  |Some(Context.AutomaticReview key)=>configured_reviewer snapshot key
  |Some _=>None
  |None=>settings<-Observation.origin_settings(Context.context_origin configuration)snapshot;;
    policy_reviewer snapshot(Domain.settings_approval settings)end
 |None=>match value with Draft.MessageBody task _ _=>
   settings<-Observation.task_settings task snapshot;;policy_reviewer snapshot(Domain.settings_approval settings)
  |_=>None end end.
Definition choose_reviewer snapshot value:=match current_reviewer snapshot value with
 |Some key=>Some key|None=>default_reviewer snapshot(body_model snapshot value)end.
Definition choose_primary workspace primary := match primary with
 |Some path=>if existsb(String.eqb path)(Domain.workspace_roots workspace)
   then Domain.Workspace(Domain.workspace_roots workspace)(Some path)else workspace
 |None=>workspace end.
Definition modify_context snapshot body configuration field incoming :option Context.configuration:=
 match field with
 |Fields.ContextOrigin=>text<-as_string incoming;;source<-context_origin_choice body text;;Some(with_context_origin source configuration)
 |Fields.WorkspaceDirectories=>match incoming with JNull=>Some(with_context_workspace None configuration)
   |JArray values=>roots<-traverse as_string values;;workspace<-current_workspace snapshot configuration;;
    let primary:=match Selvedge.Kernel.Domain.workspace_primary workspace with Some path=>if existsb(String.eqb path)roots then Some path else hd_error roots|None=>hd_error roots end in
    Some(with_context_workspace(Some(Selvedge.Kernel.Domain.Workspace roots primary))configuration)|_=>None end
 |Fields.WorkspacePrimary=>primary<-DraftCodec.decode_option_text incoming;;workspace<-current_workspace snapshot configuration;;
   Some(with_context_workspace(Some(choose_primary workspace primary))configuration)
 |Fields.SandboxMode=>match incoming with JNull=>Some(with_context_sandbox None configuration)
   |JString mode=>sandbox<-current_sandbox snapshot configuration;;access<-match mode with "read-only"=>Some Selvedge.Kernel.Domain.ReadOnly|"workspace-write"=>Some Selvedge.Kernel.Domain.WorkspaceWrite|_=>None end;;
   Some(with_context_sandbox(Some(Selvedge.Kernel.Domain.Sandbox access(Selvedge.Kernel.Domain.sandbox_network sandbox)))configuration)|_=>None end
 |Fields.NetworkAccess=>match incoming with JNull=>Some(with_context_sandbox None configuration)
   |JBool network=>sandbox<-current_sandbox snapshot configuration;;Some(with_context_sandbox(Some(Selvedge.Kernel.Domain.Sandbox(Selvedge.Kernel.Domain.sandbox_access sandbox)network))configuration)|_=>None end
 |Fields.ApprovalPolicy=>match incoming with JNull=>Some(with_context_approval None configuration)
   |JString "full-access"=>Some(with_context_approval(Some Context.Unrestricted)configuration)
   |JString "ask-for-approval"=>Some(with_context_approval(Some Context.Ask)configuration)
   |JString "approval-for-me"=>reviewer<-choose_reviewer snapshot body;;Some(with_context_approval(Some(Context.AutomaticReview reviewer))configuration)|_=>None end
 |Fields.ApprovalReviewer=>match incoming with JString reviewer=>Some(with_context_approval(Some(Context.AutomaticReview reviewer))configuration)
   |JNull=>Some(with_context_approval None configuration)|_=>None end
 |_=>None end.
Definition edit_nested key name incoming value := nested<-field key value;;Some(replace key(replace name incoming nested)value).
Definition origin_workspace_mode snapshot source:=match source with
|Context.ProjectDefaults id=>match Observation.project_by_id id snapshot with
 |Some project=>if flag "create_worktree" project then Draft.ManagedWorkspace Selvedge.Kernel.WorkspaceBackend.Local else Draft.CurrentWorkspace
 |None=>Draft.CurrentWorkspace end
|_=>Draft.CurrentWorkspace end.
Definition update_body snapshot (body:Draft.body) (field:Fields.field) (incoming:json) :option Draft.body:=
 match Observation.draft_context(Draft.Draft 0 body Draft.Editing "" None) with
 |Some configuration=>if existsb(fun candidate=>if Parameters.field_eq_dec candidate field then true else false)Parameters.context_fields
   then updated<-modify_context snapshot body configuration field incoming;;
    Some(match field,body with
    |Fields.ContextOrigin,Draft.NewTaskBody message profile reasoning _ _ work=>
      Draft.NewTaskBody message profile reasoning updated(origin_workspace_mode snapshot(Context.context_origin updated))work
    |_,_=>with_configuration updated body end)
   else match field with
   |Fields.ModelProfile=>key<-as_string incoming;;match body with
     |Draft.NewTaskBody message _ reasoning context mode work=>Some(Draft.NewTaskBody message key(ModelSelection.selected_effort snapshot key reasoning)context mode work)
     |Draft.AgentBody id revision name _ reasoning instructions context count=>Some(Draft.AgentBody id revision name key(ModelSelection.selected_effort snapshot key reasoning)instructions context count)
     |_=>None end
   |Fields.MessageText=>match body with
     |Draft.NewTaskBody message profile reasoning context mode work=>text<-as_string incoming;;Some(Draft.NewTaskBody(Draft.Text text(Draft.text_images message))profile reasoning context mode work)
     |_=>None end
   |_=>DraftCodec.decode_body(Draft.owner(Draft.Draft 0 body Draft.Editing "" None))(replace(Parameters.name field)incoming(DraftCodec.encode_body body))end
 |None=>match field,body with
   |Fields.TaskGraphDeclaration,Draft.TaskGraphBody graph _ _ work=>declaration<-as_string incoming;;
     Some(Draft.TaskGraphBody graph declaration(TextJson.parse_json declaration)work)
   |Fields.MessageText,Draft.MessageBody task message delivery=>text<-as_string incoming;;Some(Draft.MessageBody task(Draft.Text text(Draft.text_images message))delivery)
   |Fields.WorkspaceDirectories,Draft.ProjectBody project name workspace worktree=>roots<-match incoming with JArray values=>traverse as_string values|_=>None end;;
     let primary:=match Selvedge.Kernel.Domain.workspace_primary workspace with Some path=>if existsb(String.eqb path)roots then Some path else hd_error roots|None=>hd_error roots end in
     Some(Draft.ProjectBody project name(Selvedge.Kernel.Domain.Workspace roots primary)worktree)
   |Fields.WorkspacePrimary,Draft.ProjectBody project name workspace worktree=>primary<-DraftCodec.decode_option_text incoming;;Some(Draft.ProjectBody project name(choose_primary workspace primary)worktree)
   |_,Draft.CardBody card revision value assist profile keep=>match field with
     |Fields.AssistedCapture=>enabled<-as_bool incoming;;Some(Draft.CardBody card revision value enabled profile keep)
     |Fields.AssistanceProfile=>profile<-as_string incoming;;Some(Draft.CardBody card revision value assist profile keep)
     |Fields.ContinueCapture=>keep<-as_bool incoming;;Some(Draft.CardBody card revision value assist profile keep)
     |_=>updated<-DraftCodec.decode_card(replace(Parameters.name field)incoming(DraftCodec.encode_card value));;Some(Draft.CardBody card revision updated assist profile keep)end
   |_,_=>DraftCodec.decode_body(Draft.owner(Draft.Draft 0 body Draft.Editing "" None))(replace(Parameters.name field)incoming(DraftCodec.encode_body body))end end.
Definition apply_assignment snapshot value {e}(assignment:Activity.assignment e):option Draft.draft:=
 if same_editor e(Draft.owner value) && Parameters.editable e(Model.subject_declaration(Activity.assignment_subject assignment))
   && negb(Parameters.live_configuration e(Model.subject_declaration(Activity.assignment_subject assignment)))then
 let subject:=Activity.assignment_subject assignment in
 let incoming:=Schema.encode_value(Model.subject_kind subject)(Activity.assignment_value assignment)in
 updated<-update_body snapshot(Draft.contents value)(Model.subject_declaration subject)incoming;;
 Some(Draft.with_body updated value)else None.
(** Presence records the user's configuration intent. Fields omitted here retain
    the task's actual frozen values in the canonical kernel transition. *)
Definition live_command snapshot task field incoming :option (Schema.command_value Selvedge.Kernel.Commands.command_specs):=
 task_value<-DocumentState.find_task task snapshot;;
 reasoning<-string_field "reasoning" task_value;;
 let source:=JObject[("op",JString "configure_task_execution");("task_id",number task)]in
 updated<-match field with
 |Fields.ModelProfile=>key<-as_string incoming;;Some(replace "reasoning"(JString(ModelSelection.selected_effort snapshot key reasoning))(replace "profile" incoming source))
 |Fields.ReasoningEffort=>Some(replace "reasoning" incoming source)
 |Fields.SandboxMode=>Some(replace "sandbox"(JObject[("mode",incoming)])source)
 |Fields.NetworkAccess=>Some(replace "sandbox"(JObject[("network_access",incoming)])source)
 |Fields.ApprovalReviewer=>key<-as_string incoming;;Some(replace "approval"(JObject[("mode",JString "approval-for-me");("reviewer_profile",JString key)])source)
 |Fields.ApprovalPolicy=>mode<-as_string incoming;;
   approval<-if String.eqb mode "approval-for-me"then
     settings<-Observation.task_settings task snapshot;;
     reviewer<-choose_policy_reviewer snapshot task(Domain.settings_approval settings);;
     Some(JObject[("mode",JString mode);("reviewer_profile",JString reviewer)])
    else Some(JObject[("mode",JString mode)]);;
   Some(replace "approval" approval source)
 |_=>None end;;Schema.decode_command Selvedge.Kernel.Commands.command_specs updated.
Definition candidate_command snapshot now current {e}(assignment:Activity.assignment e):option(Schema.command_value Selvedge.Kernel.Commands.command_specs):=
 let subject:=Activity.assignment_subject assignment in
 let field:=Model.subject_declaration subject in
 if Parameters.live_configuration e field then
  match e with Identity.Message task=>live_command snapshot task field
   (Schema.encode_value(Model.subject_kind subject)(Activity.assignment_value assignment))|_=>None end
 else updated<-apply_assignment snapshot current assignment;;Command.command now updated.

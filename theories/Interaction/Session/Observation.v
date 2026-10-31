From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Domain Codec ModelCapabilities WorkspaceBackend Commands.
From Selvedge.Features Require Domain.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction Require Import Codec Identity Context DocumentState ModelSelection Resource Services.
From Selvedge.Interaction.Session Require Draft State.
Import ListNotations.
Open Scope string_scope.

Definition catalog (snapshot:json) : list Selvedge.Kernel.Domain.profile :=
  fold_right (fun item rest => match Codec.parse_profile item with
    |Some profile=>profile::rest|None=>rest end) [] (items "profiles" snapshot).
Definition task_profile task snapshot :=
 value<-DocumentState.find_task task snapshot;;
 bind(field "execution_profile" value)Selvedge.Kernel.Codec.parse_profile.
Definition project_by_id id snapshot := DocumentState.find_world "projects" "id" id snapshot.
Definition project_name id snapshot := match project_by_id id snapshot with
|Some project=>string_field "name" project|None=>None end.
Definition profiles snapshot := catalog snapshot.
Definition parse_observed_approval (snapshot value:json) : option Selvedge.Kernel.Domain.approval_policy :=
 match string_field "mode" value with
 |Some "full-access"=>Some Selvedge.Kernel.Domain.FullAccess
 |Some "ask-for-approval"=>Some Selvedge.Kernel.Domain.AskForApproval
 |Some "approval-for-me"=>
   match field "reviewer" value with
   |Some reviewer=>profile<-Codec.parse_profile reviewer;;Some(Selvedge.Kernel.Domain.ReviewWith profile)
   |None=>None end
 | _=>None end.
Definition parse_observed_settings snapshot value :=
 workspace<-bind(field "workspace" value)Codec.parse_workspace;;
 sandbox<-bind(field "sandbox" value)Codec.parse_sandbox;;
 approval<-bind(field "approval" value)(parse_observed_approval snapshot);;
 project<-bind(field "project_id" value)Identity.decode_id;;
 guidance<-bind(field "guidance" value)(Codec.parse_guidance workspace);; worktree<-bool_field "create_worktree" value;;
 resource<-bind(field "workspace_resource" value)Identity.decode_id;;
 Some(Selvedge.Kernel.Domain.Settings workspace project sandbox approval guidance worktree resource).
Definition environment_settings snapshot :=
 defaults<-field "defaults" snapshot;;
 bind(field "settings" defaults)(parse_observed_settings snapshot).
Definition task_settings task snapshot :=
 value<-DocumentState.find_task task snapshot;;
 bind(field "settings" value)(parse_observed_settings snapshot).
Definition project_settings project (base:Selvedge.Kernel.Domain.task_settings) snapshot :=
 value<-project_by_id project snapshot;;
 workspace<-bind(field "workspace" value)Codec.parse_workspace;;
 guidance<-bind(field "guidance" value)(Codec.parse_guidance workspace);; worktree<-bool_field "create_worktree" value;;
 Some(Selvedge.Kernel.Domain.Settings workspace (Some project) (Selvedge.Kernel.Domain.settings_sandbox base)
   (Selvedge.Kernel.Domain.settings_approval base) guidance worktree None).
Definition origin_settings source snapshot := match source with
|Context.EnvironmentDefaults=>environment_settings snapshot
|Context.ProjectDefaults project=>base<-environment_settings snapshot;;project_settings project base snapshot
|Context.ParentTask task=>task_settings task snapshot
|Context.ProjectForParent task project=>base<-task_settings task snapshot;;project_settings project base snapshot end.
Definition unavailable_origin_reason source snapshot :=
 let unavailable:="The selected context is no longer available." in
 let missing_project project:=match project_by_id project snapshot with
   |None=>"The selected project does not exist"|Some _=>unavailable end in
 match source with
 |Context.EnvironmentDefaults=>unavailable
 |Context.ProjectDefaults project=>missing_project project
 |Context.ParentTask task=>match DocumentState.find_task task snapshot with
   |None=>"The parent task no longer exists"|Some _=>unavailable end
 |Context.ProjectForParent task project=>match DocumentState.find_task task snapshot with
   |None=>"The parent task no longer exists"|Some _=>missing_project project end
 end.
Definition context_preview snapshot (configuration:Context.configuration) : Context.preview :=
 match origin_settings (Context.context_origin configuration) snapshot with
 |None=>Context.ContextUnavailable(unavailable_origin_reason(Context.context_origin configuration)snapshot)
 |Some settings=>Context.ProspectiveContext (Context.context_origin configuration)
   (Selvedge.Kernel.Domain.settings_project settings)
   (match Context.workspace_override configuration with
     |Some value=>Context.EnteredWorkspace value|None=>Context.InheritedWorkspace(Selvedge.Kernel.Domain.settings_workspace settings)end)
   (match Context.sandbox_override configuration with
     |Some value=>Context.ChosenSandbox value|None=>Context.InheritedSandbox(Selvedge.Kernel.Domain.settings_sandbox settings)end)
   (match Context.approval_override configuration with
     |Some value=>Context.ChosenApproval value|None=>Context.InheritedApproval(Selvedge.Kernel.Domain.settings_approval settings)end)
   (match Context.workspace_override configuration with
     |Some _=>Context.AwaitingDirectoryGuidance|None=>Context.InheritedGuidance(Selvedge.Kernel.Guidance.json(Selvedge.Kernel.Domain.settings_guidance settings))end)
 end.
Definition draft_context value := match Draft.contents value with
|Draft.NewTaskBody _ _ _ configuration _ _|Draft.AgentBody _ _ _ _ _ _ configuration _
|Draft.ForkBody _ _ _ configuration=>Some configuration|_=>None end.
Definition draft_preview snapshot value := match draft_context value with
|Some configuration=>context_preview snapshot configuration
|None=>Context.ContextUnavailable "This object does not select a prospective context." end.
Definition frozen_preview snapshot task := match task_settings task snapshot with
|None=>Context.ContextUnavailable "The task is no longer available."
|Some settings=>Context.ProspectiveContext (Context.ParentTask task) (Selvedge.Kernel.Domain.settings_project settings)
 (Context.InheritedWorkspace(Selvedge.Kernel.Domain.settings_workspace settings))
 (Context.InheritedSandbox(Selvedge.Kernel.Domain.settings_sandbox settings))
 (Context.InheritedApproval(Selvedge.Kernel.Domain.settings_approval settings))
 (Context.InheritedGuidance(Selvedge.Kernel.Guidance.json(Selvedge.Kernel.Domain.settings_guidance settings))) end.
Definition observe_field snapshot (value:Draft.draft) (field:Fields.field) : Fields.observed :=
 let prospective configuration:=Fields.ContextValue(context_preview snapshot configuration)(catalog snapshot) in
 match Draft.contents value with
 |Draft.WorkNameBody _ name=>match field with Fields.WorkName=>Fields.TextValue name|_=>Fields.NotApplicable end
 |Draft.NewTaskBody message profile reasoning context mode _=>match field with
   |Fields.MessageText=>Fields.TextValue(Draft.text_value message)
   |Fields.ModelProfile|Fields.ReasoningEffort=>Fields.ModelValue profile reasoning
   |Fields.TaskEnvironment=>Fields.TextValue(match mode with Draft.CurrentWorkspace=>"current"|Draft.ManagedWorkspace backend=>WorkspaceBackend.name backend end)
   |_=>prospective context end
 |Draft.MessageBody task message delivery=>match field with
   |Fields.MessageText=>Fields.TextValue(Draft.text_value message)
   |Fields.DeliveryIntent=>Fields.DeliveryValue delivery
   |Fields.ModelProfile|Fields.ReasoningEffort=>match DocumentState.find_task task snapshot with
     |Some value=>match string_field "profile" value,string_field "reasoning" value with
       |Some profile,Some effort=>Fields.ModelValue profile effort
       |_,_=>Fields.ContextValue(Context.ContextUnavailable "The task model has not been observed.")[]end
     |None=>Fields.ContextValue(Context.ContextUnavailable "The task is no longer available.")[]end
   |_=>match task_settings task snapshot with
     |Some settings=>Fields.CommittedContextValue task settings(catalog snapshot)
     |None=>Fields.ContextValue(Context.ContextUnavailable "The task context has not been observed.")[]end end
 |Draft.ProjectBody project name workspace worktree=>match field with
   |Fields.ContextOrigin=>Fields.ProjectValue project
   |Fields.ProjectName=>Fields.TextValue name|Fields.CreateWorktree=>Fields.ToggleValue worktree
   |Fields.WorkspaceDirectories|Fields.WorkspacePrimary=>Fields.WorkspaceValue workspace|_=>Fields.NotApplicable end
 |Draft.CardBody _ _ card assist profile keep=>match field with
   |Fields.CardTitle=>Fields.TextValue(Selvedge.Features.Domain.draft_title card)
   |Fields.CardDescription=>Fields.TextValue(Selvedge.Features.Domain.draft_description card)
   |Fields.CardStage=>Fields.StageValue(Selvedge.Features.Domain.draft_stage card)
   |Fields.CardPriority=>Fields.PriorityValue(Selvedge.Features.Domain.draft_priority card)
   |Fields.CardOwner=>Fields.OwnerValue(Selvedge.Features.Domain.draft_owner card)
   |Fields.CardProject=>Fields.ProjectValue(Selvedge.Features.Domain.draft_project card)
   |Fields.CardLabels=>Fields.TextsValue(Selvedge.Features.Domain.draft_labels card)
   |Fields.CardAttachments=>Fields.AttachmentsValue(Selvedge.Features.Domain.draft_attachments card)
   |Fields.ContinueCapture=>Fields.ToggleValue keep
   |Fields.AssistedCapture|Fields.AssistanceProfile=>Fields.AssistanceValue assist profile
   |_=>Fields.NotApplicable end
 |Draft.AgentBody _ _ name profile reasoning instructions context concurrency=>match field with
   |Fields.AgentName=>Fields.TextValue name|Fields.AgentInstructions=>Fields.TextValue instructions
   |Fields.ModelProfile|Fields.ReasoningEffort=>Fields.ModelValue profile reasoning
   |Fields.AgentConcurrency=>Fields.CountValue concurrency|_=>prospective context end
 |Draft.ForkBody _ count messages context=>match field with
   |Fields.ForkCount=>Fields.CountValue count|Fields.ForkMessages=>Fields.TextsValue messages
   |_=>prospective context end
 |Draft.CompactBody _ summary=>match field with Fields.CompactionSummary=>Fields.OptionalTextValue summary|_=>Fields.NotApplicable end
 |Draft.TaskGraphBody _ declaration _ _=>match field with Fields.TaskGraphDeclaration=>Fields.TextValue declaration|_=>Fields.NotApplicable end
 |Draft.TitlePromptsBody _ task agent=>match field with
   |Fields.TaskTitlePrompt=>Fields.TextValue task|Fields.AgentTitlePrompt=>Fields.TextValue agent|_=>Fields.NotApplicable end
 end.

(** Directory evidence belongs to the requested workspace and editor. Message
    edits may reuse that evidence; captured submissions have independent worker
    admission and settle only their captured draft revision. *)
Definition matching_directory (draft:Draft.draft)
    (resource:resource Services.preparation Services.directory_observation):bool:=
 match resource_request resource with
 |None=>false
 |Some request=>same_editor (Draft.owner draft)(Draft.owner(Services.preparation_draft request)) &&
   match Draft.explicit_workspace draft,Draft.explicit_workspace(Services.preparation_draft request)with
   |Some current,Some requested=>Json.equal (Selvedge.Kernel.Codec.workspace_json current)
     (Selvedge.Kernel.Codec.workspace_json requested)
   |_,_=>false end
 end.
Definition directory_evidence state draft :=
 find(matching_directory draft)(Services.preparations(State.service_state state)).
Definition observe_preview state draft preview:=match preview,directory_evidence state draft with
|Context.ProspectiveContext source project workspace sandbox approval Context.AwaitingDirectoryGuidance,
 Some(Loaded _ _ observed)=>Context.ProspectiveContext source project workspace sandbox approval
  (Context.ObservedDirectoryGuidance(Services.observed_guidance observed))
|preview,_=>preview end.
Definition observe_field_in_state snapshot state draft field:=
 match observe_field snapshot draft field with
 |Fields.ContextValue preview reviewers=>Fields.ContextValue(observe_preview state draft preview)reviewers
 |value=>value end.

Definition workspace_for snapshot draft:=match Draft.explicit_workspace draft with
|Some workspace=>Some workspace|None=>match draft_context draft with
 |Some configuration=>option_map Selvedge.Kernel.Domain.settings_workspace(origin_settings(Context.context_origin configuration)snapshot)
 |None=>match Draft.owner draft with Identity.Message task=>option_map Selvedge.Kernel.Domain.settings_workspace(task_settings task snapshot)|_=>None end end end.
Definition workspace_for_edit snapshot draft : string + Selvedge.Kernel.Domain.workspace :=
 match draft_context draft with
 |Some configuration=>match context_preview snapshot configuration with
   |Context.ContextUnavailable reason=>inl reason
   |Context.ProspectiveContext _ _ workspace _ _ _=>inr(match workspace with
     |Context.InheritedWorkspace value|Context.EnteredWorkspace value=>value end)
   end
 |None=>match workspace_for snapshot draft with
   |Some workspace=>inr workspace|None=>inl "The working directories have not been observed." end
 end.
Definition worktree_observation snapshot state (draft:Draft.draft):option(resource(editor*string)bool):=
 let observation:=Services.workspace_git(State.service_state state)in
 match bind(workspace_for snapshot draft)Selvedge.Kernel.Domain.workspace_primary,resource_request observation with
 |Some primary,Some(owner,path)=>if same_editor owner(Draft.owner draft)&&String.eqb path primary
   then Some observation else None
 |_,_=>None end.
Definition worktree_available snapshot state draft:=match worktree_observation snapshot state draft with
 |Some(Loaded _ _ true)=>true|_=>false end.
Definition worktree_submission_allowed snapshot state draft:=match Draft.contents draft with
 |Draft.NewTaskBody _ _ _ _ (Draft.ManagedWorkspace WorkspaceBackend.Local) _=>worktree_available snapshot state draft
 |_=>true end.
Definition worktree_preference snapshot state (draft:Draft.draft):option(Schema.command_value Selvedge.Kernel.Commands.command_specs):=
 if worktree_available snapshot state draft then match Draft.contents draft with
 |Draft.NewTaskBody _ _ _ configuration mode _=>match mode with
  |Draft.ManagedWorkspace WorkspaceBackend.TencentCvm=>None
  |_=>match Context.context_origin configuration with
   |Context.ProjectDefaults id=>project<-project_by_id id snapshot;;previous<-bool_field "create_worktree" project;;
    let enabled:=match mode with Draft.ManagedWorkspace WorkspaceBackend.Local=>true|_=>false end in
    if Bool.eqb previous enabled then None else Schema.decode_command Selvedge.Kernel.Commands.command_specs
     (JObject[("op",JString "update_project");("project_id",number id);("create_worktree",JBool enabled)])
   |_=>None end end
 |_=>None end else None.

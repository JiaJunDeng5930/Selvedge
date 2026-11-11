From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Domain Codec ModelCapabilities Workspace WorkspaceBackend Commands.
From Selvedge.Features Require Domain.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Interaction Require Import Codec Identity Context ModelSelection.
From Selvedge.Interaction Require World.
From Selvedge.Programming Require Import Resource.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Interaction.Experience Require ContextObservation.
Import ListNotations.
Open Scope string_scope.

Definition reuse_catalog_decoder (decode:list json -> list Selvedge.Kernel.Domain.profile) := decode.
Definition decode_catalog :=
  reuse_catalog_decoder (fold_right (fun item rest => match Codec.parse_profile item with
    |Some profile=>profile::rest|None=>rest end) []).
Definition catalog (snapshot:json) : list Selvedge.Kernel.Domain.profile :=
  decode_catalog (items "profiles" snapshot).
Definition task_profile task snapshot :=
 value<-World.find_task task snapshot;;
 bind(field "execution_profile" value)Selvedge.Kernel.Codec.parse_profile.
Definition project_by_id id snapshot := World.find_world "projects" "id" id snapshot.
Definition project_name id snapshot := match project_by_id id snapshot with
|Some project=>string_field "name" project|None=>None end.
Definition profiles snapshot := catalog snapshot.
Definition parse_observed_approval := ContextObservation.parse_observed_approval.
Definition parse_observed_settings := ContextObservation.parse_observed_settings.
Definition environment_settings snapshot :=
 defaults<-field "defaults" snapshot;;
 bind(field "settings" defaults)(parse_observed_settings snapshot).
Definition task_settings := ContextObservation.task_settings.
Definition project_settings project (base:Selvedge.Kernel.Domain.task_settings) snapshot :=
 value<-project_by_id project snapshot;;
 workspace<-bind(field "workspace" value)Codec.parse_workspace;;
 guidance<-bind(field "guidance" value)(Codec.parse_guidance workspace);; worktree<-bool_field "create_worktree" value;;
 Some(Selvedge.Kernel.Domain.Settings workspace (Some project) (Selvedge.Kernel.Domain.settings_sandbox base)
   (Selvedge.Kernel.Domain.settings_approval base) guidance worktree None (Selvedge.Kernel.Domain.settings_realtime_context base)).
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
 |Context.ParentTask task=>match World.find_task task snapshot with
   |None=>"The parent task no longer exists"|Some _=>unavailable end
 |Context.ProjectForParent task project=>match World.find_task task snapshot with
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
|Draft.NewTaskBody _ _ _ configuration _ _
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
   |Fields.ModelProfile|Fields.ReasoningEffort=>match World.find_task task snapshot with
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
 |Draft.ForkBody _ count messages context=>match field with
   |Fields.ForkCount=>Fields.CountValue count|Fields.ForkMessages=>Fields.TextsValue messages
   |_=>prospective context end
 |Draft.CompactBody _ summary=>match field with Fields.CompactionSummary=>Fields.OptionalTextValue summary|_=>Fields.NotApplicable end
 |Draft.TaskGraphBody _ declaration _ _=>match field with Fields.TaskGraphDeclaration=>Fields.TextValue declaration|_=>Fields.NotApplicable end
 |Draft.TitlePromptsBody _ task agent profile=>match field with
   |Fields.TaskTitlePrompt=>Fields.TextValue task|Fields.AgentTitlePrompt=>Fields.TextValue agent
   |Fields.AgentTitleProfile=>Fields.OptionalTextValue profile|_=>Fields.NotApplicable end
 end.

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
Definition workspace_git_request snapshot (draft:Draft.draft) : option (editor * string) :=
 primary<-bind(workspace_for snapshot draft)Selvedge.Kernel.Domain.workspace_primary;;
 Some(Draft.owner draft,primary).
Definition workspace_git_request_matches (request:editor * string)
    (observation:resource (editor * string) bool) : bool :=
 let '(owner,path):=request in
 match resource_request observation with
 |Some(observed_owner,observed_path)=>same_editor owner observed_owner&&String.eqb path observed_path
 |None=>false end.
Inductive git_problem := GitPrimaryRequired | GitCheckPending | GitRepositoryRequired | GitCheckFailed.
Definition git_request_problem request observation : option git_problem :=
 if workspace_git_request_matches request observation then
  match observation with
  |Loaded _ _ true=>None
  |Loaded _ _ false=>Some GitRepositoryRequired
  |Failed _ _ _=>Some GitCheckFailed
  |_=>Some GitCheckPending end
 else Some GitCheckPending.
Definition workspace_git_problem snapshot observation draft : option git_problem :=
 match workspace_git_request snapshot draft with
 |None=>Some GitPrimaryRequired
 |Some request=>git_request_problem request observation end.
Definition worktree_available snapshot observation draft:=match workspace_git_problem snapshot observation draft with
 |None=>true|Some _=>false end.
Definition worktree_required draft:=match Draft.contents draft with
 |Draft.NewTaskBody _ _ _ _ (Draft.ManagedWorkspace WorkspaceBackend.Local) _=>true
 |Draft.ProjectBody _ _ _ requested=>requested
 |_=>false end.
Definition cloud_workspace_requested draft:=match Draft.contents draft with
 |Draft.NewTaskBody _ _ _ _ (Draft.ManagedWorkspace WorkspaceBackend.TencentCvm) _=>true
 |_=>false end.
Definition cloud_workspace_configured snapshot :=
 match string_field "configured_cloud_backend" snapshot with
 |Some backend=>String.eqb backend (WorkspaceBackend.name WorkspaceBackend.TencentCvm)
 |None=>false end.
Inductive cloud_directory_problem := CloudDirectoryRequired | CloudDirectoryChecking | CloudDirectoryUnavailable
 | CloudProjectDirectoryRequired (project:N) | CloudProjectPrimaryMismatch (project:N).
Record cloud_source := CloudSource { cloud_project:option N; cloud_primary:string }.
Definition cloud_source_selection snapshot
    (observed:option (string + (Selvedge.Kernel.Domain.workspace * json))) draft
    : option (cloud_directory_problem + cloud_source) :=
 if cloud_workspace_requested draft && cloud_workspace_configured snapshot then
  match draft_preview snapshot draft with
  |Context.ProspectiveContext _ project directory _ _ _=>
   let project_space:=id<-project;;value<-project_by_id id snapshot;;bind(field "workspace" value)Codec.parse_workspace in
   let selected effective := match Selvedge.Kernel.Domain.workspace_primary effective with
    |Some primary=>match project,project_space with
      |Some id,Some source=>if Workspace.same_primary effective source then inr(CloudSource project primary)
       else inl(CloudProjectPrimaryMismatch id)
      |_,_=>inr(CloudSource project primary)end
    |None=>match project with Some id=>inl(CloudProjectPrimaryMismatch id)|None=>inl CloudDirectoryRequired end end in
   match project,bind project_space Selvedge.Kernel.Domain.workspace_primary with
   |Some id,None=>Some(inl(CloudProjectDirectoryRequired id))
   |_,_=>Some(match directory with
    |Context.InheritedWorkspace effective=>selected effective
    |Context.EnteredWorkspace proposed=>match Selvedge.Kernel.Domain.workspace_primary proposed,observed with
      |None,_=>selected proposed
      |Some _,Some(inr(effective,_))=>selected effective
      |Some _,Some(inl _)=>inl CloudDirectoryUnavailable
      |Some _,None=>inl CloudDirectoryChecking end end)end
  |Context.ContextUnavailable _=>None end
 else None.
Definition worktree_submission_problem snapshot observation draft :=
 if worktree_required draft then workspace_git_problem snapshot observation draft else None.
Definition worktree_preference snapshot observation (draft:Draft.draft):option(Schema.command_value Selvedge.Kernel.Commands.command_specs):=
 if worktree_available snapshot observation draft then match Draft.contents draft with
 |Draft.NewTaskBody _ _ _ configuration mode _=>match mode with
  |Draft.ManagedWorkspace WorkspaceBackend.TencentCvm=>None
  |_=>match Context.context_origin configuration with
   |Context.ProjectDefaults id=>project<-project_by_id id snapshot;;previous<-bool_field "create_worktree" project;;
    let enabled:=match mode with Draft.ManagedWorkspace WorkspaceBackend.Local=>true|_=>false end in
    let verified_project_primary:=match workspace_git_request snapshot draft,
      bind(bind(field "workspace" project)Codec.parse_workspace)Selvedge.Kernel.Domain.workspace_primary with
     |Some(_,checked),Some primary=>String.eqb checked primary|_,_=>false end in
    if Bool.eqb previous enabled || (enabled && negb verified_project_primary) then None
    else Schema.decode_command Selvedge.Kernel.Commands.command_specs
     (JObject[("op",JString "update_project");("project_id",number id);("create_worktree",JBool enabled)])
   |_=>None end end
 |_=>None end else None.

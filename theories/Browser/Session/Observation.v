From Stdlib Require Import List Bool.
From Stdlib Require Import String.
From Selvedge.Foundation Require Json.
From Selvedge.Kernel Require Codec.
From Selvedge.Interaction.Submission Require Observation Values.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require Import Identity.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Browser.Session Require State.

Definition catalog := Selvedge.Interaction.Submission.Observation.catalog.
Definition task_profile := Selvedge.Interaction.Submission.Observation.task_profile.
Definition context_preview := Selvedge.Interaction.Submission.Observation.context_preview.
Definition draft_context := Selvedge.Interaction.Submission.Observation.draft_context.
Definition draft_preview := Selvedge.Interaction.Submission.Observation.draft_preview.
Definition workspace_for := Selvedge.Interaction.Submission.Observation.workspace_for.
Definition workspace_for_edit := Selvedge.Interaction.Submission.Observation.workspace_for_edit.
Definition workspace_git_request := Selvedge.Interaction.Submission.Observation.workspace_git_request.
Definition workspace_git_request_matches := Selvedge.Interaction.Submission.Observation.workspace_git_request_matches.
Definition worktree_required := Selvedge.Interaction.Submission.Observation.worktree_required.
Definition cloud_workspace_requested := Selvedge.Interaction.Submission.Observation.cloud_workspace_requested.
Definition cloud_workspace_configured := Selvedge.Interaction.Submission.Observation.cloud_workspace_configured.

Inductive directory_selection_preview := AwaitingDirectory
 | PreviewDirectory (request:editor * string) (primary:bool) (problem:option Observation.git_problem).
Definition directory_preview snapshot state : option directory_selection_preview :=
 let services:=State.service_state state in
 let listing:=Services.directory services in
 request<-resource_request listing;;
 let owner:=Services.directory_editor request in
 let draft:=State.current_draft state owner in
 let requires_git:=worktree_required draft in
 match listing with
 |Loaded _ _ catalog=>match Json.string_field "path" catalog with
  |Some path=>if String.eqb path(Services.directory_location services)then
   if requires_git then match workspace_for_edit snapshot draft with
    |inr workspace=>body<-Values.add_workspace_directory snapshot(Draft.contents draft)workspace path;;
     let primary:=match workspace_git_request snapshot(Draft.with_body body draft)with
      |Some(_,next)=>String.eqb next path|None=>false end in
     Some(PreviewDirectory(owner,path)primary(Observation.git_request_problem(owner,path)(Services.workspace_git services)))
    |inl _=>Some AwaitingDirectory end
   else None else Some AwaitingDirectory
  |None=>Some AwaitingDirectory end
 |_=>if requires_git then Some AwaitingDirectory else None end.
Definition directory_selection_allowed preview := match preview with
 |Some AwaitingDirectory|Some(PreviewDirectory _ true (Some _))=>false
 |_=>true end.

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
Definition worktree_submission_problem snapshot state :=
 Selvedge.Interaction.Submission.Observation.worktree_submission_problem snapshot
   (Services.workspace_git(State.service_state state)).
Definition worktree_preference snapshot state :=
 Selvedge.Interaction.Submission.Observation.worktree_preference snapshot
   (Services.workspace_git(State.service_state state)).

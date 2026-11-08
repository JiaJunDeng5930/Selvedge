From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Codec.
From Selvedge.Interaction Require Import Codec Identity World.
Open Scope string_scope.

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
Definition task_settings task snapshot :=
 value<-World.find_task task snapshot;;
 bind(field "settings" value)(parse_observed_settings snapshot).

Definition profile_label (value:Selvedge.Kernel.Domain.profile):string:=
 match string_field "name"(Selvedge.Kernel.Domain.profile_metadata value)with
 |Some name=>name|None=>Selvedge.Kernel.Domain.profile_provider value++" / "++Selvedge.Kernel.Domain.profile_model value end.
Definition sandbox_label sandbox:=match Selvedge.Kernel.Domain.sandbox_access sandbox with
|Selvedge.Kernel.Domain.ReadOnly=>"Read only"|Selvedge.Kernel.Domain.WorkspaceWrite=>"Workspace write"end.
Definition network_label sandbox:=if Selvedge.Kernel.Domain.sandbox_network sandbox then "Network allowed"else "Network restricted".
Definition approval_caption approval:=match approval with
|Selvedge.Kernel.Domain.FullAccess=>"Full access"|Selvedge.Kernel.Domain.AskForApproval=>"Ask"
|Selvedge.Kernel.Domain.ReviewWith _=>"Automatic review"end.
Definition filesystem_summary sandbox approval := match approval with
|Selvedge.Kernel.Domain.FullAccess=>"Full access"|_=>sandbox_label sandbox end.
Definition network_summary sandbox approval := match approval with
|Selvedge.Kernel.Domain.FullAccess=>"Network available"|_=>network_label sandbox end.

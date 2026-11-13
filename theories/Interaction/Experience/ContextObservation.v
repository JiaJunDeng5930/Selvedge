From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Codec Domain.
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
From Selvedge.Kernel Require RealtimeContext.

Definition parse_observed_settings snapshot value :=
 workspace<-bind(field "workspace" value)Codec.parse_workspace;;
 sandbox<-bind(field "sandbox" value)Codec.parse_sandbox;;
 approval<-bind(field "approval" value)(parse_observed_approval snapshot);;
 project<-bind(field "project_id" value)Identity.decode_id;;
 guidance<-bind(field "guidance" value)(Codec.parse_guidance workspace);; worktree<-bool_field "create_worktree" value;;
 resource<-bind(field "workspace_resource" value)Identity.decode_id;;
 realtime<-bind(field "realtime_context" value)RealtimeContext.parse_sources;;
 Some(Selvedge.Kernel.Domain.Settings workspace project sandbox approval guidance worktree resource realtime).
Definition task_settings task snapshot :=
 value<-World.find_task task snapshot;;
 bind(field "settings" value)(parse_observed_settings snapshot).

Definition profile_name value :=
 match string_field "name"(Domain.profile_metadata value)with
 |Some name=>name|None=>Domain.profile_provider value++" / "++Domain.profile_model value end.
Definition profile_effort_label value :=
 match Domain.profile_policy value with
 |Domain.FixedReasoning=>"Fixed effort"|Domain.AdaptivePolicy _=>"Adaptive effort" end.
Definition localized_profile_effort_label value :=
 match Domain.profile_policy value with
 |Domain.FixedReasoning=>"固定推理强度"|Domain.AdaptivePolicy _=>"自适应推理强度" end.
(** Disambiguate equal model names among the profiles available to the control.
    The profile key identifies a configuration even when provider and effort policy agree. *)
Definition profile_label_with (effort_label : Domain.profile -> string) profiles value :=
 let name:=profile_name value in
 let key:=Domain.profile_key value in
 let provider:=Domain.profile_provider value in
 let peers:=filter(fun other=>negb(String.eqb key(Domain.profile_key other)) &&
   String.eqb name(profile_name other))profiles in
 let same_provider other:=String.eqb provider(Domain.profile_provider other)in
 let base:=if forallb same_provider peers then name else name++" · "++provider in
 match filter same_provider peers with
 |nil=>base
 |same_provider_peers=>let effort:=effort_label value in
   let qualified:=base++" · "++effort in
   if existsb(fun other=>String.eqb effort(effort_label other))same_provider_peers
   then qualified++" ("++key++")" else qualified
 end.
Definition profile_label := profile_label_with profile_effort_label.
Definition localized_profile_label := profile_label_with localized_profile_effort_label.
Definition sandbox_label sandbox:=match Selvedge.Kernel.Domain.sandbox_access sandbox with
|Selvedge.Kernel.Domain.ReadOnly=>"只读"|Selvedge.Kernel.Domain.WorkspaceWrite=>"工作目录内可写"end.
Definition network_label sandbox:=if Selvedge.Kernel.Domain.sandbox_network sandbox then "允许联网"else "联网受限".
Definition approval_caption approval:=match approval with
|Selvedge.Kernel.Domain.FullAccess=>"完全访问"|Selvedge.Kernel.Domain.AskForApproval=>"询问"
|Selvedge.Kernel.Domain.ReviewWith _=>"自动审批"end.
Definition sandbox_summary sandbox approval unrestricted (limited : Domain.sandbox -> string) :=
 match approval with Domain.FullAccess=>unrestricted|_=>limited sandbox end.
Definition filesystem_summary sandbox approval := sandbox_summary sandbox approval "完全访问" sandbox_label.
Definition network_summary sandbox approval := sandbox_summary sandbox approval "允许联网" network_label.

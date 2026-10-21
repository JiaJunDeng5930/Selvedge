From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Numbers Domain Codec Context Commands State Tasks ContextUpdates Reasoning ReasoningView ApprovalProtocol ContextSelection WorkspaceBackend.
From Selvedge.Features Require Import Domain Observation CompactionCodec WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition indexed {A B : Type} := @Numbers.indexed A B.
Definition association := Selvedge.Features.Domain.association.
Definition task_owner (id : N) (value : task) (features : Selvedge.Features.Domain.state) := Selvedge.Features.Domain.owner_id id (task_lineage value) features.
Definition operation_status (value : operation) := match operation_stage value with
 | Executing _ | Elevated _ _ => "running"
 | AwaitingApproval _ _ | Granted _ => "awaiting_approval"
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => "result_pending" end.
Definition operation_stage_name (value : operation) := match operation_stage value with
 | Executing _ => "executing" | Elevated _ _ => "elevated_executing"
 | AwaitingApproval _ _ => "approval_pending" | Granted _ => "approval_granted"
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => "result_pending" end.
Definition operation_summary (settings : task_settings) (value : operation) := JObject [
 ("call",call_json (operation_call value));("context",settings_json settings);
 ("reviewer",match operation_stage value with
 | AwaitingApproval _ reviewer | Granted reviewer | Elevated _ reviewer => Codec.reviewer_json reviewer | _ => JNull end);
 ("operation_id", number (operation_id value)); ("call_id", JString (call_id (operation_call value)));
 ("tool", JString (call_name (operation_call value))); ("status", JString (operation_status value));
 ("stage",JString (operation_stage_name value));
 ("awaitingHuman", JBool (match operation_stage value with AwaitingApproval _ HumanReviewer => true | _ => false end))].
Definition activity_name := Domain.activity_name.
Definition controls := Tasks.available_controls.
Definition awaiting_human (value : task) := existsb (fun operation =>
 match operation_stage operation with AwaitingApproval _ HumanReviewer => true | _ => false end) (task_operations value).
Definition status_label (value : task) := match task_lifecycle value with
 | Running _ _ => if task_busy value then "Working" else "Ready"
 | Frozen _ _ => "Paused" | Stopped _ _ => "Stopped" | Archived => "Archived" end.
Definition task_summary (id : N) (value : task) (features : Selvedge.Features.Domain.state) := JObject [
 ("id", number id); ("parent", optional_number (hd_error (task_lineage value)));
 ("side_parent", optional_number (task_side_parent value));
 ("profile", JString (profile_key (task_current_profile value)));
 ("provider", JString (profile_provider (task_current_profile value)));
 ("model", JString (profile_model (task_current_profile value)));
 ("reasoning", JString (profile_reasoning (task_current_profile value)));
 ("status", JString (task_status value)); ("status_label", JString (status_label value)); ("controls", JArray (controls (task_lifecycle value)));
 ("phase", JString (activity_name (task_activity value)));
 ("cursor", number (N.of_nat (List.length (task_history value))));
 ("queued", number (N.of_nat (List.length (task_queued value))));
 ("operations", JArray (map (operation_summary (task_current_settings value)) (task_operations value)));
 ("plugins", JArray (contract_plugins (task_contract value)));
 ("settings", settings_json (task_current_settings value));
 ("max_fork", number (contract_max_fork (task_contract value)));
 ("max_descendants", number (contract_max_descendants (task_contract value)));
 ("work_id", optional_number (task_owner id value features));
 ("title", JString (Selvedge.Features.Observation.task_title id value features));
 ("control", JString (task_status value)); ("working", JBool (task_busy value));
 ("awaitingHuman", JBool (awaiting_human value));
 ("pendingMessages", number (N.of_nat (List.length (task_queued value))));
 ("statusLabel", JString (status_label value))].
Definition task_snapshot (id : N) (value : task) (features : Selvedge.Features.Domain.state) :=
 match task_summary id value features with
 | JObject fields => JObject (fields ++ [("tools", JArray (map tool_json (contract_tools (task_contract value))));
 ("lineage", JArray (map number (task_lineage value)));
 ("queued_messages", JArray (map content_json (task_queued value)));
 ("guidance",settings_guidance (task_current_settings value));
 ("history", JArray (map (message_json id) (task_history value)));
 ("context", JArray (map Context.snapshot_json (ContextUpdates.bindings (task_history value))));
 ("model_pending", match task_activity value with AskingModel ticket callable mode =>
  JObject [("operation_id",number ticket);("ticket",number ticket);("mode",JString (output_mode_name mode));("callable",JArray (map JString callable))]
 | _ => JNull end)])
 | value => value end.
Definition project_json (id : N) (value : project) := JObject [
 ("id", number id); ("project_id", number id); ("name", JString (project_name value));
 ("workspace", workspace_json (project_workspace value)); ("guidance", Domain.project_guidance value);
 ("create_worktree", JBool (project_worktree value))].
Definition work_json := @Selvedge.Features.Observation.work_json.
Definition stage_name := @Selvedge.Features.Observation.stage_name.
Definition priority_name := @Selvedge.Features.Observation.priority_name.
Definition owner_name := @Selvedge.Features.Observation.owner_name.
Definition attachment_json := @Selvedge.Features.Observation.attachment_json.
Definition card_json := @Selvedge.Features.Observation.card_json.
Definition agent_json := @Selvedge.Features.Observation.agent_json.
Definition present_values {A : Type} := @Selvedge.Features.Observation.present_values A.
Definition board_json := @Selvedge.Features.Observation.board_json.
Definition rights_json := @Selvedge.Features.Observation.rights_json.
Definition grant_json := @Selvedge.Features.Observation.grant_json.
Definition remote_json := @Selvedge.Features.Observation.remote_json.
Definition worktree_json := @Selvedge.Features.Observation.worktree_json.
Definition graph_message_json := @Selvedge.Features.Observation.graph_message_json.
Definition graph_action_json := @Selvedge.Features.Observation.graph_action_json.
Definition graph_rule_json := @Selvedge.Features.Observation.graph_rule_json.
Definition graph_json := @Selvedge.Features.Observation.graph_json.
Definition graph_snapshot id graph features :=
 match graph_json id graph with JObject fields=>JObject(fields++
  [("work_id",optional_number(association id (Selvedge.Features.Domain.feature_graph_owners features)))])
 |other=>other end.
Definition world_json (value : world) :=
 let features := world_features value in JObject [
 ("sequence", number (world_sequence value));
 ("compaction",Selvedge.Features.CompactionCodec.state_json (Selvedge.Features.Domain.feature_compaction features));
 ("title_settings", Selvedge.Features.Observation.title_settings_json (Selvedge.Features.Domain.feature_title_settings features));
 ("defaults", JObject [("settings",settings_json (Tasks.creation_defaults (world_environment value)))]);
 ("tasks", JArray (indexed (fun id task => task_snapshot id task features) 0 (world_tasks value)));
 ("profiles", JArray (map profile_json (environment_profiles (world_environment value))));
 ("tools", JArray (map tool_json (environment_tools (world_environment value))));
 ("projects", JArray (fold_right (fun value rest => match value with Some value => value :: rest | None => rest end) []
 (indexed (fun id project => if project_deleted project then None else Some (project_json id project)) 0 (world_projects value))));
 ("works", JArray (indexed work_json 0 (Selvedge.Features.Domain.feature_works features)));
 ("graphs", JArray (present_values(fun id graph=>graph_snapshot id graph features)(Selvedge.Features.Domain.feature_graphs features)));
 ("board", Selvedge.Features.Observation.board_json_in_world value);
 ("worktrees", JArray (map worktree_json (Selvedge.Features.Domain.feature_worktrees features)));
 ("remote", remote_json (Selvedge.Features.Domain.feature_remote features))].
Definition history_json (id : N) (task : task) := JArray (map (message_json id) (task_history task)).
Definition effect_json (state : world) (value : effect) : json :=
 match value with
 | ObserveContext id ticket task => JObject [
   ("kind", JString "observe_context"); ("task_id", number id); ("ticket", number ticket);
   ("settings", settings_json (task_current_settings task));
   ("resource", WorkspaceBinding.execution (task_current_settings task) state); ("definitions", definitions_json);
   ("bindings", JArray (map Context.snapshot_json (ContextUpdates.bindings (task_history task))))]
 | RequestModel id ticket model task scope reserve =>
   let source := ContextSelection.history_json id (task_history task) in
   let selected := ContextSelection.latest source (if (0 <? reserve)%N then scope else "") 0 ContextSelection.Original in
   JObject [
   ("kind", JString "model"); ("task_id", number id); ("ticket", number ticket);
   ("model", model_json model); ("output_mode", JString (match task_activity task with AskingModel _ _ mode => output_mode_name mode | _ => "plain" end));
   ("settings", settings_json (task_current_settings task));
   ("resource", WorkspaceBinding.execution (task_current_settings task) state); ("sampling", Reasoning.sampling model (task_current_profile task));
   ("history", JArray (if (0 <? reserve)%N then ContextSelection.assemble selected source scope else ContextSelection.portable_messages source));
   ("context_selected", JBool (0 <? reserve)%N);
   ("context_scope", JString scope); ("context_replacement_source", match selected with
     | ContextSelection.Replacement length _ => number length | _ => JNull end);
   ("output_reserve_tokens", number reserve); ("source_length", number (N.of_nat (List.length (task_history task))));
   ("tools", JArray (map tool_json (contract_tools (task_contract task))));
   ("callable", JArray (map JString (match task_activity task with AskingModel _ callable _ => callable | _ => [] end)))]
 | RequestReasoning id ticket model task => JObject [
   ("kind", JString "reasoning"); ("task_id", number id); ("ticket", number ticket);
   ("model", model_json model); ("history", JArray (Reasoning.evaluator_history id task));
   ("history_preview", JBool true); ("history_preview_bytes", number (N.of_nat ReasoningView.maximum_bytes))]
 | ExecuteTool id ticket operation tool call settings access => JObject [
   ("kind", JString "tool"); ("task_id", number id); ("ticket", number ticket);
   ("operation_id", number operation); ("tool", tool_json tool); ("call", call_json call);
   ("execution", JObject [("workspace", workspace_json (settings_workspace settings));
      ("resource", WorkspaceBinding.execution settings state);
      ("sandbox", sandbox_json (settings_sandbox settings)); ("access", JString (match access with DefaultAccess => "sandboxed" | ElevatedAccess => "unrestricted" end))])]
 | RequestApproval id ticket profile call task => JObject [
   ("kind", JString "approval"); ("task_id", number id); ("ticket", number ticket);
   ("model", model_json profile); ("call", call_json call);
   ("settings", settings_json (task_current_settings task));
   ("instructions", JString ApprovalProtocol.instructions);
   ("user_requests", JArray (fold_right (fun message rest => match message with UserMessage parts => content_json parts :: rest | _ => rest end) [] (task_history task)))]
 | CheckTool id ticket plugin tool call => JObject [
   ("kind", JString "hook"); ("task_id", number id); ("ticket", number ticket);
   ("plugin", plugin); ("tool", tool_json tool); ("call", call_json call)]
 | CheckResult id ticket operation plugin call value error => JObject [
   ("kind", JString "after_hook"); ("task_id", number id); ("ticket", number ticket);
   ("operation_id", number operation); ("plugin", plugin); ("call", call_json call);
   ("value", value); ("error", JBool error)]
 | NotifyPlugins events => JObject [("kind", JString "plugin_events"); ("events", JArray events)]
 | ResetModelSession id => JObject [("kind", JString "reset_model_session"); ("task_id", number id)]
 | CancelTask id => JObject [("kind", JString "cancel"); ("task_id", number id)]
 | CancelTicket id ticket => JObject [("kind", JString "cancel_ticket"); ("task_id", number id); ("ticket", number ticket)]
 | ContinueScheduling => JObject [("kind", JString "continue")]
 | CreateWorktree id root workspace backend => JObject [("kind", JString "worktree_create"); ("backend",JString (WorkspaceBackend.name backend)); ("task_id", number id);
   ("source_root", JString root); ("workspace", workspace_json workspace)]
 | ArchiveWorktree id source root backend => JObject [("kind", JString "worktree_archive"); ("backend",JString (WorkspaceBackend.name backend)); ("task_id", number id); ("root", JString root); ("source_root", JString source)]
 | SuggestTitle id ticket profile prompt => JObject [
   ("kind", JString "task_title"); ("task_id", number id); ("ticket", number ticket);
   ("model", model_json profile); ("prompt", JString prompt)]
 | SuggestCard id ticket revision profile prompt draft retitle => JObject [
   ("kind", JString "board_text"); ("card_id", number id); ("ticket", number ticket);
   ("model", model_json profile); ("prompt", JString prompt); ("retitle", JBool retitle)]
 | RunConnectionJob id job => JObject [
   ("kind", JString "chatgpt_exec"); ("operation_id", number id);
   ("arguments", Selvedge.Features.Domain.job_arguments_json job); ("execution", JObject [
    ("workspace",workspace_json (Selvedge.Features.Domain.job_workspace job));("resource",JNull);("sandbox",sandbox_json (Selvedge.Features.Domain.job_sandbox job));
    ("access",JString "sandboxed");("scope",JString "project")])]
 | CancelConnectionJob id => JObject [("kind", JString "chatgpt_cancel"); ("operation_id", number id)]
 | MaintainContext request => Selvedge.Features.CompactionCodec.effect_json request
 end.
Definition envelope (durable : bool) (value : decision) := JObject [
 ("durable", JBool durable); ("reply", decision_reply value);
 ("effects", JArray (map (effect_json (decision_world value)) (decision_effects value)))].

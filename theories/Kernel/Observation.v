From Selvedge.Kernel Require Import ModelDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Numbers Domain Codec Context Commands State Tasks ContextUpdates Reasoning ReasoningView ApprovalProtocol ContextSelection WorkspaceBackend Workspace.
From Selvedge.Features Require Import Domain Observation CompactionCodec WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition indexed {A B : Type} := @Selvedge.Foundation.Registry.indexed A B.
Definition association := Selvedge.Features.Domain.association.
(* Auxiliary text generation reuses the connection, without the Task's effort
   or adaptive evaluator. The provider resolves its ordinary default effort. *)
Definition task_text_model_json := Codec.task_text_model_json.
Definition task_owner (id : N) (value : task) (features : Selvedge.Features.Domain.state) := Selvedge.Features.Domain.owner_id id (task_lineage value) features.
Definition operation_status (value : operation) := match operation_stage value with
 | Executing _ | Elevated _ _ => "running"
 | AwaitingApproval _ _ => "awaiting_approval"
 | Granted _ => "approved_waiting_to_run"
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => "result_pending" end.
Definition operation_stage_name (value : operation) := match operation_stage value with
 | Executing _ => "executing" | Elevated _ _ => "elevated_executing"
 | AwaitingApproval _ _ => "approval_pending" | Granted _ => "approval_granted"
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => "result_pending" end.
Definition operation_summary (settings : task_settings) (value : operation) := JObject ([
 ("call",call_json (operation_call value));("context",settings_json settings);
 ("reviewer",match operation_stage value with
 | AwaitingApproval _ reviewer | Granted reviewer | Elevated _ reviewer => Codec.reviewer_json reviewer | _ => JNull end);
 ("operation_id", number (operation_id value)); ("call_id", JString (call_id (operation_call value)));
 ("tool", JString (call_name (operation_call value))); ("status", JString (operation_status value));
 ("announced", JBool (operation_announced value));
 ("stage",JString (operation_stage_name value));
 ("awaitingHuman", JBool (match operation_stage value with AwaitingApproval _ HumanReviewer => true | _ => false end))] ++
 (match operation_stage value with
  | AwaitingApproval _ _ | Granted _ =>
    [("arguments", call_arguments (operation_call value))]
  | Elevated ticket _ => [("execution_ticket", number ticket)]
  | _ => [] end)).
Definition activity_name := Domain.activity_name.
Definition controls := Tasks.available_controls.
Definition awaiting_human (value : task) := existsb (fun operation =>
 match operation_stage operation with AwaitingApproval _ HumanReviewer => true | _ => false end) (task_operations value).
Definition status_label (value : task) := match task_lifecycle value with
 | Running _ _ => if task_busy value then "Working" else "Ready"
 | Frozen _ _ => "Paused" | Stopped _ _ => "Stopped" | Archived _ => "Archived" end.
(** UI observations include the frozen context consumed by the experience layer;
    the model-tool settings codec remains the narrower protocol it already owns. *)
Definition experience_approval_json (value : approval_policy) :=
  match value with
  | ReviewWith reviewer => match approval_json value with
    | JObject fields => JObject (fields ++ [("reviewer", profile_json reviewer)])
    | value => value end
  | _ => approval_json value end.
Definition experience_settings_json (value : task_settings) :=
  match settings_json value with
  | JObject fields => JObject (set_field "approval" (experience_approval_json (settings_approval value))
      fields ++ [("guidance", settings_guidance value);
      ("create_worktree", JBool (settings_worktree value))])
  | value => value
  end.
Definition task_summary (id : N) (value : task) (features : Selvedge.Features.Domain.state) := JObject [
 ("id", number id); ("parent", optional_number (hd_error (task_lineage value)));
 ("side_parent", optional_number (task_side_parent value));
 ("profile", JString (profile_key (task_current_profile value)));
 ("execution_profile", profile_json (task_current_profile value));
 ("provider", JString (profile_provider (task_current_profile value)));
 ("model", JString (profile_model (task_current_profile value)));
 ("reasoning", JString (profile_reasoning (task_current_profile value)));
 ("status", JString (task_status value)); ("status_label", JString (status_label value)); ("controls", JArray (controls (task_lifecycle value)));
 ("phase", JString (activity_name (task_activity value)));
 ("cursor", number (N.of_nat (List.length (task_history value))));
 ("queued", number (N.of_nat (List.length (task_queued value))));
 ("operations", JArray (map (operation_summary (task_current_settings value)) (task_operations value)));
 ("plugins", JArray (contract_plugins (task_contract value)));
 ("settings", experience_settings_json (task_current_settings value));
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
 ("history", JArray (map (public_message_json id) (task_history value)));
 ("context", JArray (map Context.snapshot_json (ContextUpdates.bindings (task_history value))));
 ("model_pending", match task_activity value with AskingModel ticket callable mode =>
  JObject [("operation_id",number ticket);("ticket",number ticket);("mode",JString (output_mode_name mode));("callable",JArray (map JString callable))]
 | _ => JNull end)])
 | value => value end.
Definition project_fields (id : N) (value : project) := [
 ("id", number id); ("project_id", number id); ("name", JString (project_name value));
 ("workspace", workspace_json (project_workspace value)); ("guidance", Domain.project_guidance value);
 ("workspace_resource",optional_number (project_resource value)); ("create_worktree", JBool (project_worktree value))].
Definition project_json (id : N) (value : project) := JObject (project_fields id value).
Definition project_task_count (id : N) (tasks : list task) :=
 N.of_nat (List.length (filter (fun task => match settings_project (task_current_settings task) with
 | Some selected => N.eqb selected id | None => false end) tasks)).
Definition project_summary_json (tasks : list task) (id : N) (value : project) :=
 JObject (project_fields id value ++ [
 ("root_count", number (N.of_nat (List.length (workspace_roots (project_workspace value)))));
 ("primary_root", optional_string (workspace_primary (project_workspace value)));
 ("task_count", number (project_task_count id tasks))]).
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
Definition projects_json (projects : list project) (tasks : list task) :=
 map (fun entry => project_summary_json tasks (fst entry) (snd entry)) (Workspace.ordered_projects projects).
Definition worktree_json := @Selvedge.Features.Observation.worktree_json.
Definition graph_message_json := @Selvedge.Features.Observation.graph_message_json.
Definition graph_action_json := @Selvedge.Features.Observation.graph_action_json.
Definition graph_rule_json := @Selvedge.Features.Observation.graph_rule_json.
Definition graph_json := @Selvedge.Features.Observation.graph_json.
Definition graph_snapshot id graph features :=
 match graph_json id graph with JObject fields=>JObject(fields++
  [("work_id",optional_number(association id (Selvedge.Features.Domain.feature_graph_owners features)))])
 |other=>other end.
Definition fork_observation (id:N)(task:task)(value:world):json:=JObject[
 ("parent_ready",JBool(Tasks.fork_parent_ready Tasks.ManualFork task));
 ("capacities",JArray(map(fun ancestor=>match Tasks.ancestor_capacity value ancestor with
  |None=>JNull|Some(descendants,limit)=>JObject[("descendants",number descendants);("limit",number limit)]end)
  (id::task_lineage task)))].
Definition task_snapshot_in_world id task value:=
 match task_snapshot id task(world_features value)with
 |JObject fields=>JObject(fields++[("fork",fork_observation id task value)])|result=>result end.
Definition world_json (value : world) :=
 let features := world_features value in JObject [
 ("sequence", number (world_sequence value));
 ("compaction",Selvedge.Features.CompactionCodec.state_json (Selvedge.Features.Domain.feature_compaction features));
 ("title_settings", Selvedge.Features.Observation.title_settings_json (Selvedge.Features.Domain.feature_title_settings features));
 ("defaults", JObject [("settings",experience_settings_json (Tasks.creation_defaults (world_environment value)))]);
 ("tasks", JArray (indexed (fun id task => task_snapshot_in_world id task value) 0 (world_tasks value)));
 ("profiles", JArray (map profile_json (environment_profiles (world_environment value))));
 ("tools", JArray (map tool_json (environment_tools (world_environment value))));
 ("projects", JArray (projects_json (world_projects value) (world_tasks value)));
 ("works", JArray (indexed work_json 0 (Selvedge.Features.Domain.feature_works features)));
 ("graphs", JArray (present_values(fun id graph=>graph_snapshot id graph features)(Selvedge.Features.Domain.feature_graphs features)));
 ("board", Selvedge.Features.Observation.board_json_in_world value);
 ("worktrees", JArray (map worktree_json (Selvedge.Features.Domain.feature_worktrees features)));
 ("remote", remote_json (Selvedge.Features.Domain.feature_remote features))].
Definition history_json (id : N) (task : task) := JArray (map (public_message_json id) (task_history task)).
Definition effect_packet (state : world) (value : effect) := match value with
 | ObserveContext id ticket task => ModelDeclarations.pack ModelDeclarations.observe_context
   [!id;ticket;settings_json (task_current_settings task);WorkspaceBinding.execution (task_current_settings task) state;
    map definition_json definitions;map Context.snapshot_json (ContextUpdates.bindings (task_history task))!]
 | RequestModel request =>
   let id := ModelRequest.owner request in
   let model := ModelRequest.model (ModelRequest.selection request) in
   let task := ModelRequest.context_task request in
   let scope := ModelRequest.scope request in let reserve := ModelRequest.reserve request in
   let source := ContextSelection.history_json id (task_history task) in
   let selected := ContextSelection.latest source (if (0 <? reserve)%N then scope else "") 0 ContextSelection.Original in
   ModelDeclarations.pack ModelDeclarations.request_model [!id;ModelRequest.ticket request;model_json model;output_mode_value (ModelRequest.mode request);
    settings_json (task_current_settings task);WorkspaceBinding.execution (task_current_settings task) state;
    Reasoning.sampling model (task_current_profile task);
    (if (0 <? reserve)%N then ContextSelection.assemble selected source scope else ContextSelection.portable_messages source);
    (0 <? reserve)%N;scope;(match selected with ContextSelection.Replacement length _ => Some length | _ => None end);
    reserve;N.of_nat (List.length (task_history task));map tool_json (contract_tools (task_contract task));ModelRequest.callable request!]
 | RequestReasoning id ticket task => let model := task_current_profile task in ModelDeclarations.pack ModelDeclarations.reasoning
   [!id;ticket;model_json model;Reasoning.evaluator_history id task;Reasoning.evaluator_project_context task;
    true;N.of_nat ReasoningView.maximum_bytes!]
 | ExecuteTool id ticket operation tool call settings access => ModelDeclarations.pack ModelDeclarations.tool
   [!id;ticket;operation;tool_json tool;wire_call_json call;
    JObject [("workspace",workspace_json (settings_workspace settings));("resource",WorkspaceBinding.execution settings state);
      ("sandbox",sandbox_json (settings_sandbox settings));("access",JString (match access with DefaultAccess=>"sandboxed"|ElevatedAccess=>"unrestricted" end))]!]
 | RequestApproval id ticket profile call task => ModelDeclarations.pack ModelDeclarations.approval
   [!id;ticket;model_json profile;wire_call_json call;settings_json (task_current_settings task);
    ApprovalProtocol.instructions;ApprovalProtocol.user_request_text (task_history task)!]
 | CheckTool id ticket plugin tool call => ModelDeclarations.pack ModelDeclarations.hook [!id;ticket;plugin;tool_json tool;wire_call_json call!]
 | CheckResult id ticket operation plugin call value error => ModelDeclarations.pack ModelDeclarations.after_hook [!id;ticket;operation;plugin;wire_call_json call;value;error!]
 | ResetModelSession id => ModelDeclarations.pack ModelDeclarations.reset_model_session [!id!]
 | CancelTask id => ModelDeclarations.pack ModelDeclarations.cancel [!id!]
 | CancelTicket id ticket => ModelDeclarations.pack ModelDeclarations.cancel_ticket [!id;ticket!] | ContinueScheduling => ModelDeclarations.pack ModelDeclarations.continue [!!]
 | CreateWorktree id root workspace backend => ModelDeclarations.pack ModelDeclarations.worktree_create [!WorkspaceBackend.to_value backend;id;root;workspace_json workspace!]
 | ArchiveWorktree id source root backend => ModelDeclarations.pack ModelDeclarations.worktree_archive [!WorkspaceBackend.to_value backend;id;root;source!]
 | RequestFeature sent => RequestTypes.encode_packet sent (world_features state)
 | CancelConnectionJob id => ModelDeclarations.pack ModelDeclarations.chatgpt_cancel [!id!]
 | MaintainContext request => Selvedge.Features.CompactionCodec.effect_packet request
 end.
Definition effect_fields state value := Schema.encode_fields (ModelDeclarations.packet_fields (effect_packet state value)).
Definition effect_json state value := ModelDeclarations.encode_packet (effect_packet state value).
Definition envelope_with_effects (durable : bool) (reply : json) (effects : list json) := JObject [
 ("durable", JBool durable); ("reply", reply); ("effects", JArray effects)].
Definition envelope (durable : bool) (value : decision) :=
 envelope_with_effects durable (decision_reply value)
   (map (effect_json (decision_world value)) (decision_effects value)).

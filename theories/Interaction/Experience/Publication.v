From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Context State Tasks ContextUpdates Observation Workspace.
From Selvedge.Features Require CompactionCodec Observation.

Module Features := Selvedge.Features.Observation.

Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** Public commands, events and the browser snapshot use the same Task and
    Project facts. The snapshot includes the detail needed to read them locally. *)
Definition awaiting_human (value : task) := existsb (fun operation =>
 match operation_stage operation with AwaitingApproval _ HumanReviewer => true | _ => false end) (task_operations value).
Definition status_label (value : task) := match task_lifecycle value with
 | Running _ _ => if task_busy value then "Working" else "Ready"
 | Frozen _ _ => "Paused" | Stopped _ _ => "Stopped" | Archived _ => "Archived" end.
From Selvedge.Kernel Require RealtimeContext.

(** Task observations include the frozen context consumed by the experience layer;
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
      fields ++ [("guidance", Guidance.json (settings_guidance value));
      ("create_worktree", JBool (settings_worktree value));
      ("realtime_context", RealtimeContext.sources_json (settings_realtime_context value))])
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
 ("status", JString (task_status value)); ("status_label", JString (status_label value)); ("controls", JArray (Tasks.available_controls (task_lifecycle value)));
 ("phase", JString (Domain.activity_name (task_activity value)));
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
 ("guidance",Guidance.json (settings_guidance (task_current_settings value)));
 ("history", JArray (map (public_message_json id) (task_history value)));
 ("context", JArray (map Context.snapshot_json (ContextUpdates.bindings (task_history value))));
 ("model_pending", match task_activity value with AskingModel ticket callable mode =>
  JObject [("operation_id",number ticket);("ticket",number ticket);("mode",JString (output_mode_name mode));("callable",JArray (map JString callable))]
 | _ => JNull end)])
 | value => value end.
Definition project_task_count (id : N) (tasks : list task) :=
 N.of_nat (List.length (filter (fun task => match settings_project (task_current_settings task) with
 | Some selected => N.eqb selected id | None => false end) tasks)).
Definition project_summary_json (tasks : list task) (id : N) (value : project) :=
 JObject (project_fields id value ++ [
 ("root_count", number (N.of_nat (List.length (workspace_roots (project_workspace value)))));
 ("primary_root", optional_string (workspace_primary (project_workspace value)));
 ("task_count", number (project_task_count id tasks))]).
Definition projects_json (projects : list project) (tasks : list task) :=
 map (fun entry => project_summary_json tasks (fst entry) (snd entry)) (Workspace.ordered_projects projects).
Definition graph_snapshot id graph :=
 match Features.graph_json id graph with JObject fields=>JObject(fields++
  [("work_id",optional_number(Selvedge.Features.Domain.graph_work graph))])
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
 ("compaction",Selvedge.Features.CompactionCodec.state_json (fun id => find_task id value) (Selvedge.Features.Domain.feature_compaction features));
 ("title_settings", Selvedge.Features.Observation.title_settings_json (Selvedge.Features.Domain.feature_title_settings features));
 ("defaults", JObject [("settings",experience_settings_json (Tasks.creation_defaults (world_environment value)))]);
 ("tasks", JArray (indexed (fun id task => task_snapshot_in_world id task value) 0 (world_tasks value)));
 ("profiles", JArray (map profile_json (environment_profiles (world_environment value))));
 ("tools", JArray (map tool_json (environment_tools (world_environment value))));
 ("projects", JArray (projects_json (world_projects value) (world_tasks value)));
 ("works", JArray (indexed Features.work_json 0 (Selvedge.Features.Domain.feature_works features)));
 ("graphs", JArray (Features.present_values graph_snapshot (Selvedge.Features.Domain.feature_graphs features)));
 ("board", Selvedge.Features.Observation.board_json_in_world value);
 ("worktrees", JArray (map Features.worktree_json (Selvedge.Features.Domain.feature_worktrees features)));
 ("remote", Features.remote_json (Selvedge.Features.Domain.feature_remote features))].

From Selvedge.Features Require Workflow WorkflowTypes CompactionTypes.
From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require IndexedRegistry.
From Selvedge.Kernel Require Import Numbers Domain Codec Context State Tasks ContextUpdates Observation Workspace.
From Selvedge.Kernel Require ContextTypes FeatureRequestAdmission WorkspaceUses TaskRegistry.
From Selvedge.Kernel Require Conversation.
From Selvedge.Features Require BoardFacts CompactionCodec Observation.
From Selvedge.Programming Require CardScope.

Module Features := Selvedge.Features.Observation.

Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope bool_scope.

(** Public commands, events and the browser snapshot use the same Task and
    Project facts. The snapshot includes the detail needed to read them locally. *)
Definition awaiting_human (value : task) := existsb (fun operation =>
 match operation_stage operation with AwaitingApproval _ HumanReviewer => true | _ => false end) (task_operations value).
Definition status_label (value : task) := match task_lifecycle value with
 | Running (WaitingForInput _ _) _ => "Waiting for input"
 | Running _ _ => if task_busy value then "Working" else "Ready"
 | Frozen _ _ => "Paused" | Stopped _ _ => "Stopped" | Archived _ => "Archived" end.
From Selvedge.Kernel Require RealtimeContext.
From Selvedge.Foundation Require ListCount.

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
Definition task_label_fields id value features := [
 ("work_id", optional_number (task_owner id value features));
 ("title", JString (Features.task_title id value features))].
Definition named_title_changes same_tree same_value before after :=
 let titles value := Selvedge.Features.Domain.feature_titles (world_features value) in
 option_map (fun changes => map (IndexedRegistry.difference_id _) (filter (fun change =>
   let previous := match IndexedRegistry.difference_before _ change with
     | Some status => Features.named_title status | None => None end in
   match previous, Features.named_title (IndexedRegistry.difference_after _ change) with
   | None, None => false | Some old, Some current => negb (String.eqb old current) | _, _ => true end) changes))
  (IndexedRegistry.diff_trie same_tree same_value (titles before) (titles after) 0 1 []).
Definition task_summary_with_cursor (include_cursor : bool) (id : N) (value : task) (features : Selvedge.Features.Domain.state) := JObject ([
 ("id", number id); ("parent", optional_number (hd_error (task_lineage value)));
 ("side_parent", optional_number (task_side_parent value));
 ("profile", JString (profile_key (task_current_profile value)));
 ("execution_profile", profile_json (task_current_profile value));
 ("provider", JString (profile_provider (task_current_profile value)));
 ("model", JString (profile_model (task_current_profile value)));
 ("reasoning", JString (profile_reasoning (task_current_profile value)));
 ("status", JString (task_status value)); ("status_label", JString (status_label value)); ("controls", JArray (Tasks.available_controls (task_lifecycle value)));
 ("phase", JString (Domain.activity_name (task_activity value)))] ++
 (if include_cursor then [("cursor", number (N.of_nat (List.length (task_history value))))] else []) ++
 [("queued", number (N.of_nat (List.length (task_queued value))));
 ("operations", JArray (map (operation_summary (task_current_settings value)) (task_operations value)));
 ("plugins", JArray (contract_plugins (task_contract value)));
 ("settings", experience_settings_json (task_current_settings value));
 ("max_fork", number (contract_max_fork (task_contract value)));
 ("max_descendants", number (contract_max_descendants (task_contract value)));
 ("control", JString (task_status value)); ("working", JBool (task_busy value));
 ("awaitingHuman", JBool (awaiting_human value));
 ("pendingMessages", number (N.of_nat (List.length (task_queued value))));
 ("statusLabel", JString (status_label value))] ++ task_label_fields id value features).
Definition task_summary := task_summary_with_cursor true.
Definition observe_history (facts : list ContextTypes.snapshot * bool) (event : message) :=
 let '(bindings,failed):=facts in
 (ContextUpdates.update_bindings bindings event, BoardFacts.observe_failure failed event).
Definition history_json id history := JArray (map (conversation_message_json id) history).
Definition task_snapshot_with_payload (include_history include_tools include_context include_history_facts : bool)
 (id : N) (value : task) (features : Selvedge.Features.Domain.state) :=
 match task_summary_with_cursor include_history_facts id value features with
 | JObject fields =>
 let history:=task_history value in
 let busy:=task_busy value in
 (* The context already visits the history. Observe the settled outcome in that
    pass only when it can affect the projected stage. *)
 let '(context,failed):=if include_context then
   (if busy || negb include_history_facts then (ContextUpdates.bindings history,false)
    else fold_left observe_history history ([],false))
   else ([],if include_history_facts && negb busy then BoardFacts.latest_failure value else false) in
 JObject (fields ++
 (if include_tools then [("tools", JArray (map tool_json (contract_tools (task_contract value))))] else []) ++
 [("lineage", JArray (map number (task_lineage value)));
 ("queued_messages", JArray (map content_json (task_queued value)));
 ("guidance",Guidance.json (settings_guidance (task_current_settings value)))] ++
 (if include_context then [("context", JArray (map Context.snapshot_json context))] else []) ++
 (if include_history_facts then [("has_assistant_reply", JBool (existsb Conversation.message_has_assistant_reply history));
 ("execution_failed", JBool failed);
 ("card_link_stage", JString (Selvedge.Features.Domain.stage_name
   (BoardFacts.stage_after_execution BoardFacts.initial_link_stage busy (fun _=>failed))))] else []) ++
 [("model_pending", match task_activity value with AskingModel ticket callable mode =>
  JObject [("operation_id",number ticket);("ticket",number ticket);("mode",JString (output_mode_name mode));("callable",JArray (map JString callable))]
 | _ => JNull end)] ++
 if include_history then [("history", history_json id history)] else [])
 | value => value end.
Definition task_snapshot := task_snapshot_with_payload true true true true.
Definition project_task_count (id : N) (tasks : list task) :=
 N.of_nat (ListCount.count (fun task => match settings_project (task_current_settings task) with
 | Some selected => N.eqb selected id | None => false end) tasks).
Definition project_summary_fields id value count :=
 project_fields id value ++ [
 ("root_count", number (N.of_nat (List.length (workspace_roots (project_workspace value)))));
 ("primary_root", optional_string (workspace_primary (project_workspace value)));
 ("task_count", number count); ("sort_order", number (project_order value))].
Definition project_summary_json (tasks : list task) (id : N) (value : project) :=
 JObject (project_summary_fields id value (project_task_count id tasks)).
Definition published_project_count id value :=
 N.of_nat (List.length (WorkspaceUses.project_tasks id (TaskRegistry.workspace_uses (world_task_registry value)))).
Definition project_publication_at id value :=
 match find_project id value with
 | Some current => if project_deleted current then JNull else
   JObject (project_summary_fields id current (published_project_count id value))
 | None => JNull
 end.
Definition projects_json (projects : list project) (tasks : list task) :=
 map (fun entry => project_summary_json tasks (fst entry) (snd entry)) (Workspace.ordered_projects projects).
Definition graph_snapshot id graph :=
 match Features.graph_json id graph with JObject fields=>JObject(fields++
  [("work_id",optional_number(Selvedge.Features.Domain.graph_work graph))])
 |other=>other end.
Definition fork_observation (include_capacity:bool) (id:N)(task:task)(value:world):json:=JObject(
 [("parent_ready",JBool(Tasks.fork_parent_ready Tasks.ManualFork task))] ++
 if include_capacity then [("capacities",JArray(map(fun ancestor=>match Tasks.ancestor_capacity value ancestor with
  |None=>JNull|Some(descendants,limit)=>JObject[("descendants",number descendants);("limit",number limit)]end)
  (id::task_lineage task)))] else []).
Definition task_snapshot_fields_in_world include_history include_tools include_context include_history_facts include_capacity id task value :=
 match task_snapshot_with_payload include_history include_tools include_context include_history_facts id task (world_features value) with
 |JObject fields=>JObject(fields++[("fork",fork_observation include_capacity id task value)])|result=>result end.
Definition task_snapshot_in_world := task_snapshot_fields_in_world true true true true true.
Definition task_publication := task_snapshot_fields_in_world false.

Definition task_publication_references (include_capacity:bool) id task value :=
 JObject (task_label_fields id task (world_features value) ++
   if include_capacity then [("fork", fork_observation true id task value)] else []).
(* Keep image bytes on the shared display catalog. Task contracts and provider
   requests carry the ordinary tool metadata. *)
Definition display_tool_json tool :=
 match tool_icon tool, tool_json tool with
 | Some source, JObject fields => JObject (fields ++ [("icon",JString source)])
 | _, value => value end.

(** A card preview depends on the admitted board revision, queue, drafting
    eligibility and linked execution activity. Use the same observation for
    live publication and for the world actually used to assess a proposal. *)
Definition card_fact value id card := JArray [
 number id;
 number (Selvedge.Features.Domain.card_revision card);
 JBool (BoardFacts.busy card value);
 JBool (BoardFacts.has_workflow id value);
 JBool (BoardFacts.workflow_in_progress id value)].
Definition card_save_facts (value : world) :=
 let board := BoardFacts.registry value in
 let cards := Selvedge.Features.Domain.board_cards board in
 JObject [
  ("automatic", JBool (Selvedge.Features.Domain.board_automatic board));
  ("draft_profile", JString (Selvedge.Features.Domain.board_draft_profile board));
  ("identity_available", JBool (N.ltb (N.of_nat (List.length cards)) 4294967295));
  ("order", JArray (map number (Selvedge.Features.Domain.board_order board)));
  ("cards", JArray (Features.present_values (card_fact value) cards));
  ("projects", JArray (map (fun item => number (fst item))
    (filter (fun item => negb (project_deleted (snd item)))
      (indexed (fun id project => (id,project)) 0 (world_projects value)))));
  ("drafting_profiles", JArray (map (fun profile => JString (profile_key profile))
    (filter FeatureRequestAdmission.ordinary_profile (environment_profiles (world_environment value)))))].

Theorem card_save_facts_ignore_journal_cursor value cursor :
 card_save_facts (with_sequence cursor value) = card_save_facts value.
Proof. destruct value; reflexivity. Qed.

Definition catalog_publication_fields (value : world) := [
 ("defaults", JObject [("settings",experience_settings_json (Tasks.creation_defaults (world_environment value)))]);
 ("profiles", JArray (map profile_json (environment_profiles (world_environment value))));
 ("tools", JArray (map display_tool_json (environment_tools (world_environment value))))].
Definition card_publication_at id value :=
 match CardScope.lookup id value with
 | Some card => JObject [("card",Features.card_json_in_world value id card);("facts",card_fact value id card)]
 | None => JNull
 end.
Definition workflow_instance_at id value :=
 match Workflow.lookup_instance id value with Some instance => Workflow.instance_json value id instance | None => JNull end.
Definition project_publication_fields (value : world) := [
 ("projects", JArray (projects_json (world_projects value) (world_tasks value)))].
Definition live_publication_projections : list (string * (world -> json)) := [
 ("sequence", fun value => number (world_sequence value));
 ("compaction", fun value => Selvedge.Features.CompactionCodec.state_json
   (fun id => find_task id value) (Selvedge.Features.Domain.feature_compaction (world_features value)));
 ("title_settings", fun value => Selvedge.Features.Observation.title_settings_json
   (Selvedge.Features.Domain.feature_title_settings (world_features value)));
 ("works", fun value => JArray (indexed Features.work_json 0 (Selvedge.Features.Domain.feature_works (world_features value))));
 ("graphs", fun value => JArray (Features.present_values graph_snapshot (Selvedge.Features.Domain.feature_graphs (world_features value))));
 ("board", Selvedge.Features.Observation.board_json_in_world);
 ("card_save_facts", card_save_facts);
 ("workflows", Workflow.definitions_json);
 ("workflow_instances", Workflow.instances_json);
 ("ticket_workflows", Workflow.ticket_bindings_json);
 ("worktrees", fun value => JArray (map Features.worktree_json (Selvedge.Features.Domain.feature_worktrees (world_features value))));
 ("remote", fun value => Features.remote_json (Selvedge.Features.Domain.feature_remote (world_features value)))].

Definition project_field value (projection : string * (world -> json)) :=
 (fst projection, snd projection value).

Definition compaction_task_dependencies value :=
 map fst (Selvedge.Features.CompactionTypes.maintenance_entries
  (Selvedge.Features.Domain.feature_compaction (world_features value))).

Definition live_publication_fields (selected : string -> bool) (value : world) :=
 map (project_field value) (filter (fun projection => selected (fst projection)) live_publication_projections).

Theorem live_publication_fields_select_exactly selected value :
 live_publication_fields selected value =
 filter (fun field => selected (fst field)) (live_publication_fields (fun _ => true) value).
Proof.
 unfold live_publication_fields.
 generalize live_publication_projections as projections.
 induction projections as [|[key project] rest IH]; cbn [filter map fst]; [reflexivity|].
 unfold project_field at 2. cbn [fst snd].
 destruct (selected key); cbn [map]; now rewrite IH.
Qed.

Definition shared_publication_fields selected (catalog_changed projects_changed : bool) value :=
 live_publication_fields selected value
 ++ (if catalog_changed then catalog_publication_fields value else [])
 ++ (if projects_changed then project_publication_fields value else []).
Definition shared_publication selected catalog_changed projects_changed value :=
 JObject (shared_publication_fields selected catalog_changed projects_changed value).
Definition publication_project task := settings_project (task_current_settings task).
Definition world_json (value : world) :=
 JObject (("tasks", JArray (indexed (fun id task => task_snapshot_in_world id task value) 0 (world_tasks value)))
   :: shared_publication_fields (fun _ => true) true true value).

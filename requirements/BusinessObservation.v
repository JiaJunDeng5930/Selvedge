(** * Business information has one entry-independent meaning

    A Task, Project, Board card or Task graph has the same business facts
    whether the user asks in a browser or a terminal. The entry can choose
    headings, prominence, grouping and navigation. The published world selects
    the observed objects and their facts. An unavailable observation remains
    distinguishable from an observed empty collection.

    [Publication] defines the Task and Project observations used by both the
    existing command handlers and the browser snapshot. [Read] selects typed
    business information from that snapshot. Project membership follows the
    observed Task settings. Conversation activity keeps its occurrence identity
    when the browser groups it. *)

From Stdlib Require Import String List NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Numbers NumbersProofs Registry.
From Selvedge.Generated Require Commands.
From Selvedge.Kernel Require Context ContextUpdates Domain Observation Packet PacketProofs Queries State.
From Selvedge.Features Require BoardFacts.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require Audit World.
From Selvedge.Interaction.Experience Require Publication Read.
From Selvedge.Browser.Presentation Require Projection Collections Layers.
From Selvedge.Browser.Scene Require Model Surface Construction.
Import ListNotations.
Open Scope string_scope.

Export PacketProofs(actual_admitted_query_delivers_its_observation).

Lemma selected_world_identity collection key id snapshot value :
 World.find_world collection key id snapshot = Some value ->
 natural_field key value = Some id.
Proof.
 unfold World.find_world.
 intros Selected. apply find_some in Selected as [_ Matches].
 destruct (natural_field key value) as [observed|] eqn:Identity; [|discriminate].
 apply N.eqb_eq in Matches. now subst.
Qed.

Theorem observed_task_has_requested_identity snapshot id task :
 Read.find_task id snapshot = Some task -> Read.task_id task = id.
Proof.
 unfold Read.find_task, World.find_task.
 destruct (World.find_world "tasks" "id" id snapshot) as [value|] eqn:Selected; [|discriminate].
 cbn [bind]. unfold Read.observe_task.
 rewrite (selected_world_identity _ _ _ _ _ Selected).
 cbn [bind].
 repeat match goal with
 | |- context [string_field ?name value] => destruct (string_field name value); cbn [bind]
 | |- context [existsb ?predicate ?entries] => destruct (existsb predicate entries)
 | |- context [bool_field ?name value] => destruct (bool_field name value); cbn [bind]
 | |- context [field ?name value] => destruct (field name value); cbn [bind]
 | |- context [id_field ?name ?source] => destruct (id_field name source); cbn [bind]
 end;
 intros Observed; inversion Observed; reflexivity.
Qed.

Theorem observed_project_has_requested_identity snapshot id project :
 Read.find_project id snapshot = Some project -> Read.project_id project = id.
Proof.
 unfold Read.find_project.
 destruct (World.find_world "projects" "project_id" id snapshot) as [value|] eqn:Selected; [|discriminate].
 cbn [bind]. unfold Read.observe_project.
 rewrite (selected_world_identity _ _ _ _ _ Selected).
 cbn [bind].
 destruct (string_field "name" value); cbn [bind]; [|discriminate].
 destruct (bind (field "workspace" value) Read.KernelCodec.parse_workspace) as [workspace|]; cbn [bind]; [|discriminate].
 destruct (bind (field "guidance" value) (Read.KernelCodec.parse_guidance workspace)); cbn [bind]; [|discriminate].
 intros Observed. now inversion Observed.
Qed.

Lemma find_numbered_observation {A} (encode : N -> A -> json) :
 (forall id value, natural_field "id" (encode id value) = Some id) ->
 forall values offset index selected,
 Registry.registry_at index values = Some selected ->
 find (fun value => match natural_field "id" value with
                   | Some id => N.eqb (offset + index) id | None => false end)
   (Registry.indexed encode offset values) = Some (encode (offset + index)%N selected).
Proof.
 intros Identity values. induction values as [|head rest IH]; intros offset index selected Found;
   cbn [Registry.registry_at Registry.indexed find] in Found |- *; [discriminate|].
 rewrite Identity.
 destruct (N.eqb index 0) eqn:AtHead.
 - apply N.eqb_eq in AtHead. subst index.
   rewrite N.add_0_r, N.eqb_refl. now inversion Found.
 - apply N.eqb_neq in AtHead.
   assert (Different : N.eqb (offset + index) offset = false) by (apply N.eqb_neq; lia).
   rewrite Different.
   replace (offset + index)%N with (N.succ offset + N.pred index)%N by lia.
   now apply IH.
Qed.

Lemma published_task_is_selected_by_its_registry_id value id task :
 State.find_task id value = Some task ->
 World.find_task id (Packet.world_json value) =
   Some (Publication.task_snapshot_in_world id task value).
Proof.
 intros Found.
 change (find (fun raw => match natural_field "id" raw with
                         | Some found => N.eqb (0 + id) found | None => false end)
   (Registry.indexed (fun id task => Publication.task_snapshot_in_world id task value)
     0 (State.world_tasks value)) =
   Some (Publication.task_snapshot_in_world (0 + id) task value)).
 refine (find_numbered_observation (fun key selected =>
   Publication.task_snapshot_in_world key selected value) _
   (State.world_tasks value) 0 id task Found).
 intros key selected.
 unfold Publication.task_snapshot_in_world, Publication.task_snapshot, Publication.task_summary.
 destruct (Domain.task_busy selected);
   [|destruct (fold_left Publication.observe_history (Domain.task_history selected) ([],false))].
 all: apply NumbersProofs.natural_print_parse.
Qed.

Lemma published_optional_id value :
 decode_id (Selvedge.Kernel.Codec.optional_number value) = Some value.
Proof.
 destruct value as [value|]; [|reflexivity].
 change (option_map (@Some N) (Numbers.parse_natural (Numbers.show_natural value)) = Some (Some value)).
 now rewrite NumbersProofs.natural_print_parse.
Qed.

Lemma published_history_observes_context_and_failure history context failed :
 fold_left Publication.observe_history history (context, failed) =
 (fold_left ContextUpdates.update_bindings history context,
  fold_left BoardFacts.observe_failure history failed).
Proof.
 revert context failed. induction history as [|event rest IH]; intros context failed.
 - reflexivity.
 - cbn [fold_left Publication.observe_history]. apply IH.
Qed.

Theorem task_snapshot_preserves_context_and_predicts_the_board_stage id task features :
 let snapshot := Publication.task_snapshot id task features in
 field "context" snapshot = Some (JArray (map Context.snapshot_json
   (ContextUpdates.bindings (Domain.task_history task)))) /\
 string_field "card_link_stage" snapshot = Some (Selvedge.Features.Domain.stage_name
   (BoardFacts.stage_after_task BoardFacts.initial_link_stage task)).
Proof.
 unfold Publication.task_snapshot, Publication.task_summary, BoardFacts.stage_after_task, BoardFacts.busy_task.
 destruct (Domain.task_busy task).
 - split; reflexivity.
 - rewrite published_history_observes_context_and_failure. split; reflexivity.
Qed.

Lemma published_task_summary_is_observable id task features :
 Read.observe_task (Publication.task_summary id task features) =
 Some (Read.ObservedTask id (Selvedge.Features.Observation.task_title id task features)
   (Domain.task_status task) (Publication.status_label task) (Domain.task_busy task)
   (Domain.settings_project (Domain.task_current_settings task))
   (Observation.task_owner id task features) (hd_error (Domain.task_lineage task))).
Proof.
 unfold Read.observe_task.
 change (natural_field "id" (Publication.task_summary id task features)) with
   (Numbers.parse_natural (Numbers.show_natural id)).
 rewrite NumbersProofs.natural_print_parse.
 change (string_field "title" (Publication.task_summary id task features)) with
   (Some (Selvedge.Features.Observation.task_title id task features)).
 change (string_field "status" (Publication.task_summary id task features)) with
   (Some (Domain.task_status task)).
 cbn [bind].
 change (string_field "status_label" (Publication.task_summary id task features)) with
   (Some (Publication.status_label task)).
 change (bool_field "working" (Publication.task_summary id task features)) with
   (Some (Domain.task_busy task)).
 change (field "settings" (Publication.task_summary id task features)) with
   (Some (Publication.experience_settings_json (Domain.task_current_settings task))).
 cbn [bind].
 change (id_field "project_id" (Publication.experience_settings_json (Domain.task_current_settings task))) with
   (decode_id (Selvedge.Kernel.Codec.optional_number (Domain.settings_project (Domain.task_current_settings task)))).
 change (id_field "work_id" (Publication.task_summary id task features)) with
   (decode_id (Selvedge.Kernel.Codec.optional_number (Observation.task_owner id task features))).
 change (id_field "parent" (Publication.task_summary id task features)) with
   (decode_id (Selvedge.Kernel.Codec.optional_number (hd_error (Domain.task_lineage task)))).
 rewrite !published_optional_id.
 unfold Domain.task_status. destruct (Domain.task_lifecycle task); reflexivity.
Qed.

Theorem browser_and_cli_read_the_same_task_summary request value task :
 let id := Commands.read_task_id request in
 State.find_task id value = Some task ->
 N.leb (Queries.default_n (Commands.read_after request) 0)
   (N.of_nat (List.length (Domain.task_history task))) = true ->
 let summary := Publication.task_summary id task (State.world_features value) in
 exists observed,
  Read.find_task id (Packet.world_json value) = Some observed /\
  Read.observe_task summary = Some observed /\
  bind (Packet.query (Commands.Cmd_read request) None value)
    (fun reply => bind (field "result" reply) (field "task")) = Some summary.
Proof.
 cbn zeta. intros Found Page. eexists. split.
 - unfold Read.find_task. rewrite (published_task_is_selected_by_its_registry_id _ _ _ Found).
   cbn [bind]. unfold Publication.task_snapshot_in_world, Publication.task_snapshot.
   destruct (Domain.task_busy task);
     [|destruct (fold_left Publication.observe_history (Domain.task_history task) ([],false))];
     apply published_task_summary_is_observable.
 - split; [apply published_task_summary_is_observable|].
   change (bind (field "result" (Queries.handle_read request None value)) (field "task") =
     Some (Publication.task_summary (Commands.read_task_id request) task (State.world_features value))).
   unfold Queries.handle_read, Queries.read_task. rewrite Found, Page. reflexivity.
Qed.

Theorem published_and_cli_project_collections_agree request value :
 field "projects" (Packet.world_json value) =
 bind (Packet.query (Commands.Cmd_list_projects request) None value) (field "result").
Proof. reflexivity. Qed.

Theorem project_task_selection_is_exact tasks project task :
 In task (Read.project_tasks (Some project) tasks) <->
 In task tasks /\ Read.task_project task = Some project.
Proof.
 unfold Read.project_tasks. rewrite filter_In.
 unfold Read.same_id. destruct (Read.task_project task) as [observed|].
 - rewrite N.eqb_eq. split; intros [Member Identity]; split; auto.
   + now subst.
   + now inversion Identity.
 - split; intros [_ Impossible]; discriminate.
Qed.

Theorem task_timeline_has_the_browser_audit_events snapshot id raw history :
 World.find_task id snapshot = Some raw ->
 array_field "history" raw = Some history ->
 Read.task_timeline id snapshot = Some (flat_map Audit.entries (Audit.groups 0 history)).
Proof.
 intros Selected History. unfold Read.task_timeline.
 rewrite Selected. cbn [bind]. rewrite History, Audit.grouping_preserves_events. reflexivity.
Qed.

Theorem browser_project_members_use_observed_task_membership snapshot project tasks task :
 Read.tasks snapshot = Some tasks ->
 exists members, Projection.project_members snapshot project = Some members /\
  (In task members <-> In task tasks /\ Read.task_project task = Some project).
Proof.
 intros Observed. unfold Projection.project_members. rewrite Observed.
 eexists. split; [reflexivity|apply project_task_selection_is_exact].
Qed.

Theorem browser_card_face_uses_observed_facts snapshot state card board_parent candidates parent :
 let rendered := Collections.card_node snapshot state board_parent candidates parent card in
 exists face,
  Surface.node_meaning rendered = Surface.CardContent face /\
  Model.card_title face = Read.card_title card /\
  Model.card_status face = Read.card_activity_label (Read.card_activity card) /\
  Model.card_owner face = Read.card_owner_label snapshot (Read.card_owner card).
Proof. intros rendered. eexists. repeat split; reflexivity. Qed.

Theorem browser_task_detail_shows_observed_status snapshot state id task details parent :
 Projection.task_details_observation snapshot id = Some (task, details) ->
 In (Construction.read_only parent "status" "Status" (Read.task_caption task))
    (Layers.task_details snapshot state id parent).
Proof.
 intros Observed. unfold Layers.task_details. rewrite Observed.
 apply in_or_app. right. apply in_or_app. right. apply in_or_app. left. simpl. auto.
Qed.

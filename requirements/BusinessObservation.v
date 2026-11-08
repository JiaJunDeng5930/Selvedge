(** * Business information has one entry-independent meaning

    A Task, Project, Board card, Agent or Task graph has the same business facts
    whether the user asks in a browser or a terminal. The entry can choose
    headings, prominence, grouping and navigation. The published world selects
    the observed objects and their facts. An unavailable observation remains
    distinguishable from an observed empty collection.

    [Read] provides typed facts to the browser pages. The command-line query
    encodes those facts at the HTTP boundary. In particular, asking for one Task
    yields its own identity, context and activity. Project membership depends
    on the observed Task settings, including when the entry renders a tree.
    The conversation renderer may group activity while the terminal reads it
    linearly. Both omit the same internal receipts and keep chronological
    occurrence identities. *)

From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require Audit World.
From Selvedge.Interaction.Experience Require Read.
Import ListNotations.
Open Scope string_scope.

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

Theorem task_query_keeps_shared_task_facts snapshot id task :
 Read.find_task id snapshot = Some task ->
 exists response,
  Read.describe snapshot (Read.TaskInformation id) = Some response /\
  field "task" response = Some (Read.encode_task task) /\
  field "details" response = Some (Read.encode_optional Read.encode_task_details (Read.task_details_for id snapshot)) /\
  field "context" response = Some (Read.encode_optional Read.encode_context (Read.task_context id snapshot)).
Proof.
 intros Observed.
 pose proof (observed_task_has_requested_identity _ _ _ Observed) as Identity.
 cbn [Read.describe]. rewrite Observed. eexists. split; [reflexivity|].
 unfold Read.encode_task_information. now rewrite Identity.
Qed.

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

From Selvedge.Browser.Presentation Require Projection Collections Layers.
From Selvedge.Browser.Scene Require Model Surface Construction.

Theorem browser_task_details_are_the_queried_details snapshot id task details :
 Projection.task_details_observation snapshot id = Some (task, details) ->
 exists response,
  Read.describe snapshot (Read.TaskInformation id) = Some response /\
  field "task" response = Some (Read.encode_task task) /\
  field "details" response = Some (Read.encode_task_details details).
Proof.
 unfold Projection.task_details_observation.
 destruct (Read.find_task id snapshot) as [found|] eqn:Task; [|discriminate].
 cbn [bind].
 destruct (Read.task_details_for id snapshot) as [value|] eqn:Details; [|discriminate].
 intros Observed. injection Observed as <- <-.
 destruct (task_query_keeps_shared_task_facts _ _ _ Task) as [response [Query [Summary [Information _]]]].
 rewrite Details in Information. exists response. auto.
Qed.

Theorem browser_project_members_are_the_queried_members snapshot id project :
 Read.find_project id snapshot = Some project ->
 exists response,
  Read.describe snapshot (Read.ProjectInformation id) = Some response /\
  field "tasks" response =
    Some (Read.encode_optional (Read.encode_list Read.encode_task) (Projection.project_members snapshot id)).
Proof.
 intros Project.
 pose proof (observed_project_has_requested_identity _ _ _ Project) as Identity.
 cbn [Read.describe]. rewrite Project. eexists. split; [reflexivity|].
 unfold Read.encode_project_information, Projection.project_members. now rewrite Identity.
Qed.

Theorem browser_card_keeps_queried_facts snapshot state id card board_parent candidates parent :
 Read.find_card id snapshot = Some card ->
 let rendered := Collections.card_node snapshot state board_parent candidates parent card in
 exists face response,
  Surface.node_meaning rendered = Surface.CardContent face /\
  Read.describe snapshot (Read.CardInformation id) = Some response /\
  field "title" response = Some (JString (Model.card_title face)) /\
  field "activity_label" response = Some (JString (Model.card_status face)) /\
  field "owner_label" response = Some (JString (Model.card_owner face)).
Proof.
 intros Card rendered.
 cbn [Read.describe]. rewrite Card. do 2 eexists. repeat split; reflexivity.
Qed.

Theorem browser_task_detail_shows_the_queried_status snapshot state id task details parent :
 Projection.task_details_observation snapshot id = Some (task, details) ->
 exists response,
  Read.describe snapshot (Read.TaskInformation id) = Some response /\
  field "task" response = Some (Read.encode_task task) /\
  In (Construction.read_only parent "status" "Status" (Read.task_caption task))
    (Layers.task_details snapshot state id parent).
Proof.
 intros Observed.
 destruct (browser_task_details_are_the_queried_details _ _ _ _ Observed)
   as [response [Query [Task _]]].
 exists response. split; [exact Query|]. split; [exact Task|].
 unfold Layers.task_details. rewrite Observed.
 apply in_or_app. right. apply in_or_app. left. simpl. auto.
Qed.

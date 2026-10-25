From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant WorldInvariantProofs FeatureFrameProofs.
From Selvedge.Features Require Import Domain State TitleRuntime.
Import ListNotations.
Module F := Selvedge.Features.Domain.

Lemma storing_a_title_keeps_task_requirements : forall owner status before,
 tasks_valid 0 (world_tasks (TitleRuntime.store owner status before)) (TitleRuntime.store owner status before) =
 tasks_valid 0 (world_tasks before) before.
Proof. intros; apply registry_requirements_read_only_the_task_and_project_registries; reflexivity. Qed.

Lemma storing_a_title_keeps_worktree_requirements : forall owner status before,
 worktrees_valid (TitleRuntime.store owner status before) = worktrees_valid before.
Proof. reflexivity. Qed.
Lemma storing_a_title_keeps_board_requirements : forall owner status before,
 board_valid (TitleRuntime.store owner status before) = board_valid before.
Proof. reflexivity. Qed.
Lemma storing_a_title_keeps_sharing_requirements : forall owner status before,
 sharing_valid (TitleRuntime.store owner status before) = sharing_valid before.
Proof. reflexivity. Qed.
Lemma storing_a_title_keeps_graph_entry_requirements : forall entries first owner status before,
 graphs_valid first entries (TitleRuntime.store owner status before) = graphs_valid first entries before.
Proof.
 induction entries as [|entry rest IH]; intros; cbn [graphs_valid]; [reflexivity|].
 rewrite IH. destruct entry; reflexivity.
Qed.
Lemma storing_a_title_keeps_graph_requirements : forall owner status before,
 graph_registry_valid (TitleRuntime.store owner status before) = graph_registry_valid before.
Proof. intros; unfold graph_registry_valid; cbn; now rewrite storing_a_title_keeps_graph_entry_requirements. Qed.
Lemma storing_a_title_keeps_work_requirements : forall owner status before,
 works_valid (TitleRuntime.store owner status before) = works_valid before.
Proof. reflexivity. Qed.
Lemma storing_a_title_keeps_maintenance_requirements : forall owner status before,
 compaction_valid (TitleRuntime.store owner status before) = compaction_valid before.
Proof. reflexivity. Qed.

Lemma an_absent_title_has_no_previous_registry_entry : forall owner before,
 TitleRuntime.entry owner before = None ->
 filter (fun entry => negb (N.eqb owner (F.title_task entry))) (F.feature_titles (world_features before)) =
 F.feature_titles (world_features before).
Proof.
 intros owner before Absent. unfold TitleRuntime.entry in Absent.
 remember (F.feature_titles (world_features before)) as entries in *.
 clear Heqentries. induction entries as [|entry rest IH]; cbn in *; [reflexivity|].
 destruct (N.eqb owner (F.title_task entry)) eqn:Same; [discriminate|].
 cbn. now rewrite IH.
Qed.

Lemma storing_a_fresh_title_allocates_one_feature_ticket : forall owner ticket selected prompt before,
 TitleRuntime.entry owner before = None ->
 feature_tickets (world_features (TitleRuntime.store owner (F.TitlePending ticket selected prompt) before)) =
 ticket :: feature_tickets (world_features before).
Proof.
 intros owner ticket selected prompt before Absent.
 unfold TitleRuntime.store. cbn [with_features Selvedge.Features.State.with_titles set].
 rewrite (an_absent_title_has_no_previous_registry_entry owner before Absent).
 reflexivity.
Qed.

Lemma storing_a_title_preserves_every_other_world_requirement : forall owner status before,
 well_formed before ->
 titles_valid (TitleRuntime.store owner status before) = true ->
 tickets_valid (TitleRuntime.store owner status before) = true ->
 well_formed (TitleRuntime.store owner status before).
Proof.
 intros owner status before Valid Titles Tickets. destruct Valid as [Environment Projects Tasks Supply Features].
 constructor.
 - exact Environment.
 - exact Projects.
 - change (tasks_valid 0 (world_tasks (TitleRuntime.store owner status (world_structure before)))
     (TitleRuntime.store owner status (world_structure before)) = true).
   now rewrite storing_a_title_keeps_task_requirements.
 - exact Tickets.
 - change (features_valid (TitleRuntime.store owner status (world_structure before)) = true).
   unfold features_valid in *.
   rewrite storing_a_title_keeps_worktree_requirements, storing_a_title_keeps_board_requirements,
     storing_a_title_keeps_sharing_requirements, storing_a_title_keeps_graph_requirements,
     storing_a_title_keeps_work_requirements, storing_a_title_keeps_maintenance_requirements.
   repeat rewrite andb_true_iff in *. intuition.
Qed.

Lemma distinct_tickets_pass_the_unique_checker : forall values,
 NoDup values -> unique_tickets values = true.
Proof.
 intros values Unique. unfold unique_tickets.
 assert (Same : nodup N.eq_dec values = values).
 { induction Unique as [|first rest Absent Unique IH]; cbn; [reflexivity|].
   destruct (in_dec N.eq_dec first rest); [contradiction|]. now rewrite IH. }
 rewrite Same. apply Nat.eqb_refl.
Qed.

Lemma inserting_one_fresh_ticket_preserves_distinctness : forall (left right : list N) ticket,
 NoDup (left ++ right) -> ~ In ticket (left ++ right) ->
 NoDup (left ++ ticket :: right).
Proof.
 induction left as [|first rest IH]; intros right ticket Unique Fresh; cbn in *.
 - constructor; assumption.
 - inversion Unique as [|? ? Absent Tail]; subst. constructor.
   + intro Member. apply in_app_iff in Member as [InRest|[Same|InRight]].
     * apply Absent. apply in_app_iff; now left.
     * apply Fresh. subst; now left.
     * apply Absent. apply in_app_iff; now right.
   + apply IH; [exact Tail|]. intro Member. apply Fresh; now right.
Qed.

Theorem a_fresh_title_preserves_global_ticket_ownership : forall owner selected prompt before,
 tickets_valid before = true -> TitleRuntime.entry owner before = None ->
 tickets_valid (TitleRuntime.store owner
   (F.TitlePending (world_next_ticket before) selected prompt)
   (with_ticket (N.succ (world_next_ticket before)) before)) = true.
Proof.
 intros owner selected prompt before Supply Absent.
 unfold tickets_valid in Supply. apply andb_true_iff in Supply as [Unique Bounds].
 unfold tickets_valid. cbn [world_tasks world_next_ticket].
 rewrite storing_a_fresh_title_allocates_one_feature_ticket by exact Absent.
 apply andb_true_iff; split.
 - apply distinct_tickets_pass_the_unique_checker, inserting_one_fresh_ticket_preserves_distinctness.
   + now apply unique_tickets_denotes_distinct_correlation_owners.
   + intro Member. apply forallb_forall with (x:=world_next_ticket before) in Bounds; [|exact Member].
     now rewrite N.ltb_irrefl in Bounds.
 - apply forallb_forall; intros ticket Member.
   apply in_app_iff in Member as [Task|[Fresh|Feature]].
   + apply N.ltb_lt. apply N.lt_lt_succ_r. apply N.ltb_lt.
     apply forallb_forall with (x:=ticket) in Bounds; [exact Bounds|]. apply in_app_iff; now left.
   + subst ticket. apply N.ltb_lt, N.lt_succ_diag_r.
   + apply N.ltb_lt. apply N.lt_lt_succ_r. apply N.ltb_lt.
     apply forallb_forall with (x:=ticket) in Bounds; [exact Bounds|]. apply in_app_iff; now right.
Qed.

Lemma storing_one_eligible_title_preserves_title_requirements :
 forall owner ticket selected prompt task before,
 titles_valid before = true -> TitleRuntime.entry owner before = None ->
 find_task owner before = Some task -> (ticket < world_next_ticket before)%N ->
 profile_valid selected = true -> TitleRuntime.capable selected = true ->
 (N.of_nat (String.length prompt) <= Titles.maximum_instruction_bytes +
  N.of_nat (String.length Titles.title_format) +
  (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format))))%N ->
 titles_valid (TitleRuntime.store owner (F.TitlePending ticket selected prompt) before) = true.
Proof.
 intros owner ticket selected prompt task before Valid Absent Owned Bound Profile Capable Prompt.
 assert (NoOwner : ~ In owner (map F.title_task (F.feature_titles (world_features before)))).
 { intro Member. apply in_map_iff in Member as [entry [Identity Member]].
   unfold TitleRuntime.entry in Absent.
   pose proof (find_none _ _ Absent entry Member) as Different.
   cbn in Different. rewrite Identity, N.eqb_refl in Different. discriminate. }
 assert (OldTitles : forallb (fun entry => title_valid entry (TitleRuntime.store owner (F.TitlePending ticket selected prompt) before))
   (F.feature_titles (world_features before)) =
   forallb (fun entry => title_valid entry before) (F.feature_titles (world_features before))) by reflexivity.
 unfold titles_valid in Valid. repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[TaskPrompt AgentPrompt] Unique] Entries].
 unfold titles_valid. unfold TitleRuntime.store.
 cbn [with_features Selvedge.Features.State.with_titles set].
 rewrite (an_absent_title_has_no_previous_registry_entry owner before Absent).
 cbn [map forallb]. repeat rewrite andb_true_iff; repeat split; try assumption.
 - apply distinct_tickets_pass_the_unique_checker. constructor; [exact NoOwner|].
   now apply unique_tickets_denotes_distinct_correlation_owners.
 - change (title_valid (F.TitleEntry owner (F.TitlePending ticket selected prompt)) before &&
     forallb (fun entry => title_valid entry before) (F.feature_titles (world_features before)) = true).
   rewrite Entries. apply andb_true_iff; split; [|reflexivity].
   unfold title_valid. cbn [F.title_value F.title_task]. rewrite Owned. cbn [present].
   repeat rewrite andb_true_iff. repeat split; try assumption;
     [now apply N.ltb_lt|now apply N.leb_le].
Qed.

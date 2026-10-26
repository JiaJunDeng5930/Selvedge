From Selvedge.Kernel Require Import FeatureFrameProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks WorldInvariant WorldInvariantProofs
 AfterHookPreservation ForkPreservation ForkLineageProofs CompactionEntryPreservation TicketSupplyProofs.
From Selvedge.Features Require Import Board BoardFacts TaskGraph Work WorkspaceBinding Compaction.
Import ListNotations.
Open Scope list_scope.
Definition without_history (value : task) := with_history [] value.
Local Ltac erase_task_projection := intros [contract profile settings lifecycle history queued lineage side cursor consumed]; reflexivity.
Definition feature_core_valid := FeatureFrameProofs.feature_core_valid.
Lemma observing_equal_history_erasure : forall (A : Type) (observe : task -> A) left right,
 (forall value, observe (without_history value) = observe value) ->
 without_history left = without_history right -> observe left = observe right.
Proof.
 intros A observe left right Stable Same.
 rewrite <- (Stable left), <- (Stable right), Same; reflexivity.
Qed.

Definition registry_lookup_commutes_with_mapping := @Selvedge.Foundation.RegistryProofs.registry_lookup_commutes_with_mapping.

Lemma observing_a_registry_with_equal_history_erasure :
 forall (A : Type) (observe : task -> A) missing before after owner,
 (forall value, observe (without_history value) = observe value) ->
 map without_history (world_tasks before) = map without_history (world_tasks after) ->
 (match find_task owner before with Some value => observe value | None => missing end) =
 (match find_task owner after with Some value => observe value | None => missing end).
Proof.
 intros A observe missing before after owner Stable Same.
 assert (Lookup : option_map without_history (find_task owner before) =
   option_map without_history (find_task owner after)).
 { unfold find_task; rewrite <- !registry_lookup_commutes_with_mapping, Same; reflexivity. }
 destruct (find_task owner before) as [old|]; destruct (find_task owner after) as [next|];
   cbn in Lookup; try discriminate; [|reflexivity].
 eapply observing_equal_history_erasure; [exact Stable|].
 exact (f_equal (fun value => match value with Some task => task | None => without_history old end) Lookup).
Qed.

Section FeatureOperationFrame.
Variables before after : world.
Hypothesis SameRegistry : map without_history (world_tasks before) = map without_history (world_tasks after).
Hypothesis SameFeatures : world_features before = world_features after.
Hypothesis SameProjects : world_projects before = world_projects after.
Hypothesis LaterTickets : (world_next_ticket before <= world_next_ticket after)%N.

Local Lemma tree_requirement_is_unchanged : forall entry,
 WorldInvariant.tree_owner_valid entry before = WorldInvariant.tree_owner_valid entry after.
Proof.
 intro entry. unfold WorldInvariant.tree_owner_valid. f_equal.
 apply observing_a_registry_with_equal_history_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Theorem unchanged_history_fields_preserve_other_feature_requirements :
 WorldInvariant.features_valid before = true -> feature_core_valid after = true.
Proof.
 change (FeatureFrameProofs.feature_core_valid before && WorldInvariant.compaction_valid before = true ->
   FeatureFrameProofs.feature_core_valid after = true).
 intro Valid. apply andb_true_iff in Valid as [Core Maintenance].
 eapply feature_core_requirements_follow_task_observations; try eassumption.
 - intros owner old Found.
   destruct (equal_registry_maps_retain_tasks _ without_history before after owner old SameRegistry Found)
     as [next [After Frame]]. exists next; split; [exact After|].
   eapply observing_equal_history_erasure; [erase_task_projection|exact Frame].
 - intros entry Valid; rewrite <- tree_requirement_is_unchanged; exact Valid.
Qed.
End FeatureOperationFrame.

Definition checkpoint_history_world owner current summary before :=
 put_task owner (checkpoint_task current summary) before.

Lemma a_checkpoint_keeps_the_history_erased_registry : forall owner current summary before,
 find_task owner before = Some current ->
 map without_history (world_tasks (checkpoint_history_world owner current summary before)) =
 map without_history (world_tasks before).
Proof.
 intros owner current summary before Found.
 apply replacing_equal_projection_keeps_registry_observations with (old:=current); [exact Found|].
 destruct current; reflexivity.
Qed.

Theorem an_idle_checkpoint_preserves_the_whole_task_registry : forall before owner current summary,
 WorldInvariant.well_formed before -> find_task owner before = Some current -> Compaction.idle current = true ->
 WorldInvariant.tasks_valid 0 (world_tasks (checkpoint_history_world owner current summary before))
   (checkpoint_history_world owner current summary before) = true.
Proof.
 intros before owner current summary Valid Owned Idle.
 assert (Unchanged : with_ticket (world_next_ticket before) before = before) by (destruct before; reflexivity).
 unfold checkpoint_history_world; rewrite <- Unchanged at 1 2.
 eapply task_replacement_preserves_registry_requirements with (relation:=fork_retains_task) (old:=current).
 - apply fork_retains_task_reflexive.
 - apply fork_retains_configuration.
 - exact Valid.
 - exact Owned.
 - apply a_checkpoint_retains_every_persistent_task_field.
 - pose proof (lookup_task_requirements before owner current Valid Owned) as Original.
   rewrite task_requirements_ignore_the_journal_cursor in Original.
   destruct (a_valid_task_has_its_progress_requirements owner current before Original) as [Context _].
   destruct (checkpoint_records_preserve_context_bindings_and_pending_progress current summary Idle)
     as [Bindings [Phase [Remaining Tickets]]].
   destruct (Remaining owner) as [Checked Operations].
   unfold task_progress_requirements; rewrite Bindings; auto.
Qed.

Lemma a_checkpoint_history_keeps_other_features_valid : forall before owner current summary,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 feature_core_valid (checkpoint_history_world owner current summary before) = true.
Proof.
 intros before owner current summary Valid Owned.
 apply unchanged_history_fields_preserve_other_feature_requirements with (before:=before).
 - symmetry; now apply a_checkpoint_keeps_the_history_erased_registry.
 - reflexivity.
 - reflexivity.
 - apply N.le_refl.
 - apply FeatureFrameProofs.well_formed_feature_requirements; exact Valid.
Qed.

Lemma storing_maintenance_keeps_graph_entries : forall entries first maintenance before,
 WorldInvariant.graphs_valid first entries (Compaction.store maintenance before) =
 WorldInvariant.graphs_valid first entries before.
Proof. intros; apply graph_entries_requirements_follow_entry_observations; reflexivity. Qed.

Lemma storing_maintenance_keeps_other_features_valid : forall maintenance before,
 feature_core_valid (Compaction.store maintenance before) = feature_core_valid before.
Proof.
 intros maintenance before. unfold feature_core_valid, FeatureFrameProofs.feature_core_valid, WorldInvariant.graph_registry_valid.
 cbn [world_features]. rewrite storing_maintenance_keeps_graph_entries. reflexivity.
Qed.

Theorem checkpoint_entries_preserve_all_maintenance_requirements : forall before owner current summary,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 WorldInvariant.compaction_valid (checkpoint_world owner current summary before) = true.
Proof.
 intros before owner current summary Valid Owned.
 pose proof (FeatureFrameProofs.well_formed_feature_requirements before Valid) as Features.
 unfold WorldInvariant.features_valid in Features. apply andb_true_iff in Features as [_ Maintenance].
 pose proof (compaction_current_entry_has_its_counter_bounds owner current before Maintenance Owned)
   as [Maintained [Attempted Useful]].
 unfold WorldInvariant.compaction_valid in Maintenance. apply andb_true_iff in Maintenance as [Unique Entries].
 unfold WorldInvariant.compaction_valid.
 change (WorldInvariant.unique_tickets (map fst (CompactionTypes.maintenance_entries
   (Compaction.with_entry owner (Compaction.checkpoint_entry (task_history current)
     (Compaction.current_entry owner (Compaction.registry before))) (Compaction.registry before)))) &&
   forallb (fun entry => WorldInvariant.maintenance_entry_valid entry (checkpoint_world owner current summary before))
     (CompactionTypes.maintenance_entries (Compaction.with_entry owner
       (Compaction.checkpoint_entry (task_history current) (Compaction.current_entry owner (Compaction.registry before)))
       (Compaction.registry before))) = true).
 apply andb_true_iff; split.
 - now apply compaction_upsert_has_one_entry_per_owner.
 - apply compaction_upsert_preserves_valid_entries.
   + eapply a_checkpoint_entry_is_valid_for_its_appended_history with (current:=current).
     * eapply LifecycleProofs.find_put_task; exact Owned.
     * eapply N.le_trans; [exact Maintained|exact Useful].
     * exact Attempted.
   + intros actual entry Member Different.
     assert (Lookup : find_task actual (checkpoint_world owner current summary before) = find_task actual before).
     { change (registry_at actual (replace owner (checkpoint_task current summary) (world_tasks before)) =
         registry_at actual (world_tasks before)).
       apply registry_replace_other; congruence. }
     unfold WorldInvariant.maintenance_entry_valid. rewrite Lookup.
     apply forallb_forall with (x:=(actual,entry)) in Entries; [exact Entries|exact Member].
Qed.

Definition maintenance_tickets (entry : N * CompactionTypes.entry) : list N :=
 (match Compaction.measurement_ticket (CompactionTypes.entry_measurement (snd entry)) with Some ticket => [ticket] | None => [] end) ++
 (match Compaction.provider_job_ticket (CompactionTypes.entry_job (snd entry)) with Some ticket => [ticket] | None => [] end).

Lemma checkpointing_maintenance_withdraws_only_existing_tickets : forall owner history entry before,
 ticket_subsequence
  (WorldInvariant.feature_tickets (world_features (Compaction.store
    (Compaction.with_entry owner (Compaction.checkpoint_entry history entry) (Compaction.registry before)) before)))
  (WorldInvariant.feature_tickets (world_features before)).
Proof.
 intros owner history entry before.
 unfold WorldInvariant.feature_tickets.
 change (ticket_subsequence
  (flat_map (fun entry => match Selvedge.Features.Domain.title_value entry with
    Selvedge.Features.Domain.TitlePending ticket _ _ => [ticket] | _ => [] end)
      (Selvedge.Features.Domain.feature_titles (world_features before)) ++
   flat_map (fun value => match Selvedge.Features.Domain.card_enrichment value with
    Selvedge.Features.Domain.Enriching ticket _ _ => [ticket] | _ => [] end)
      (WorldInvariant.cards_present (Selvedge.Features.Domain.feature_board (world_features before))) ++
   flat_map maintenance_tickets (filter (fun pair : N * CompactionTypes.entry => negb (N.eqb (fst pair) owner))
      (CompactionTypes.maintenance_entries (Compaction.registry before))))
  (flat_map (fun entry => match Selvedge.Features.Domain.title_value entry with
    Selvedge.Features.Domain.TitlePending ticket _ _ => [ticket] | _ => [] end)
      (Selvedge.Features.Domain.feature_titles (world_features before)) ++
   flat_map (fun value => match Selvedge.Features.Domain.card_enrichment value with
    Selvedge.Features.Domain.Enriching ticket _ _ => [ticket] | _ => [] end)
      (WorldInvariant.cards_present (Selvedge.Features.Domain.feature_board (world_features before))) ++
   flat_map maintenance_tickets (CompactionTypes.maintenance_entries (Compaction.registry before)))).
 apply ticket_subsequence_append; [apply ticket_subsequence_reflexive|].
 apply ticket_subsequence_append; [apply ticket_subsequence_reflexive|].
 apply filtering_ticket_groups_keeps_a_subsequence.
Qed.

Theorem checkpointing_maintenance_preserves_global_ticket_ownership : forall owner history entry before,
 WorldInvariant.tickets_valid before = true ->
 WorldInvariant.tickets_valid (Compaction.store
   (Compaction.with_entry owner (Compaction.checkpoint_entry history entry) (Compaction.registry before)) before) = true.
Proof.
 intros owner history entry before Valid.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners before Valid) as [Unique Bounds].
 assert (Subsequence : ticket_subsequence
   (flat_map WorldInvariant.task_tickets (world_tasks before) ++ WorldInvariant.feature_tickets
    (world_features (Compaction.store (Compaction.with_entry owner (Compaction.checkpoint_entry history entry)
      (Compaction.registry before)) before)))
   (flat_map WorldInvariant.task_tickets (world_tasks before) ++ WorldInvariant.feature_tickets (world_features before))).
 { apply ticket_subsequence_append; [apply ticket_subsequence_reflexive|].
   apply checkpointing_maintenance_withdraws_only_existing_tickets. }
 apply distinct_bounded_owners_form_a_valid_ticket_supply.
 - eapply ticket_subsequence_preserves_uniqueness; eauto.
 - apply Forall_forall; intros ticket Member.
   rewrite Forall_forall in Bounds. apply Bounds. eapply ticket_subsequence_includes; eauto.
Qed.

Theorem an_idle_checkpoint_preserves_all_world_requirements : forall before owner current summary,
 WorldInvariant.well_formed before -> find_task owner before = Some current -> Compaction.idle current = true ->
 WorldInvariant.well_formed (checkpoint_world owner current summary before).
Proof.
 intros before owner current summary Valid Owned Idle.
 pose proof (an_idle_checkpoint_preserves_the_whole_task_registry before owner current summary Valid Owned Idle) as Tasks.
 pose proof (a_checkpoint_history_keeps_other_features_valid before owner current summary Valid Owned) as Features.
 pose proof (checkpoint_entries_preserve_all_maintenance_requirements before owner current summary Valid Owned) as Maintenance.
 assert (Tickets : WorldInvariant.tickets_valid (checkpoint_history_world owner current summary before) = true).
 { apply withdrawing_task_tickets_preserves_global_ticket_supply with (current:=current).
   - exact (WorldInvariant.tickets_requirement before Valid).
   - exact Owned.
   - destruct (checkpoint_records_preserve_context_bindings_and_pending_progress current summary Idle) as [_ [_ [_ Same]]].
     rewrite Same. apply ticket_subsequence_reflexive. }
 constructor.
 - exact (WorldInvariant.environment_requirement before Valid).
 - exact (WorldInvariant.projects_requirement before Valid).
 - unfold WorldInvariant.world_structure. rewrite task_registry_requirements_ignore_the_journal_cursor.
   rewrite FeatureFrameProofs.registry_requirements_read_only_the_task_and_project_registries
     with (before:=checkpoint_history_world owner current summary before) by reflexivity.
   exact Tasks.
 - exact (checkpointing_maintenance_preserves_global_ticket_ownership owner (task_history current)
     (Compaction.current_entry owner (Compaction.registry before))
     (checkpoint_history_world owner current summary before) Tickets).
 - unfold WorldInvariant.world_structure. rewrite FeatureFrameProofs.feature_requirements_ignore_journal_cursor.
   change (feature_core_valid (checkpoint_world owner current summary before) &&
     WorldInvariant.compaction_valid (checkpoint_world owner current summary before) = true).
   rewrite Maintenance, andb_true_r.
   unfold checkpoint_world. rewrite storing_maintenance_keeps_other_features_valid. exact Features.
Qed.

From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks WorldInvariant WorldInvariantProofs
 AfterHookPreservation ForkPreservation ForkLineageProofs CompactionEntryPreservation TerminalTicketProofs.
From Selvedge.Features Require Import Board BoardFacts TaskGraph Work WorkspaceBinding Compaction.
Import ListNotations.
Open Scope list_scope.
Definition without_history (value : task) := with_history [] value.
Local Ltac erase_task_projection := intros [contract profile settings lifecycle history queued lineage side cursor consumed]; reflexivity.
Definition feature_core_valid (value : world) :=
 WorldInvariant.titles_valid value && WorldInvariant.remote_valid (Selvedge.Features.Domain.feature_remote (world_features value)) &&
 WorldInvariant.worktrees_valid value && WorldInvariant.board_valid value && WorldInvariant.sharing_valid value &&
 WorldInvariant.graph_registry_valid value && WorldInvariant.works_valid value.
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

Local Lemma same_task_presence : forall owner,
 WorldInvariant.present (find_task owner before) = WorldInvariant.present (find_task owner after).
Proof.
 intro owner. unfold WorldInvariant.present.
 apply observing_a_registry_with_equal_history_erasure; [reflexivity|exact SameRegistry].
Qed.

Local Lemma earlier_ticket_stays_allocated : forall ticket,
 (ticket <? world_next_ticket before)%N = true -> (ticket <? world_next_ticket after)%N = true.
Proof. intros ticket Earlier; apply N.ltb_lt in Earlier; apply N.ltb_lt; lia. Qed.

Local Lemma title_requirement_survives : forall entry,
 WorldInvariant.title_valid entry before = true -> WorldInvariant.title_valid entry after = true.
Proof.
 intros entry Valid. unfold WorldInvariant.title_valid in *.
 rewrite <- same_task_presence. apply andb_true_iff in Valid as [Found Valid].
 apply andb_true_iff; split; [exact Found|].
 destruct (Selvedge.Features.Domain.title_value entry); try exact Valid.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[Ticket Profile] Capable] Budget].
 repeat split; try assumption; apply earlier_ticket_stays_allocated; exact Ticket.
Qed.

Local Lemma tree_requirement_is_unchanged : forall entry,
 WorldInvariant.tree_owner_valid entry before = WorldInvariant.tree_owner_valid entry after.
Proof.
 intro entry. unfold WorldInvariant.tree_owner_valid. f_equal.
 apply observing_a_registry_with_equal_history_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Local Lemma card_requirement_survives : forall card,
 WorldInvariant.card_valid card before = true -> WorldInvariant.card_valid card after = true.
Proof.
 intros card Valid. unfold WorldInvariant.card_valid in *.
 assert (Draft : Board.valid_draft (Selvedge.Features.Domain.card_contents card) before =
   Board.valid_draft (Selvedge.Features.Domain.card_contents card) after).
 { unfold Board.valid_draft, BoardFacts.valid_draft, BoardFacts.lookup_agent, BoardFacts.registry;
   rewrite SameProjects, SameFeatures; reflexivity. }
 assert (Linked : (match Selvedge.Features.Domain.card_task card with
   | Some owner => WorldInvariant.present (find_task owner before) | None => true end) =
   (match Selvedge.Features.Domain.card_task card with
   | Some owner => WorldInvariant.present (find_task owner after) | None => true end)).
 { destruct (Selvedge.Features.Domain.card_task card); [apply same_task_presence|reflexivity]. }
 apply andb_true_iff in Valid as [Static Enrichment].
 apply andb_true_iff; split; [rewrite <- Draft, <- Linked; exact Static|].
 destruct (Selvedge.Features.Domain.card_enrichment card); try exact Enrichment.
 repeat rewrite andb_true_iff in Enrichment |- *.
 destruct Enrichment as [[Ticket Revision] Active].
 repeat split; try assumption; apply earlier_ticket_stays_allocated; exact Ticket.
Qed.

Local Lemma work_task_owner_is_unchanged : forall owner,
 Work.task_owner owner before = Work.task_owner owner after.
Proof.
 intro owner; unfold Work.task_owner; rewrite <- SameFeatures.
 apply observing_a_registry_with_equal_history_erasure; [erase_task_projection|exact SameRegistry].
Qed.

Local Lemma graph_requirement_is_unchanged : forall owner graph,
 WorldInvariant.graph_valid owner graph before = WorldInvariant.graph_valid owner graph after.
Proof.
 intros owner graph. unfold WorldInvariant.graph_valid; rewrite <- SameFeatures. f_equal.
 apply forallb_equal_predicates; intro node; rewrite same_task_presence.
 unfold TaskGraph.task_in_work; destruct (Selvedge.Features.Domain.association owner
   (Selvedge.Features.Domain.feature_graph_owners (world_features before))); [rewrite work_task_owner_is_unchanged|]; reflexivity.
Qed.

Local Lemma graph_registry_requirement_is_unchanged :
 WorldInvariant.graph_registry_valid before = WorldInvariant.graph_registry_valid after.
Proof.
 unfold WorldInvariant.graph_registry_valid; rewrite <- SameFeatures. f_equal.
 generalize (Selvedge.Features.Domain.feature_graphs (world_features before)).
 intros graphs; generalize 0%N; induction graphs as [|graph rest IH]; intro owner; [reflexivity|].
 cbn [WorldInvariant.graphs_valid]. rewrite IH.
 destruct graph; [rewrite graph_requirement_is_unchanged|]; reflexivity.
Qed.

Local Lemma works_requirement_is_unchanged :
 WorldInvariant.works_valid before = WorldInvariant.works_valid after.
Proof.
 unfold WorldInvariant.works_valid, WorldInvariant.work_owners_valid, Work.lookup.
 rewrite <- SameFeatures. f_equal. f_equal.
 apply forallb_equal_predicates; intros [owner work].
 apply observing_a_registry_with_equal_history_erasure; [erase_task_projection|exact SameRegistry].
Qed.
Theorem unchanged_history_fields_preserve_other_feature_requirements :
 WorldInvariant.features_valid before = true -> feature_core_valid after = true.
Proof.
 intro Valid. unfold WorldInvariant.features_valid in Valid. unfold feature_core_valid.
 repeat rewrite andb_true_iff in Valid. repeat rewrite andb_true_iff.
 destruct Valid as [[[[[[[Titles Remote] Trees] Board] Sharing] Graphs] Works] Maintenance].
 repeat split.
 - unfold WorldInvariant.titles_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Titles |- *; destruct Titles as [[[TaskPrompt AgentPrompt] Unique] Entries].
   repeat split; try assumption. apply forallb_forall; intros entry Member.
   apply title_requirement_survives; apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.remote_valid in *; rewrite <- SameFeatures; exact Remote.
 - unfold WorldInvariant.worktrees_valid in *; rewrite <- SameFeatures.
   apply andb_true_iff in Trees as [Unique Entries]; apply andb_true_iff; split; [exact Unique|].
   apply forallb_forall; intros entry Member; rewrite <- tree_requirement_is_unchanged.
   apply forallb_forall with (x:=entry) in Entries; assumption.
 - unfold WorldInvariant.board_valid in *; rewrite <- SameFeatures.
   repeat rewrite andb_true_iff in Board |- *.
   destruct Board as [[[[[[[Cards Agents] CardBound] AgentBound] Entries] Unique] AgentEntries] Draft].
   repeat split; try assumption. apply forallb_forall; intros card Member.
   apply card_requirement_survives; apply forallb_forall with (x:=card) in Entries; assumption.
 - unfold WorldInvariant.sharing_valid in *; unfold WorkspaceBinding.resource_ready, WorkspaceBinding.owned in *.
   rewrite <- SameFeatures, <- SameProjects; exact Sharing.
 - rewrite <- graph_registry_requirement_is_unchanged; exact Graphs.
 - rewrite <- works_requirement_is_unchanged; exact Works.
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

Lemma a_checkpoint_keeps_every_lineage : forall owner current summary before,
 find_task owner before = Some current ->
 map task_lineage (world_tasks (checkpoint_history_world owner current summary before)) =
 map task_lineage (world_tasks before).
Proof.
 intros owner current summary before Found.
 apply replacing_equal_projection_keeps_registry_observations with (old:=current); [exact Found|reflexivity].
Qed.

Lemma checkpoint_task_validity_at : forall before owner current,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 WorldInvariant.task_valid owner current before = true.
Proof.
 intros before owner current Valid Found.
 pose proof (lookup_task_requirements before owner current Valid Found) as Task.
 unfold WorldInvariant.world_structure in Task. now rewrite task_requirements_ignore_the_journal_cursor in Task.
Qed.

Lemma every_checkpoint_lookup_keeps_its_local_progress : forall before owner current summary,
 WorldInvariant.well_formed before -> find_task owner before = Some current -> Compaction.idle current = true ->
 forall queried next, find_task queried (checkpoint_history_world owner current summary before) = Some next ->
 exists old, find_task queried before = Some old /\ fork_retains_task old next /\
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history next)) = true /\
 WorldInvariant.phase_valid next = true /\ WorldInvariant.checked_phase queried next = true /\
 WorldInvariant.operations_valid queried next = true.
Proof.
 intros before owner current summary Valid Owned Idle queried next Found.
 destruct (N.eq_dec queried owner) as [Same|Different].
 - subst queried.
   assert (Lookup : find_task owner (checkpoint_history_world owner current summary before) = Some (checkpoint_task current summary)).
   { eapply LifecycleProofs.find_put_task; exact Owned. }
   rewrite Lookup in Found; inversion Found; subst next.
   exists current; split; [exact Owned|]. split; [apply a_checkpoint_retains_every_persistent_task_field|].
   pose proof (checkpoint_task_validity_at before owner current Valid Owned) as Task.
   pose proof (a_valid_task_has_its_progress_requirements owner current before Task) as [Context _].
   destruct (checkpoint_records_preserve_context_bindings_and_pending_progress current summary Idle)
     as [Bindings [Phase [Remaining Tickets]]]. rewrite Bindings. split; [exact Context|].
   destruct (Remaining owner) as [Checked Operations]. auto.
 - change (registry_at queried (replace owner (checkpoint_task current summary) (world_tasks before)) = Some next) in Found.
   rewrite registry_replace_other in Found by congruence.
   exists next; split; [exact Found|]. split; [apply fork_retains_task_reflexive|].
   apply a_valid_task_has_its_progress_requirements with (before:=before).
   eapply checkpoint_task_validity_at; eauto.
Qed.

Theorem an_idle_checkpoint_preserves_the_whole_task_registry : forall before owner current summary,
 WorldInvariant.well_formed before -> find_task owner before = Some current -> Compaction.idle current = true ->
 WorldInvariant.tasks_valid 0 (world_tasks (checkpoint_history_world owner current summary before))
   (checkpoint_history_world owner current summary before) = true.
Proof.
 intros before owner current summary Valid Owned Idle.
 pose proof (checkpoint_transactions_have_their_exact_task_frame owner current summary before Owned) as [Retained _].
 pose proof (a_checkpoint_keeps_every_lineage owner current summary before Owned) as Lineages.
 apply task_registry_requirement_from_every_lookup. intros queried next Found.
 change (WorldInvariant.task_valid queried next (checkpoint_history_world owner current summary before) = true).
 destruct (every_checkpoint_lookup_keeps_its_local_progress before owner current summary Valid Owned Idle queried next Found)
   as [old [Old [Frame [Context [Phase [Checked Operations]]]]]].
 pose proof (checkpoint_task_validity_at before queried old Valid Old) as Task.
 eapply retained_task_requirements_lift with (before:=before) (old:=old); [exact Frame|reflexivity| | |exact Context|exact Phase|exact Checked|exact Operations|exact Task].
 - eapply existing_lineage_survives_a_fork; [exact Frame|exact Retained|].
   unfold WorldInvariant.task_valid in Task; repeat rewrite andb_true_iff in Task; tauto.
 - rewrite <- (task_frame_preserves_contract old next Frame).
   rewrite descendant_count_depends_only_on_lineages with (right:=world_tasks before) by exact Lineages.
   apply N.leb_le. unfold WorldInvariant.task_valid in Task; repeat rewrite andb_true_iff in Task; tauto.
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
Proof.
 induction entries as [|entry rest IH]; intros; cbn [WorldInvariant.graphs_valid]; [reflexivity|].
 rewrite IH. destruct entry; reflexivity.
Qed.

Lemma storing_maintenance_keeps_other_features_valid : forall maintenance before,
 feature_core_valid (Compaction.store maintenance before) = feature_core_valid before.
Proof.
 intros maintenance before. unfold feature_core_valid, WorldInvariant.graph_registry_valid.
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

Lemma dropping_a_ticket_prefix_keeps_a_subsequence : forall prefix selected original,
 ticket_subsequence selected original -> ticket_subsequence selected (prefix ++ original).
Proof. induction prefix; intros; cbn; [assumption|constructor; now apply IHprefix]. Qed.

Lemma filtering_ticket_groups_keeps_a_subsequence : forall A (tickets : A -> list N) keep groups,
 ticket_subsequence (flat_map tickets (filter keep groups)) (flat_map tickets groups).
Proof.
 intros A tickets keep groups; induction groups as [|first rest IH]; cbn; [constructor|].
 destruct (keep first); cbn.
 - apply ticket_subsequence_append; [apply ticket_subsequence_reflexive|exact IH].
 - now apply dropping_a_ticket_prefix_keeps_a_subsequence.
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
 unfold WorldInvariant.tickets_valid. apply andb_true_iff; split.
 - apply distinct_tickets_pass_the_uniqueness_checker.
   eapply ticket_subsequence_preserves_uniqueness; eauto.
 - apply forallb_forall; intros ticket Member. apply N.ltb_lt.
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

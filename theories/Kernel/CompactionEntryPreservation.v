From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json RegistryProofs KeyedListProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State ContextSelection ContextProofs
 WorldInvariant WorldInvariantProofs FeatureFrameProofs ForkPreservation AfterHookAuthorizationProofs.
From Selvedge.Features Require Import Compaction CompactionTypes.
Import ListNotations.
Open Scope list_scope.
Module C := Selvedge.Features.CompactionTypes.
Module A := Selvedge.Features.Compaction.

Lemma compaction_current_entry_has_its_counter_bounds : forall owner current before,
 WorldInvariant.compaction_valid before = true -> find_task owner before = Some current ->
 let entry := A.current_entry owner (A.registry before) in
 (C.entry_maintained entry <= C.entry_useful entry)%N /\
 (C.entry_attempted entry <= A.useful (task_history current))%N /\
 (C.entry_useful entry <= A.useful (task_history current))%N.
Proof.
 intros owner current before Valid Found.
 unfold A.current_entry, A.find_entry.
 destruct (find _ _) as [[actual entry]|] eqn:Entry.
 - apply find_some in Entry as [Member Same]. cbn in Same.
   apply N.eqb_eq in Same; subst actual; cbn.
   unfold WorldInvariant.compaction_valid in Valid.
   apply andb_true_iff in Valid as [_ Entries].
   apply forallb_forall with (x:=(owner,entry)) in Entries; [|exact Member].
   unfold WorldInvariant.maintenance_entry_valid in Entries; rewrite Found in Entries.
   repeat rewrite andb_true_iff in Entries.
   destruct Entries as [[[Maintained Attempted] Useful] Job].
   repeat split; now apply N.leb_le.
 - cbn. repeat split; lia.
Qed.

Lemma compaction_upsert_selects_its_new_entry : forall owner replacement maintenance,
 CommitAdmission.compaction_entry_at owner (C.maintenance_entries (A.with_entry owner replacement maintenance)) =
 Some replacement.
Proof.
 intros. unfold CommitAdmission.compaction_entry_at, A.with_entry, set; cbn.
 now rewrite N.eqb_refl.
Qed.

Lemma compaction_removing_one_key_keeps_every_other_lookup : forall entries owner actual,
 actual <> owner ->
 find (fun pair : N * C.entry => N.eqb actual (fst pair))
   (filter (fun pair => negb (N.eqb (fst pair) owner)) entries) =
 find (fun pair => N.eqb actual (fst pair)) entries.
Proof.
 intros entries owner actual Different.
 replace (filter (fun pair : N * C.entry => negb (N.eqb (fst pair) owner)) entries)
   with (filter (fun pair => negb (N.eqb owner (fst pair))) entries).
 - eapply filtering_another_key_preserves_lookup; [intros; now apply N.eqb_eq|exact Different].
 - apply filter_ext; intros; now rewrite N.eqb_sym.
Qed.

Lemma compaction_upsert_keeps_every_other_lookup : forall owner actual replacement maintenance,
 actual <> owner ->
 CommitAdmission.compaction_entry_at actual (C.maintenance_entries (A.with_entry owner replacement maintenance)) =
 CommitAdmission.compaction_entry_at actual (C.maintenance_entries maintenance).
Proof.
 intros owner actual replacement maintenance Different.
 unfold CommitAdmission.compaction_entry_at, A.with_entry, set; cbn.
 assert (Other : N.eqb actual owner = false) by (apply N.eqb_neq; exact Different).
 rewrite Other.
 rewrite compaction_removing_one_key_keeps_every_other_lookup by exact Different.
 reflexivity.
Qed.

Lemma a_checkpoint_entry_records_the_exact_settled_input : forall history entry,
 (C.entry_maintained entry <= A.useful history)%N ->
 (C.entry_attempted entry <= A.useful history)%N ->
 C.entry_useful (A.checkpoint_entry history entry) = A.useful history /\
 C.entry_maintained (A.checkpoint_entry history entry) = A.useful history /\
 C.entry_attempted (A.checkpoint_entry history entry) = A.useful history /\
 C.entry_job (A.checkpoint_entry history entry) = C.NoJob /\
 C.entry_measurement (A.checkpoint_entry history entry) = C.Unmeasured.
Proof.
 intros history entry Maintained Attempted.
 unfold A.checkpoint_entry, A.with_measurement, A.with_job, set; cbn.
 rewrite !N.max_l by assumption; repeat split; reflexivity.
Qed.

Lemma a_checkpoint_entry_is_valid_for_its_appended_history : forall owner history entry replacement current after,
 find_task owner after = Some (with_history (history ++ [ContextReplacement replacement]) current) ->
 (C.entry_maintained entry <= A.useful history)%N ->
 (C.entry_attempted entry <= A.useful history)%N ->
 WorldInvariant.maintenance_entry_valid (owner,A.checkpoint_entry history entry) after = true.
Proof.
 intros owner history entry replacement current after Found Maintained Attempted.
 unfold WorldInvariant.maintenance_entry_valid; rewrite Found.
 destruct (a_checkpoint_entry_records_the_exact_settled_input history entry Maintained Attempted)
   as [Useful [Kept [Tried [Job Measurement]]]].
 rewrite Useful,Kept,Tried,Job. cbv [Domain.with_history set]; cbn.
 unfold A.useful; rewrite filter_app; cbn; rewrite app_nil_r, !N.leb_refl; reflexivity.
Qed.

Lemma compaction_replacement_keeps_the_input_count : forall history replacement,
 A.useful (history ++ [ContextReplacement replacement]) = A.useful history.
Proof.
 intros; unfold A.useful; rewrite filter_app; cbn; now rewrite app_nil_r.
Qed.

Lemma compaction_supplied_history_is_an_exact_append : forall current summary,
 ContextSelection.adopt (task_history current) (ContextSelection.portable summary) (task_history current) =
 task_history current ++ [ContextSelection.record (N.of_nat (List.length (task_history current)))
   (ContextSelection.portable summary)].
Proof.
 intros; unfold ContextSelection.adopt.
 rewrite the_same_history_retains_its_captured_prefix; reflexivity.
Qed.

Lemma compaction_upsert_preserves_valid_entries : forall owner replacement maintenance after,
 WorldInvariant.maintenance_entry_valid (owner,replacement) after = true ->
 (forall actual entry, In (actual,entry) (C.maintenance_entries maintenance) -> actual <> owner ->
   WorldInvariant.maintenance_entry_valid (actual,entry) after = true) ->
 forallb (fun entry => WorldInvariant.maintenance_entry_valid entry after)
   (C.maintenance_entries (A.with_entry owner replacement maintenance)) = true.
Proof.
 intros owner replacement maintenance after New Retained.
 change (WorldInvariant.maintenance_entry_valid (owner,replacement) after &&
   forallb (fun entry => WorldInvariant.maintenance_entry_valid entry after)
    (filter (fun pair => negb (N.eqb (fst pair) owner)) (C.maintenance_entries maintenance)) = true).
 rewrite New; cbn. apply forallb_forall; intros [actual entry] Member.
 apply filter_In in Member as [Member Different].
 apply Retained; [exact Member|].
 cbn in Different. apply negb_true_iff, N.eqb_neq in Different. exact Different.
Qed.

Lemma compaction_upsert_has_one_entry_per_owner : forall owner replacement maintenance,
 WorldInvariant.unique_tickets (map fst (C.maintenance_entries maintenance)) = true ->
 WorldInvariant.unique_tickets (map fst
   (C.maintenance_entries (A.with_entry owner replacement maintenance))) = true.
Proof.
 intros owner replacement maintenance Unique.
 apply unique_tickets_denotes_distinct_correlation_owners in Unique.
 assert (Filtered : NoDup (map fst (filter (fun pair : N * C.entry => negb (N.eqb (fst pair) owner))
   (C.maintenance_entries maintenance)))).
 { exact (filtering_preserves_unique_keys (N * C.entry) N (@fst N C.entry)
     (fun key => negb (N.eqb key owner)) (C.maintenance_entries maintenance) Unique). }
 assert (Fresh : ~ In owner (map fst (filter (fun pair : N * C.entry => negb (N.eqb (fst pair) owner))
   (C.maintenance_entries maintenance)))).
 { intro Member. apply in_map_iff in Member as [[actual entry] [Same Member]].
   cbn in Same; subst actual. apply filter_In in Member as [_ Different].
   rewrite N.eqb_refl in Different; discriminate. }
 unfold A.with_entry, set; cbn.
 assert (Nodup : NoDup (owner :: map fst (filter
   (fun pair : N * C.entry => negb (N.eqb (fst pair) owner)) (C.maintenance_entries maintenance))))
   by (constructor; assumption).
 change (WorldInvariant.unique_tickets (owner :: map fst (filter
   (fun pair : N * C.entry => negb (N.eqb (fst pair) owner)) (C.maintenance_entries maintenance))) = true).
 apply FeatureFrameProofs.distinct_ticket_list_passes_checker. exact Nodup.
Qed.

Lemma compaction_current_entry_finds_a_unique_member : forall owner entry maintenance,
 NoDup (map fst (C.maintenance_entries maintenance)) ->
 In (owner,entry) (C.maintenance_entries maintenance) ->
 A.current_entry owner maintenance = entry.
Proof.
 intros owner entry maintenance Unique Member.
 unfold A.current_entry,A.find_entry.
 assert (Same : find (fun pair : N * C.entry => N.eqb (fst pair) owner) (C.maintenance_entries maintenance) =
   find (fun pair => N.eqb owner (fst pair)) (C.maintenance_entries maintenance)).
 { generalize (C.maintenance_entries maintenance) as entries.
   intros entries; induction entries as [|[actual value] rest IH]; cbn; [reflexivity|].
   rewrite N.eqb_sym. destruct (N.eqb owner actual); [reflexivity|exact IH]. }
 rewrite Same.
 change (match option_map snd (find (fun pair => N.eqb (fst (owner,entry)) (fst pair))
   (C.maintenance_entries maintenance)) with Some entry => entry | None => C.empty_entry end = entry).
 rewrite a_unique_registry_key_finds_its_own_entry; [reflexivity|exact Unique|exact Member].
Qed.

Lemma compaction_upsert_retains_monotone_counters : forall owner replacement maintenance,
 NoDup (map fst (C.maintenance_entries maintenance)) ->
 (forall entry, In (owner,entry) (C.maintenance_entries maintenance) ->
   (C.entry_useful entry <= C.entry_useful replacement)%N /\
   (C.entry_maintained entry <= C.entry_maintained replacement)%N /\
   (C.entry_attempted entry <= C.entry_attempted replacement)%N) ->
 CommitAdmission.retained_compaction_entries (C.maintenance_entries maintenance)
   (C.maintenance_entries (A.with_entry owner replacement maintenance)) = true.
Proof.
 intros owner replacement maintenance Unique Monotone.
 apply keyed_retention_follows_each_lookup; intros [actual entry] Member; cbn [fst snd].
 destruct (N.eq_dec actual owner) as [Same|Different].
 - subst actual; rewrite compaction_upsert_selects_its_new_entry.
   unfold CommitAdmission.retained_compaction_entry.
   destruct (Monotone entry Member) as [Useful [Maintained Attempted]].
   repeat rewrite andb_true_iff; repeat split; now apply N.leb_le.
 - rewrite compaction_upsert_keeps_every_other_lookup by exact Different.
   unfold CommitAdmission.compaction_entry_at.
   change (CommitAdmission.retained_compaction_entry entry
     (option_map snd (find (fun pair => N.eqb (fst (actual,entry)) (fst pair))
       (C.maintenance_entries maintenance))) = true).
   rewrite a_unique_registry_key_finds_its_own_entry by assumption.
   cbn [option_map snd CommitAdmission.retained_compaction_entry]; now rewrite !N.leb_refl.
Qed.

Definition checkpoint_task (current : task) (summary : string) :=
 with_history (task_history current ++ [ContextSelection.record (N.of_nat (List.length (task_history current)))
   (ContextSelection.portable summary)]) current.
Definition checkpoint_world (owner : N) (current : task) (summary : string) (before : world) :=
 A.store (A.with_entry owner (A.checkpoint_entry (task_history current) (A.current_entry owner (A.registry before)))
   (A.registry before)) (put_task owner (checkpoint_task current summary) before).

Lemma supplied_checkpoints_use_the_declared_world_constructor : forall owner current summary before,
 decision_world (A.supplied owner current summary before) = checkpoint_world owner current summary before.
Proof.
 intros; unfold A.supplied, A.supplied_change; rewrite compaction_supplied_history_is_an_exact_append; reflexivity.
Qed.

Lemma a_checkpoint_retains_every_persistent_task_field : forall current summary,
 ForkPreservation.fork_retains_task current (checkpoint_task current summary).
Proof.
 intros current summary; split.
 - destruct current as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle; reflexivity.
 - exists [ContextSelection.record (N.of_nat (List.length (task_history current)))
     (ContextSelection.portable summary)]. reflexivity.
Qed.

Theorem checkpoint_transactions_have_their_exact_task_frame : forall owner current summary before,
 find_task owner before = Some current ->
 (forall actual original, find_task actual before = Some original ->
   exists next, find_task actual (checkpoint_world owner current summary before) = Some next /\
     ForkPreservation.fork_retains_task original next) /\
 world_environment (checkpoint_world owner current summary before) = world_environment before /\
 world_projects (checkpoint_world owner current summary before) = world_projects before /\
 world_next_ticket (checkpoint_world owner current summary before) = world_next_ticket before /\
 List.length (world_tasks (checkpoint_world owner current summary before)) = List.length (world_tasks before).
Proof.
 intros owner current summary before Found; split.
 - exact (task_replacement_retains_each_lookup fork_retains_task fork_retains_task_reflexive
     before owner current (checkpoint_task current summary) (world_next_ticket before) Found
     (a_checkpoint_retains_every_persistent_task_field current summary)).
 - repeat split; try reflexivity. apply registry_replace_length.
Qed.

Theorem checkpoint_records_preserve_context_bindings_and_pending_progress : forall current summary,
 A.idle current = true ->
 ContextUpdates.bindings (task_history (checkpoint_task current summary)) = ContextUpdates.bindings (task_history current) /\
 WorldInvariant.phase_valid (checkpoint_task current summary) = true /\
 (forall owner, WorldInvariant.checked_phase owner (checkpoint_task current summary) = true /\
   WorldInvariant.operations_valid owner (checkpoint_task current summary) = true) /\
 WorldInvariant.task_tickets (checkpoint_task current summary) = WorldInvariant.task_tickets current.
Proof.
 intros current summary Idle. split.
 - apply context_replacement_preserves_the_reconstructed_sources.
 - destruct current as [contract profile settings lifecycle history queued lineage side cursor consumed].
   destruct lifecycle as [phase operations|phase operations|phase operations|operations];
     try destruct phase; destruct operations; cbn in Idle; try discriminate;
     cbn [checkpoint_task Domain.with_history set WorldInvariant.phase_valid WorldInvariant.phase_calls
       WorldInvariant.calls_valid WorldInvariant.checked_phase WorldInvariant.operations_valid
       WorldInvariant.task_tickets WorldInvariant.phase_tickets Domain.task_activity Domain.task_operations];
     repeat split; reflexivity.
Qed.

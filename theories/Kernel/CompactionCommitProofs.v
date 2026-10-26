From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Inputs WorldInvariant WorldInvariantProofs
 CommitAdmission AfterHookAuthorizationProofs FeatureFrameProofs FeatureAuthorityProofs ForkPreservation
 CompactionEntryPreservation CheckpointWorldProofs DeferredCommit DeferredCommitProofs CompactionCommit Delivery Notifications.
From Selvedge.Features Require Import Domain State Compaction CompactionTypes CompactionProofs.
Import ListNotations.
Open Scope list_scope.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.
Module A := CommitAdmission.
Module M := Selvedge.Features.Compaction.
Module MP := Selvedge.Features.CompactionProofs.

Lemma an_idle_checkpoint_keeps_its_own_task_authority : forall source raw before actual old_features next_features current summary,
 M.alive current = true ->
 A.retained_task source raw before actual old_features next_features current (checkpoint_task current summary) = true.
Proof.
 intros source raw before actual old_features next_features current summary Alive.
 unfold A.retained_task, checkpoint_task, with_history, set.
 cbn -[A.same_contract A.same_profile A.same_settings A.same_naturals ContextSelection.history_extends A.same_archived_task].
 rewrite the_same_lineage_has_the_same_ancestors, the_same_creation_contract_has_the_same_configuration,
   the_same_profile_has_the_same_configuration, the_same_settings_have_the_same_configuration; cbn.
 rewrite appended_history_preserves_captured_prefix by apply the_same_history_retains_its_captured_prefix.
 unfold A.same_archived_task. destruct current as [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct lifecycle; cbn in Alive |- *; try discriminate; reflexivity.
Qed.

Lemma checkpointing_keeps_the_complete_task_authority : forall source raw owner current summary before,
 find_task owner before = Some current -> M.alive current = true ->
 A.retained_tasks source raw before (checkpoint_world owner current summary before) = true.
Proof.
 intros source raw owner current summary before Owned Alive.
 unfold A.retained_tasks. eapply replacing_one_task_keeps_authority_across_other_features; [exact Owned|].
 intros; now apply an_idle_checkpoint_keeps_its_own_task_authority.
Qed.

Lemma checkpointing_keeps_maintenance_counter_authority : forall owner current (summary : string) before,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 A.compaction_evolution (M.registry before)
  (M.with_entry owner (M.checkpoint_entry (task_history current) (M.current_entry owner (M.registry before)))
    (M.registry before)) = true.
Proof.
 intros owner current summary before Valid Owned.
 pose proof (FeatureFrameProofs.well_formed_feature_requirements before Valid) as Features.
 unfold WorldInvariant.features_valid in Features. apply andb_true_iff in Features as [_ Maintenance].
 pose proof Maintenance as Original. unfold WorldInvariant.compaction_valid in Maintenance.
 apply andb_true_iff in Maintenance as [Unique Entries].
 apply unique_tickets_denotes_distinct_correlation_owners in Unique.
 unfold A.compaction_evolution. apply andb_true_iff; split; [apply N.leb_refl|].
 apply compaction_upsert_retains_monotone_counters; [exact Unique|].
 intros entry Member.
 pose proof (compaction_current_entry_finds_a_unique_member owner entry (M.registry before) Unique Member) as Selected.
 rewrite Selected.
 apply forallb_forall with (x:=(owner,entry)) in Entries; [|exact Member].
 unfold WorldInvariant.maintenance_entry_valid in Entries. rewrite Owned in Entries.
 repeat rewrite andb_true_iff in Entries.
 unfold M.checkpoint_entry, M.with_measurement, M.with_job, set; cbn.
 repeat split.
 - apply N.leb_le. tauto.
 - apply N.le_max_r.
 - apply N.le_max_r.
Qed.

Lemma checkpointing_keeps_every_feature_authority : forall owner current (summary : string) before,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 A.features_evolution (world_features before) (world_features (checkpoint_world owner current summary before)) = true.
Proof.
 intros owner current summary before Valid Owned.
 pose proof (FeatureFrameProofs.well_formed_feature_requirements before Valid) as Features.
 pose proof (well_formed_features_admit_their_unchanged_configuration before Features) as Original.
 pose proof (checkpointing_keeps_maintenance_counter_authority owner current summary before Valid Owned) as Counter.
 unfold A.features_evolution, A.titles_evolution, A.same_title_prompts in Original |- *.
 unfold checkpoint_world, M.store, M.registry, with_features, Selvedge.Features.State.with_compaction, set.
 cbn -[A.board_evolution A.compaction_evolution] in *.
 match goal with |- context [A.compaction_evolution ?old ?next] =>
   let Actual := fresh "Actual" in assert (Actual : A.compaction_evolution old next = true) by exact Counter;
   rewrite Actual
 end.
 repeat rewrite andb_true_iff in *. tauto.
Qed.

Lemma compaction_lookup_agrees_with_the_owning_registry : forall owner maintenance,
 A.compaction_entry_at owner (C.maintenance_entries maintenance) = M.find_entry owner maintenance.
Proof.
 intros owner maintenance. unfold A.compaction_entry_at, M.find_entry.
 f_equal. generalize (C.maintenance_entries maintenance) as entries.
 intros entries; induction entries as [|[actual entry] rest IH]; cbn; [reflexivity|].
 rewrite N.eqb_sym. destruct (N.eqb actual owner); [reflexivity|exact IH].
Qed.

Lemma a_checkpoint_retires_each_cancelled_request : forall owner current summary before effect,
 In effect (M.cancellations owner (M.current_entry owner (M.registry before))) ->
 A.compaction_effect_valid effect before (checkpoint_world owner current summary before) = true.
Proof.
 intros owner current summary before effect Member.
 unfold M.current_entry in Member.
 destruct (M.find_entry owner (M.registry before)) as [entry|] eqn:Found.
 - assert (Was : A.compaction_entry_at owner (C.maintenance_entries (M.registry before)) = Some entry).
   { rewrite compaction_lookup_agrees_with_the_owning_registry. exact Found. }
   assert (Now : A.compaction_entry_at owner (C.maintenance_entries
      (F.feature_compaction (world_features (checkpoint_world owner current summary before)))) =
      Some (M.checkpoint_entry (task_history current) (M.current_entry owner (M.registry before)))).
   { apply compaction_upsert_selects_its_new_entry. }
   unfold M.cancellations in Member. apply in_app_iff in Member as [Measure|Job].
   + destruct (M.measurement_ticket (C.entry_measurement entry)) as [ticket|] eqn:Ticket; [|contradiction].
     destruct Measure as [<-|[]]. cbn [A.compaction_effect_valid]. unfold A.compaction_cancel_retired.
     change (match A.compaction_entry_at owner (C.maintenance_entries (M.registry before)) with
       | Some old => (match M.measurement_ticket (C.entry_measurement old) with Some pending => N.eqb ticket pending | None => false end) ||
          (match M.job_ticket (C.entry_job old) with Some pending => N.eqb ticket pending | None => false end)
       | None => false end && negb
       (match A.compaction_entry_at owner (C.maintenance_entries
          (F.feature_compaction (world_features (checkpoint_world owner current summary before)))) with
       | Some next => (match M.measurement_ticket (C.entry_measurement next) with Some pending => N.eqb ticket pending | None => false end) ||
          (match M.job_ticket (C.entry_job next) with Some pending => N.eqb ticket pending | None => false end)
       | None => false end) = true).
     rewrite Was, Now, Ticket. cbn [M.checkpoint_entry M.with_measurement M.with_job set C.entry_measurement C.entry_job M.measurement_ticket M.job_ticket].
     now rewrite N.eqb_refl.
   + destruct (M.job_ticket (C.entry_job entry)) as [ticket|] eqn:Ticket; [|contradiction].
     destruct Job as [<-|[]]. cbn [A.compaction_effect_valid]. unfold A.compaction_cancel_retired.
     unfold M.registry in Was. rewrite Was, Now, Ticket. cbn [M.checkpoint_entry M.with_measurement M.with_job set C.entry_measurement C.entry_job M.measurement_ticket M.job_ticket].
     rewrite N.eqb_refl, orb_true_r. reflexivity.
 - cbn [M.cancellations M.measurement_ticket M.job_ticket C.empty_entry C.entry_measurement C.entry_job] in Member.
   contradiction.
Qed.

Definition checkpoint_decision owner current summary before :=
 Decision (checkpoint_world owner current summary before)
   (success (JObject [("accepted"%string,JBool true)]))
   (map MaintainContext (M.cancellations owner (M.current_entry owner (M.registry before))) ++ [ContinueScheduling]).
Definition summary_admitted current summary :=
 negb (String.eqb summary ""%string) &&
 (N.of_nat (String.length summary) <=? Selvedge.Kernel.Compaction.summary_limit_bytes)%N &&
 ContextSelection.closed_prefix (task_history current).

Theorem an_admitted_checkpoint_constructs_its_exact_result : forall request before current summary,
 find_task (Commands.compact_task_id request) before = Some current ->
 M.alive current = true -> M.idle current = true ->
 Commands.compact_summary request = Some summary -> summary_admitted current summary = true ->
 CompactionCommit.candidate request before =
 checkpoint_decision (Commands.compact_task_id request) current summary before.
Proof.
 intros request before current summary Owned Alive Idle Summary Admitted.
 unfold CompactionCommit.candidate,DeferredCommit.continue_result.
 apply CommandResult.appending_effects_to_an_accepted_result.
 unfold M.handle_compact_result; rewrite Owned,Alive,Summary,Idle.
 unfold summary_admitted in Admitted; rewrite Admitted.
 unfold M.supplied_change,M.commit_change.
 rewrite compaction_supplied_history_is_an_exact_append; reflexivity.
Qed.

Lemma cancelling_maintenance_allocates_no_new_ticket : forall owner entry first after,
 A.effect_tickets_fresh first after (map MaintainContext (M.cancellations owner entry) ++ [ContinueScheduling]) = true.
Proof.
 intros. unfold M.cancellations.
 destruct (M.measurement_ticket (C.entry_measurement entry)); destruct (M.job_ticket (C.entry_job entry)); reflexivity.
Qed.

Lemma checkpoint_effects_retain_their_live_delivery : forall owner current summary before,
 Dispatch.retain_live_effects (checkpoint_decision owner current summary before) =
 checkpoint_decision owner current summary before.
Proof.
 intros. unfold checkpoint_decision, M.cancellations.
 destruct (M.measurement_ticket (C.entry_measurement (M.current_entry owner (M.registry before))));
 destruct (M.job_ticket (C.entry_job (M.current_entry owner (M.registry before)))); reflexivity.
Qed.

Lemma maintenance_effects_have_exact_authority : forall effects source raw before after,
 A.effects_authorized source raw before after (map MaintainContext effects ++ [ContinueScheduling]) =
 forallb (fun effect => A.compaction_effect_valid effect before after) effects.
Proof.
 induction effects as [|effect rest IH]; intros; cbn [map app A.effects_authorized A.effect_authorized A.feature_effect_valid forallb];
 [reflexivity|now rewrite IH].
Qed.

Theorem every_admitted_checkpoint_has_complete_commit_authority : forall source raw owner current summary before,
 WorldInvariant.well_formed before -> find_task owner before = Some current -> M.alive current = true ->
 A.transition_authorized true source raw before (checkpoint_decision owner current summary before) = true.
Proof.
 intros source raw owner current summary before Valid Owned Alive.
 unfold A.transition_authorized. apply andb_true_iff; split.
 - apply andb_true_iff; split.
   + unfold A.world_evolution. repeat rewrite andb_true_iff; repeat split.
     * now apply checkpointing_keeps_the_complete_task_authority.
     * apply N.leb_refl.
     * apply N.leb_refl.
     * now apply checkpointing_keeps_every_feature_authority.
   + apply cancelling_maintenance_allocates_no_new_ticket.
 - change (A.effects_authorized source raw before (checkpoint_world owner current summary before)
     (map MaintainContext (M.cancellations owner (M.current_entry owner (M.registry before))) ++ [ContinueScheduling]) = true).
   rewrite maintenance_effects_have_exact_authority. apply forallb_forall.
   intros effect Member. now apply a_checkpoint_retires_each_cancelled_request.
Qed.

Theorem every_admitted_checkpoint_with_its_actual_budget_commits : forall request raw before current summary,
 WorldInvariant.world_valid before = true -> find_task (Commands.compact_task_id request) before = Some current ->
 M.alive current = true -> M.idle current = true ->
 Commands.compact_summary request = Some summary -> summary_admitted current summary = true ->
 Delivery.fits true (checkpoint_decision (Commands.compact_task_id request) current summary before) = true ->
 CompactionCommit.packet raw request before =
 (with_sequence (N.succ (world_sequence before)) (checkpoint_world (Commands.compact_task_id request) current summary before),
  Notifications.envelope true true (Some (UserCommand (Commands.Cmd_compact request))) before
    (checkpoint_decision (Commands.compact_task_id request) current summary before)).
Proof.
 intros request raw before current summary World Owned Alive Idle Summary Admitted Budget.
 unfold CompactionCommit.packet.
 rewrite an_admitted_checkpoint_constructs_its_exact_result with (current:=current) (summary:=summary) by assumption.
 apply a_constructed_candidate_with_its_actual_budget_is_committed.
 - apply checkpoint_effects_retain_their_live_delivery.
 - apply well_formed_worlds_pass_the_checker, an_idle_checkpoint_preserves_all_world_requirements; try assumption.
   now apply the_world_checker_establishes_all_requirements.
 - apply every_admitted_checkpoint_has_complete_commit_authority; try assumption.
   now apply the_world_checker_establishes_all_requirements.
 - exact Budget.
Qed.

Definition manual_waiting_candidate owner current before :=
 DeferredCommit.continue (MP.manual_waiting_decision owner current before).

Theorem an_open_manual_compaction_constructs_its_exact_wait : forall owner current operations before,
 find_task owner before = Some current ->
 task_lifecycle current = Running Idle operations ->
 TicketedRequest.Scoped.resources_available current before = true ->
 M.job_pending (C.entry_job (M.current_entry owner (M.registry before))) = false ->
 ContextSelection.closed_prefix (task_history current) = false ->
 CompactionCommit.candidate (Commands.Build_compact owner None) before =
 manual_waiting_candidate owner current before.
Proof.
 intros; unfold CompactionCommit.candidate,DeferredCommit.continue_result.
 unfold manual_waiting_candidate,DeferredCommit.continue,MP.manual_waiting_decision.
 apply CommandResult.appending_effects_to_an_accepted_result.
 apply MP.manual_compaction_accepts_an_open_prefix_and_waits with (operations:=operations); assumption.
Qed.

Lemma a_manual_wait_keeps_maintenance_requirements : forall owner current before,
 WorldInvariant.compaction_valid before = true -> find_task owner before = Some current ->
 WorldInvariant.compaction_valid (MP.manual_waiting_world owner current before) = true.
Proof.
 intros owner current before Valid Found.
 pose proof (compaction_current_entry_has_its_counter_bounds owner current before Valid Found)
   as [Maintained [Attempted Useful]].
 unfold WorldInvariant.compaction_valid in Valid; apply andb_true_iff in Valid as [Unique Entries].
 unfold WorldInvariant.compaction_valid.
 change (WorldInvariant.unique_tickets (map fst (C.maintenance_entries (M.with_entry owner
     (MP.manual_waiting_entry current (M.current_entry owner (M.registry before)) before) (M.registry before)))) &&
   forallb (fun entry => WorldInvariant.maintenance_entry_valid entry (MP.manual_waiting_world owner current before))
    (C.maintenance_entries (M.with_entry owner
     (MP.manual_waiting_entry current (M.current_entry owner (M.registry before)) before) (M.registry before))) = true).
 apply andb_true_iff; split.
 - now apply compaction_upsert_has_one_entry_per_owner.
 - apply compaction_upsert_preserves_valid_entries.
   + unfold WorldInvariant.maintenance_entry_valid.
     change (match find_task owner before with
       | None => false | Some task =>
       ((C.entry_maintained (M.current_entry owner (M.registry before)) <=?
          C.entry_useful (M.current_entry owner (M.registry before))) &&
        (C.entry_attempted (M.current_entry owner (M.registry before)) <=? M.useful (task_history task)) &&
        (C.entry_useful (M.current_entry owner (M.registry before)) <=? M.useful (task_history task)))%N &&
       ContextSelection.history_extends (task_history current) (task_history task) end = true).
     rewrite Found, the_same_history_retains_its_captured_prefix, andb_true_r.
     repeat rewrite andb_true_iff; repeat split; now apply N.leb_le.
   + intros actual entry Member Different.
     change (WorldInvariant.maintenance_entry_valid (actual,entry) before = true).
     apply forallb_forall with (x:=(actual,entry)) in Entries; assumption.
Qed.

Theorem a_manual_wait_preserves_all_world_requirements : forall owner current before,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 WorldInvariant.well_formed (MP.manual_waiting_world owner current before).
Proof.
 intros owner current before Valid Found.
 pose proof (FeatureFrameProofs.well_formed_feature_requirements before Valid) as Features.
 assert (Maintenance : WorldInvariant.compaction_valid before = true).
 { unfold WorldInvariant.features_valid in Features; now apply andb_true_iff in Features as [_ Maintenance]. }
 constructor.
 - exact (WorldInvariant.environment_requirement before Valid).
 - exact (WorldInvariant.projects_requirement before Valid).
 - unfold WorldInvariant.world_structure.
   rewrite task_registry_requirements_ignore_the_journal_cursor.
   rewrite FeatureFrameProofs.registry_requirements_read_only_the_task_and_project_registries
     with (before:=before) by reflexivity.
   pose proof (WorldInvariant.tasks_requirement before Valid) as Tasks.
   unfold WorldInvariant.world_structure in Tasks.
   now rewrite task_registry_requirements_ignore_the_journal_cursor in Tasks.
 - change (WorldInvariant.tickets_valid (M.store
     (M.with_entry owner (M.checkpoint_entry (task_history current) (M.current_entry owner (M.registry before)))
       (M.registry before)) before) = true).
   apply checkpointing_maintenance_preserves_global_ticket_ownership.
   exact (WorldInvariant.tickets_requirement before Valid).
 - unfold WorldInvariant.world_structure.
   rewrite FeatureFrameProofs.feature_requirements_ignore_journal_cursor.
   change (feature_core_valid (MP.manual_waiting_world owner current before) &&
     WorldInvariant.compaction_valid (MP.manual_waiting_world owner current before) = true).
   rewrite a_manual_wait_keeps_maintenance_requirements by assumption; rewrite andb_true_r.
   unfold MP.manual_waiting_world; rewrite storing_maintenance_keeps_other_features_valid.
   unfold WorldInvariant.features_valid in Features.
   change (feature_core_valid before && WorldInvariant.compaction_valid before = true) in Features.
   now apply andb_true_iff in Features as [Core _].
Qed.

Lemma a_manual_wait_keeps_maintenance_authority : forall owner current before,
 WorldInvariant.well_formed before ->
 A.compaction_evolution (M.registry before)
   (M.with_entry owner (MP.manual_waiting_entry current (M.current_entry owner (M.registry before)) before)
     (M.registry before)) = true.
Proof.
 intros owner current before Valid.
 pose proof (FeatureFrameProofs.well_formed_feature_requirements before Valid) as Features.
 unfold WorldInvariant.features_valid in Features; apply andb_true_iff in Features as [_ Maintenance].
 unfold WorldInvariant.compaction_valid in Maintenance; apply andb_true_iff in Maintenance as [Unique _].
 apply unique_tickets_denotes_distinct_correlation_owners in Unique.
 unfold A.compaction_evolution; apply andb_true_iff; split; [apply N.leb_refl|].
 apply compaction_upsert_retains_monotone_counters; [exact Unique|].
 intros entry Member.
 rewrite (compaction_current_entry_finds_a_unique_member owner entry (M.registry before) Unique Member).
 unfold MP.manual_waiting_entry, M.with_observation, M.with_measurement, M.with_job, set; cbn.
 repeat split; apply N.le_refl.
Qed.

Lemma a_manual_wait_keeps_every_feature_authority : forall owner current before,
 WorldInvariant.well_formed before ->
 A.features_evolution (world_features before) (world_features (MP.manual_waiting_world owner current before)) = true.
Proof.
 intros owner current before Valid.
 pose proof (FeatureFrameProofs.well_formed_feature_requirements before Valid) as Features.
 pose proof (well_formed_features_admit_their_unchanged_configuration before Features) as Original.
 pose proof (a_manual_wait_keeps_maintenance_authority owner current before Valid) as Maintenance.
 unfold A.features_evolution, A.titles_evolution, A.same_title_prompts in Original |- *.
 unfold MP.manual_waiting_world, M.store, M.registry, with_features, Selvedge.Features.State.with_compaction, set.
 cbn -[A.board_evolution A.compaction_evolution] in *.
 match goal with |- context [A.compaction_evolution ?old ?next] =>
   let Actual := fresh "Actual" in assert (Actual : A.compaction_evolution old next = true) by exact Maintenance;
   rewrite Actual
 end.
 repeat rewrite andb_true_iff in *. tauto.
Qed.

Lemma a_manual_wait_retires_each_cancelled_request : forall owner current before effect,
 In effect (M.cancellations owner (M.current_entry owner (M.registry before))) ->
 A.compaction_effect_valid effect before (MP.manual_waiting_world owner current before) = true.
Proof.
 intros owner current before effect Member.
 assert (Cancelled : exists ticket, effect = C.Cancel owner ticket).
 { unfold M.cancellations in Member; apply in_app_iff in Member as [Member|Member].
   - destruct (M.measurement_ticket (C.entry_measurement (M.current_entry owner (M.registry before))));
       [destruct Member as [<-|[]]; eauto|contradiction].
   - destruct (M.job_ticket (C.entry_job (M.current_entry owner (M.registry before))));
       [destruct Member as [<-|[]]; eauto|contradiction]. }
 destruct Cancelled as [ticket ->].
 pose proof (a_checkpoint_retires_each_cancelled_request owner current ""%string before
   (C.Cancel owner ticket) Member) as Retired.
 assert (Waiting : A.compaction_entry_at owner
   (C.maintenance_entries (F.feature_compaction (world_features (MP.manual_waiting_world owner current before)))) =
   Some (MP.manual_waiting_entry current (M.current_entry owner (M.registry before)) before)).
 { apply compaction_upsert_selects_its_new_entry. }
 assert (Checkpoint : A.compaction_entry_at owner
   (C.maintenance_entries (F.feature_compaction (world_features (checkpoint_world owner current ""%string before)))) =
   Some (M.checkpoint_entry (task_history current) (M.current_entry owner (M.registry before)))).
 { apply compaction_upsert_selects_its_new_entry. }
 cbn [A.compaction_effect_valid] in Retired |- *.
 unfold A.compaction_cancel_retired in Retired |- *.
 rewrite Checkpoint in Retired; rewrite Waiting; exact Retired.
Qed.

Theorem every_manual_wait_has_complete_commit_authority : forall source raw owner current before,
 WorldInvariant.well_formed before ->
 A.transition_authorized true source raw before (manual_waiting_candidate owner current before) = true.
Proof.
 intros source raw owner current before Valid.
 unfold A.transition_authorized; apply andb_true_iff; split.
 - apply andb_true_iff; split.
   + unfold A.world_evolution; repeat rewrite andb_true_iff; repeat split.
     * unfold A.retained_tasks; apply unchanged_tasks_keep_authority_across_other_features.
     * apply N.leb_refl.
     * apply N.leb_refl.
     * now apply a_manual_wait_keeps_every_feature_authority.
   + apply cancelling_maintenance_allocates_no_new_ticket.
 - change (A.effects_authorized source raw before (MP.manual_waiting_world owner current before)
     (map MaintainContext (M.cancellations owner (M.current_entry owner (M.registry before))) ++ [ContinueScheduling]) = true).
   rewrite maintenance_effects_have_exact_authority; apply forallb_forall.
   intros effect Member; now apply a_manual_wait_retires_each_cancelled_request.
Qed.

Theorem an_open_manual_compaction_with_its_actual_budget_commits : forall owner current operations raw before,
 WorldInvariant.world_valid before = true -> find_task owner before = Some current ->
 task_lifecycle current = Running Idle operations ->
 TicketedRequest.Scoped.resources_available current before = true ->
 M.job_pending (C.entry_job (M.current_entry owner (M.registry before))) = false ->
 ContextSelection.closed_prefix (task_history current) = false ->
 Delivery.fits true (manual_waiting_candidate owner current before) = true ->
 CompactionCommit.packet raw (Commands.Build_compact owner None) before =
 (with_sequence (N.succ (world_sequence before)) (MP.manual_waiting_world owner current before),
  Notifications.envelope true true (Some (UserCommand (Commands.Cmd_compact (Commands.Build_compact owner None))))
    before (manual_waiting_candidate owner current before)).
Proof.
 intros owner current operations raw before World Found Lifecycle Available NoJob Open Budget.
 pose proof (the_world_checker_establishes_all_requirements before World) as Valid.
 unfold CompactionCommit.packet.
 rewrite an_open_manual_compaction_constructs_its_exact_wait with (current:=current) (operations:=operations) by assumption.
 apply a_constructed_candidate_with_its_actual_budget_is_committed.
 - unfold manual_waiting_candidate, MP.manual_waiting_decision, DeferredCommit.continue, M.cancellations.
   destruct (M.measurement_ticket (C.entry_measurement (M.current_entry owner (M.registry before))));
   destruct (M.job_ticket (C.entry_job (M.current_entry owner (M.registry before)))); reflexivity.
 - apply well_formed_worlds_pass_the_checker; now apply a_manual_wait_preserves_all_world_requirements.
 - now apply every_manual_wait_has_complete_commit_authority.
 - exact Budget.
Qed.

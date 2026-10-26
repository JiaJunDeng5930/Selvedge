From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State Tasks ContextSelection WorldInvariant
 CommitAdmission AfterHookAuthorizationProofs ForkAuthorizationProofs ForkPreservation ForkConstructionProofs
 NativeResultWorldFrame NativeForkPreservation TaskAuthorityProofs.
Import ListNotations.
Open Scope list_scope.

Lemma active_native_history_progress_retains_authority :
 forall source raw before owner features old next phase operations running,
 task_lifecycle old = result_lifecycle running phase operations ->
 native_result_task_frame old = native_result_task_frame next ->
 (exists suffix,task_history next = task_history old ++ suffix) ->
 CommitAdmission.retained_task source raw before owner features features old next = true.
Proof.
 intros source raw before owner features
   [oc op os ol oh oq oa osp osc omc] [nc np ns nl nh nq na nsp nsc nmc]
   phase operations running Lifecycle Frame [suffix History].
 cbn [task_lifecycle] in Lifecycle; subst ol.
 destruct running; destruct nl;
   cbn [native_result_task_frame result_lifecycle with_history with_lifecycle] in Frame;
   inversion Frame; subst; unfold CommitAdmission.retained_task;
   rewrite the_same_lineage_has_the_same_ancestors,
     the_same_creation_contract_has_the_same_configuration,
     the_same_profile_has_the_same_configuration,
     the_same_settings_have_the_same_configuration;
   cbn -[ContextSelection.history_extends];
   cbn in History; rewrite History,andb_true_r;
   apply appended_history_preserves_captured_prefix,the_same_history_retains_its_captured_prefix.
Qed.

Theorem a_single_active_native_result_retains_cross_state_authority :
 forall source raw before born owner original current phase operations running,
 WorldInvariant.well_formed before ->
 find_task owner before = Some original ->
 task_lifecycle original = result_lifecycle running phase operations ->
 native_result_task_frame original = native_result_task_frame current ->
 (exists suffix,task_history current = task_history original ++ suffix) ->
 (exists retained,find_task owner born = Some retained) ->
 (forall other old,other <> owner -> find_task other before = Some old -> find_task other born = Some old) ->
 world_next_ticket before <= world_next_ticket born ->
 world_projects born = world_projects before -> world_features born = world_features before ->
 CommitAdmission.world_evolution source raw before (put_task owner current born) = true.
Proof.
 intros source raw before born owner original current phase operations running
   Valid Found Lifecycle Frame History [retained Present] Others Later Projects Features.
 unfold CommitAdmission.world_evolution,CommitAdmission.retained_tasks.
 unfold put_task,with_tasks; cbv [set]; cbn; rewrite Features.
 apply andb_true_iff; split.
 - apply andb_true_iff; split.
   + apply andb_true_iff; split.
     * apply retained_task_registries_follow_lookups; intros offset task Original.
       change (find_task offset before = Some task) in Original.
       destruct (N.eq_dec offset owner) as [Same|Different].
       -- subst offset; rewrite Found in Original; inversion Original; subst task.
          exists current; split.
          ++ change (find_task owner (put_task owner current born) = Some current).
             eapply LifecycleProofs.find_put_task; exact Present.
          ++ rewrite N.add_0_l; eapply active_native_history_progress_retains_authority; eauto.
       -- exists task; split.
          ++ unfold find_task,put_task,with_tasks; cbn.
             rewrite RegistryProofs.registry_replace_other by congruence.
             apply Others; assumption.
          ++ rewrite N.add_0_l; apply a_task_is_its_own_retained_configuration.
     * cbn. apply N.leb_le; exact Later.
   + cbn. rewrite Projects; apply N.leb_refl.
 - cbn. rewrite ?Features.
   exact (well_formed_features_admit_their_unchanged_configuration (WorldInvariant.world_structure before)
     (WorldInvariant.features_requirement before Valid)).
Qed.

From Selvedge.Kernel Require Import Numbers Codec NativeForkCommit NativeForkCommitProofs NativeForkSchedulingProofs NativeForkStartProofs.

Lemma a_retained_native_parent_settles_with_cross_state_authority :
 forall entry raw before (accepted : NativeForkCommit.plan before) after parent result failed,
 let step := NativeForkCommit.planned_step accepted in
 WorldInvariant.well_formed before -> WorldInvariant.well_formed after ->
 find_task (Scheduler.native_fork_owner step) after = Some parent ->
 parent = continued_parent accepted -> world_next_ticket after = world_next_ticket before ->
 (forall other old,other <> Scheduler.native_fork_owner step ->
   find_task other before = Some old -> find_task other after = Some old) ->
 world_projects after = world_projects before -> world_features after = world_features before ->
 CommitAdmission.world_evolution entry raw before
   (decision_world (Scheduler.internal_result (Scheduler.native_fork_owner step)
     (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step)
     result failed parent after)) = true.
Proof.
 intros entry raw before accepted after parent result failed step Valid AfterValid Found Parent Supply
   Others Projects Features.
 pose proof (a_selected_native_fork_settlement_uses_its_exact_result_task
   before accepted after parent result failed AfterValid Found Parent Supply) as Exact.
 fold step in Exact; rewrite Exact.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [_ [_ [phase [operations [running [Lifecycle NonIdle]]]]]].
 set (original := TaskScope.selected (NativeForkCommit.planned_target accepted)).
 fold original in Lifecycle.
 eapply a_single_active_native_result_retains_cross_state_authority with
   (original:=original) (phase:=phase) (operations:=operations) (running:=running).
 - exact Valid.
 - apply every_native_fork_plan_has_its_observed_source.
 - exact Lifecycle.
 - rewrite Parent; unfold continued_parent; fold step; fold original.
   eapply continuing_an_active_result_keeps_its_task_frame; exact Lifecycle.
 - rewrite result_task_history.
   exists (match Callbacks.after_plugins parent with
   | [] => [FunctionOutput (call_id (Scheduler.native_fork_invocation step)) result failed]
   | _ => [ToolReceipt (Scheduler.native_fork_owner step) (world_next_ticket before)
       (Scheduler.native_fork_invocation step) result failed] end).
   rewrite Parent; unfold continued_parent; fold step; fold original.
   unfold with_activity; rewrite Lifecycle; destruct running; reflexivity.
 - exists parent; destruct (Callbacks.after_plugins parent); exact Found.
 - intros other old Different Original; destruct (Callbacks.after_plugins parent);
   apply Others; assumption.
 - destruct (Callbacks.after_plugins parent); destruct after; cbn in Supply |- *; lia.
 - destruct (Callbacks.after_plugins parent); exact Projects.
 - destruct (Callbacks.after_plugins parent); exact Features.
Qed.

Theorem every_native_fork_settlement_retains_its_actual_cross_state_authority :
 forall entry raw before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 WorldInvariant.well_formed before ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (ForkCommitProofs.settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (Selvedge.Generated.Commands.fork_child_count (Scheduler.native_fork_request step)) messages
   (Selvedge.Generated.Commands.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 CommitAdmission.world_evolution entry raw before
   (decision_world (requested_settlement accepted messages parent selected)) = true.
Proof.
 intros entry raw before accepted messages parent selected step Valid Admissible.
 destruct (a_native_fork_keeps_its_parent_and_exact_ticket_supply before accepted messages parent selected (proj1 Admissible))
   as [Found Supply].
 pose proof (fork_candidate_keeps_the_non_task_world_frame
   (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (Scheduler.native_fork_owner step) (Selvedge.Generated.Commands.fork_child_count (Scheduler.native_fork_request step))
   messages parent selected (started_world accepted)) as [_ [_ [Projects Features]]].
 unfold requested_settlement; fold step.
 eapply a_retained_native_parent_settles_with_cross_state_authority; try eassumption.
 - eapply every_admissible_native_fork_constructs_a_well_formed_birth_world; eassumption.
 - eapply each_native_fork_keeps_the_exact_started_parent; exact Admissible.
 - intros other old Different Original.
   unfold requested_world,fork_candidate; fold step; cbn [fork_retained fork_snapshot_parent fork_invocation].
   apply fork_children_preserve_every_existing_task.
   rewrite a_native_fork_start_is_the_exact_pending_phase_change.
   unfold find_task,put_task,with_tasks; cbv [set]; cbn.
   rewrite registry_replace_other by congruence; exact Original.
Qed.

Theorem every_refused_native_fork_retains_its_actual_cross_state_authority :
 forall entry raw before (accepted : NativeForkCommit.plan before) code reason,
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution entry raw before
   (decision_world (refused_settlement accepted code reason)) = true.
Proof.
 intros entry raw before accepted code reason Valid.
 unfold refused_settlement.
 eapply a_retained_native_parent_settles_with_cross_state_authority; try reflexivity.
 - exact Valid.
 - apply every_selected_native_fork_starts_in_a_well_formed_world; exact Valid.
 - apply a_started_native_fork_keeps_its_continued_parent.
 - intros other old Different Original.
   rewrite a_native_fork_start_is_the_exact_pending_phase_change.
   unfold find_task,put_task,with_tasks; cbv [set]; cbn.
   rewrite registry_replace_other by congruence; exact Original.
Qed.

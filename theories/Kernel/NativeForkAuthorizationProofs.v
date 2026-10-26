From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State Tasks ContextSelection WorldInvariant
 CommitAdmission AfterHookAuthorizationProofs ForkAuthorizationProofs ForkPreservation ForkConstructionProofs
 NativeResultWorldFrame NativeForkPreservation.
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

Lemma retained_task_registries_follow_their_actual_lookups :
 forall source raw before features old next first,
 (forall offset task,registry_at offset old = Some task ->
   exists current,registry_at offset next = Some current /\
   CommitAdmission.retained_task source raw before (first+offset)%N features features task current = true) ->
 CommitAdmission.retained_tasks_from source raw before first features features old next = true.
Proof.
 intros source raw before features old; induction old as [|task rest IH]; intros next first Retained; [reflexivity|].
 destruct (Retained 0%N task eq_refl) as [current [Found Head]].
 destruct next as [|next remaining]; [discriminate|].
 cbn [registry_at] in Found; inversion Found; subst current.
 cbn [CommitAdmission.retained_tasks_from]. rewrite N.add_0_r in Head; rewrite Head; cbn [andb].
 apply IH; intros offset original Original.
 assert (Earlier : registry_at (N.succ offset) (task :: rest) = Some original).
 { rewrite registry_lookup_after_head; exact Original. }
 destruct (Retained (N.succ offset) original Earlier) as [after [Observed Authority]].
 exists after; split.
 - rewrite registry_lookup_after_head in Observed; exact Observed.
 - replace (N.succ first+offset)%N with (first+N.succ offset)%N by lia; exact Authority.
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
     * apply retained_task_registries_follow_their_actual_lookups; intros offset task Original.
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
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call) as [_ [_ [phase [operations [running [Lifecycle NonIdle]]]]]].
 set (original := TaskScope.selected (NativeForkCommit.planned_target accepted)).
 fold original in Lifecycle.
 pose proof (each_native_fork_keeps_the_exact_started_parent before accepted messages parent selected Admissible) as Parent.
 fold step in Parent; fold original in Parent.
 destruct (a_native_fork_keeps_its_parent_and_exact_ticket_supply before accepted messages parent selected (proj1 Admissible)) as [Found Supply].
 pose proof (fork_candidate_keeps_the_non_task_world_frame
   (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (Scheduler.native_fork_owner step) (Selvedge.Generated.Commands.fork_child_count (Scheduler.native_fork_request step))
   messages parent selected (started_world accepted)) as [_ [_ [Projects Features]]].
 fold (requested_world accepted messages parent selected) in Projects,Features.
 change (world_projects (requested_world accepted messages parent selected) = world_projects (started_world accepted)) in Projects.
 change (world_features (requested_world accepted messages parent selected) = world_features (started_world accepted)) in Features.
 assert (StartedProjects : world_projects (started_world accepted) = world_projects before).
 { rewrite a_native_fork_start_is_the_exact_pending_phase_change; destruct before; reflexivity. }
 assert (StartedFeatures : world_features (started_world accepted) = world_features before).
 { rewrite a_native_fork_start_is_the_exact_pending_phase_change; destruct before; reflexivity. }
 rewrite StartedProjects in Projects; rewrite StartedFeatures in Features.
 rewrite (each_native_fork_settlement_uses_its_exact_result_task before accepted messages parent selected Valid Admissible).
 set (current := result_task (Scheduler.native_fork_owner step) (world_next_ticket before) (Scheduler.native_fork_invocation step)
   (Scheduler.native_fork_remaining step) (number 0) false parent).
 eapply a_single_active_native_result_retains_cross_state_authority with
   (original:=original) (phase:=phase) (operations:=operations) (running:=running).
 - exact Valid.
 - apply every_native_fork_plan_has_its_observed_source.
 - exact Lifecycle.
 - unfold current; rewrite Parent; unfold result_task,native_result_task_frame.
   destruct (Callbacks.after_plugins (with_activity (PendingCalls (Scheduler.native_fork_remaining step)) original));
   destruct original as [contract profile settings lifecycle history queued lineage side cursor consumed];
   cbn [task_lifecycle] in Lifecycle; subst lifecycle; destruct running; reflexivity.
 - unfold current; rewrite result_task_history.
   exists (match Callbacks.after_plugins parent with
   | [] => [FunctionOutput (call_id (Scheduler.native_fork_invocation step)) (number 0) false]
   | _ => [ToolReceipt (Scheduler.native_fork_owner step) (world_next_ticket before) (Scheduler.native_fork_invocation step) (number 0) false] end).
   rewrite Parent; unfold with_activity; rewrite Lifecycle; destruct running; reflexivity.
 - exists parent; destruct (Callbacks.after_plugins parent); exact Found.
 - intros other old Different Original.
   destruct (Callbacks.after_plugins parent);
   change (find_task other (requested_world accepted messages parent selected) = Some old);
   unfold requested_world,fork_candidate; fold step;
   cbn [fork_retained fork_snapshot_parent fork_invocation];
   apply fork_children_preserve_every_existing_task;
   rewrite a_native_fork_start_is_the_exact_pending_phase_change;
   unfold find_task,put_task,with_tasks; cbv [set]; cbn;
   rewrite registry_replace_other by congruence; exact Original.
 - destruct (Callbacks.after_plugins parent); destruct (requested_world accepted messages parent selected); cbn in Supply |- *; lia.
 - destruct (Callbacks.after_plugins parent); destruct (requested_world accepted messages parent selected); exact Projects.
 - destruct (Callbacks.after_plugins parent); destruct (requested_world accepted messages parent selected); exact Features.
Qed.

Theorem every_refused_native_fork_retains_its_actual_cross_state_authority :
 forall entry raw before (accepted : NativeForkCommit.plan before) code reason,
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution entry raw before
   (decision_world (refused_settlement accepted code reason)) = true.
Proof.
 intros entry raw before accepted code reason Valid.
 set (step := NativeForkCommit.planned_step accepted).
 set (original := TaskScope.selected (NativeForkCommit.planned_target accepted)).
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [_ [_ [phase [operations [running [Lifecycle NonIdle]]]]]].
 fold original in Lifecycle.
 pose proof (a_started_native_fork_keeps_its_continued_parent before accepted) as Found.
 destruct (a_refused_native_fork_keeps_the_exact_error_and_continuation before accepted code reason Valid)
   as [Exact _].
 rewrite Exact.
 set (current := result_task (Scheduler.native_fork_owner step) (world_next_ticket before)
   (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step)
   (failure code reason) true (continued_parent accepted)).
 eapply a_single_active_native_result_retains_cross_state_authority with
   (original:=original) (phase:=phase) (operations:=operations) (running:=running).
 - exact Valid.
 - apply every_native_fork_plan_has_its_observed_source.
 - exact Lifecycle.
 - unfold current,continued_parent; fold step; fold original.
   unfold result_task,native_result_task_frame.
   destruct (Callbacks.after_plugins (with_activity (PendingCalls (Scheduler.native_fork_remaining step)) original));
   destruct original as [contract profile settings lifecycle history queued lineage side cursor consumed];
   cbn [task_lifecycle] in Lifecycle; subst lifecycle; destruct running; reflexivity.
 - unfold current; rewrite result_task_history.
   exists (match Callbacks.after_plugins (continued_parent accepted) with
   | [] => [FunctionOutput (call_id (Scheduler.native_fork_invocation step)) (failure code reason) true]
   | _ => [ToolReceipt (Scheduler.native_fork_owner step) (world_next_ticket before)
       (Scheduler.native_fork_invocation step) (failure code reason) true] end).
   unfold continued_parent; fold step; fold original.
   unfold with_activity; rewrite Lifecycle; destruct running; reflexivity.
 - exists (continued_parent accepted); destruct (Callbacks.after_plugins (continued_parent accepted)); exact Found.
 - intros other old Different Original.
   destruct (Callbacks.after_plugins (continued_parent accepted));
   change (find_task other (started_world accepted) = Some old);
   rewrite a_native_fork_start_is_the_exact_pending_phase_change;
   unfold find_task,put_task,with_tasks; cbv [set]; cbn;
   rewrite registry_replace_other by congruence; exact Original.
 - assert (Supply : world_next_ticket (started_world accepted) = world_next_ticket before).
   { rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity. }
   destruct (Callbacks.after_plugins (continued_parent accepted));
   destruct (started_world accepted); cbn in Supply |- *; lia.
 - destruct (Callbacks.after_plugins (continued_parent accepted));
   change (world_projects (started_world accepted) = world_projects before);
   rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity.
 - destruct (Callbacks.after_plugins (continued_parent accepted));
   change (world_features (started_world accepted) = world_features before);
   rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity.
Qed.

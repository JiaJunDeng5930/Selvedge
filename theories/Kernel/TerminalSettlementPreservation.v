From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Callbacks History ContextUpdates
 WorldInvariant WorldInvariantProofs ForkPreservation ForkLineageProofs LifecycleProofs
 TerminalSettlement TerminalSettlementProofs TerminalTicketProofs ArchivedRuntimeFrameProofs.
Import ListNotations.
Open Scope list_scope.

Theorem terminal_after_settlement_preserves_every_world_requirement :
 forall before owner current operations original plugin previous failed outcome,
 WorldInvariant.well_formed before -> find_task owner before = Some current ->
 task_lifecycle current = Archived operations -> In original operations ->
 WorldInvariant.well_formed (put_task owner
   (settled_task owner original plugin previous failed outcome current) before).
Proof.
 intros before owner current operations original plugin previous failed outcome Valid Found ArchivedTask Owned.
 set (settled := settled_task owner original plugin previous failed outcome current).
 set (after := put_task owner settled before).
 assert (Frame : fork_retains_task current settled).
 { unfold settled; eapply settlement_preserves_the_archived_frame; exact ArchivedTask. }
 assert (Installed : find_task owner after = Some settled).
 { unfold after; eapply find_put_task; exact Found. }
 assert (Other : forall queried, queried <> owner -> find_task queried after = find_task queried before).
 { intros queried Different; unfold after, find_task, put_task.
   rewrite writing_tasks_installs_the_registry, registry_replace_other by congruence; reflexivity. }
 assert (Fields : world_environment after = world_environment before /\
   world_projects after = world_projects before /\ world_features after = world_features before /\
   world_next_ticket after = world_next_ticket before).
 { unfold after, put_task; destruct before; repeat split; reflexivity. }
 destruct Fields as [Environment [Projects [Features Tickets]]].
 assert (Retained : forall queried old, find_task queried before = Some old ->
  exists next, find_task queried after = Some next /\ fork_retains_task old next).
 { intros queried old Lookup; destruct (N.eq_dec queried owner) as [Same|Different].
   - subst queried; rewrite Found in Lookup; inversion Lookup; subst old; exists settled; auto.
   - exists old; split; [rewrite Other by exact Different; exact Lookup|apply fork_retains_task_reflexive]. }
 assert (Lineages : map task_lineage (world_tasks after) = map task_lineage (world_tasks before)).
 { unfold after, put_task; rewrite writing_tasks_installs_the_registry.
   eapply replacing_equal_projection_keeps_registry_observations; [exact Found|].
   eapply task_frame_preserves_lineage; exact Frame. }
 assert (Progress : forall queried next, find_task queried after = Some next ->
  exists old, find_task queried before = Some old /\ fork_retains_task old next /\
    task_progress_requirements queried next).
 { intros queried next Lookup; destruct (N.eq_dec queried owner) as [Same|Different].
   - subst queried; rewrite Installed in Lookup; inversion Lookup; subst next.
     exists current; split; [exact Found|]; split; [exact Frame|].
     pose proof (a_valid_task_has_its_progress_requirements owner current before
       (lookup_task_requirements before owner current Valid Found)) as [Context [Phase [Checked Operations]]].
     unfold task_progress_requirements; repeat split.
     + unfold settled; rewrite terminal_settlement_keeps_its_history_suffix,
       terminal_receipts_preserve_context_bindings; exact Context.
     + unfold settled, WorldInvariant.phase_valid, WorldInvariant.calls_valid, task_activity;
       rewrite terminal_settlement_keeps_its_archived_lifecycle with (operations:=operations) by exact ArchivedTask; reflexivity.
     + unfold settled, WorldInvariant.checked_phase, task_activity;
       rewrite terminal_settlement_keeps_its_archived_lifecycle with (operations:=operations) by exact ArchivedTask; reflexivity.
     + unfold settled; eapply terminal_settlement_preserves_the_remaining_operation_rights; eauto.
   - rewrite Other in Lookup by exact Different.
     exists next; split; [exact Lookup|]; split; [apply fork_retains_task_reflexive|].
     eapply a_valid_task_has_its_progress_requirements, lookup_task_requirements; eauto. }
 constructor.
 - change (WorldInvariant.environment_valid (world_environment after) = true).
   rewrite Environment; exact (WorldInvariant.environment_requirement before Valid).
 - change (WorldInvariant.projects_valid after = true).
   unfold WorldInvariant.projects_valid; rewrite Projects; exact (WorldInvariant.projects_requirement before Valid).
 - change (WorldInvariant.tasks_valid 0 (world_tasks after) (WorldInvariant.world_structure after) = true).
   apply task_registry_requirement_from_every_lookup; intros queried next Lookup.
   change (find_task queried after = Some next) in Lookup.
   destruct (Progress queried next Lookup) as [old [Old [RetainedFrame [Context [Phase [Checked Operations]]]]]].
   pose proof (lookup_task_requirements before queried old Valid Old) as OldValid.
   eapply retained_task_requirements_lift with (old:=old) (before:=WorldInvariant.world_structure before);
     try exact RetainedFrame; try exact Context; try exact Phase; try exact Checked; try exact Operations;
     try exact OldValid.
   + exact (eq_sym Projects).
   + eapply existing_lineage_survives_a_fork with (before:=WorldInvariant.world_structure before); [exact RetainedFrame| |].
     * intros ancestor prior Ancestor; change (find_task ancestor before = Some prior) in Ancestor.
       destruct (Retained ancestor prior Ancestor) as [now [At Related]]; exists now; auto.
     * eapply task_valid_has_its_lineage_requirement; exact OldValid.
   + rewrite <- (task_frame_preserves_contract old next RetainedFrame).
     change (Tasks.descendant_count queried (world_tasks after) <= contract_max_descendants (task_contract old))%N.
     rewrite (descendant_count_depends_only_on_lineages queried _ _ Lineages).
     unfold WorldInvariant.task_valid in OldValid.
     repeat rewrite andb_true_iff in OldValid.
     apply N.leb_le; tauto.
 - change (WorldInvariant.tickets_valid after = true).
   unfold after, settled; eapply terminal_settlement_preserves_global_ticket_supply; eauto.
 - change (WorldInvariant.features_valid (WorldInvariant.world_structure after) = true).
   eapply feature_requirements_survive_a_fork with (before:=WorldInvariant.world_structure before).
   + exact (eq_sym Features).
   + exact (eq_sym Projects).
   + change (world_next_ticket before <= world_next_ticket after)%N. rewrite Tickets; reflexivity.
   + intros queried old Lookup; change (find_task queried before = Some old) in Lookup.
     destruct (Retained queried old Lookup) as [next [At Related]]; exists next; auto.
   + exact (WorldInvariant.features_requirement before Valid).
Qed.

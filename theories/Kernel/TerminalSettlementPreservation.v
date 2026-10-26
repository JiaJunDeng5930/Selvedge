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
 pose proof (a_valid_task_has_its_progress_requirements owner current before
   (lookup_task_requirements before owner current Valid Found)) as [Context [Phase [Checked Operations]]].
 replace (put_task owner (settled_task owner original plugin previous failed outcome current) before)
   with (put_task owner (settled_task owner original plugin previous failed outcome current)
     (with_ticket (world_next_ticket before) before)) by (destruct before; reflexivity).
 eapply fork_replacement_preserves_every_world_requirement; try eassumption; [|reflexivity| | | | |].
 - eapply settlement_preserves_the_archived_frame; exact ArchivedTask.
 - rewrite terminal_settlement_keeps_its_history_suffix, terminal_receipts_preserve_context_bindings; exact Context.
 - unfold WorldInvariant.phase_valid, WorldInvariant.calls_valid, task_activity;
   rewrite terminal_settlement_keeps_its_archived_lifecycle with (operations:=operations) by exact ArchivedTask; reflexivity.
 - unfold WorldInvariant.checked_phase, task_activity;
   rewrite terminal_settlement_keeps_its_archived_lifecycle with (operations:=operations) by exact ArchivedTask; reflexivity.
 - eapply terminal_settlement_preserves_the_remaining_operation_rights; eauto.
 - change (WorldInvariant.tickets_valid (put_task owner
     (settled_task owner original plugin previous failed outcome current) before) = true).
   eapply terminal_settlement_preserves_global_ticket_supply; eauto.
Qed.

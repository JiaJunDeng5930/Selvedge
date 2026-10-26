From Stdlib Require Import List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Registry.
From Selvedge.Kernel Require Import Domain State Callbacks WorldInvariant
 WorldInvariantProofs TerminalSettlementProofs.
From Selvedge.Kernel Require Export TicketSupplyProofs.
Import ListNotations.
Open Scope list_scope.

Theorem archived_operation_removal_withdraws_only_task_tickets :
 forall current operations identity suffix,
 task_lifecycle current = Archived operations ->
 ticket_subsequence
  (task_tickets (with_operations (Callbacks.remove_operation identity (task_operations current))
    (append_history suffix current)))
  (task_tickets current).
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed]
   operations identity suffix ArchivedTask; cbn in ArchivedTask; subst lifecycle.
 cbv [task_tickets task_activity task_operations with_operations append_history with_history with_lifecycle RecordSet.set]; cbn.
 apply filtering_operations_withdraws_only_their_tickets.
Qed.

Theorem archived_operation_removal_preserves_global_ticket_supply :
 forall before owner current operations identity suffix,
 tickets_valid before = true -> find_task owner before = Some current ->
 task_lifecycle current = Archived operations ->
 tickets_valid (put_task owner
  (with_operations (Callbacks.remove_operation identity (task_operations current))
    (append_history suffix current)) before) = true.
Proof.
 intros; eapply withdrawing_task_tickets_preserves_global_ticket_supply; eauto.
 eapply archived_operation_removal_withdraws_only_task_tickets; eauto.
Qed.

Theorem settlement_task_tickets_are_a_subsequence :
 forall owner original plugin previous failed outcome current operations,
 task_lifecycle current = Archived operations ->
 ticket_subsequence
  (task_tickets (settled_task owner original plugin previous failed outcome current))
  (task_tickets current).
Proof.
 intros; unfold settled_task; destruct (result_value previous failed outcome).
 eapply archived_operation_removal_withdraws_only_task_tickets; eauto.
Qed.

Theorem terminal_settlement_preserves_global_ticket_supply :
 forall before owner current operations original plugin previous failed outcome,
 well_formed before -> find_task owner before = Some current ->
 task_lifecycle current = Archived operations ->
 tickets_valid (put_task owner
  (settled_task owner original plugin previous failed outcome current) before) = true.
Proof.
 intros before owner current operations original plugin previous failed outcome Valid Found ArchivedTask.
 eapply withdrawing_task_tickets_preserves_global_ticket_supply; [|exact Found|].
 - exact (tickets_requirement before Valid).
 - eapply settlement_task_tickets_are_a_subsequence; exact ArchivedTask.
Qed.

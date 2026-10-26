From Stdlib Require Import List Bool NArith PeanoNat Lia Sorting.Permutation.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant
 WorldInvariantProofs ForkPreservation TicketSupplyProofs.
Import ListNotations.
Open Scope list_scope.

Lemma a_well_formed_world_has_a_valid_ticket_supply : forall value,
 WorldInvariant.well_formed value -> WorldInvariant.tickets_valid value = true.
Proof.
 intros value Valid; pose proof (WorldInvariant.tickets_requirement value Valid) as Tickets.
 change (WorldInvariant.tickets_valid value = true) in Tickets; exact Tickets.
Qed.

Definition replacing_one_native_result_adds_its_fresh_ticket :=
 replacing_one_registry_entry_lifts_a_fresh_ticket task WorldInvariant.task_tickets.

(* Native result processing may keep all existing leases and allocate one result
   identity. The task-local execution proof supplies precisely that observation. *)
Theorem a_native_result_preserves_global_ticket_ownership :
 forall value owner source next (allocates : bool),
 WorldInvariant.well_formed value -> find_task owner value = Some source ->
 WorldInvariant.task_tickets next =
   WorldInvariant.task_tickets source ++
     (if allocates then [world_next_ticket value] else []) ->
 WorldInvariant.tickets_valid
   (put_task owner next (with_ticket
     (if allocates then N.succ (world_next_ticket value) else world_next_ticket value) value)) = true.
Proof.
 intros value owner source next allocates WellFormed Found Updated.
 pose proof (a_well_formed_world_has_a_valid_ticket_supply value WellFormed) as Valid.
 destruct allocates.
 - eapply one_fresh_owner_preserves_the_ticket_supply; [exact Valid|reflexivity|].
   unfold allocated_tickets; cbn.
   change (Permutation
     (flat_map WorldInvariant.task_tickets (replace owner next (world_tasks value)) ++
       WorldInvariant.feature_tickets (world_features value))
     ((world_next_ticket value :: flat_map WorldInvariant.task_tickets (world_tasks value)) ++
       WorldInvariant.feature_tickets (world_features value))).
   apply Permutation_app_tail.
   eapply replacing_one_native_result_adds_its_fresh_ticket; [exact Found|].
   rewrite Updated; apply Permutation_app_comm.
 - rewrite app_nil_r in Updated.
   change (WorldInvariant.unique_tickets
     (flat_map WorldInvariant.task_tickets (replace owner next (world_tasks value)) ++
       WorldInvariant.feature_tickets (world_features value)) &&
     forallb (fun ticket => (ticket <? world_next_ticket value)%N)
       (flat_map WorldInvariant.task_tickets (replace owner next (world_tasks value)) ++
       WorldInvariant.feature_tickets (world_features value)) = true).
   rewrite (replacing_equal_ticket_ownership_keeps_the_registry_supply
     (world_tasks value) owner source next Found (eq_sym Updated)); exact Valid.
Qed.

Lemma owned_operation_tickets_precede_the_next_ticket : forall value owner source,
 WorldInvariant.well_formed value -> find_task owner value = Some source ->
 Forall (fun operation => Forall (fun ticket => (ticket < world_next_ticket value)%N)
   (WorldInvariant.operation_tickets operation)) (task_operations source).
Proof.
 intros value owner source WellFormed Found; apply owned_operation_tickets_are_bounded with (owner:=owner);
   [exact (WorldInvariant.tickets_requirement value WellFormed)|exact Found].
Qed.

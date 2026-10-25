From Stdlib Require Import List Bool NArith PeanoNat Lia Sorting.Permutation.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant
 WorldInvariantProofs ForkPreservation.
Import ListNotations.
Open Scope list_scope.

Lemma a_well_formed_world_has_a_valid_ticket_supply : forall value,
 WorldInvariant.well_formed value -> WorldInvariant.tickets_valid value = true.
Proof.
 intros value Valid; pose proof (WorldInvariant.tickets_requirement value Valid) as Tickets.
 change (WorldInvariant.tickets_valid value = true) in Tickets; exact Tickets.
Qed.

Lemma replacing_one_native_result_adds_its_fresh_ticket :
 forall (values : list task) owner source next ticket,
 registry_at owner values = Some source ->
 Permutation (WorldInvariant.task_tickets next) (ticket :: WorldInvariant.task_tickets source) ->
 Permutation (flat_map WorldInvariant.task_tickets (replace owner next values))
   (ticket :: flat_map WorldInvariant.task_tickets values).
Proof.
 intros values; induction values as [|first rest IH]; intros owner source next ticket Found Updated;
   [discriminate|].
 cbn in Found; cbn [replace]; destruct (N.eqb owner 0).
 - inversion Found; subst first; cbn [flat_map].
   change (Permutation (WorldInvariant.task_tickets next ++ flat_map WorldInvariant.task_tickets rest)
     ((ticket :: WorldInvariant.task_tickets source) ++ flat_map WorldInvariant.task_tickets rest)).
   apply Permutation_app_tail; exact Updated.
 - cbn [flat_map]; eapply Permutation_trans.
   + apply Permutation_app_head; eapply IH; eauto.
   + apply Permutation_sym; apply Permutation_middle.
Qed.

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
 - pose proof (a_valid_ticket_supply_has_unique_allocated_owners value Valid) as [Unique Bounded].
   set (before_tickets := flat_map WorldInvariant.task_tickets (world_tasks value) ++
     WorldInvariant.feature_tickets (world_features value)) in *.
   set (after_tickets := flat_map WorldInvariant.task_tickets
     (replace owner next (world_tasks value)) ++
     WorldInvariant.feature_tickets (world_features value)).
   assert (Added : Permutation after_tickets (world_next_ticket value :: before_tickets)).
   { unfold after_tickets, before_tickets.
     change (Permutation (flat_map WorldInvariant.task_tickets (replace owner next (world_tasks value)) ++
       WorldInvariant.feature_tickets (world_features value))
       ((world_next_ticket value :: flat_map WorldInvariant.task_tickets (world_tasks value)) ++
       WorldInvariant.feature_tickets (world_features value))).
     apply Permutation_app_tail.
     eapply replacing_one_native_result_adds_its_fresh_ticket; [exact Found|].
     rewrite Updated; change (Permutation (WorldInvariant.task_tickets source ++ [world_next_ticket value])
       ([world_next_ticket value] ++ WorldInvariant.task_tickets source)).
     apply Permutation_app_comm. }
   assert (Fresh : ~ In (world_next_ticket value) before_tickets).
   { intro Member; apply Forall_forall with (x:=world_next_ticket value) in Bounded; [lia|exact Member]. }
   assert (Distinct : NoDup after_tickets).
   { eapply Permutation_NoDup; [apply Permutation_sym; exact Added|constructor; assumption]. }
   change (WorldInvariant.unique_tickets after_tickets &&
     forallb (fun ticket => (ticket <? N.succ (world_next_ticket value))%N) after_tickets = true).
   apply andb_true_iff; split.
   + unfold WorldInvariant.unique_tickets; rewrite nodup_fixed_point by exact Distinct.
     apply Nat.eqb_refl.
   + apply forallb_forall; intros ticket Member; apply N.ltb_lt.
     apply (Permutation_in _ Added) in Member; destruct Member as [<-|Member]; [lia|].
     apply Forall_forall with (x:=ticket) in Bounded; [lia|exact Member].
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
 intros value owner source WellFormed Found.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners value
   (a_well_formed_world_has_a_valid_ticket_supply value WellFormed)) as [_ Bounded].
 apply Forall_forall; intros operation Member; apply Forall_forall; intros ticket Owned.
 apply Forall_forall with (x:=ticket) in Bounded; [exact Bounded|].
 apply in_or_app; left; apply in_flat_map; exists source; split.
 - clear Bounded; unfold find_task in Found.
   generalize dependent owner; induction (world_tasks value) as [|first rest IH];
     intros owner Found; [discriminate|].
   cbn in Found; destruct (N.eqb owner 0).
   + inversion Found; subst first; left; reflexivity.
   + right; eapply IH; exact Found.
 - unfold WorldInvariant.task_tickets; apply in_or_app; right.
   apply in_flat_map; exists operation; auto.
Qed.

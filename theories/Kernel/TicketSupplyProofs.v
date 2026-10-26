From Stdlib Require Import List Bool NArith PeanoNat Lia Sorting.Permutation.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State WorldInvariant WorldInvariantProofs.
Import ListNotations.
Open Scope list_scope.

Definition allocated_tickets (value : world) :=
 flat_map WorldInvariant.task_tickets (world_tasks value) ++ WorldInvariant.feature_tickets (world_features value).

Lemma distinct_tickets_pass_the_uniqueness_checker : forall tickets,
 NoDup tickets -> unique_tickets tickets = true.
Proof.
 intros tickets Unique; unfold unique_tickets.
 rewrite (nodup_fixed_point N.eq_dec Unique); apply Nat.eqb_refl.
Qed.

Lemma distinct_bounded_owners_form_a_valid_ticket_supply : forall value,
 NoDup (allocated_tickets value) ->
 Forall (fun ticket => (ticket < world_next_ticket value)%N) (allocated_tickets value) ->
 WorldInvariant.tickets_valid value = true.
Proof.
 intros value Unique Bounded; unfold WorldInvariant.tickets_valid.
 change (WorldInvariant.unique_tickets (allocated_tickets value) &&
   forallb (fun ticket => (ticket <? world_next_ticket value)%N) (allocated_tickets value) = true).
 apply andb_true_iff; split.
 - apply distinct_tickets_pass_the_uniqueness_checker; exact Unique.
 - apply forallb_forall; intros ticket Member; apply N.ltb_lt.
   apply Forall_forall with (x:=ticket) in Bounded; assumption.
Qed.

Theorem one_fresh_owner_preserves_the_ticket_supply : forall before after,
 WorldInvariant.tickets_valid before = true ->
 world_next_ticket after = N.succ (world_next_ticket before) ->
 Permutation (allocated_tickets after) (world_next_ticket before :: allocated_tickets before) ->
 WorldInvariant.tickets_valid after = true.
Proof.
 intros before after Valid Next Added.
 destruct (a_valid_ticket_supply_has_unique_allocated_owners before Valid) as [Unique Bounded].
 apply distinct_bounded_owners_form_a_valid_ticket_supply.
 - eapply Permutation_NoDup; [apply Permutation_sym; exact Added|constructor; [|exact Unique]].
   intro Member; apply Forall_forall with (x:=world_next_ticket before) in Bounded; [lia|exact Member].
 - apply Forall_forall; intros ticket Member; rewrite Next.
   apply (Permutation_in _ Added) in Member; destruct Member as [<-|Member]; [lia|].
   apply Forall_forall with (x:=ticket) in Bounded; [lia|exact Member].
Qed.

Lemma replacing_one_registry_entry_lifts_a_fresh_ticket :
 forall (A : Type) (tickets : A -> list N) values owner original replacement ticket,
 registry_at owner values = Some original ->
 Permutation (tickets replacement) (ticket :: tickets original) ->
 Permutation (flat_map tickets (replace owner replacement values)) (ticket :: flat_map tickets values).
Proof.
 intros A tickets values; induction values as [|first rest IH]; intros owner original replacement ticket
   Found Updated; [discriminate|].
 cbn in Found; cbn [replace]; destruct (N.eqb owner 0).
 - inversion Found; subst first; cbn [flat_map].
   change (Permutation (tickets replacement ++ flat_map tickets rest)
     ((ticket :: tickets original) ++ flat_map tickets rest)).
   apply Permutation_app_tail; exact Updated.
 - cbn [flat_map]; eapply Permutation_trans.
   + apply Permutation_app_head; eapply IH; eauto.
   + apply Permutation_sym; apply Permutation_middle.
Qed.

Lemma owned_operation_tickets_are_bounded : forall value owner source,
 WorldInvariant.tickets_valid value = true -> find_task owner value = Some source ->
 Forall (fun operation => Forall (fun ticket => (ticket < world_next_ticket value)%N)
   (WorldInvariant.operation_tickets operation)) (task_operations source).
Proof.
 intros value owner source Valid Found.
 destruct (a_valid_ticket_supply_has_unique_allocated_owners value Valid) as [_ Bounded].
 apply Forall_forall; intros operation Member; apply Forall_forall; intros ticket Owned.
 apply Forall_forall with (x:=ticket) in Bounded; [exact Bounded|].
 apply in_or_app; left; apply in_flat_map; exists source; split.
 - eapply registry_lookup_is_member; exact Found.
 - unfold WorldInvariant.task_tickets; apply in_or_app; right; apply in_flat_map; exists operation; auto.
Qed.

(* Settlement only withdraws existing correlation owners. Keeping their order
   makes both uniqueness and the allocation bound consequences of the supply
   before the callback, without a new allocation premise. *)
Inductive ticket_subsequence : list N -> list N -> Prop :=
| ticket_subsequence_empty : ticket_subsequence [] []
| ticket_subsequence_keep : forall ticket selected original,
    ticket_subsequence selected original ->
    ticket_subsequence (ticket :: selected) (ticket :: original)
| ticket_subsequence_drop : forall ticket selected original,
    ticket_subsequence selected original ->
    ticket_subsequence selected (ticket :: original).

Lemma ticket_subsequence_reflexive : forall tickets,
 ticket_subsequence tickets tickets.
Proof. induction tickets; constructor; assumption. Qed.

Lemma ticket_subsequence_includes : forall selected original,
 ticket_subsequence selected original -> incl selected original.
Proof.
 intros selected original Subsequence; induction Subsequence; intros owned Member;
 cbn in *; [contradiction|destruct Member as [<-|Member]; auto|auto].
Qed.

Lemma ticket_subsequence_preserves_uniqueness : forall selected original,
 ticket_subsequence selected original -> NoDup original -> NoDup selected.
Proof.
 intros selected original Subsequence; induction Subsequence; intros Unique.
 - constructor.
 - inversion Unique; subst; constructor; [|auto].
   intro Member; match goal with Fresh : ~ In ticket original |- _ =>
     apply Fresh; eapply ticket_subsequence_includes; eauto end.
 - inversion Unique; subst; auto.
Qed.

Lemma ticket_subsequence_append : forall left left_original right right_original,
 ticket_subsequence left left_original -> ticket_subsequence right right_original ->
 ticket_subsequence (left ++ right) (left_original ++ right_original).
Proof.
 intros left left_original right right_original Prefix Suffix; induction Prefix;
 cbn; [exact Suffix|constructor; exact IHPrefix|constructor; exact IHPrefix].
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

Definition filtering_operations_withdraws_only_their_tickets :=
 filtering_ticket_groups_keeps_a_subsequence operation operation_tickets.

Lemma replacing_an_owner_withdraws_only_its_tickets : forall entries owner current replacement,
 registry_at owner entries = Some current ->
 ticket_subsequence (task_tickets replacement) (task_tickets current) ->
 ticket_subsequence (flat_map task_tickets (replace owner replacement entries))
   (flat_map task_tickets entries).
Proof.
 intros entries; induction entries as [|first rest IH]; intros owner current replacement Found Subsequence;
 cbn in Found; [discriminate|].
 cbn; destruct (N.eqb owner 0).
 - inversion Found; subst. apply ticket_subsequence_append;
   [exact Subsequence|apply ticket_subsequence_reflexive].
 - apply ticket_subsequence_append; [apply ticket_subsequence_reflexive|].
   eapply IH; eauto.
Qed.

Lemma withdrawing_task_tickets_preserves_global_ticket_supply : forall before owner current replacement,
 tickets_valid before = true -> find_task owner before = Some current ->
 ticket_subsequence (task_tickets replacement) (task_tickets current) ->
 tickets_valid (put_task owner replacement before) = true.
Proof.
 intros before owner current replacement Valid Found Subsequence.
 pose proof (a_valid_ticket_supply_has_unique_allocated_owners before Valid) as [Unique Bounded].
 assert (Global : ticket_subsequence
   (flat_map task_tickets (replace owner replacement (world_tasks before)) ++
      feature_tickets (world_features before))
   (flat_map task_tickets (world_tasks before) ++ feature_tickets (world_features before))).
 { apply ticket_subsequence_append; [|apply ticket_subsequence_reflexive].
   eapply replacing_an_owner_withdraws_only_its_tickets; eauto. }
 apply distinct_bounded_owners_form_a_valid_ticket_supply.
 - eapply ticket_subsequence_preserves_uniqueness; eauto.
 - apply Forall_forall; intros ticket Member; rewrite Forall_forall in Bounded; apply Bounded.
   eapply ticket_subsequence_includes; eauto.
Qed.

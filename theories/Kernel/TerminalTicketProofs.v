From Stdlib Require Import List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Registry.
From Selvedge.Kernel Require Import Domain State Callbacks WorldInvariant
 WorldInvariantProofs TerminalSettlementProofs.
Import ListNotations.
Open Scope list_scope.

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

Lemma filtering_operations_withdraws_only_their_tickets : forall keep operations,
 ticket_subsequence (flat_map operation_tickets (filter keep operations))
   (flat_map operation_tickets operations).
Proof.
 intros keep operations; induction operations as [|operation rest IH]; [constructor|].
 change (ticket_subsequence
   (flat_map operation_tickets (if keep operation then operation :: filter keep rest else filter keep rest))
   (operation_tickets operation ++ flat_map operation_tickets rest)).
 destruct (keep operation).
 - change (ticket_subsequence
     (operation_tickets operation ++ flat_map operation_tickets (filter keep rest))
     (operation_tickets operation ++ flat_map operation_tickets rest)).
   apply ticket_subsequence_append; [apply ticket_subsequence_reflexive|exact IH].
 - induction (operation_tickets operation) as [|ticket tickets Tail]; cbn;
   [exact IH|constructor; exact Tail].
Qed.

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

Lemma distinct_tickets_pass_the_uniqueness_checker : forall tickets,
 NoDup tickets -> unique_tickets tickets = true.
Proof.
 intros tickets Unique; unfold unique_tickets.
 rewrite (nodup_fixed_point N.eq_dec Unique); apply Nat.eqb_refl.
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
 unfold tickets_valid, put_task, with_tasks; cbn.
 apply andb_true_iff; split.
 - apply distinct_tickets_pass_the_uniqueness_checker.
   eapply ticket_subsequence_preserves_uniqueness; eauto.
 - apply forallb_forall; intros ticket Member; apply N.ltb_lt.
   rewrite Forall_forall in Bounded; apply Bounded.
   eapply ticket_subsequence_includes; eauto.
Qed.

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

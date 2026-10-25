From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State WorldInvariant.
Import ListNotations.

Theorem the_initial_world_is_well_formed : world_valid State.initial = true.
Proof. reflexivity. Qed.
Theorem a_journal_cursor_does_not_change_domain_validity : forall sequence value,
 world_valid (with_sequence sequence value) = world_valid value.
Proof. intros sequence []; reflexivity. Qed.
Theorem the_world_checker_establishes_all_requirements : forall value,
 world_valid value = true -> well_formed value.
Proof.
 intros value Valid; unfold world_valid in Valid.
 repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[[Environment Projects] Tasks] Tickets] Features].
 constructor; assumption.
Qed.
Theorem well_formed_worlds_pass_the_checker : forall value,
 well_formed value -> world_valid value = true.
Proof.
 intros value [Environment Projects Tasks Tickets Features].
 unfold world_valid; rewrite Environment, Projects, Tasks, Tickets, Features; reflexivity.
Qed.
Theorem an_admitted_world_satisfies_the_commit_requirements : forall before candidate,
 world_valid before = true -> world_valid (decision_world (validate before candidate)) = true.
Proof.
 intros before candidate Before; unfold validate, validate_with_status.
 destruct (world_valid (decision_world candidate)) eqn:Checked; [exact Checked|exact Before].
Qed.
Theorem an_invalid_candidate_restores_the_world_and_discards_every_effect : forall before candidate,
 world_valid (decision_world candidate) = false ->
 decision_world (validate before candidate) = before /\ decision_effects (validate before candidate) = [].
Proof. intros; unfold validate, validate_with_status; rewrite H; split; reflexivity. Qed.
Theorem a_valid_candidate_is_committed_without_substitution : forall before candidate,
 world_valid (decision_world candidate) = true -> validate before candidate = candidate.
Proof. intros; unfold validate, validate_with_status; rewrite H; reflexivity. Qed.


Lemma deduplicating_tickets_never_increases_the_length : forall tickets,
 List.length (nodup N.eq_dec tickets) <= List.length tickets.
Proof.
 induction tickets as [|ticket rest IH]; [reflexivity|].
 cbn; destruct (in_dec N.eq_dec ticket rest); cbn; lia.
Qed.
Lemma unchanged_ticket_cardinality_requires_distinct_owners : forall tickets,
 List.length tickets = List.length (nodup N.eq_dec tickets) -> NoDup tickets.
Proof.
 induction tickets as [|ticket rest IH]; intros Same; [constructor|].
 cbn in Same; destruct (in_dec N.eq_dec ticket rest) as [Repeated|Fresh].
 - pose proof (deduplicating_tickets_never_increases_the_length rest); lia.
 - cbn in Same; constructor; [exact Fresh|apply IH; lia].
Qed.
Theorem unique_tickets_denotes_distinct_correlation_owners : forall tickets,
 unique_tickets tickets = true -> NoDup tickets.
Proof.
 intros tickets Unique; unfold unique_tickets in Unique; apply Nat.eqb_eq in Unique.
 apply unchanged_ticket_cardinality_requires_distinct_owners; exact Unique.
Qed.
Theorem a_valid_ticket_supply_has_unique_allocated_owners : forall state,
 tickets_valid state = true ->
 let tickets := flat_map task_tickets (world_tasks state) ++ feature_tickets (world_features state) in
 NoDup tickets /\ Forall (fun ticket => (ticket < world_next_ticket state)%N) tickets.
Proof.
 intros state Valid; unfold tickets_valid in Valid; apply andb_true_iff in Valid as [Unique Bounded].
 split; [apply unique_tickets_denotes_distinct_correlation_owners; exact Unique|].
 apply Forall_forall; intros ticket Owned; apply N.ltb_lt.
 rewrite forallb_forall in Bounded; apply Bounded; exact Owned.
Qed.

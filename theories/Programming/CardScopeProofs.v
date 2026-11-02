From Stdlib Require Import String Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Codec.
From Selvedge.Features Require Domain.
From Selvedge.Programming Require CommandResult CardScope.
From Selvedge.Programming Require Import OptionObservationProofs.
Open Scope string_scope.
Module F := Selvedge.Features.Domain.

Lemma selecting_a_card_retains_the_observed_value : forall id revision value,
 CardScope.select_card id revision value = match CardScope.lookup id value with
 | Some card => if N.eqb revision (F.card_revision card) then CommandResult.Accepted card
   else CommandResult.refuse "card_conflict" "The card changed in another view or during execution. Refresh its current values before applying this edit."
 | None => CommandResult.refuse "card_not_found" "The board card does not exist" end.
Proof.
 intros id revision value; destruct (CardScope.lookup id value) as [card|] eqn:Found;
 unfold CardScope.select_card,CardScope.select_card_reference.
 - eapply observe_present; [exact Found|]; intros Observed.
   destruct (N.eqb revision (F.card_revision card)); reflexivity.
 - eapply observe_absent; [exact Found|]; intros Missing; reflexivity.
Qed.

Theorem stale_card_is_atomic : forall id expected value card run,
 CardScope.lookup id value = Some card -> expected <> F.card_revision card ->
 let refused := CardScope.with_card id expected value run in
 bool_default "ok" (decision_reply refused) true = false /\
 decision_world refused = value /\ decision_effects refused = nil.
Proof.
 intros id expected value card run found different; cbv zeta.
 unfold CardScope.with_card; rewrite selecting_a_card_retains_the_observed_value; unfold CommandResult.resolve. rewrite found. apply N.eqb_neq in different. rewrite different. repeat split; reflexivity.
Qed.

From Stdlib Require Import List Bool NArith.
From Selvedge.Programming Require Import OptionObservationProofs.
From Selvedge.Kernel Require Import Domain State TerminalSettlement.

Lemma observed_resolution_tracks_its_eligibility : forall payload before current observed,
 (match resolve_observed payload before current observed with Some _ => true | None => false end) =
 (match TerminalSettlement.resolved_update payload current with Some _ => true | None => false end).
Proof.
 intros; unfold resolve_observed; eapply observe_cases.
 - intros selected Observed; now rewrite Observed.
 - intros Missing; now rewrite Missing.
Qed.
Lemma terminal_resolution_tracks_the_real_eligibility : forall payload before,
 (match resolve_request payload before with Some _ => true | None => false end) =
 (match find_task (owner payload) before with Some current => (match TerminalSettlement.resolved_update payload current with Some _ => true | None => false end) | None => false end).
Proof.
 intros; unfold resolve_request; eapply observe_cases.
 - intros current Found; rewrite observed_resolution_tracks_its_eligibility; now rewrite Found.
 - intros Missing; now rewrite Missing.
Qed.
Lemma observed_resolution_retains_the_callback_payload : forall payload before current observed accepted,
 resolve_observed payload before current observed = Some accepted -> request accepted = payload.
Proof.
 intros payload before current observed accepted; unfold resolve_observed; eapply observe_cases.
 - intros selected Observed Equal; inversion Equal; reflexivity.
 - intros Missing Equal; discriminate.
Qed.
Lemma resolution_retains_the_callback_payload : forall payload before accepted,
 resolve_request payload before = Some accepted -> request accepted = payload.
Proof.
 intros payload before accepted; unfold resolve_request; eapply observe_cases.
 - intros current Found; apply observed_resolution_retains_the_callback_payload.
 - intros Missing Equal; discriminate.
Qed.

Theorem every_owned_terminal_callback_resolves_its_finite_transaction :
 forall payload before current,
 find_task (TerminalSettlement.owner payload) before = Some current ->
 (match TerminalSettlement.resolved_update payload current with Some _ => true | None => false end) = true ->
 exists accepted, TerminalSettlement.resolve_request payload before = Some accepted.
Proof.
 intros payload before current Found Eligible.
 pose proof (terminal_resolution_tracks_the_real_eligibility payload before) as Resolves.
 rewrite Found, Eligible in Resolves.
 destruct (TerminalSettlement.resolve_request payload before) as [accepted|]; [eauto|discriminate].
Qed.

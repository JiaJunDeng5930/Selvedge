From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Inputs TerminalSettlement TerminalSettlementPlanProofs.
From Selvedge.Programming Require Import DeferredCommit DeferredCommitProofs.
From Selvedge.Kernel Require Import Dispatch Delivery Notifications.
Import ListNotations.
Open Scope string_scope.

Theorem a_terminal_settlement_commits_before_independent_runtime_work :
 forall before (accepted : TerminalSettlement.plan before) raw,
 Delivery.fits true (TerminalSettlement.candidate accepted) = true ->
 TerminalSettlement.packet accepted raw =
 (with_sequence (N.succ (world_sequence before)) (decision_world (TerminalSettlement.candidate accepted)),
  Notifications.envelope true true (Some (TerminalSettlement.source accepted)) before
    (TerminalSettlement.candidate accepted)).
Proof.
 intros before accepted raw Fits; unfold TerminalSettlement.packet.
 apply a_constructed_candidate_with_its_actual_budget_is_committed; [|exact Fits].
 reflexivity.
Qed.

Theorem every_owned_terminal_callback_resolves_its_finite_transaction :
 forall payload before current,
 find_task (TerminalSettlement.owner payload) before = Some current ->
 TerminalSettlement.eligible payload current = true ->
 exists accepted, TerminalSettlement.resolve_request payload before = Some accepted.
Proof.
 intros payload before current Found Eligible.
 pose proof (terminal_resolution_tracks_the_real_eligibility payload before) as Resolves.
 rewrite Found, Eligible in Resolves.
 destruct (TerminalSettlement.resolve_request payload before) as [accepted|]; [eauto|discriminate].
Qed.

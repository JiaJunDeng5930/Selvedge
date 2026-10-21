From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State.
From Selvedge.Features Require Import Domain Board.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
Theorem stale_card_is_atomic : forall id expected value card run,
 Board.lookup id value = Some card -> expected <> F.card_revision card ->
 Board.with_card id expected value run =
 reject "card_conflict"%string "The card changed in another view or during execution. Refresh its current values before applying this edit."%string value.
Proof.
 intros id expected value card run found different.
 unfold Board.with_card. rewrite found. apply N.eqb_neq in different. rewrite different. reflexivity.
Qed.
(** Once linked, edits cannot change the execution request, even when idle. *)
Theorem linked_execution_inputs_are_immutable : forall id expected value card target observed input,
 Board.lookup id value = Some card -> F.card_task card = Some target ->
 Board.changes_execution input = true ->
 decision_world (Board.update_card id expected observed input value) = value.
Proof.
 intros id expected value card target observed input found linked changed.
 unfold Board.update_card, Board.at_clock. destruct (Board.clock observed); [|reflexivity].
 unfold Board.with_card. rewrite found. destruct (N.eqb expected (F.card_revision card)); [|reflexivity].
 destruct (Board.parse_patch input (F.card_contents card)); [|reflexivity].
 unfold Board.unlinked, BoardFacts.unlinked. rewrite linked, changed. simpl.
 rewrite Bool.andb_false_r. reflexivity.
Qed.

(** Stopping suppresses the next model turn; committed asynchronous work
    still owns its Board concurrency slot until its callbacks settle. *)
Theorem stopped_operation_keeps_card_locked : forall card value task phase first rest,
 BoardFacts.linked_task card value=Some task ->
 Selvedge.Kernel.Domain.task_lifecycle task=Selvedge.Kernel.Domain.Stopped phase (first::rest) ->
 BoardFacts.mutable card value=false /\ BoardFacts.runnable card value=false.
Proof.
 intros card value task phase first rest linked stopped.
 assert (busy:BoardFacts.busy card value=true).
 { unfold BoardFacts.busy. rewrite linked. unfold BoardFacts.busy_task, Selvedge.Kernel.Domain.task_busy, Selvedge.Kernel.Domain.task_activity, Selvedge.Kernel.Domain.task_operations. rewrite stopped. apply Bool.orb_true_r. }
 assert (locked:BoardFacts.mutable card value=false).
 { unfold BoardFacts.mutable. rewrite busy. repeat rewrite Bool.orb_true_r. reflexivity. }
 split; [exact locked|]. unfold BoardFacts.runnable. now rewrite locked.
Qed.

From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Import CodeBlock.
Import ListNotations.

Theorem copy_writes_the_observed_literal : forall state ticket text,
  In (Clipboard ticket text) (snd (step Copy state)) -> text = literal state.
Proof.
  intros state ticket text sent; unfold step in sent; destruct (copy state); simpl in sent; try contradiction.
  all: destruct sent as [same | impossible]; [inversion same; reflexivity | contradiction].
Qed.
Theorem pending_copy_is_not_duplicated : forall state ticket,
  copy state = Pending ticket -> snd (step Copy state) = [].
Proof. intros state ticket pending; unfold step; rewrite pending; reflexivity. Qed.
Theorem stale_copy_completion_changes_nothing : forall state ticket current succeeded,
  copy state = Pending current -> ticket <> current -> step (Copied ticket succeeded) state = (state, []).
Proof.
  intros state ticket current succeeded pending different; unfold step; rewrite pending.
  assert (N.eqb ticket current = false) by (apply N.eqb_neq; assumption).
  rewrite H; reflexivity.
Qed.
Theorem changing_literal_retires_pending_feedback : forall state text,
  text <> literal state -> copy (fst (step (SourceChanged text) state)) = Idle.
Proof.
  intros state text different; unfold step.
  assert (String.eqb text (literal state) = false) by (apply String.eqb_neq; assumption).
  rewrite H; reflexivity.
Qed.
Theorem wrapping_does_not_change_copied_text : forall state,
  literal (fst (step ToggleWrap state)) = literal state.
Proof. reflexivity. Qed.
